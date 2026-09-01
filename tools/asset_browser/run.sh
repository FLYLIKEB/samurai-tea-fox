#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

if [ "${ASSET_BROWSER_REPO:-}" = "" ]; then
  if [ -f "$PROJECT_ROOT/../samurai-tea-fox-asset-browser/asset_browser/asset_browser.py" ]; then
    ASSET_BROWSER_REPO="$PROJECT_ROOT/../samurai-tea-fox-asset-browser"
  else
    ASSET_BROWSER_REPO="/Users/jwp/Developer/samurai-tea-fox-asset-browser"
  fi
fi

exec python3 "$ASSET_BROWSER_REPO/asset_browser/asset_browser.py" \
  --project-root "$PROJECT_ROOT" \
  "$@"
