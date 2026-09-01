from __future__ import annotations

import json
import re
import struct
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
RESOURCE_PATH_PATTERN = re.compile(r'path="(res://[^"\r\n]+)"')
STABLE_ID_FALLBACK = re.compile(r"^[a-z][a-z0-9_]*$")
TEXT_RESOURCE_SUFFIXES = {".tscn", ".tres"}
PNG_ALPHA_COLOR_TYPES = {4, 6}


class AssetValidationError(ValueError):
    pass


@dataclass(frozen=True)
class PngHeader:
    width: int
    height: int
    color_type: int
    has_transparency_chunk: bool

    @property
    def supports_alpha(self) -> bool:
        return self.color_type in PNG_ALPHA_COLOR_TYPES or self.has_transparency_chunk


class AssetManifestValidator:
    def __init__(self, project_root: Path):
        self.project_root = project_root.resolve()
        self.errors: list[str] = []

    def validate(self, manifest_path: str | Path = "assets/asset-manifest.json") -> dict[str, int]:
        self.errors = []
        manifest_file = self._project_path(manifest_path)
        manifest = self._read_json(manifest_file, "asset manifest")
        if not isinstance(manifest, dict):
            raise AssetValidationError("asset manifest must be a JSON object")

        self._require_equal(manifest.get("schema_version"), 1, "manifest schema_version")
        stable_id_pattern, confirmed_statuses = self._validate_art_assets_contract(manifest)
        nearest_filter, base_size = self._validate_style_and_import_policy(manifest)
        promoted_assets = self._load_promoted_assets(manifest)
        runtime_roots = self._res_roots(manifest.get("runtime_roots"), "runtime_roots")
        placeholder_policy = manifest.get("placeholder_policy", {})
        assets = manifest.get("assets")
        if not isinstance(assets, list):
            self.errors.append("manifest assets must be an array")
            assets = []

        registered_paths: set[str] = set()
        seen_ids: set[str] = set()
        for index, asset in enumerate(assets):
            self._validate_asset(
                asset,
                index,
                stable_id_pattern,
                confirmed_statuses,
                nearest_filter,
                base_size,
                runtime_roots,
                placeholder_policy,
                promoted_assets,
                seen_ids,
                registered_paths,
            )

        resource_count = self._validate_resource_references(manifest, registered_paths)
        if self.errors:
            raise AssetValidationError("\n".join(f"- {error}" for error in self.errors))
        return {"asset_count": len(assets), "resource_count": resource_count}

    def _validate_art_assets_contract(self, manifest: dict[str, Any]) -> tuple[re.Pattern[str], set[str]]:
        contract = manifest.get("art_assets_contract")
        if not isinstance(contract, dict):
            self.errors.append("art_assets_contract must be an object")
            return STABLE_ID_FALLBACK, set()
        if contract.get("dataset") != "art_assets":
            self.errors.append("art_assets_contract.dataset must be 'art_assets'")
        schema = self._read_res_json(contract.get("schema"), "export schema")
        if not isinstance(schema, dict):
            return STABLE_ID_FALLBACK, set()
        dataset = schema.get("datasets", {}).get("art_assets", {})
        required_fields = set(dataset.get("required_fields", []))
        if not {"id", "name", "status"}.issubset(required_fields):
            self.errors.append("export schema art_assets must require id, name, and status")
        mapped_fields = set(dataset.get("notion", {}).get("field_map", {}).values())
        expected_spec_fields = {"kind", "width", "height", "direction_count", "frame_count", "files"}
        missing = sorted(expected_spec_fields - mapped_fields)
        if missing:
            self.errors.append(f"export schema art_assets is missing mapped fields: {', '.join(missing)}")
        pattern_text = schema.get("stable_id_pattern", STABLE_ID_FALLBACK.pattern)
        try:
            pattern = re.compile(pattern_text)
        except re.error:
            self.errors.append("export schema stable_id_pattern is invalid")
            pattern = STABLE_ID_FALLBACK
        return pattern, set(dataset.get("confirmed_statuses", []))

    def _validate_style_and_import_policy(self, manifest: dict[str, Any]) -> tuple[str, int]:
        style = self._read_res_json(manifest.get("style_tokens"), "art style tokens")
        pixel_rules = style.get("pixel_rules", {}) if isinstance(style, dict) else {}
        nearest_filter = pixel_rules.get("texture_filter")
        if nearest_filter != "nearest":
            self.errors.append("art style tokens pixel_rules.texture_filter must be 'nearest'")
        base_size = pixel_rules.get("base_tile_size_px")
        if not isinstance(base_size, int) or base_size <= 0:
            self.errors.append("art style tokens base_tile_size_px must be a positive integer")
            base_size = 32

        policy = manifest.get("import_policy")
        if not isinstance(policy, dict):
            self.errors.append("import_policy must be an object")
            return "nearest", base_size
        if policy.get("texture_filter") != nearest_filter:
            self.errors.append("manifest import filter must match art style tokens")
        setting = policy.get("godot_project_setting")
        expected = policy.get("godot_nearest_value")
        project_file = self.project_root / "project.godot"
        project_text = self._read_text(project_file, "Godot project settings")
        if isinstance(setting, str) and isinstance(expected, int):
            match = re.search(rf"(?m)^{re.escape(setting)}\s*=\s*(-?\d+)\s*$", project_text)
            if match is None:
                self.errors.append(f"project.godot is missing nearest filter setting {setting}")
            elif int(match.group(1)) != expected:
                self.errors.append(f"project.godot {setting} must be {expected} for nearest filtering")
        else:
            self.errors.append("import_policy must declare Godot nearest setting and integer value")
        return str(nearest_filter or "nearest"), base_size

    def _load_promoted_assets(self, manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
        promoted = self._read_res_json(manifest.get("promoted_assets"), "promoted assets manifest")
        if not isinstance(promoted, dict) or not isinstance(promoted.get("assets"), list):
            self.errors.append("promoted assets manifest must contain an assets array")
            return {}
        return {
            f"res://{entry['path']}": entry
            for entry in promoted["assets"]
            if isinstance(entry, dict) and isinstance(entry.get("path"), str)
        }

    def _validate_asset(
        self,
        asset: Any,
        index: int,
        stable_id_pattern: re.Pattern[str],
        confirmed_statuses: set[str],
        nearest_filter: str,
        base_size: int,
        runtime_roots: list[str],
        placeholder_policy: Any,
        promoted_assets: dict[str, dict[str, Any]],
        seen_ids: set[str],
        registered_paths: set[str],
    ) -> None:
        label = f"assets[{index}]"
        if not isinstance(asset, dict):
            self.errors.append(f"{label} must be an object")
            return
        asset_id = asset.get("id")
        label = f"asset {asset_id!r}"
        if not isinstance(asset_id, str) or stable_id_pattern.fullmatch(asset_id) is None:
            self.errors.append(f"{label} has an invalid stable ID")
        elif asset_id in seen_ids:
            self.errors.append(f"{label} duplicates stable ID {asset_id}")
        else:
            seen_ids.add(asset_id)
        for field in ("name", "status", "kind", "path"):
            if not isinstance(asset.get(field), str) or not asset[field]:
                self.errors.append(f"{label} is missing non-empty {field}")
        if confirmed_statuses and asset.get("status") not in confirmed_statuses:
            self.errors.append(f"{label} status must be confirmed by the art_assets export schema")

        path = asset.get("path")
        if not isinstance(path, str):
            return
        if not any(path.startswith(root) for root in runtime_roots):
            self.errors.append(f"{label} path is outside declared runtime roots: {path}")
        if path in registered_paths:
            self.errors.append(f"{label} duplicates registered path {path}")
        registered_paths.add(path)
        promoted = promoted_assets.get(path)
        if promoted is None:
            self.errors.append(f"{label} path is not in the promoted assets manifest: {path}")
        elif (promoted.get("width"), promoted.get("height")) != (asset.get("width"), asset.get("height")):
            self.errors.append(f"{label} dimensions disagree with the promoted assets manifest")

        placeholder_policy = placeholder_policy if isinstance(placeholder_policy, dict) else {}
        allow_placeholders = placeholder_policy.get("allow_runtime_placeholders") is True
        if asset.get("placeholder") is not False and not allow_placeholders:
            self.errors.append(f"{label} is a runtime placeholder, but placeholders are forbidden")
        lowered_parts = {part.lower() for part in PurePosixPath(path.removeprefix("res://")).parts}
        for segment in placeholder_policy.get("forbidden_path_segments", []):
            if isinstance(segment, str) and segment.lower() in lowered_parts:
                self.errors.append(f"{label} path contains forbidden placeholder segment {segment!r}")

        if asset.get("texture_filter") != nearest_filter:
            self.errors.append(f"{label} texture_filter must be {nearest_filter!r}")
        file_path = self._res_path(path)
        if file_path is None or not file_path.is_file():
            self.errors.append(f"{label} file is missing: {path}")
            return
        try:
            png = read_png_header(file_path)
        except AssetValidationError as error:
            self.errors.append(f"{label} {error}")
            return
        width = asset.get("width")
        height = asset.get("height")
        if (png.width, png.height) != (width, height):
            self.errors.append(
                f"{label} PNG size is {png.width}x{png.height}, expected {width}x{height}"
            )
        if asset.get("alpha_required") is True and not png.supports_alpha:
            self.errors.append(f"{label} PNG must provide an alpha channel")
        self._validate_frame_grid(asset, label, base_size)

    def _validate_frame_grid(self, asset: dict[str, Any], label: str, base_size: int) -> None:
        grid = asset.get("frame_grid")
        if not isinstance(grid, dict):
            self.errors.append(f"{label} frame_grid must be an object")
            return
        keys = ("columns", "rows", "frame_width", "frame_height")
        if any(not isinstance(grid.get(key), int) or grid[key] <= 0 for key in keys):
            self.errors.append(f"{label} frame_grid values must be positive integers")
            return
        if grid["columns"] * grid["frame_width"] != asset.get("width"):
            self.errors.append(f"{label} frame grid width does not match declared PNG width")
        if grid["rows"] * grid["frame_height"] != asset.get("height"):
            self.errors.append(f"{label} frame grid height does not match declared PNG height")
        if grid["columns"] * grid["rows"] != asset.get("frame_count"):
            self.errors.append(f"{label} frame_count does not match frame grid")
        if not isinstance(asset.get("direction_count"), int) or asset["direction_count"] <= 0:
            self.errors.append(f"{label} direction_count must be a positive integer")
        elif isinstance(asset.get("frame_count"), int) and asset["frame_count"] % asset["direction_count"] != 0:
            self.errors.append(f"{label} frame_count must be divisible by direction_count")
        if asset.get("kind") == "character_sprite" and (
            grid["frame_width"] != base_size or grid["frame_height"] != base_size
        ):
            self.errors.append(f"{label} character frames must be {base_size}x{base_size}")

    def _validate_resource_references(self, manifest: dict[str, Any], registered_paths: set[str]) -> int:
        roots = self._res_roots(manifest.get("resource_scan_roots"), "resource_scan_roots")
        references = 0
        for root in roots:
            directory = self._res_path(root)
            if directory is None or not directory.is_dir():
                self.errors.append(f"resource scan root is missing: {root}")
                continue
            for resource_file in sorted(directory.rglob("*")):
                if resource_file.suffix not in TEXT_RESOURCE_SUFFIXES:
                    continue
                text = self._read_text(resource_file, str(resource_file.relative_to(self.project_root)))
                for resource_path in RESOURCE_PATH_PATTERN.findall(text):
                    references += 1
                    target = self._res_path(resource_path)
                    if target is None or not target.is_file():
                        source = resource_file.relative_to(self.project_root)
                        self.errors.append(f"broken resource reference in {source}: {resource_path}")
                    if resource_path.lower().endswith(".png") and resource_path not in registered_paths:
                        source = resource_file.relative_to(self.project_root)
                        self.errors.append(f"unregistered PNG reference in {source}: {resource_path}")
        return references

    def _res_roots(self, value: Any, label: str) -> list[str]:
        if not isinstance(value, list) or not value:
            self.errors.append(f"{label} must be a non-empty array")
            return []
        roots = []
        for item in value:
            if not isinstance(item, str) or self._res_path(item) is None:
                self.errors.append(f"{label} contains an invalid res:// path: {item!r}")
                continue
            roots.append(item)
        return roots

    def _read_res_json(self, value: Any, label: str) -> Any:
        path = self._res_path(value)
        if path is None:
            self.errors.append(f"{label} path must be a safe res:// path")
            return {}
        return self._read_json(path, label)

    def _read_json(self, path: Path, label: str) -> Any:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.errors.append(f"could not read {label} at {path}: {error}")
            return {}

    def _read_text(self, path: Path, label: str) -> str:
        try:
            return path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            self.errors.append(f"could not read {label}: {error}")
            return ""

    def _project_path(self, value: str | Path) -> Path:
        path = Path(value)
        return path if path.is_absolute() else self.project_root / path

    def _res_path(self, value: Any) -> Path | None:
        if not isinstance(value, str) or not value.startswith("res://"):
            return None
        relative = PurePosixPath(value.removeprefix("res://"))
        if relative.is_absolute() or ".." in relative.parts:
            return None
        resolved = (self.project_root / Path(*relative.parts)).resolve()
        try:
            resolved.relative_to(self.project_root)
        except ValueError:
            return None
        return resolved

    def _require_equal(self, actual: Any, expected: Any, label: str) -> None:
        if actual != expected:
            self.errors.append(f"{label} must be {expected!r}")


def read_png_header(path: Path) -> PngHeader:
    try:
        data = path.read_bytes()
    except OSError as error:
        raise AssetValidationError(f"could not read PNG {path}: {error}") from error
    if len(data) < 33 or data[:8] != PNG_SIGNATURE:
        raise AssetValidationError(f"is not a valid PNG: {path}")
    ihdr_length = struct.unpack(">I", data[8:12])[0]
    if data[12:16] != b"IHDR" or ihdr_length != 13:
        raise AssetValidationError(f"has an invalid PNG IHDR chunk: {path}")
    width, height, bit_depth, color_type = struct.unpack(">IIBB", data[16:26])
    if width <= 0 or height <= 0 or bit_depth == 0 or color_type not in {0, 2, 3, 4, 6}:
        raise AssetValidationError(f"has invalid PNG header values: {path}")
    has_transparency_chunk = False
    offset = 8
    while offset + 12 <= len(data):
        chunk_length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_end = offset + 12 + chunk_length
        if chunk_end > len(data):
            raise AssetValidationError(f"has a truncated PNG chunk: {path}")
        if chunk_type == b"tRNS":
            has_transparency_chunk = True
        if chunk_type == b"IEND":
            break
        offset = chunk_end
    return PngHeader(width, height, color_type, has_transparency_chunk)
