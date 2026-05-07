# SPACE23

![SPACE23 Screenshot](screenshot.png)

**SPACE23** is an ultra-high fidelity, procedural space shooter built in **Godot 4**.
Developed with a strict "draconian" approach: zero bloat, pure math-driven aesthetics, and performance-first logic.

## 🚀 Vision
The goal of SPACE23 is to push the boundaries of WebGL/WebAssembly gaming by delivering an arcade experience that looks and feels like a premium Next-Gen title, running natively in the browser. 
There are almost no static assets. Ships, trails, explosions, black holes, and the universe itself are rendered entirely via code and custom GLSL-style CanvasItem Shaders.

## ⚔️ Core Mechanics
- **Procedural Universe**: Fluid dynamics, deep parallax backgrounds, and HDR Bloom-driven starfields.
- **Hit-Stop & Game Feel**: The engine physically halts for milliseconds on impact, providing a visceral, arcade-perfect sense of weight.
- **Time Dilation (Superhot-style)**: Time is tied to the player's movement. Stop, and the universe freezes. Dash, and reality snaps back to normal speed. 
- **Gravitational Anomalies**: Black hole powerups that physically warp the game screen (UV distortion) and bend the rules of gravity, swallowing enemies and bullets whole.
- **Granular Audio System**: Sound effects are generated procedurally by taking micro-slices of the currently playing music track, guaranteeing perfect audio-visual synchrony.

## 🛠 Tech Stack
- **Engine**: Godot 4.4 (GDScript)
- **Target**: HTML5 (WebAssembly / WebGL 2)
- **Rendering**: Custom Fragment Shaders in `shaders/*.gdshader` (ACES Tonemapping, Screen-space Distortion, Chromatic Aberration).

## 🚀 Running the Game
1. Install [Git LFS](https://git-lfs.com) — the audio tracks are managed by LFS (see below).
2. Open the project in Godot 4.4.
3. Hit `F5` to run `Main.tscn`.
4. To build for the web, the CI generates `export_presets.cfg` automatically; in locale crealo via Editor → Project → Export.

## 📦 Git LFS
I file binari pesanti (`*.mp3`, `screenshot.png`) sono dichiarati come LFS in `.gitattributes`. Per chi clona:

```bash
git lfs install
git clone <repo>
# `git lfs pull` parte automaticamente alla checkout se LFS è installato.
```

Per la **migrazione one-shot** della history esistente (riscrive i commit, da fare una volta sola sul branch `main`):

```bash
git lfs install
git lfs migrate import --everything --include="*.mp3,screenshot.png"
git push --force-with-lease origin main
```

Dopo la migrazione il repo passa da ~16 MB a < 1 MB di blob git regolari.
