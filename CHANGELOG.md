# Changelog

All notable changes to SPACE23 will be documented in this file.

## [0.1.3] - 2026-05-08

Polish pass. Big visual upgrade for the nebula and the ship; a few real bugs surfaced in a draconian audit; the camera shake stops feeling like a quake.

### Fixed
- **Spectrum analyzer dead on Pages → nebula didn't react to music.** Godot 4 web export's `AudioEffectSpectrumAnalyzer` returns near-zero magnitudes despite audio playing. Added a synthesised fallback beat derived from `audio_stream_player.get_playback_position()` (130 BPM, sharp kick + rolling mid + rapid high). `audio_low/mid/high = max(real, synth)` — desktop spectrum dominates, web synth carries.
- **`_ai_invader` never fired after spawn.** The line `e.shoot_timer -= delta` was missing, so all invader-class enemies (types 4 / 6 / 7) had a frozen timer that never reached the `<= 0` threshold. Three enemy patterns moved decoratively without ever shooting.
- **Fighter leak on LEAVE state.** `_ai_fighter` flies off the top of the screen and self-marks `e.hp = 0`, but the cleanup predicate only caught `pos.y > screen + 100` (off the bottom). The dead fighter stayed in the enemies array indefinitely. Cleanup widened to also catch `hp <= 0` and `pos.y < -300`.
- **Comet loop reset visible.** The two procedural comets in `BackgroundRenderer` wrap-around when off-screen, but at full opacity right up to the boundary the teleport itself flashed. Added an 80 px edge alpha fade — the loop becomes imperceptible.
- **Boot splash regression.** Replaced the gameplay-screenshot splash with a hand-written SVG of just the ship matching `Player.gd` `ship_renderer` coordinates, rasterized at 1280×1280, wired with `boot_splash/fullsize=true` so it fills the viewport instead of leaving a white slab on the right.
- **GDScript parse error from `fract()`** in the synth fallback (GLSL function used in GDScript) — script failed to load → audio dead until fixed (`fmod(beat, 1.0)`).
- **Bus layout self-loop.** A defensive `bus/0/send = &"Master"` added to `default_bus_layout.tres` was a routing self-loop that broke the bus on web export. Reverted.
- **WebGL early-return safety.** `starfield_layer` in `nebula.gdshader` had two `return vec3(0.0)` early exits, fragile in WebGL 2 / GLSL ES 3. Refactored to a single return path with `step()` providing the visibility mask. Same treatment for the radial-blur sample loop in `post.gdshader`: pulled outside the inner non-uniform branch so `texture()` derivatives stay well-defined.

### Changed
- **Camera shake → soft contour.** `CAMERA_SHAKE_MAX 22 → 10` (~-88% from v0.1.1's 80). The visual punch now arrives via a new screen-space radial blur masked around the ship; the camera offset is just a gentle sussulto.
- **Radial blur masked on the ship.** New `ship_uv` and `radial_blur` uniforms in `post.gdshader`. 5-tap blur along `(uv - ship_uv)` modulated by `smoothstep(0.18, 0.55, dist_ship)` (aspect-corrected so the calm zone is circular). Driven by `shake_intensity / CAMERA_SHAKE_MAX`, so every `add_shake` call site (kill, hit, bomb drop, boss kill) gets the punch for free without the camera moving.
- **Procedural-shader starfield in `nebula.gdshader`.** Replaced most of the CPU procedural-array stars with two GPU starfield layers built from a hashed cell grid. Loops perfectly via UV.y modulo, twinkles via `sin(time · twinkle_hz + phase)`, per-star colour from a 4-bin distribution (white-warm / pale-blue / pale-yellow / pink), audio-reactive amplitude. CPU arrays trimmed to a small foreground "speed streak" layer.
- **Speed streaks layer.** Sparse vertical lines in `nebula.gdshader` (~0.8% coverage on a 160×35 grid), scrolling at 4× starfield speed, intensity modulated by `audio_low`. Subtle but the brain reads them as warp-speed motion.
- **Landmark sizes / opacity / staggering.** Sizes -15% (planet 380 → 320, galaxy 480 → 410, nebula 520 → 440, blackhole 380 → 320, cluster 280 → 240). Modulate brought near neutral white with a faint colour hint (no more "scala di grigi" feel). Single-landmark guard preserved. Initial deep-landmark accumulators now staggered deterministically (cluster 0.85 → galaxy 0.65 → nebula 0.45 → blackhole 0.25) so the four kinds spawn at distinct times.
- **Project setting free wins.** `anti_aliasing/quality/msaa_2d=1` (2× MSAA — smooths the procedural ship/wings/asteroids/etc.), `anti_aliasing/quality/screen_space_aa=1` (FXAA), `viewport/hdr_2d=true` (allows HDR colours to survive into the bloom pass on WebGL Compatibility — likely the largest local-vs-Pages visual gap closer).
- **Static `default_bus_layout.tres`.** Audio bus layout now a static resource (Master + SpectrumAnalyzer effect at index 0) instead of being created at runtime via `AudioServer.add_bus()`. Godot 4 web export does not route runtime-added buses; this was the root cause of the no-audio-on-Pages bug.
- **AudioContext autoplay unlock.** New `audio-fix.js` loaded from `<head>` via `html/head_include` hooks the `AudioContext` constructor and resumes any suspended instance from a window-level capture-phase listener — robust against Godot 4.4's canvas-only resume sometimes missing clicks that landed on Control nodes.

### Added
- **Live-modulated ship.** Three small additions to `Player._on_ship_draw`:
  - **Hit flash** — ~80 ms white burst on damage. HDR cockpit and neon trim flare into bloom; reads instantly as "I just got hit" without competing with the 400 ms i-frame alpha flicker.
  - **Audio-reactive trim glow** — neon edges multiplied by `(1 + audio_low * 0.55)` live. Trim breathes with the bass without needing a shader on the body.
  - **Cockpit health pulse** — at full HP, magenta steady at 4 Hz amplitude 0.15 (ambient breath). At 0 HP, lerps to red-alarm and pulses at 18 Hz amplitude 0.6. Survival tension feedback ON the ship.
- **Damage deformation.** Below 60% HP the silhouette starts to dent. Wing tips droop, hull-back pulled in, nose skewed. Determinist offset (no per-frame jitter). Medkit pickup heals → next draw, dents gone.
- **Vector thrust on roll.** The 3 engine flame `ColorRect` nodes rotate by `-roll * 0.7` so when the ship banks, flames lean opposite as if vectoring thrust.
- **Trail color shift on bass.** Engine trail base colour `Color(0.2, 1.5, 3.0)` lerps toward `Color(2.5, 2.5, 3.0)` on bass kicks. Trail burns brighter in sync with the music.
- **Custom boot splash + app icon.** Procedural-ship `boot.png` rendered from `boot.svg` matching `ship_renderer` coordinates. `saturn.png` as application icon.

## [0.1.2] - 2026-05-08

## [0.1.2] - 2026-05-08

### Fixed
- **Procedural-landmark images looked pixelated and grayscale.** Body sizes overshot the source PNG resolution (Mercury source ~256 px scaled to 600 px+ → visible pixelation), and the modulate alpha was so close to gray that the planets read as monochrome. Sizes pulled back to ~380–520 px (max ~2× the PNG native), modulate now neutral white with a faint color hint instead of uniform gray.
- **`_tick_playing` was running during GAMEOVER.** Substate dispatch was a non-exclusive chain of `if`/`if`/`elif`/`else` instead of a clean cascade, so flow_state, score, camera lerp and bomb_buffer all kept ticking on the corpse, and the wave director kept spawning enemies. Substate is now strictly mutually exclusive (`if` / `elif` / `elif` / `elif` / `else`); wave + boss gate widened to `game_state == "PLAYING"`.

### Changed
- **Audio bands now visually distinct on the nebula.** Previously bass, mid, and high all just brightened the same two palette colors (`c_neb1` / `c_neb2`); on track-0's purple/blue palette the result was "the cloud got a bit brighter", indistinguishable bands. Added band-specific additive tints on top of the palette glow:
  - Bass → warm red/orange wash on `n1` cloud peaks
  - Mid  → cool cyan/blue surge on `n2` cloud peaks
  - High → pink/magenta shimmer on `n2` cloud peaks plus brighter sparkle
  Each band paints a qualitatively different colour regardless of the track palette, so a kick now visibly reddens the nebula, a synth/pad shifts cyan, hi-hats add pink shimmer.
- **Spectrum analyzer gain ×4 → ×6**, lerp rate 10 → 18. Raw magnitudes from Godot's `AudioEffectSpectrumAnalyzer` are 0.05–0.3 in typical music; ×6 with clamp lets real beats actually saturate the analyzer output to 1.0, and the snappier lerp gives bass attacks the punch they were missing.
- **`KICK_PARALLAX_BOOST` 2.5 → 3.5**. With the player still and the music between kicks, the parallax was previously near-stationary; the bigger boost from `audio_low` keeps the field perceptibly scrolling.
- **`bass_baseline` in nebula shader 2.5 → 2.0**, leaving more room for the new band-specific tints to be readable on top of the always-on palette glow.

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
