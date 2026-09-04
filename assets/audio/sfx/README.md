# Procedural SFX stream

`procedural_sfx.tres` is the shared `AudioStreamGenerator` used by `SfxEventRouter`.
The router keeps the canonical SFX event IDs, default volume, pitch, cooldown, and
generated waveform profiles in code so gameplay and UI callers never hard-code
audio resource paths.
