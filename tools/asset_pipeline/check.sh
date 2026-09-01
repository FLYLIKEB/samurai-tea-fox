#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.tools.test_asset_pipeline
PYTHONDONTWRITEBYTECODE=1 python3 -m tools.asset_pipeline check --root .
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/test_runner.gd
