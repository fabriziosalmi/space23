# BG v2 — A Procedural Universe Strip That Doesn't Get Boring

Status: **proposal / pre-implementation**.
Audience: anyone who'll touch the background pipeline next.
Scope: replace the current ad-hoc parallax with a chunked, curated, infinite vertical strip of real astronomical imagery interleaved with procedural texture, designed for zero perceptible streaming latency and a session-grade variety.

---

## 1. What's there today

The background is split between two parents under `Main`:

```
Main (Node2D)
├── BackgroundRenderer (Node2D, z = -10)
│   ├── nebula_bg (ColorRect, fullscreen, shader = nebula.gdshader)
│   ├── deep_layer (Node2D)        — galaxies/nebulae/blackholes/clusters
│   │   └── Sprite2D × N           — added at runtime, freed when off-screen
│   ├── planet_layer (Node2D)      — solar-system planet flyovers
│   │   └── Sprite2D × N
│   └── (CPU draw loop)            — comets, asteroids, deep starfield, streaks
└── (rest of the world: Player, EnemySystem, ProjectileSystem, …)
```

`BackgroundRenderer` owns four CPU layers (`layer_deep`, `layer_mid`, `layer_near`, `layer_top`) of dictionaries — points, asteroid groups, comets — drawn each frame from `_draw()`. It also drives the planet/deep landmark spawners on a per-frame distance accumulator.

`nebula.gdshader` runs a fullscreen ColorRect underneath everything. It paints two FBM cloud octaves, an audio-reactive sub-cloud, two procedural starfield layers (hash-grid + twinkle) and a sparse vertical "speed streak" pass.

Spawn pacing for sprites lives in `BackgroundRenderer`:

- `planet_distance_accum` advances by `parallax_speed * delta * REFERENCE_SCROLL_SPEED`. Every `PLANET_INTERVAL_PX = 3500` it pops the next planet from the cycle and instantiates a Sprite2D.
- `deep_distance_accum[kind]` advances independently for each of {galaxy, nebula, blackhole, cluster}. Each kind has its own `interval_px` (6500 – 12000) and a guard in `_has_visible_landmark()` that prevents two simultaneous deep landmarks.

No persistence. Every distance-step the universe is regenerated ad-hoc from a small static pool: 8 planet PNGs, 4 deep-landmark PNGs, the nebula shader.

## 2. What works

- **Audio reactivity is good.** `audio_low/mid/high` flow into the nebula shader as uniforms and into `effective_speed` as a kick-driven parallax boost. The cloud pulse, the bass-tinted nebula and the speed streaks already give the background a rhythm.
- **Sprite cleanup is correct.** Off-screen sprites are `queue_free`'d, deep-landmark accumulator decoupling means a still player still sees pacing.
- **The shader is cheap.** ~6 fragment passes (FBM × 3 + 2 starfields + streaks + sparkle) on a fullscreen quad — fine on WebGL Compatibility.
- **The `*_distance_accum` design** generalises cleanly to chunked / streamed content. We can keep that idea and replace the *source* of events.

## 3. What doesn't

- **Twelve images, infinite time.** With 8 planets and 4 deep landmarks on simple cycle/interval logic, a 5-minute session shows the same Saturn three or four times. Recognition kills immersion fast.
- **Pacing is decoupled from content.** A galaxy can land on top of a planet which can land while a comet is mid-flight. Visual density is random; cinematography is impossible.
- **No themes, no narrative.** A procedural strip should have *moments* — solar-system flyby, deep void, nebula approach, dense cluster, black-hole vicinity — and right now it has uniform random density with reused assets.
- **Procedural starfield twinkles forever.** Stars don't *go anywhere*. No constellations, no star clusters resolving as you approach, no nebulosity gradient.
- **No real composition.** Every body is centered horizontally at random, fades in at top, drifts down, fades out. A background of *real* photos should leverage their composition (galaxies framed off-center, nebulae filling the frame, planet rings cutting across the screen).
- **Shader scroll bugs.** Until v0.1.7 the starfield, streaks and clouds scrolled *up* (now corrected). The shader was easy to write wrong because direction is implicit in `+=` vs `-=` of UV.y — this is exactly the kind of error a more declarative system would not allow.

## 4. Vision

A **single long vertical strip** the player traverses from bottom to top (visually: world scrolls down). The strip is not infinite in implementation — it is a finite list of **chunks**, each ~30 seconds of in-game distance, replayed in order. When the strip ends, the camera fades to black for ~2 seconds, the strip resets, and we fade back in. The transition is meant to be felt (a moment of breath) but not jarring.

Each chunk is a **curated composition**:

- 0 – 6 chunks shipped, each with a **theme**:
  - `00_solar_system_sweep` (planets, asteroids, sun glare)
  - `01_interstellar_drift` (sparse, deep starfield, distant nebulae)
  - `02_nebula_dive` (close clouds, dust, foreground filaments)
  - `03_open_cluster_pass` (dense star fields, hot blue stars resolving)
  - `04_black_hole_vicinity` (lensing, accretion glow, gravitational distortion in shader)
  - `05_galactic_arm_traverse` (galaxy-edge, dust lanes, OB associations)
- Each chunk declares a **palette** (overrides per-track tint locally) and a **density profile** (objects/min, types).
- Within a chunk, **events** (sprites, comets, distortions, palette beats) are placed at known distances, not drawn from a uniform random.

The session experience: discrete recognisable acts, looped without feeling looped.

### 4.1 Strip dimensions — wider than the viewport

A strip's logical width is **greater than the viewport**, recommended default `1.4×` (a 1280-wide screen reads from a 1792-wide strip). The viewport's horizontal centre tracks a smoothed `player.position.x`; the strip slides laterally under the screen. The payoff is twofold:

- **Real multi-layer parallax.** Each layer shifts laterally by its own fraction of the player's offset from centre. The skeleton already exists in `BackgroundRenderer` as `lateral_factor_mid / near / top`, but with values like `0.0001 – 0.0006` the effect is fractional pixels per frame — sub-perceptual. With a wider strip, those factors can grow by an order of magnitude without exposing strip edges. Recommended starting depths:

  | Layer | Depth factor | Visible shift at `MAX_SPEED` |
  |---|---|---|
  | Nebula shader (innermost) | `0.05` | barely perceptible |
  | Deep landmarks (galaxy, BH) | `0.20` | gentle |
  | Planets | `0.45` | clear |
  | Foreground asteroids / comets | `0.85` | strong |
  | (Player) | `1.0` | reference |

  Applied as `layer_offset_x = -player_offset_from_centre * depth_factor`. The resulting per-layer differential reads as physical depth.

- **Off-axis composition.** With every body having to fit inside `[0, screen_w]` and look balanced regardless of where the player sits, today's chunks can only frame bodies near horizontal centre. With lateral room, a strip can place a galaxy at strip-x `0.18`, a black hole at `0.84`, a nebula filling `0.30 – 0.95` — and the player only fully *uncovers* that composition by leaning into the side. Strips become explorable on a small scale.

Practical bounds: below `1.2×` the parallax payoff disappears; above `1.6×` the player at MAX_SPEED with `depth_factor = 0.85` can see strip edges. `1.4×` keeps the visible region inside the strip across all layer factors above.

### 4.2 Track alignment — one strip per track

Strip boundaries align with **track endings**, not with internal track structure (drop, post-drop, …). Mapping is **one strip per track**:

- `audio_manager.playlist[i]` ↔ `chunk_provider.chunks[i]`
- `audio_manager.is_transitioning` (the existing track-end gate) → triggers `BackgroundDirector.begin_transition()`
- The 5 s track-transition gap subdivides cleanly as `0 – 2 s` strip fade-out, `2 – 3 s` black, `3 – 5 s` next strip fade-in. The player perceives **one** break (the music handing off and the universe handing off, in lockstep), not two layered ones.

Why not strip-changes mid-track: a strip transition is a 2 s fade-to-black. Inserting one mid-track is a discontinuity the music does not motivate. Inserting one *only* at the track gap uses time the player is already perceiving as "between things".

Implication for strip length: a strip needs to last at least one track. With current tracks (1.5 – 3 min) and `gsm = 1.0` baseline, that's a distance budget of roughly **1500 – 3500 distance units** per strip. The strip is **not** fixed-length — it ends when its track ends. The author composes for the expected track length plus a 30 % buffer of filler:

- If authored events finish before the track does, a `deep_transit` tail-loop kicks in (uniform deep-space starfield + occasional comet, no landmarks). It's intentionally low-density so the strip can extend by minutes without recognisable repeats.
- If the track ends before the authored events finish, unplayed events are skipped. Skip pressure is reduced by composing the most "important" events early in the chunk's distance budget.

This also resolves a previously open question: chunk pacing is **distance-keyed internally** (events fire at the distance the player crosses) but **track-keyed externally** (the strip's lifecycle is the track's lifecycle).

## 5. Three architectural approaches

### Option A — Extend the current ad-hoc spawner

Add more PNGs and more pools, randomise harder, weight by recent-history.

- ✅ Smallest code delta.
- ✅ No new file format.
- ❌ Doesn't solve composition. Still uniform random density.
- ❌ Doesn't prevent collisions between bodies or give cinematography.
- ❌ Boredom kicks in at the same point (~5 min) just with different repeats.

Verdict: **insufficient**. This is what we have, with more assets. Worth doing anyway as a stopgap; not the v2.

### Option B — Hand-authored chunks as `.tres` resources

A chunk is a `BackgroundChunk.gd` Resource with an array of `BackgroundEvent`s, each declaring `(distance_offset, kind, x_ratio, scale, modulate, …)`. The director streams events into the active window. Six chunks shipped; play in order; loop.

- ✅ Total artistic control. Each chunk is composed by hand or a small offline tool.
- ✅ Trivial to extend: add a `.tres`, register it in the playlist.
- ✅ Transition logic is straightforward (chunk-end hook fades, chunk-start primes).
- ✅ Maps cleanly onto Godot's Resource system — game designers can edit in the inspector.
- ❌ Requires authoring tooling or a careful hand-edit workflow.
- ❌ At least a few hours per chunk to compose well.
- ➖ The procedural shader nebula stays. It's good. It runs *under* the chunk content.

Verdict: **recommended.** The cost is asset & authoring time, which is real but bounded; the gain is structural (boredom-killer) and visual.

### Option C — Generate chunks from a model at build time / on the fly

A `ChunkGenerator` samples from typed pools (planet/nebula/cluster/blackhole/asteroid/comet/cloud_band) under a chunk-level "recipe" (e.g. `dense_cluster`, `void`, `nebula_traverse`). Generates 3 – 4 chunks ahead of the player, hard-bakes them at game-start (or on-the-fly during loading screens between tracks).

- ✅ Variety per session: every run picks different specifics. With seeded RNG, runs can be reproducible.
- ✅ Composes within a recipe — not pure uniform random.
- ✅ Extensible: a new recipe is a new template, not a new chunk.
- ❌ More code. Recipes need a small DSL or schema.
- ❌ Authoring composition rules is harder than authoring a single composition.
- ❌ Still bounded by asset count: same N PNGs reused with different framings.

Verdict: **defer, build on top of B.** Once Option B is shipping, Option C is "swap the chunk source from `.tres` files to a generator". Same downstream pipeline.

## 6. Recommended path: B with C-shaped seams

Ship Option B first. Treat the `.tres` chunks as the source of truth. Build the streaming + transition logic to be **agnostic to where chunks come from** — a `ChunkProvider` interface with one implementation today (`StaticChunkPlaylist`) and one stubbed for tomorrow (`GeneratedChunkProvider`).

The proposed runtime structure:

```
Main
└── BackgroundRenderer
    ├── nebula_bg (ColorRect, shader)         — keep as-is, palette-driven
    ├── chunk_layer (Node2D)                  — replaces deep_layer + planet_layer
    │   └── BackgroundDirector (Node)
    │       ├── chunk_provider: ChunkProvider — interface, default StaticChunkPlaylist
    │       ├── active_chunks: Array[Chunk]   — current + ~1.5 ahead
    │       └── live_sprites: Array[Sprite2D] — in viewport window
    └── (CPU layers stay for foreground comets/asteroids)
```

`BackgroundDirector` owns:

- **Window**: events whose distance is in `[player_dist - 200, player_dist + 1500]` are alive.
- **Materialisation**: events become `Sprite2D` (or `ColorRect` with shader, for distortions) on entering the window. Each event carries a `strip_x` in `[0, strip_width]` (wider than viewport — see §4.1); render position is `(strip_x - viewport_offset_x * layer.depth_factor, distance_y)`. `queue_free()` on exit.
- **Lateral camera**: `viewport_offset_x` is a smoothed lerp of `(player.position.x - screen_w / 2)`. Each layer reads it scaled by its own `depth_factor` (table in §4.1). The nebula shader receives a `lateral_offset` uniform applied to the cloud / starfield UVs at `0.05 ×` the player offset.
- **Track binding**: subscribes to `audio_manager.is_transitioning`. On track gap, calls `begin_transition()`, advances the chunk pointer, primes the next chunk's palette and `width_multiplier`. The 5 s track-transition window is the strip-transition window — same animation curve (see §4.2).
- **Tail-loop / skip**: when authored events for the active strip exhaust before the track ends, falls back to a `deep_transit` filler (uniform sparse starfield + comets at low rate). When the track ends with unplayed events queued, they're discarded.
- **Loop**: when `chunk_provider` runs out of chunks, it cycles back to chunk 0 with an optional palette permutation; the player perceives the loop as a colour shift, not a structural reset.

`ChunkProvider` is the seam where Option C plugs in later — static array today, model later.

The shader stays. It runs underneath. Per-chunk palette overrides are passed as additional uniforms or as a tween of the existing `c_bg / c_neb1 / c_neb2`.

The current CPU layers (comet, asteroid, near, top) collapse to: foreground comets/asteroids only, on `layer_top`. Mid/near star fields and deep landmarks move into chunk events.

## 7. Asset specifications

To keep this concrete, what to produce now:

### Format

- **PNG with alpha**, sRGB.
- **Premultiplied alpha** preferred (Godot's `process/premult_alpha` import flag handles it). Removes fringing on bright edges against dark space.
- **Power-of-two dimensions** preferred (256, 512, 1024) for VRAM efficiency on web. Not required, but it reads cleaner on Compatibility.

### Sizes by kind

| Kind | Native px (w × h) | Notes |
|---|---|---|
| planet, small | 256 × 256 | Mercury-size up to Mars-size |
| planet, large | 512 × 512 | Jupiter, Saturn (with rings; rings *can* extend beyond the body, so reserve canvas) |
| moon, asteroid, fragment | 128 × 128 | foreground bodies; multiple per chunk |
| nebula, large | 1024 × 1024 | dominates a chunk; sized to fill ~70 % of viewport height |
| nebula, filament | 512 × 1024 | tall, vertical; designed to sweep past the camera |
| galaxy, face-on | 768 × 768 | spirals, ellipticals |
| galaxy, edge-on | 1024 × 384 | dust lane horizontally — dramatic when entering |
| globular cluster | 384 × 384 | dense star bunch |
| black hole | 512 × 512 | accretion disc; intentionally smaller than nebulae |
| structure / station | 256 × 512 | optional: human-built objects, vertical orientation |

Sizes are **target** — Godot scales freely; oversize sources lose nothing visually but cost VRAM and download size on web. Keep total bg PNG payload under ~5 MB compressed. The wider strip (§4.1) does **not** require larger source PNGs — it just gives bodies a wider canvas to be *placed in*. A nebula meant to fill the screen vertically still wants `1024 × 1024`; a galaxy framed off-axis at strip-x `0.18` is still a `768 × 768`.

### Sources

Public-domain / CC0:

- **NASA / ESA Hubble** — most bodies, public domain (with a usage notice). Good catalogue at [esahubble.org](https://esahubble.org/images/) — filter by `Image Use Policy: Free for non-commercial`.
- **NASA APOD** — frequently public domain. Always check per-image credit.
- **JWST** — public domain. Excellent for nebulae and deep field.
- **Solar System** — NASA's planetary missions (Cassini, Voyager, New Horizons, Juno, MRO) are public domain. The current `planets/01_mercury.png … 08_neptune.png` set lives here.

Do not use Stellarium or anything CC-BY-SA without including attribution and the SA clause — too messy for a game.

### Folder structure (proposed)

```
bg/
├── library/
│   ├── planets/        — used by chunk events; the existing planets/01_…08_… can move here
│   ├── moons/          — small bodies, named (Europa, Titan, Enceladus, …)
│   ├── nebulae/        — Carina, Eagle, Veil, Horsehead, Crab, Trifid …
│   ├── galaxies/       — Andromeda (have it), Sombrero, Pinwheel, Centaurus A, NGC1300 …
│   ├── clusters/       — globular: M13 (have it), M22, Omega Cen; open: Pleiades, Hyades
│   ├── black_holes/    — current Kerr render + variants
│   └── structures/     — optional, sci-fi flavour
└── chunks/
    ├── 00_solar_system_sweep.tres
    ├── 01_interstellar_drift.tres
    ├── 02_nebula_dive.tres
    ├── 03_open_cluster_pass.tres
    ├── 04_black_hole_vicinity.tres
    └── 05_galactic_arm_traverse.tres
```

`library/` is flat; chunks reference paths.

### What to produce first (minimum viable)

- 6 planet/moon shots (one solar-system flyby chunk needs ~6 distinct bodies).
- 3 nebulae (one nebula-dive chunk).
- 3 galaxies, varied composition (one galactic arm chunk).
- 1 dense cluster image (one cluster pass).
- 1 enhanced black hole (one BH vicinity chunk).

That's ~14 new images. Plus the existing 12 carry forward into `library/`.

## 8. Migration plan

Phased, each phase shippable on its own:

**Phase 0** *(this PR / next release)* — Document the plan, freeze the current background as v1, fix the cloud direction bug. **Done.**

**Phase 1** — Add `BackgroundChunk` and `BackgroundEvent` resources (with `width_multiplier`, `palette`, `events[]`, `shader_override`). Add `BackgroundDirector` with a `StaticChunkPlaylist` containing **a single chunk that reproduces today's behaviour** (`legacy_random_drift`, `width_multiplier = 1.0`, no lateral camera). Replace the spawners in `BackgroundRenderer` with calls into the director; subscribe to `audio_manager.is_transitioning` for the track-aligned transition. No visible change. Tests confirm distance-based pacing identical to v1. *Risk: low. Output: same look, new pipeline, track binding wired up.*

**Phase 1.5** — Wire lateral camera. Director computes `viewport_offset_x` from `player.position.x`. Apply per-layer depth factors (start with the §4.1 table). Bump `legacy_random_drift.width_multiplier` to `1.4` and let the existing sprites place freely in the wider strip. *Risk: medium — first visually-novel change. Output: the parallax that the current `lateral_factor_*` constants only hint at.*

**Phase 2** — Compose the first real chunk by hand: `00_solar_system_sweep.tres`, `width_multiplier = 1.4`. Slot it into the playlist matching `audio_manager.playlist[0]`. Tail-loop `deep_transit` filler if the track length exceeds the authored events. *Risk: low. Output: first themed strip aligned 1:1 with first track.*

**Phase 3** — Compose remaining chunks (5 more). Each is a half-day of design + tuning. Drop `legacy_random_drift` once chunk 0 – 5 cover full session length. *Risk: time. Output: full v2 experience.*

**Phase 4** — Implement the chunk transition (fade-to-black + audio-reactivity damp on chunk boundary). 1 day. *Risk: low. Output: polish.*

**Phase 5** *(optional)* — Implement `GeneratedChunkProvider` (Option C). Recipes drive a small generator. Not needed if Phase 3 produces enough variety per session. *Risk: medium. Output: per-session variety.*

## 9. Open questions

- ~~**Chunk length / time vs distance**~~ — resolved in §4.2: distance-keyed internally, track-keyed externally.
- ~~**Audio coupling**~~ — resolved in §4.2: 1:1 with the playlist, transitions ride the existing 5 s track gap.
- **Per-chunk shader variants**: the nebula shader is one fullscreen pass today. A chunk like `04_black_hole_vicinity` may want a custom shader (lensing, distortion). Plan: a chunk can declare an optional `shader_override` Resource; the director swaps the ColorRect material for the duration of the chunk and restores it on exit.
- **VRAM budget on web**: 30 PNGs at ~512 px average ≈ ~30 MB uncompressed in VRAM. With Godot's lossless texture import, the download is ~5 – 8 MB. Acceptable. Lossy compression would shave another 50 % at the cost of banding on smooth nebulae — not worth it.
- **Lateral parallax tuning**: the depth-factor table in §4.1 (`0.05 / 0.20 / 0.45 / 0.85`) is a starting estimate. Real values come from a debug overlay (toggle a wireframe of strip + viewport sample window) and a/b feel testing. Per-chunk overrides are cheap (just a few floats in the chunk Resource) if a specific scene wants a different depth distribution — e.g. `04_black_hole_vicinity` may want flatter parallax to keep the BH near-static.
- **Strip width per chunk**: `1.4×` is the proposed default but may not suit every theme. A `02_nebula_dive` strip filled with foreground filaments may want `1.2×` (tighter feel, more claustrophobic); a `05_galactic_arm_traverse` may want `1.6×` (open, panoramic). Make `width_multiplier` a per-chunk Resource field with sensible default.
- **Filler character**: `deep_transit` is intentionally minimal so it can extend by minutes without repeats, but the player may notice the *transition into* filler as "things got quiet, did the game break?". Mitigation: filler picks up the **chunk's own palette** so the colour stays continuous; only the event density drops. If still perceptible, escalate to per-chunk filler variants.

---

That's the plan. Phase 0 ships now (this PR). Phase 1 is the natural next checkpoint and the correct place to commit before any artistic work begins, because it lets us validate the pipeline against the current behaviour before swapping content.
