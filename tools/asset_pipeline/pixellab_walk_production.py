#!/usr/bin/env python3
"""Produce DEV-62 PixelLab walking spritesheets from approved 4-dir frames.

The script is intentionally resume-safe: existing raw direction frames and final
sheets are validated before any PixelLab call is made.
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import hashlib
import json
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
RAW_ROOT = ROOT / "assets/source/imagegen/pixellab-character-walk-20260902/raw"
METADATA_PATH = ROOT / "assets/sprites/characters/walk-production-metadata.json"
API_BASE = "https://api.pixellab.ai/v2"
FRAME_SIZE = 32
FRAMES_PER_DIRECTION = 8
DIRECTIONS = ("south", "west", "east", "north")
DIRECTION_TO_SOURCE = {
    "south": "front",
    "west": "left",
    "east": "right",
    "north": "back",
}
ART_IDS = {
    "CHR-1": "ART-14",
    "CHR-2": "ART-15",
    "CHR-3": "ART-16",
    "CHR-4": "ART-17",
    "CHR-5": "ART-18",
    "CHR-6": "ART-19",
    "CHR-7": "ART-20",
    "CHR-8": "ART-21",
    "CHR-9": "ART-22",
}


@dataclass(frozen=True)
class CharacterSpec:
    character_id: str
    slug: str
    name: str
    directory: Path
    final_name: str
    identity: str
    seed_base: int
    source_pattern: str

    @property
    def final_path(self) -> Path:
        return self.directory / self.final_name

    def source_path(self, direction: str) -> Path:
        source_direction = DIRECTION_TO_SOURCE[direction]
        return self.directory / self.source_pattern.format(direction=source_direction)


CHARACTERS = [
    CharacterSpec(
        "CHR-1",
        "kitsune_father",
        "Kitsune father",
        ROOT / "assets/sprites/characters/family/chr-1-kitsune-father",
        "kitsune_father_walk_4dir_8f_32x32.png",
        "tea-loving kitsune father, warm older fox-spirit silhouette, calm parental presence, tea vessel cue",
        620100,
        "kitsune_father_{direction}_32x32.png",
    ),
    CharacterSpec(
        "CHR-2",
        "wasteland_daimyo",
        "Wasteland daimyo",
        ROOT / "assets/sprites/characters/bosses/chr-2-wasteland-daimyo",
        "wasteland_daimyo_walk_4dir_8f_32x32.png",
        "imposing two-headed wasteland daimyo, simple red and gold daimyo clothing, fixed sword and tea ware",
        620200,
        "wasteland_daimyo_{direction}_32x32.png",
    ),
    CharacterSpec(
        "CHR-3",
        "furuta_oribe",
        "Furuta Oribe",
        ROOT / "assets/sprites/characters/rivals/chr-3-furuta-oribe",
        "furuta_oribe_walk_4dir_8f_32x32.png",
        "Furuta Oribe tea rival, asymmetric clothing and pose, green tea ware cue, imperfect wabi-sabi silhouette",
        620300,
        "furuta_oribe_{direction}_32x32.png",
    ),
    CharacterSpec(
        "CHR-4",
        "snow_monk",
        "Snow monk",
        ROOT / "assets/sprites/characters/bosses/chr-4-snow-monk",
        "snow_monk_walk_4dir_8f_32x32.png",
        "snow-country monk boss, shaved simple head, long robe and beads, slow grounded walking posture",
        620400,
        "snow_monk_{direction}_32x32.png",
    ),
    CharacterSpec(
        "CHR-5",
        "sen_rikyu",
        "Sen Rikyu",
        ROOT / "assets/sprites/characters/bosses/chr-5-sen-rikyu",
        "sen_rikyu_walk_4dir_8f_32x32.png",
        "small elder tea master Sen Rikyu, black hat, dark modest clothes, restrained non-villain silhouette",
        620500,
        "sen_rikyu_{direction}_32x32.png",
    ),
    CharacterSpec(
        "CHR-6",
        "yokai_tea_master",
        "Yokai tea master",
        ROOT / "assets/sprites/characters/bosses/chr-6-yokai-tea-master",
        "yokai_tea_master_walk_4dir_8f_32x32.png",
        "humanoid minimal yokai tea master, old cup, tea tin, incense cue, uncanny but readable silhouette",
        620600,
        "yokai_tea_master_{direction}_32x32.png",
    ),
    CharacterSpec(
        "CHR-7",
        "mountain_potter",
        "Mountain potter",
        ROOT / "assets/sprites/characters/bosses/chr-7-mountain-potter",
        "mountain_potter_walk_4dir_8f_32x32.png",
        "mountain potter boss, dirty work clothes, rolled sleeves, head cloth, hammer and tools fixed",
        620700,
        "mountain_potter_{direction}_32x32.png",
    ),
    CharacterSpec(
        "CHR-8",
        "fox_samurai",
        "Muchau fox samurai",
        ROOT / "assets/sprites/characters/player/chr-8-fox-samurai",
        "fox_samurai_walk_4dir_8f_32x32.png",
        "Muchau, human and kitsune hybrid, large red fox ears and tail, small sword at one hip, tea tin and tea ware at other hip",
        620800,
        "fox_samurai_{direction}_idle_32x32.png",
    ),
    CharacterSpec(
        "CHR-9",
        "wandering_tea_merchant",
        "Wandering tea merchant",
        ROOT / "assets/sprites/characters/npcs/chr-9-wandering-tea-merchant",
        "wandering_tea_merchant_walk_4dir_8f_32x32.png",
        "wandering tea merchant NPC, travel pack and tea goods fixed, modest road-worn silhouette",
        620900,
        "wandering_tea_merchant_{direction}_32x32.png",
    ),
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--character", action="append", choices=[c.character_id for c in CHARACTERS])
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--without-last-frame", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--poll-seconds", type=int, default=5)
    args = parser.parse_args()

    selected = [c for c in CHARACTERS if not args.character or c.character_id in args.character]
    if not selected:
        raise SystemExit("No characters selected.")

    env = load_env()
    base_url = env.get("PIXELLAB_API_BASE_URL", API_BASE).rstrip("/")
    api_key = env.get("PIXELLAB_API_KEY")
    if not api_key and not args.dry_run:
        raise SystemExit("PIXELLAB_API_KEY is missing from .env.local, .env, or environment.")

    RAW_ROOT.mkdir(parents=True, exist_ok=True)
    metadata = load_metadata()
    metadata.setdefault("schema_version", 1)
    metadata.setdefault("task_id", "DEV-62")
    metadata.setdefault("official_schema_checked_at", "2026-09-02")
    metadata.setdefault("endpoint", "/animate-with-text-v3")
    metadata.setdefault("grid", {
        "canvas_px": [256, 128],
        "cell_px": [32, 32],
        "directions": list(DIRECTIONS),
        "frames_per_direction": FRAMES_PER_DIRECTION,
        "total_frames": FRAMES_PER_DIRECTION * len(DIRECTIONS),
    })
    metadata.setdefault("characters", {})

    style = json.loads((ROOT / "assets/style/art-style-tokens.json").read_text(encoding="utf-8"))
    positive_tokens = style["prompt_assembly"]["default_positive_prefix"]
    negative_tokens = style["prompt_assembly"]["default_negative_suffix"]

    source_hashes_before = collect_source_hashes(selected)
    validate_sources(selected)

    if args.dry_run:
        for character in selected:
            print(f"DRY {character.character_id} {character.final_path.relative_to(ROOT)}")
            for direction in DIRECTIONS:
                print(f"DRY source {direction}: {character.source_path(direction).relative_to(ROOT)}")
        return 0

    print("Checking PixelLab /balance without printing account amounts.")
    request_json(base_url, "/balance", api_key, method="GET")

    for character in selected:
        produce_character(
            character,
            base_url,
            api_key,
            metadata,
            positive_tokens,
            negative_tokens,
            use_last_frame=not args.without_last_frame,
            force=args.force,
            poll_seconds=max(args.poll_seconds, 5),
        )
        save_metadata(metadata)

    source_hashes_after = collect_source_hashes(selected)
    if source_hashes_before != source_hashes_after:
        raise SystemExit("Source reference hashes changed during production; refusing to continue.")

    metadata["source_hash_immutability"] = {
        "checked_at": utc_now(),
        "status": "passed",
        "sha256": source_hashes_after,
    }
    save_metadata(metadata)
    validate_outputs(selected, metadata)
    save_metadata(metadata)
    print(f"Completed {len(selected)} character walk sheets.")
    return 0


def produce_character(
    character: CharacterSpec,
    base_url: str,
    api_key: str,
    metadata: dict[str, Any],
    positive_tokens: list[str],
    negative_tokens: list[str],
    use_last_frame: bool,
    force: bool,
    poll_seconds: int,
) -> None:
    character_raw = RAW_ROOT / character.character_id.lower()
    character_raw.mkdir(parents=True, exist_ok=True)
    character_meta = metadata["characters"].setdefault(character.character_id, {})
    character_meta.update({
        "art_id": ART_IDS[character.character_id],
        "name": character.name,
        "source_directory": str(character.directory.relative_to(ROOT)),
        "final_path": str(character.final_path.relative_to(ROOT)),
        "directions": list(DIRECTIONS),
        "frames_per_direction": FRAMES_PER_DIRECTION,
        "used_last_frame": use_last_frame,
    })
    character_meta.setdefault("jobs", {})
    if character.final_path.exists() and not force:
        character_meta["final_sha256"] = sha256_file(character.final_path)
        character_meta["validation"] = validate_sheet(character.final_path)
        character_meta["motion_metrics"] = collect_motion_metrics(character, character_raw)
        print(f"SKIP final exists {character.character_id}: {character.final_path.relative_to(ROOT)}")
        return

    print(f"Producing {character.character_id} {character.slug}")
    futures: dict[concurrent.futures.Future[dict[str, Any]], str] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        for direction in DIRECTIONS:
            futures[executor.submit(
                produce_direction,
                character,
                direction,
                base_url,
                api_key,
                positive_tokens,
                negative_tokens,
                use_last_frame,
                character_raw,
                poll_seconds,
            )] = direction
        for future in concurrent.futures.as_completed(futures):
            direction = futures[future]
            character_meta["jobs"][direction] = future.result()
            save_metadata(metadata)

    frames_by_direction = {}
    for direction in DIRECTIONS:
        frames_by_direction[direction] = [
            character_raw / direction / f"frame_{index:02d}.png"
            for index in range(FRAMES_PER_DIRECTION)
        ]
    compose_sheet(character.final_path, frames_by_direction)
    make_contact_sheet(character.final_path, character_raw / "contact_1x.png", scale=1)
    make_contact_sheet(character.final_path, character_raw / "contact_2x.png", scale=2)
    make_loop_gif(character_raw, character_raw / "loop_preview.gif")
    character_meta["final_sha256"] = sha256_file(character.final_path)
    character_meta["raw_contact_sheets"] = [
        str((character_raw / "contact_1x.png").relative_to(ROOT)),
        str((character_raw / "contact_2x.png").relative_to(ROOT)),
    ]
    character_meta["raw_loop_gif"] = str((character_raw / "loop_preview.gif").relative_to(ROOT))
    character_meta["validation"] = validate_sheet(character.final_path)
    character_meta["motion_metrics"] = collect_motion_metrics(character, character_raw)
    print(f"WROTE {character.final_path.relative_to(ROOT)}")


def produce_direction(
    character: CharacterSpec,
    direction: str,
    base_url: str,
    api_key: str,
    positive_tokens: list[str],
    negative_tokens: list[str],
    use_last_frame: bool,
    character_raw: Path,
    poll_seconds: int,
) -> dict[str, Any]:
    direction_raw = character_raw / direction
    direction_raw.mkdir(parents=True, exist_ok=True)
    existing_frames = [direction_raw / f"frame_{index:02d}.png" for index in range(FRAMES_PER_DIRECTION)]
    if all(path.exists() for path in existing_frames):
        validate_frames(existing_frames)
        return {
            "status": "reused_raw_frames",
            "direction": direction,
            "frame_paths": [str(path.relative_to(ROOT)) for path in existing_frames],
            "source_path": str(character.source_path(direction).relative_to(ROOT)),
            "source_sha256": sha256_file(character.source_path(direction)),
        }

    prompt = build_prompt(character, direction, positive_tokens, negative_tokens)
    seed = character.seed_base + DIRECTIONS.index(direction)
    source_path = character.source_path(direction)
    request_body: dict[str, Any] = {
        "first_frame": {"base64": image_as_data_uri(source_path)},
        "action": prompt,
        "frame_count": FRAMES_PER_DIRECTION,
        "seed": seed,
        "no_background": True,
        "drift_threshold": 0.08,
        "enhance_prompt": False,
    }
    if use_last_frame:
        request_body["last_frame"] = {"base64": image_as_data_uri(source_path)}

    redacted_summary = {
        "endpoint": "/animate-with-text-v3",
        "direction": direction,
        "frame_count": FRAMES_PER_DIRECTION,
        "seed": seed,
        "no_background": True,
        "drift_threshold": 0.08,
        "enhance_prompt": False,
        "last_frame": "same_as_first_frame" if use_last_frame else None,
        "prompt": prompt,
        "source_path": str(source_path.relative_to(ROOT)),
        "source_sha256": sha256_file(source_path),
    }
    (direction_raw / "request_redacted.json").write_text(
        json.dumps(redacted_summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    job_file = direction_raw / "job_redacted.json"
    if job_file.exists():
        job_summary = json.loads(job_file.read_text(encoding="utf-8"))
        job_id = job_summary["background_job_id"]
        print(f"RESUME JOB {character.character_id} {direction} {job_id}")
    else:
        response = request_json(base_url, "/animate-with-text-v3", api_key, request_body, method="POST")
        job_id = response["background_job_id"]
        job_file.write_text(
            json.dumps({"background_job_id": job_id, "initial_status": response.get("status")}, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"JOB {character.character_id} {direction} {job_id}")
    job = poll_job(base_url, api_key, job_id, poll_seconds)
    frames = extract_frame_images(job.get("last_response") or {})
    returned_count = len(frames)
    if returned_count < FRAMES_PER_DIRECTION:
        raise RuntimeError(f"{character.character_id} {direction} returned {returned_count} frames")
    returned_raw = direction_raw / "returned_frames"
    returned_raw.mkdir(parents=True, exist_ok=True)
    for index, image in enumerate(frames):
        image.convert("RGBA").save(returned_raw / f"returned_frame_{index:02d}.png")
    trim_note = None
    if returned_count > FRAMES_PER_DIRECTION:
        trim_note = {
            "type": "trimmed_extra_returned_frames",
            "returned": returned_count,
            "selected": FRAMES_PER_DIRECTION,
            "reason": "PixelLab returned more frames than requested frame_count=8; kept the first eight frames for the DEV-62 fixed grid.",
        }
        frames = frames[:FRAMES_PER_DIRECTION]
    frame_paths = []
    corrections = []
    if trim_note:
        corrections.append(trim_note)
    for index, image in enumerate(frames):
        image = image.convert("RGBA")
        if image.size != (FRAME_SIZE, FRAME_SIZE):
            corrections.append({"frame": index, "from": list(image.size), "to": [FRAME_SIZE, FRAME_SIZE]})
            image = image.resize((FRAME_SIZE, FRAME_SIZE), Image.Resampling.NEAREST)
        path = direction_raw / f"frame_{index:02d}.png"
        image.save(path)
        frame_paths.append(path)
    validate_frames(frame_paths)
    return {
        "status": "completed",
        "background_job_id": job_id,
        "direction": direction,
        "seed": seed,
        "prompt": prompt,
        "source_path": str(source_path.relative_to(ROOT)),
        "source_sha256": sha256_file(source_path),
        "image_source": "quantized_images" if (job.get("last_response") or {}).get("quantized_images") else "images",
        "frame_paths": [str(path.relative_to(ROOT)) for path in frame_paths],
        "frame_sha256": [sha256_file(path) for path in frame_paths],
        "corrections": corrections,
        "validation": {"status": "passed", "frame_count": len(frame_paths), "rgba": True, "size": [32, 32]},
    }


def build_prompt(
    character: CharacterSpec,
    direction: str,
    positive_tokens: list[str],
    negative_tokens: list[str],
) -> str:
    direction_label = {
        "south": "walking south, facing directly forward toward camera",
        "west": "walking west, strict left cardinal sprite, no 3/4 turn",
        "east": "walking east, strict right cardinal sprite, no 3/4 turn",
        "north": "walking north, back-facing cardinal sprite, no 3/4 turn",
    }[direction]
    positive = ", ".join(positive_tokens[:7])
    negative = ", ".join(negative_tokens[:10])
    prompt = (
        f"{direction_label}. 8-frame seamless walk cycle for one 32x32 pixel character. "
        f"{character.identity}. Gentle readable alternating footsteps, subtle 1px body bob, "
        "ears/tail/weapon/tea ware stay attached and keep the same silhouette; preserve the first frame identity and palette. "
        f"{positive}. Transparent background, no shadow plate, no extra character, no text. "
        "Low saturation, clear ink outline, no anti-aliasing, square-tile low top-down cardinal view. "
        f"Avoid: {negative}, side-scrolling scene, isometric, three-quarter view."
    )
    if len(prompt) > 1000:
        raise RuntimeError(f"Prompt too long for {character.character_id} {direction}: {len(prompt)}")
    return prompt


def compose_sheet(final_path: Path, frames_by_direction: dict[str, list[Path]]) -> None:
    final_path.parent.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (FRAME_SIZE * FRAMES_PER_DIRECTION, FRAME_SIZE * len(DIRECTIONS)), (0, 0, 0, 0))
    for row, direction in enumerate(DIRECTIONS):
        for column, path in enumerate(frames_by_direction[direction]):
            image = Image.open(path).convert("RGBA")
            sheet.paste(image, (column * FRAME_SIZE, row * FRAME_SIZE))
    sheet.save(final_path)


def make_contact_sheet(sheet_path: Path, output_path: Path, scale: int) -> None:
    image = Image.open(sheet_path).convert("RGBA")
    if scale != 1:
        image = image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
    image.save(output_path)


def make_loop_gif(character_raw: Path, output_path: Path) -> None:
    rows = []
    for direction in DIRECTIONS:
        frames = [
            Image.open(character_raw / direction / f"frame_{index:02d}.png").convert("RGBA")
            for index in range(FRAMES_PER_DIRECTION)
        ]
        rows.append(frames)
    preview_frames = []
    for index in range(FRAMES_PER_DIRECTION):
        canvas = Image.new("RGBA", (FRAME_SIZE * len(DIRECTIONS) * 2, FRAME_SIZE * 2), (0, 0, 0, 0))
        for column, direction_frames in enumerate(rows):
            frame = direction_frames[index].resize((FRAME_SIZE * 2, FRAME_SIZE * 2), Image.Resampling.NEAREST)
            canvas.paste(frame, (column * FRAME_SIZE * 2, 0), frame)
        preview_frames.append(canvas)
    preview_frames[0].save(
        output_path,
        save_all=True,
        append_images=preview_frames[1:],
        duration=110,
        loop=0,
        disposal=2,
    )


def extract_frame_images(last_response: dict[str, Any]) -> list[Image.Image]:
    payloads = last_response.get("quantized_images") or last_response.get("images") or []
    images = []
    for payload in payloads:
        images.append(decode_image_payload(payload))
    return images


def decode_image_payload(payload: Any) -> Image.Image:
    if isinstance(payload, dict):
        for key in ("base64", "image", "url"):
            if key in payload:
                return decode_image_payload(payload[key])
        raise RuntimeError(f"Unknown image payload keys: {sorted(payload.keys())}")
    if not isinstance(payload, str):
        raise RuntimeError(f"Unsupported image payload type: {type(payload)!r}")
    if payload.startswith("http://") or payload.startswith("https://"):
        with urllib.request.urlopen(payload, timeout=60) as response:
            return Image.open(BytesIO(response.read())).convert("RGBA")
    if "," in payload and payload[:64].startswith("data:image"):
        payload = payload.split(",", 1)[1]
    return Image.open(BytesIO(base64.b64decode(payload))).convert("RGBA")


def poll_job(base_url: str, api_key: str, job_id: str, poll_seconds: int) -> dict[str, Any]:
    deadline = time.monotonic() + 900
    while True:
        job = request_json(base_url, f"/background-jobs/{job_id}", api_key, method="GET")
        status = job.get("status")
        print(f"POLL {job_id} {status}")
        if status == "completed":
            return job
        if status == "failed":
            raise RuntimeError(f"PixelLab job failed: {job_id}")
        if time.monotonic() > deadline:
            raise TimeoutError(f"PixelLab job timeout: {job_id}")
        time.sleep(poll_seconds)


def request_json(
    base_url: str,
    path: str,
    api_key: str,
    body: dict[str, Any] | None = None,
    method: str = "POST",
    attempts: int = 4,
) -> dict[str, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        request = urllib.request.Request(
            f"{base_url}{path}",
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            last_error = exc
            retryable = exc.code in {429, 500, 502, 503, 504}
            body_text = exc.read().decode("utf-8", errors="replace")[:240]
            if not retryable or attempt == attempts:
                raise RuntimeError(f"PixelLab HTTP {exc.code} for {path}: {body_text}") from exc
            wait = min(30, 3 * attempt)
            print(f"RETRY HTTP {exc.code} {path} attempt {attempt}/{attempts}; waiting {wait}s")
            time.sleep(wait)
        except (urllib.error.URLError, TimeoutError) as exc:
            last_error = exc
            if attempt == attempts:
                raise
            wait = min(30, 3 * attempt)
            print(f"RETRY network {path} attempt {attempt}/{attempts}; waiting {wait}s")
            time.sleep(wait)
    raise RuntimeError(f"PixelLab request failed: {last_error}")


def validate_sources(characters: list[CharacterSpec]) -> None:
    for character in characters:
        for direction in DIRECTIONS:
            path = character.source_path(direction)
            if not path.exists():
                raise FileNotFoundError(path)
            image = Image.open(path)
            if image.size != (FRAME_SIZE, FRAME_SIZE) or image.mode not in {"RGBA", "LA", "P"}:
                raise RuntimeError(f"Invalid source {path}: mode={image.mode} size={image.size}")
            if image.convert("RGBA").getchannel("A").getbbox() is None:
                raise RuntimeError(f"Source has no visible alpha pixels: {path}")


def validate_outputs(characters: list[CharacterSpec], metadata: dict[str, Any]) -> None:
    output_validation = {}
    for character in characters:
        character_raw = RAW_ROOT / character.character_id.lower()
        output_validation[character.character_id] = {
            "sheet": validate_sheet(character.final_path),
            "motion_metrics": collect_motion_metrics(character, character_raw),
        }
    metadata["output_validation"] = {"checked_at": utc_now(), "status": "passed", "characters": output_validation}


def collect_motion_metrics(character: CharacterSpec, character_raw: Path) -> dict[str, Any]:
    metrics: dict[str, Any] = {
        "status": "passed",
        "minimum_unique_frames_per_direction": 4,
        "directions": {},
        "risks": [],
    }
    for direction in DIRECTIONS:
        frame_paths = [character_raw / direction / f"frame_{index:02d}.png" for index in range(FRAMES_PER_DIRECTION)]
        if not all(path.exists() for path in frame_paths):
            raise RuntimeError(f"Missing raw frames for motion metrics: {character.character_id} {direction}")
        validate_frames(frame_paths)
        hashes = [sha256_file(path) for path in frame_paths]
        frame0 = Image.open(frame_paths[0]).convert("RGBA")
        frame7 = Image.open(frame_paths[-1]).convert("RGBA")
        seam = compare_frames(frame0, frame7)
        unique_count = len(set(hashes))
        duplicate_0_7 = hashes[0] == hashes[-1]
        metrics["directions"][direction] = {
            "unique_frame_count": unique_count,
            "unique_frame_minimum_met": unique_count >= 4,
            "frame_0_7_exact_duplicate": duplicate_0_7,
            "loop_seam_pixel_difference": seam,
            "frame_sha256": hashes,
        }
        if unique_count < 4:
            metrics["status"] = "risk"
            metrics["risks"].append({
                "character_id": character.character_id,
                "direction": direction,
                "type": "low_unique_frame_count",
                "unique_frame_count": unique_count,
            })
        if duplicate_0_7:
            metrics["risks"].append({
                "character_id": character.character_id,
                "direction": direction,
                "type": "frame_0_7_exact_duplicate",
            })
    return metrics


def compare_frames(left: Image.Image, right: Image.Image) -> dict[str, Any]:
    if left.size != right.size:
        raise RuntimeError(f"Cannot compare frames with different sizes: {left.size} != {right.size}")
    differing_pixels = 0
    channel_abs_delta_sum = 0
    max_channel_delta = 0
    for left_pixel, right_pixel in zip(left.getdata(), right.getdata(), strict=True):
        deltas = [abs(int(a) - int(b)) for a, b in zip(left_pixel, right_pixel, strict=True)]
        if any(delta != 0 for delta in deltas):
            differing_pixels += 1
            channel_abs_delta_sum += sum(deltas)
            max_channel_delta = max(max_channel_delta, max(deltas))
    return {
        "differing_pixels": differing_pixels,
        "total_pixels": left.width * left.height,
        "channel_abs_delta_sum": channel_abs_delta_sum,
        "max_channel_delta": max_channel_delta,
    }


def validate_frames(paths: list[Path]) -> None:
    if len(paths) != FRAMES_PER_DIRECTION:
        raise RuntimeError(f"Expected {FRAMES_PER_DIRECTION} frames, got {len(paths)}")
    for path in paths:
        image = Image.open(path).convert("RGBA")
        if image.size != (FRAME_SIZE, FRAME_SIZE):
            raise RuntimeError(f"Invalid frame size {path}: {image.size}")
        if image.getchannel("A").getbbox() is None:
            raise RuntimeError(f"Frame has no visible alpha pixels: {path}")


def validate_sheet(path: Path) -> dict[str, Any]:
    image = Image.open(path).convert("RGBA")
    if image.size != (FRAME_SIZE * FRAMES_PER_DIRECTION, FRAME_SIZE * len(DIRECTIONS)):
        raise RuntimeError(f"Invalid sheet size {path}: {image.size}")
    if image.getchannel("A").getbbox() is None:
        raise RuntimeError(f"Sheet has no visible alpha pixels: {path}")
    return {
        "status": "passed",
        "size": list(image.size),
        "mode": "RGBA",
        "directions": len(DIRECTIONS),
        "frames_per_direction": FRAMES_PER_DIRECTION,
        "total_frames": FRAMES_PER_DIRECTION * len(DIRECTIONS),
        "sha256": sha256_file(path),
    }


def image_as_data_uri(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect_source_hashes(characters: list[CharacterSpec]) -> dict[str, dict[str, str]]:
    return {
        character.character_id: {
            direction: sha256_file(character.source_path(direction))
            for direction in DIRECTIONS
        }
        for character in characters
    }


def load_metadata() -> dict[str, Any]:
    if METADATA_PATH.exists():
        return json.loads(METADATA_PATH.read_text(encoding="utf-8"))
    return {"created_at": utc_now()}


def save_metadata(metadata: dict[str, Any]) -> None:
    metadata["updated_at"] = utc_now()
    METADATA_PATH.parent.mkdir(parents=True, exist_ok=True)
    METADATA_PATH.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_env() -> dict[str, str]:
    env = {}
    for env_path in (ROOT / ".env.local", ROOT / ".env"):
        if env_path.exists():
            env.update(parse_dotenv(env_path.read_text(encoding="utf-8")))
    env.update(os.environ)
    return env


def parse_dotenv(contents: str) -> dict[str, str]:
    result = {}
    for raw_line in contents.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip().strip("\"'")
    return result


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
