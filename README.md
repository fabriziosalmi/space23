# SPACE23

[![SPACE23 — click to play](banner.svg)](https://fabriziosalmi.github.io/space23/)

A small vertical shoot-'em-up that runs in the browser. Click the banner above (or the link below) and play — no install. Source is open and every push to `main` is auto-deployed to GitHub Pages.

![SPACE23 in-game](screenshot.png)

## Play

[fabriziosalmi.github.io/space23](https://fabriziosalmi.github.io/space23/)

Loads as a WebAssembly + WebGL 2 build. Works on desktop and mobile browsers. First load fetches a few MB; after that it's cached.

## Controls

Desktop:

- Move: `WASD` / arrow keys, or hold left mouse to chase the cursor
- Fire: `Space` (held = autofire)
- Dash: `Shift`
- Smart bomb: `X`
- Pause: `Esc` / `P`

Mobile: tap-and-drag to move and autofire; on-screen `B` button for the bomb.

## What's in it

- Six music tracks. Each one drives the palette of the procedural nebula, and its drop synchronises a screen warp and a burst of enemies. One boss per track.
- Six enemy AIs (scout, fighter, tank, spinner, invader, mothership) plus a mothership boss. Around ten wave shapes — V-formation, swarm, escort, arc, grid, wall — drawn from a shuffled deck.
- Power-ups: heal, railgun, drones, black hole. The black hole physically bends the screen with the same fragment shader that handles boss-kill lensing.
- Time scaling tied to your movement, SUPERHOT-style: stop and the world slows; dash and it snaps back.
- Audio-reactive visuals: bass kicks the parallax, mids and highs drive nebula texture and post-process aberration, the wave director's pacing is coupled to the position inside the track (build-up → drop → calm).

## Run locally

Requirements: [Godot 4.4](https://godotengine.org/download) and [Git LFS](https://git-lfs.com) — the six music tracks are stored as LFS pointers.

```bash
git lfs install
git clone https://github.com/fabriziosalmi/space23.git
cd space23
# Open project.godot in Godot, then press F5
```

Project layout:

- `Main.gd`, `Player.gd`, `AudioManager.gd`, `BackgroundRenderer.gd`, `UIManager.gd` — top-level scripts.
- `systems/` — gameplay subsystems (`EnemySystem`, `ProjectileSystem`, `WaveDirector`, `BlackHoleSystem`, `ExplosionSystem`, `PowerupSystem`, `RailgunSystem`, `PostFXController`).
- `shaders/` — fragment shaders for nebula FBM, post-FX (vignette, gravitational lensing, chromatic aberration, scanlines, zoom blur, grayscale), procedural flame, planet tinting.
- `waves.json` — wave patterns and per-wave modifiers (count, density, speed, colour). Edit and reload.
- `bg/`, `planets/` — sprite assets for scrolling landmarks (planets, galaxies, nebulae, clusters, black holes).
- `*.mp3` — six music tracks (LFS).

Common tweak points:

- Enemy stats and AI: the `ENEMY_TYPES` table and the `_ai_*` routines in `systems/EnemySystem.gd`.
- Wave shapes: `waves.json` plus `WaveDirector._spawn_pattern` for new pattern types.
- Track palettes and drop times: `AudioManager.gd` `playlist` array.
- Post-process look: uniforms in `shaders/post.gdshader`.

## Tech

- Godot 4.4, Forward+ renderer, GDScript only, no third-party plugins.
- HTML5 export → WebAssembly + WebGL 2. CI under `.github/workflows/` runs the Godot headless export and publishes to GitHub Pages.
- Audio analysis via `AudioEffectSpectrumAnalyzer` on a dedicated bus (low/mid/high bands) feeding shader uniforms and gameplay timing.
- HDR pipeline: bloom + ACES tonemap; emissive surfaces use `Color(r > 1, ...)` so the global glow picks them up. Stereo SFX panning via `AudioStreamPlayer2D` with the active `Camera2D` as listener.

## Credits

- Music: composed and produced with [Suno AI](https://suno.com) using a custom v5.5 model fine-tuned on my own tracks. More of my music under the Space Invaders alias: [soundcloud.com/spaceinvaders](https://soundcloud.com/spaceinvaders).
- Background imagery (planets, galaxy, nebula, cluster, black hole): generated with Gemini's image model.
- Code: written by Gemini and Claude under my orchestration.
- Inspiration: the original Space Invaders, and Space Invaders 23 — the freetekno collective I belong to. Hence the name.

## Roadmap

This is the first browser game I'm shipping this way. If it lands, more will follow on the same skeleton: Godot 4 + GitHub Pages auto-deploy + audio-reactive scaffolding. Forks welcome.

## License

See `LICENSE` for the code. Music tracks are released for use within this game — please ask before reusing them elsewhere.
