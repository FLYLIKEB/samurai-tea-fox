# Export Targets

The Notion technical spec targets mobile and desktop from the same Godot 4.x codebase.

## Desktop

- Windows
- macOS
- Linux

Desktop input should use keyboard/controller adapters that emit `GameCommand`.

## Mobile

- Android
- iOS

Mobile input should use touch controls that emit the same `GameCommand` types as desktop input.

## Rules

- Do not fork gameplay logic by platform.
- Platform-specific code belongs in input, save-path, or export adapters.
- Keep HUD permanent resources fixed to `HP / 기운 / 心`.
- Keep pixel assets at 32x32 source scale with nearest filtering.

