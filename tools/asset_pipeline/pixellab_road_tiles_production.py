#!/usr/bin/env python3
"""Generate and collect a PixelLab 18-configuration top-down road tileset."""

from __future__ import annotations

import base64
import json
import os
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
RAW_ROOT = ROOT / "assets/source/imagegen/pixellab-road-tiles-20260903/raw"
API_BASE = "https://api.pixellab.ai/v2"
TILE_SIZE = 32


def main() -> int:
    env = load_env()
    base_url = env.get("PIXELLAB_API_BASE_URL", API_BASE).rstrip("/")
    api_key = env.get("PIXELLAB_API_KEY")
    if not api_key:
        raise SystemExit("PIXELLAB_API_KEY is missing")
    request_json(base_url, "/balance", api_key, method="GET")
    body = {
        "description": (
            "warm compacted clay footpath laid over a grassy Japanese woodland floor, "
            "subtle worn center, muted tea-green and earth palette, clear pixel clusters, "
            "seamless edges, no objects, no text, no shadows outside the tile"
        ),
        "tile_type": "square_topdown",
        "tile_size": 32,
        "tile_feature": "roads",
        "outline_mode": "segmentation",
        "seed": 9032026,
    }
    RAW_ROOT.mkdir(parents=True, exist_ok=True)
    request_file = RAW_ROOT / "request_redacted.json"
    if request_file.exists():
        previous = json.loads(request_file.read_text(encoding="utf-8"))
        job_id = previous["job_id"]
        tile_id = previous.get("tile_id", "")
    else:
        response = request_json(base_url, "/create-tiles-pro", api_key, body)
        job_id = response["background_job_id"]
        tile_id = response.get("tile_id", "")
    (RAW_ROOT / "request_redacted.json").write_text(
        json.dumps({"endpoint": "/create-tiles-pro", "job_id": job_id, "tile_id": tile_id, "request": body}, indent=2) + "\n",
        encoding="utf-8",
    )
    result = poll_job(base_url, api_key, job_id)
    payload = result.get("last_response") or result
    (RAW_ROOT / "response_redacted.json").write_text(
        json.dumps({"status": result.get("status"), "job_id": job_id, "tile_id": tile_id, "response_keys": sorted(payload.keys()) if isinstance(payload, dict) else []}, indent=2) + "\n",
        encoding="utf-8",
    )
    tiles = find_tiles(payload)
    if not tiles and tile_id:
        tileset = request_json(base_url, f"/tiles-pro/{tile_id}", api_key, method="GET")
        payload = tileset
        (RAW_ROOT / "tileset_rules_redacted.json").write_text(
            json.dumps(
                {
                    "tile_id": tile_id,
                    "road_configs": tileset.get("road_configs"),
                    "tile_rules": tileset.get("tile_rules"),
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        storage_urls = tileset.get("storage_urls", {})
        if isinstance(storage_urls, dict):
            tiles = [{"url": url, "api_key": api_key} for _, url in sorted(storage_urls.items())]
    if len(tiles) < 18:
        raise RuntimeError(f"PixelLab returned {len(tiles)} road tiles; expected at least 18")
    for index, tile in enumerate(tiles[:18]):
        image = decode_image(tile)
        if image.size != (TILE_SIZE, TILE_SIZE):
            image = image.resize((TILE_SIZE, TILE_SIZE), Image.Resampling.NEAREST)
        image.save(RAW_ROOT / f"road_{index:02d}.png")
    print(f"WROTE {len(tiles[:18])} raw road tiles; job_id={job_id}")
    return 0


def find_tiles(value):
    if isinstance(value, dict):
        for key in ("tiles", "images", "results"):
            if isinstance(value.get(key), list):
                return value[key]
        for child in value.values():
            found = find_tiles(child)
            if found:
                return found
    return []


def decode_image(tile) -> Image.Image:
    if isinstance(tile, dict):
        for key in ("base64", "image_data", "image"):
            if key in tile:
                return decode_image(tile[key])
        if "url" in tile:
            request = urllib.request.Request(tile["url"], headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(request, timeout=120) as response:
                return Image.open(__import__("io").BytesIO(response.read())).convert("RGBA")
    if isinstance(tile, str):
        encoded = tile.split(",", 1)[1] if tile.startswith("data:image") else tile
        return Image.open(__import__("io").BytesIO(base64.b64decode(encoded))).convert("RGBA")
    raise RuntimeError("PixelLab road tile did not contain a base64 image")


def poll_job(base_url: str, api_key: str, job_id: str) -> dict:
    deadline = time.monotonic() + 900
    while True:
        job = request_json(base_url, f"/background-jobs/{job_id}", api_key, method="GET")
        print(f"POLL {job_id} {job.get('status')}")
        if job.get("status") == "completed":
            return job
        if job.get("status") == "failed":
            raise RuntimeError(f"PixelLab job failed: {job_id}")
        if time.monotonic() > deadline:
            raise TimeoutError(f"PixelLab job timeout: {job_id}")
        time.sleep(8)


def request_json(base_url: str, path: str, api_key: str, body=None, method="POST"):
    data = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url}{path}", data=data, method=method,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"PixelLab HTTP {exc.code} for {path}: {exc.read().decode(errors='replace')[:240]}") from exc


def load_env() -> dict[str, str]:
    values = dict(os.environ)
    for name in (".env.local", ".env"):
        path = ROOT / name
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if "=" not in line or line.lstrip().startswith("#"):
                continue
            key, value = line.split("=", 1)
            values.setdefault(key.strip(), value.strip())
    return values


if __name__ == "__main__":
    raise SystemExit(main())
