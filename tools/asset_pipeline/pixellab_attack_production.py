#!/usr/bin/env python3
"""Produce the CHR-8 PixelLab attack spritesheet from approved idle frames."""

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
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
RAW_ROOT = ROOT / "assets/source/imagegen/pixellab-character-attack-20260903/raw/chr-8"
METADATA_PATH = ROOT / "assets/sprites/characters/attack-production-metadata.json"
FINAL_PATH = ROOT / "assets/sprites/characters/player/chr-8-fox-samurai/fox_samurai_attack_4dir_8f_32x32.png"
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
SOURCE_PATTERN = "assets/sprites/characters/player/chr-8-fox-samurai/fox_samurai_{direction}_idle_32x32.png"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--poll-seconds", type=int, default=5)
    args = parser.parse_args()

    style = json.loads((ROOT / "assets/style/art-style-tokens.json").read_text(encoding="utf-8"))
    positive_tokens = style["prompt_assembly"]["default_positive_prefix"]
    negative_tokens = style["prompt_assembly"]["default_negative_suffix"]
    source_hashes_before = collect_source_hashes()
    validate_sources()

    metadata = load_metadata()
    metadata.update({
        "schema_version": 1,
        "task": "fox_samurai_attack_animation",
        "notion_art_asset_page": "https://app.notion.com/p/3d0373699e6681df9dc7e74bcdf1e036",
        "official_schema_checked_at": "2026-09-03",
        "endpoint": "/animate-with-text-v3",
        "grid": {
            "canvas_px": [256, 128],
            "cell_px": [32, 32],
            "directions": list(DIRECTIONS),
            "frames_per_direction": FRAMES_PER_DIRECTION,
            "total_frames": FRAMES_PER_DIRECTION * len(DIRECTIONS),
        },
        "source_hashes": source_hashes_before,
    })

    if args.dry_run:
        print(f"DRY final {FINAL_PATH.relative_to(ROOT)}")
        for direction in DIRECTIONS:
            print(f"DRY source {direction}: {source_path(direction).relative_to(ROOT)}")
        return 0

    env = load_env()
    base_url = env.get("PIXELLAB_API_BASE_URL", API_BASE).rstrip("/")
    api_key = env.get("PIXELLAB_API_KEY")
    if not api_key:
        raise SystemExit("PIXELLAB_API_KEY is missing from .env.local, .env, or environment.")

    print("Checking PixelLab /balance without printing account amounts.")
    request_json(base_url, "/balance", api_key, method="GET")

    RAW_ROOT.mkdir(parents=True, exist_ok=True)
    metadata.setdefault("jobs", {})
    if FINAL_PATH.exists() and not args.force:
        metadata["final_sha256"] = sha256_file(FINAL_PATH)
        metadata["validation"] = validate_sheet(FINAL_PATH)
        save_metadata(metadata)
        print(f"SKIP final exists {FINAL_PATH.relative_to(ROOT)}")
        return 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = {
            executor.submit(
                produce_direction,
                direction,
                base_url,
                api_key,
                positive_tokens,
                negative_tokens,
                max(args.poll_seconds, 5),
            ): direction
            for direction in DIRECTIONS
        }
        for future in concurrent.futures.as_completed(futures):
            direction = futures[future]
            metadata["jobs"][direction] = future.result()
            save_metadata(metadata)

    frames_by_direction = {
        direction: [RAW_ROOT / direction / f"frame_{index:02d}.png" for index in range(FRAMES_PER_DIRECTION)]
        for direction in DIRECTIONS
    }
    compose_sheet(FINAL_PATH, frames_by_direction)
    make_contact_sheet(FINAL_PATH, RAW_ROOT / "contact_1x.png", 1)
    make_contact_sheet(FINAL_PATH, RAW_ROOT / "contact_2x.png", 2)
    make_preview_gif(RAW_ROOT, RAW_ROOT / "attack_preview.gif")

    source_hashes_after = collect_source_hashes()
    if source_hashes_before != source_hashes_after:
        raise SystemExit("Source reference hashes changed during production; refusing to continue.")
    metadata["source_hash_immutability"] = {
        "checked_at": utc_now(),
        "status": "passed",
        "sha256": source_hashes_after,
    }
    metadata["final_path"] = str(FINAL_PATH.relative_to(ROOT))
    metadata["final_sha256"] = sha256_file(FINAL_PATH)
    metadata["raw_contact_sheets"] = [
        str((RAW_ROOT / "contact_1x.png").relative_to(ROOT)),
        str((RAW_ROOT / "contact_2x.png").relative_to(ROOT)),
    ]
    metadata["raw_preview_gif"] = str((RAW_ROOT / "attack_preview.gif").relative_to(ROOT))
    metadata["validation"] = validate_sheet(FINAL_PATH)
    metadata["motion_metrics"] = collect_motion_metrics(RAW_ROOT)
    save_metadata(metadata)
    print(f"WROTE {FINAL_PATH.relative_to(ROOT)}")
    return 0


def produce_direction(
    direction: str,
    base_url: str,
    api_key: str,
    positive_tokens: list[str],
    negative_tokens: list[str],
    poll_seconds: int,
) -> dict[str, Any]:
    direction_raw = RAW_ROOT / direction
    direction_raw.mkdir(parents=True, exist_ok=True)
    frame_paths = [direction_raw / f"frame_{index:02d}.png" for index in range(FRAMES_PER_DIRECTION)]
    if all(path.exists() for path in frame_paths):
        validate_frames(frame_paths)
        return {
            "status": "reused_raw_frames",
            "direction": direction,
            "source_path": str(source_path(direction).relative_to(ROOT)),
            "source_sha256": sha256_file(source_path(direction)),
            "frame_paths": [str(path.relative_to(ROOT)) for path in frame_paths],
        }

    prompt = build_prompt(direction, positive_tokens, negative_tokens)
    seed = 930800 + DIRECTIONS.index(direction)
    body: dict[str, Any] = {
        "first_frame": {"base64": image_as_data_uri(source_path(direction))},
        "last_frame": {"base64": image_as_data_uri(source_path(direction))},
        "action": prompt,
        "frame_count": FRAMES_PER_DIRECTION,
        "seed": seed,
        "no_background": True,
        "drift_threshold": 0.08,
        "enhance_prompt": False,
    }
    request_summary = {
        "endpoint": "/animate-with-text-v3",
        "direction": direction,
        "frame_count": FRAMES_PER_DIRECTION,
        "seed": seed,
        "no_background": True,
        "drift_threshold": 0.08,
        "enhance_prompt": False,
        "last_frame": "same_as_first_frame",
        "prompt": prompt,
        "source_path": str(source_path(direction).relative_to(ROOT)),
        "source_sha256": sha256_file(source_path(direction)),
    }
    (direction_raw / "request_redacted.json").write_text(
        json.dumps(request_summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    job_file = direction_raw / "job_redacted.json"
    if job_file.exists():
        job_id = json.loads(job_file.read_text(encoding="utf-8"))["background_job_id"]
        print(f"RESUME JOB {direction} {job_id}")
    else:
        response = request_json(base_url, "/animate-with-text-v3", api_key, body, method="POST")
        job_id = response["background_job_id"]
        job_file.write_text(
            json.dumps({"background_job_id": job_id, "initial_status": response.get("status")}, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"JOB {direction} {job_id}")

    job = poll_job(base_url, api_key, job_id, poll_seconds)
    frames = extract_frame_images(job.get("last_response") or {})
    if len(frames) < FRAMES_PER_DIRECTION:
        raise RuntimeError(f"{direction} returned {len(frames)} frames")
    returned_raw = direction_raw / "returned_frames"
    returned_raw.mkdir(parents=True, exist_ok=True)
    for index, image in enumerate(frames):
        image.convert("RGBA").save(returned_raw / f"returned_frame_{index:02d}.png")
    frames = frames[:FRAMES_PER_DIRECTION]
    for index, image in enumerate(frames):
        image = image.convert("RGBA")
        if image.size != (FRAME_SIZE, FRAME_SIZE):
            image = image.resize((FRAME_SIZE, FRAME_SIZE), Image.Resampling.NEAREST)
        image.save(frame_paths[index])
    validate_frames(frame_paths)
    return {
        **request_summary,
        "status": "completed",
        "background_job_id": job_id,
        "image_source": "quantized_images" if (job.get("last_response") or {}).get("quantized_images") else "images",
        "frame_paths": [str(path.relative_to(ROOT)) for path in frame_paths],
        "frame_sha256": [sha256_file(path) for path in frame_paths],
    }


def build_prompt(direction: str, positive_tokens: list[str], negative_tokens: list[str]) -> str:
    direction_label = {
        "south": "attacking south, facing directly forward toward camera",
        "west": "attacking west, strict left cardinal sprite, no 3/4 turn",
        "east": "attacking east, strict right cardinal sprite, no 3/4 turn",
        "north": "attacking north, back-facing cardinal sprite, no 3/4 turn",
    }[direction]
    positive = ", ".join(positive_tokens[:5])
    negative = ", ".join(negative_tokens[:8])
    return (
        f"{direction_label}. 8-frame short non-looping sword attack for one 32x32 pixel character. "
        "Muchau is a human/kitsune hybrid with large red fox ears, readable tail, small sword, tea tin, and tea ware. "
        "Show anticipation, small slash, follow-through, and return to idle. Keep gear attached; preserve first-frame identity and palette. "
        f"{positive}. Transparent background, no shadow plate, no extra character, no text. "
        f"Avoid: {negative}, oversized weapon, magic aura, full screen effect, side-scrolling scene, isometric."
    )


def compose_sheet(final_path: Path, frames_by_direction: dict[str, list[Path]]) -> None:
    final_path.parent.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (FRAME_SIZE * FRAMES_PER_DIRECTION, FRAME_SIZE * len(DIRECTIONS)), (0, 0, 0, 0))
    for row, direction in enumerate(DIRECTIONS):
        for column, path in enumerate(frames_by_direction[direction]):
            sheet.paste(Image.open(path).convert("RGBA"), (column * FRAME_SIZE, row * FRAME_SIZE))
    sheet.save(final_path)


def make_contact_sheet(sheet_path: Path, output_path: Path, scale: int) -> None:
    image = Image.open(sheet_path).convert("RGBA")
    if scale != 1:
        image = image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
    image.save(output_path)


def make_preview_gif(raw_root: Path, output_path: Path) -> None:
    frames = []
    for index in range(FRAMES_PER_DIRECTION):
        canvas = Image.new("RGBA", (FRAME_SIZE * len(DIRECTIONS) * 2, FRAME_SIZE * 2), (0, 0, 0, 0))
        for column, direction in enumerate(DIRECTIONS):
            frame = Image.open(raw_root / direction / f"frame_{index:02d}.png").convert("RGBA")
            frame = frame.resize((FRAME_SIZE * 2, FRAME_SIZE * 2), Image.Resampling.NEAREST)
            canvas.paste(frame, (column * FRAME_SIZE * 2, 0), frame)
        frames.append(canvas)
    frames[0].save(output_path, save_all=True, append_images=frames[1:], duration=70, loop=0, disposal=2)


def extract_frame_images(last_response: dict[str, Any]) -> list[Image.Image]:
    payloads = last_response.get("quantized_images") or last_response.get("images") or []
    return [decode_image_payload(payload) for payload in payloads]


def decode_image_payload(payload: Any) -> Image.Image:
    if isinstance(payload, dict):
        for key in ("base64", "image", "url"):
            if key in payload:
                return decode_image_payload(payload[key])
        raise RuntimeError(f"Unknown image payload keys: {sorted(payload.keys())}")
    if not isinstance(payload, str):
        raise RuntimeError(f"Unsupported image payload type: {type(payload)!r}")
    if payload.startswith(("http://", "https://")):
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


def request_json(base_url: str, path: str, api_key: str, body: dict[str, Any] | None = None, method: str = "POST") -> dict[str, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
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
        body_text = exc.read().decode("utf-8", errors="replace")[:240]
        raise RuntimeError(f"PixelLab HTTP {exc.code} for {path}: {body_text}") from exc


def validate_sources() -> None:
    for direction in DIRECTIONS:
        path = source_path(direction)
        image = Image.open(path)
        if image.size != (FRAME_SIZE, FRAME_SIZE):
            raise RuntimeError(f"Invalid source size {path}: {image.size}")
        if image.convert("RGBA").getchannel("A").getbbox() is None:
            raise RuntimeError(f"Source has no visible alpha pixels: {path}")


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


def collect_motion_metrics(raw_root: Path) -> dict[str, Any]:
    metrics: dict[str, Any] = {"status": "passed", "minimum_unique_frames_per_direction": 4, "directions": {}, "risks": []}
    for direction in DIRECTIONS:
        paths = [raw_root / direction / f"frame_{index:02d}.png" for index in range(FRAMES_PER_DIRECTION)]
        validate_frames(paths)
        hashes = [sha256_file(path) for path in paths]
        unique_count = len(set(hashes))
        metrics["directions"][direction] = {
            "unique_frame_count": unique_count,
            "unique_frame_minimum_met": unique_count >= 4,
            "frame_sha256": hashes,
        }
        if unique_count < 4:
            metrics["status"] = "risk"
            metrics["risks"].append({"direction": direction, "type": "low_unique_frame_count", "unique_frame_count": unique_count})
    return metrics


def source_path(direction: str) -> Path:
    return ROOT / SOURCE_PATTERN.format(direction=DIRECTION_TO_SOURCE[direction])


def image_as_data_uri(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect_source_hashes() -> dict[str, str]:
    return {direction: sha256_file(source_path(direction)) for direction in DIRECTIONS}


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
    for env_path in (ROOT / ".env.local", ROOT / ".env", ROOT.parent / "samurai-tea-fox" / ".env.local"):
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
    raise SystemExit(main())
