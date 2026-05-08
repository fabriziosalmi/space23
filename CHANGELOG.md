# Changelog

All notable changes to SPACE23 will be documented in this file.

## [0.1.1] - 2026-05-08

### Fixed
- **Web export had no audio.** Root cause: Godot 4 web export does not route audio buses created at runtime via `AudioServer.add_bus()` (godotengine/godot#115560). Defined the bus layout as a static `default_bus_layout.tres` resource (Master + SpectrumAnalyzer effect at index 0), removed the runtime `add_bus`/`set_bus_send`/`add_bus_effect` calls in `AudioManager._ready()`. Music and SFX now play on Pages.
- **AudioContext autoplay block.** Browser policy keeps every `AudioContext` suspended until a user gesture; Godot 4.4's canvas-level resume could miss clicks that landed on Control nodes. Added `audio-fix.js` injected via `html/head_include` that hooks the `AudioContext` constructor and resumes any suspended instance from a window-level capture-phase listener.
- **Game-over → retry left the viewport black.** `_tick_gameover_fx` lerps `pitch_scale → 0.01`, `zoom_blur → 0.4`, `grayscale → 1.0`, camera zoom → 2.5×, none of which were reset on retry. Added an explicit FX reset block in `_on_retry_pressed` covering camera, post-FX, audio, and transient timers (shake, hit-stop, boss lens, bomb buffer).
- **Same-frame i-frame race.** Collision detectors were only reading `player.is_invincible`, which is computed at the end of the previous `Player._process` frame. Multiple bullets hitting on the same frame all saw stale `false`, removing themselves with full side effects. Added a `hit_iframe_timer > 0` guard in both `EnemySystem` body collision and `ProjectileSystem` bullet/graze checks.
- **Engine flames did not bob with the ship body.** The three flame `ColorRect` nodes were siblings of `ship_renderer` but only `ship_renderer.position.y` got the `ship_bob` offset. Stashed the flames in an array with their base `y` and apply the same bob each frame.
- **State machine left at "INTRO" after the 5s intro completed.** `_tick_intro` cleared `is_intro` but never set `game_state = "PLAYING"`, so `toggle_pause()` (gated on `game_state == "PLAYING"`) was a no-op for the entire first playthrough. Set `game_state = "PLAYING"` at intro end.
- **Mouse-target shake jitter.** `get_global_mouse_position()` includes camera offset; while the camera shook the move-to-mouse target danced with it. Subtract `main_camera.offset` before using.
- **Planets and deep-space landmarks effectively invisible.** Pacing and spawn-Y math added up to ~50s before the first planet appeared and ~150s for the first galaxy. Tightened intervals, raised initial accumulators, bumped scroll speeds, and moved spawn Y just above the viewport so first landmarks now appear within ~5–10s of starting.

### Changed
- **Music tracks: MP3 → OGG Vorbis.** Godot 4 web's MP3 path through minimp3 in WASM is brittle for VBR streams; OGG via libvorbis is the recommended format and decodes cleanly. All six tracks re-encoded at qscale 5; total audio payload 31 MB → 27 MB.
- **Camera shake model.** Was `randf_range(-1, 1) * shake_intensity` per axis with `lerp` decay. Now Squirrel Eiserloh's trauma model: `offset = trauma² · MAX · noise` with smooth pseudo-Perlin noise (three sin frequencies decorrelated XY) and linear trauma decay. Peaks pop, decay is filmic.
- **Hit-stop differentiated by enemy "mass".** Was 0 ms on every non-boss kill, 2.0 s on bosses. Now scaled by base HP: 20 ms / 40 ms / 70 ms tiers, boss 1.2 s.
- **Post-damage i-frames.** A bullet wall could stack damage on the same frame to instantly drain HP. Added a 0.4 s invulnerability window after every hit, with a 30 Hz alpha flash on the ship for visual feedback.
- **Stereo SFX panning.** Pool of 8 `AudioStreamPlayer` → `AudioStreamPlayer2D` with `attenuation = 0` and `panning_strength = 0.6`, position propagated from each call site (explosion, kill, graze, railgun, powerup, bomb).
- **Wave director coupled to the music.** Build-up phase (3 s before the drop) lengthens the spawn timer ×1.5; on the drop, force-spawn one wave then keep timer ×0.6 for 1 s of barrage; 3–6 s post-drop, ×1.3 for breathing room.
- **Visibility hierarchy of the world.** Explicit `z_index` so threat objects (player + enemy bullets) always render above explosions, never the other way around.
- **Audio-reactive nebula re-tuned.** Spectrum analyzer gain ×2 → ×4; the lower ambient floor relies on the shader's own `bass_baseline` (raised 0.6 → 1.5) so the nebula is always lit independent of audio. Bands are now visually split: bass pumps `c_neb1` (kick = violet pulse), mid pumps `c_neb2` (synth/pad = blue surge), high gives 5× more sparkle plus a white rim on the brightest cloud peaks.
- **Lateral parallax.** Layers near and the planets/deep-landmarks now drift opposite to `player.velocity.x` with depth-graded factors.
- **Boss-explosion gravitational lensing.** The black-hole post-FX shader is reused for ~0.4 s on boss kills and smart bombs (curve `t² · 1.6`).
- **Smart-bomb input buffer.** Press during intro, transition, or hit-stop is no longer eaten — buffered for 180 ms and consumed on the next valid PLAYING frame.
- **Squared-distance collision checks** in the hot loops (`distance_to → distance_squared_to` where the result is only compared against a constant).

## [0.1.0] - 2026-05-07

Initial release. Vertical shoot-'em-up in Godot 4, deployed to GitHub Pages. See README for details.
