#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/tools -p 'test_*.py'
PYTHONDONTWRITEBYTECODE=1 python3 -m tools.notion_export validate --directory data/generated
godot --headless --path . --script res://tests/test_runner.gd
