#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
display_driver="${GODOT_DISPLAY_DRIVER:-macos}"
rendering_method="${GODOT_RENDERING_METHOD:-gl_compatibility}"

exec "${godot_bin}" \
  --path "${project_dir}" \
  --display-driver "${display_driver}" \
  --rendering-method "${rendering_method}" \
  --script res://tools/capture_biome_maps.gd \
  -- "$@"
