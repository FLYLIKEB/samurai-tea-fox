#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${NOTION_ACCESS_TOKEN:?NOTION_ACCESS_TOKEN 환경변수가 필요합니다.}"

PYTHONDONTWRITEBYTECODE=1 python3 -m tools.notion_export sync \
  --output data/generated \
  --data-version "notion-$(date +%F)" \
  --profile confirmed-test

PYTHONDONTWRITEBYTECODE=1 python3 -m tools.notion_export validate \
  --directory data/generated
