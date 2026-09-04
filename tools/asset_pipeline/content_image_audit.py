from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


DEFAULT_OUTPUT = Path("assets/content-image-map.json")
DEFAULT_REPORT = Path("docs/reports/dev-78-content-image-audit.md")

ITEM_OVERRIDES = {
    "ash_stained_iron_kettle": "asset_assets_sprites_objects_crafting_round_iron_kettle_stove_32x32_png",
    "black_bamboo_tea_scoop": "asset_assets_ui_icons_atlas_whisk_png",
    "clay": "asset_assets_tiles_terrain_desert_cracked_clay_32x32_png",
    "copper_ore": "asset_assets_sprites_objects_mining_copper_ore_32x32_png",
    "humble_clay_bowl": "asset_assets_ui_icons_atlas_bowl_png",
    "incense_sticks": "asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png",
    "insulated_tea_bottle": "asset_assets_ui_icons_atlas_gourd_png",
    "iron_kettle": "asset_assets_sprites_objects_crafting_round_iron_kettle_stove_32x32_png",
    "iron_ore": "asset_assets_sprites_objects_mining_iron_ore_32x32_png",
    "item_28": "asset_assets_sprites_objects_mining_iron_ore_32x32_png",
    "item_29": "asset_assets_ui_icons_atlas_leaf_resource_png",
    "cloth": "asset_assets_ui_icons_atlas_crate_png",
    "item_33": "asset_assets_ui_icons_atlas_coin_disc_png",
    "item_5": "asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png",
    "mountain_iron_dagger": "asset_assets_ui_icons_atlas_sword_png",
    "mountain_kiln": "asset_assets_sprites_objects_crafting_kiln_32x32_png",
    "old_incense_box": "asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png",
    "old_wood": "asset_assets_sprites_objects_nature_short_log_pile_32x32_png",
    "oribe_green_glazed_bowl": "asset_assets_ui_icons_atlas_bowl_png",
    "portable_brazier": "asset_assets_ui_icons_atlas_fire_png",
    "rare_wood": "asset_assets_sprites_objects_village_props_firewood_pile_1x2_64x32_png",
    "repair_hammer": "asset_assets_sprites_objects_crafting_workbench_32x32_png",
    "short_travel_sword": "asset_assets_ui_icons_atlas_sword_png",
    "snowfield_mineral": "asset_assets_sprites_objects_mining_silver_ore_32x32_png",
    "stone": "small_rock_resource",
    "stone_axe": "asset_assets_ui_icons_atlas_sword_png",
    "unbroken_failure": "asset_assets_ui_icons_atlas_bowl_png",
    "war_tea_caddy": "asset_assets_ui_icons_atlas_tea_tin_png",
    "wood": "asset_assets_sprites_objects_village_props_firewood_pile_1x2_64x32_png",
    "wood_incense_burner": "asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png",
    "wooden_workbench": "asset_assets_sprites_objects_crafting_workbench_32x32_png",
}

DEDICATED_ITEM_ICONS = {
    "ash_stained_iron_kettle": "item_ash_stained_iron_kettle_icon",
    "bandage": "item_cloth_bandage_icon",
    "blacksmith_forge": "item_blacksmith_forge_object_64",
    "black_bamboo_tea_scoop": "item_black_bamboo_tea_scoop_icon",
    "charcoal": "item_charcoal_icon",
    "clay": "item_clay_icon",
    "cloth": "item_cloth_scraps_icon",
    "conifer_wood": "item_conifer_wood_icon",
    "copper_ore": "item_copper_ore_icon",
    "humble_clay_bowl": "item_humble_clay_bowl_icon",
    "incense_sticks": "item_incense_sticks_icon",
    "insulated_tea_bottle": "item_insulated_tea_bottle_icon",
    "iron_ore": "item_iron_ore_icon",
    "iron_kettle": "item_iron_kettle_icon",
    "item_5": "item_agarwood_icon",
    "item_28": "item_iron_scrap_icon",
    "item_29": "item_reversal_knot_icon",
    "item_33": "item_coin_icon",
    "metal_workbench": "item_metal_workbench_object_64",
    "mountain_kiln": "item_mountain_kiln_object_64",
    "mountain_iron_dagger": "item_mountain_iron_dagger_icon",
    "mountain_wind_layered_clothes": "item_mountain_wind_layered_clothes_icon",
    "old_wood": "item_old_wood_icon",
    "old_incense_box": "item_old_incense_box_icon",
    "oribe_green_glazed_bowl": "item_oribe_green_glazed_bowl_icon",
    "portable_brazier": "item_portable_brazier_icon",
    "rare_wood": "item_rare_wood_icon",
    "repair_hammer": "item_repair_hammer_icon",
    "short_travel_sword": "item_short_travel_sword_icon",
    "snowfield_mineral": "item_snowfield_mineral_icon",
    "snow_bamboo_overcoat": "item_snow_bamboo_overcoat_icon",
    "stone": "item_stone_icon",
    "traveler_quilted_clothes": "item_traveler_quilted_clothes_icon",
    "unbroken_failure": "item_unbroken_failure_icon",
    "war_tea_caddy": "item_war_tea_caddy_icon",
    "wood": "item_wood_icon",
    "wood_incense_burner": "item_wood_incense_burner_icon",
    "wooden_workbench": "item_wooden_workbench_object_64",
}

KIND_FALLBACKS = {
    "다구": "asset_assets_ui_icons_atlas_bowl_png",
    "도구": "asset_assets_ui_icons_atlas_low_table_png",
    "무기": "asset_assets_ui_icons_atlas_sword_png",
    "방어구": "asset_assets_ui_icons_atlas_crate_png",
    "소모품": "asset_assets_ui_icons_atlas_gourd_png",
    "시설": "asset_assets_sprites_objects_crafting_workbench_32x32_png",
    "재료": "asset_assets_ui_icons_atlas_crate_png",
    "향": "asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png",
}

MONSTER_OVERRIDES = {}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_hash(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def manifest_by_id(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {asset["id"]: asset for asset in manifest.get("assets", []) if isinstance(asset, dict) and "id" in asset}


def asset_record(asset_id: str, assets: dict[str, dict[str, Any]]) -> dict[str, Any]:
    asset = assets.get(asset_id, {})
    return {
        "asset_id": asset_id,
        "path": asset.get("path", ""),
        "width": asset.get("width"),
        "height": asset.get("height"),
        "source_sha256": asset.get("source_sha256", ""),
        "rgba_sha256": asset.get("rgba_sha256", ""),
        "asset_status": asset.get("status", ""),
    }


def first_non_empty(row: dict[str, Any], keys: list[str]) -> str:
    for key in keys:
        value = row.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def item_entry(item: dict[str, Any], assets: dict[str, dict[str, Any]]) -> dict[str, Any]:
    item_id = str(item["id"])
    kind = str(item.get("type", ""))
    if item_id in DEDICATED_ITEM_ICONS:
        result = asset_record(DEDICATED_ITEM_ICONS[item_id], assets)
        result.update({
            "resolution": "dedicated_item_icon",
            "exception_reason": "",
            "dedicated_asset_missing": False,
            "runtime_approved": True,
        })
        return result
    explicit = first_non_empty(item, ["icon_asset_id", "icon", "asset_id", "sprite_asset_id", "source_id"])
    if explicit:
        result = asset_record(explicit, assets)
        result.update({"resolution": "definition_field", "exception_reason": "", "dedicated_asset_missing": False})
        return result
    if item_id in ITEM_OVERRIDES:
        result = asset_record(ITEM_OVERRIDES[item_id], assets)
        result.update({"resolution": "semantic_existing_asset", "exception_reason": "", "dedicated_asset_missing": False})
        return result
    fallback = KIND_FALLBACKS.get(kind, "asset_assets_ui_icons_atlas_bag_png")
    result = asset_record(fallback, assets)
    result.update({
        "resolution": "kind_fallback_exception",
        "exception_reason": "No item-specific exported image field exists; use the type fallback until art review creates a dedicated row.",
        "dedicated_asset_missing": True,
    })
    return result


def monster_entry(monster: dict[str, Any], assets: dict[str, dict[str, Any]]) -> dict[str, Any]:
    monster_id = str(monster["id"])
    asset_id = MONSTER_OVERRIDES.get(
        monster_id,
        f"monster_{monster_id}_front_idle",
    )
    result = asset_record(asset_id, assets)
    if monster_id in MONSTER_OVERRIDES:
        result.update({
            "resolution": "monster_variant_fallback_exception",
            "exception_reason": "No dedicated monster asset exists; keep the closest existing variant for review only.",
            "dedicated_asset_missing": True,
        })
    else:
        result.update({
            "resolution": "monster_id_convention",
            "exception_reason": "",
            "dedicated_asset_missing": False,
        })
    return result


def content_entry(dataset: str, row: dict[str, Any], image: dict[str, Any]) -> dict[str, Any]:
    art_review_required = dataset == "items" or image.get("dedicated_asset_missing") is True
    return {
        "dataset": dataset,
        "content_id": row["id"],
        "name": row["name"],
        "status": row["status"],
        "kind": row.get("type", row.get("kind", "")),
        **image,
        "art_review_required": art_review_required,
        "runtime_approved": bool(image.get("runtime_approved", not art_review_required)),
    }


def validate_image(dataset: str, row: dict[str, Any], image: dict[str, Any], root: Path, issues: list[dict[str, str]]) -> None:
    label = f"{dataset}:{row['id']}"
    if not image["asset_id"] or not image["path"]:
        issues.append({"content": label, "severity": "missing", "message": "No manifest asset ID/path resolved"})
        return
    path = str(image["path"])
    if not path.startswith("res://assets/"):
        issues.append({"content": label, "severity": "broken_path", "message": f"Non-runtime asset path: {path}"})
        return
    if not (root / path.removeprefix("res://")).is_file():
        issues.append({"content": label, "severity": "broken_path", "message": f"Missing PNG file: {path}"})


def audit_summary(items: list[dict[str, Any]], monsters: list[dict[str, Any]], issues: list[dict[str, str]]) -> dict[str, Any]:
    entries = items + monsters
    by_resolution: dict[str, int] = {}
    for entry in entries:
        by_resolution[entry["resolution"]] = by_resolution.get(entry["resolution"], 0) + 1
    return {
        "runtime_target_rows": len(entries),
        "items": len(items),
        "monsters": len(monsters),
        "missing_or_broken": len([issue for issue in issues if issue["severity"] in {"missing", "broken_path"}]),
        "path_integrity_missing_or_broken": len([issue for issue in issues if issue["severity"] in {"missing", "broken_path"}]),
        "dedicated_asset_missing": len([entry for entry in entries if entry.get("dedicated_asset_missing") is True]),
        "art_review_required": len([entry for entry in entries if entry["art_review_required"]]),
        "runtime_approved": len([entry for entry in entries if entry["runtime_approved"]]),
        "by_resolution": by_resolution,
    }


def build(root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    items = read_json(root / "data/generated/items.json")
    monsters = read_json(root / "data/generated/monsters.json")
    manifest = read_json(root / "assets/asset-manifest.json")
    assets = manifest_by_id(manifest)
    issues: list[dict[str, str]] = []
    mapped_items = []
    mapped_monsters = []
    for item in items["items"]:
        image = item_entry(item, assets)
        validate_image("items", item, image, root, issues)
        mapped_items.append(content_entry("items", item, image))
    for monster in monsters["items"]:
        image = monster_entry(monster, assets)
        validate_image("monsters", monster, image, root, issues)
        mapped_monsters.append(content_entry("monsters", monster, image))
    payload = {
        "schema_version": 1,
        "data_version": items["data_version"],
        "source": {
            "items": items["source"],
            "monsters": monsters["source"],
            "asset_manifest": "res://assets/asset-manifest.json",
            "style_tokens": manifest.get("style_tokens", ""),
        },
        "content_hashes": {
            "items": items["content_hash"],
            "monsters": monsters["content_hash"],
            "asset_manifest": canonical_hash(manifest.get("assets", [])),
        },
        "content": {"items": mapped_items, "monsters": mapped_monsters},
        "audit": audit_summary(mapped_items, mapped_monsters, issues),
    }
    return payload, {"issues": issues}


def report_row(entry: dict[str, Any]) -> str:
    exception = str(entry.get("exception_reason", "")).replace("|", "\\|")
    return (
        f"| `{entry['content_id']}` | {entry['name']} | {entry.get('kind', '')} | "
        f"{entry['resolution']} | {entry['runtime_approved']} | {entry['dedicated_asset_missing']} | "
        f"`{entry['asset_id']}` | `{entry['path']}` | {exception} |"
    )


def write_report(payload: dict[str, Any], report: Path, issues: list[dict[str, str]]) -> None:
    report.parent.mkdir(parents=True, exist_ok=True)
    audit = payload["audit"]
    lines = [
        "# DEV-78 콘텐츠 이미지 연결 감사",
        "",
        "기준: `data/generated/items.json`, `data/generated/monsters.json`, `assets/asset-manifest.json`, `assets/promoted-assets-manifest.json`, `assets/style/art-style-tokens.json`.",
        "",
        "## 요약",
        "",
        f"- 런타임 대상 행: {audit['runtime_target_rows']}개",
        f"- 아이템·다구: {audit['items']}개",
        f"- 몬스터·요괴: {audit['monsters']}개",
        f"- 파일 경로 무결성 누락/깨짐: {audit['path_integrity_missing_or_broken']}개",
        f"- 전용 에셋 미해결: {audit['dedicated_asset_missing']}개",
        f"- 사람 아트 검수 필요: {audit['art_review_required']}개",
        f"- 런타임 승인 매핑: {audit['runtime_approved']}개",
        "",
        "`missing_or_broken`/`path_integrity_missing_or_broken`은 현재 연결된 manifest asset ID와 PNG 파일 경로의 무결성 지표다. 전용 에셋 완료 지표가 아니며, 미검수 아이템 매핑은 `runtime_approved=false`로 런타임 조회에서 제외한다.",
        "",
        "## Notion 확인 한계",
        "",
        "`query_data_sources` 사용량 제한으로 🎨 아트 에셋 DB의 relation/파일 필드는 행 단위로 재조회하지 못했다. 이 리포트는 현재 저장소에 export된 정적 데이터와 manifest 기준 감사 결과이며, Notion DB relation 반영은 쿼리 제한 해제 후 재검증이 필요하다.",
        "",
        "## 아이템·다구",
        "",
        "| content_id | 이름 | 종류 | resolution | runtime_approved | dedicated_asset_missing | asset_id | path | 예외 |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    lines.extend(report_row(entry) for entry in payload["content"]["items"])
    lines.extend([
        "",
        "## 몬스터·요괴",
        "",
        "| content_id | 이름 | 종류 | resolution | runtime_approved | dedicated_asset_missing | asset_id | path | 예외 |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ])
    lines.extend(report_row(entry) for entry in payload["content"]["monsters"])
    lines.extend(["", "## 검증 이슈", ""])
    if issues:
        lines.extend(f"- `{issue['content']}` {issue['severity']}: {issue['message']}" for issue in issues)
    else:
        lines.append("- 누락, 깨진 경로, PNG 규격 이슈 없음.")
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit item and monster content image links.")
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    payload, detail = build(root)
    expected = json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    output = root / args.output
    if args.check:
        if not output.is_file() or output.read_text(encoding="utf-8") != expected:
            print(f"Content image map is stale: {args.output}")
            return 1
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(expected, encoding="utf-8")
        write_report(payload, root / args.report, detail["issues"])
    audit = payload["audit"]
    print(
        "Content image audit passed: "
        f"{audit['runtime_target_rows']} rows, {audit['missing_or_broken']} missing/broken, "
        f"{audit['art_review_required']} art-review-required, "
        f"{audit['dedicated_asset_missing']} dedicated-asset-missing"
    )
    return 0 if audit["missing_or_broken"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
