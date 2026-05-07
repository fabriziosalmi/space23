# CONTRIBUTING TO SPACE23

Welcome to SPACE23. If you intend to contribute, you must abide by the **Draconian Doctrine**.

## The Draconian Doctrine

1. **NO BLOAT**: External heavy assets (4K textures, bloated models) are strictly prohibited. Use code and math to generate aesthetics (Shaders, `_draw()`, Procedural Arrays).
2. **PERFORMANCE IS KING**: The game must run at 60 FPS in a web browser. Avoid excessive `instantiate()` calls in the hot-path. Pool resources and manage arrays strictly.
3. **READABILITY OVER CLEVERNESS**: Code must be explicit. Use strict types where necessary.
4. **NO EXTERNAL PLUGINS**: We do not rely on third-party Godot addons. If you need a feature, write it from scratch using core Godot nodes.

## Pull Requests
- Keep PRs hyper-focused on a single feature or fix.
- Ensure the game runs on HTML5 without errors before submitting.
- Document any Shader modifications extensively.
