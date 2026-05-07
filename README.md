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
- **Engine**: Godot 4.3+ (GDScript)
- **Target**: HTML5 (WebAssembly / WebGL 2)
- **Rendering**: Custom Fragment Shaders (ACES Tonemapping, Screen-space Distortion, Chromatic Aberration).

## 🚀 Running the Game
1. Open the project in Godot 4.
2. Hit `F5` to run `Main.tscn`.
3. To build for the web, ensure `export_presets.cfg` is configured for Web, then export via Editor or CLI.
