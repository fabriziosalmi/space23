# Changelog

All notable changes to SPACE23 will be documented in this file.

## [0.2.0] - 2026-05-09

Minor bump rolling up the **v0.1.18 → v0.1.24 audit campaign** — six rigorous rounds, ~30 fixes across the codebase. Critical mechanics that were silently broken since their introduction now actually work; UX gaps closed; robustness hardened; dead code cleaned. No new features and no intentional behaviour changes outside the bugs being closed.

### Critical mechanics restored
- **Graze never paid out** — `Dictionary.has(key)` returns true on key existence, not value, so the gating condition was always false. The risk/reward "skim past bullets" loop was dead since written. (v0.1.20)
- **Top-half time bonus always 0** — `int(15 * delta * factor)` truncated to 0 every frame at 60 fps. Replaced with float accumulator. (v0.1.20)
- **Boss-class enemies were ~85% phantom** — bullet vs enemy collision used `distance² < 35²` against `e.pos` as a point. Mothership (300×180 silhouette) only hittable inside a 35-radius circle around its centre; player could park *inside* the boss without taking body damage. Replaced with per-type AABB stored on each spawn, point-in-box collision. (v0.1.20)
- **Smart bomb bypassed `handle_enemy_kill`** — boss killed by bomb got `+100` instead of `+5000`, no lensing, no big hit-stop, boss HP bar stayed visible. (v0.1.18)
- **Player kept moving and firing during pause and hit-stop** — bullets accumulated while world was frozen, then launched in a burst on unpause / hit-stop end. (v0.1.18, v0.1.20)
- **Powerup timers cannibalised each other** — single `fire_buff_timer` shared between railgun and drones; pickup of one shortened the other. (v0.1.20)
- **`_tick_*` systems kept running during GAMEOVER** — enemies inseguivano un cadavere invisibile, body collisions fired SFX/shake/damage on the corpse, in-flight heal could resurrect HP while still in GAMEOVER. (v0.1.20)
- **Player powerup / cooldown timers decayed with `gsm`** — drop boost (gsm=4×) made `10s` railgun last 2.5s wallclock; intro / transition stretched timers. (v0.1.20)
- **Two boss spawns possible across track transition** — boss surviving track end stacked with the next track's boss spawn 30s later. (v0.1.20)
- **`target_speed_multiplier` could reach 7.2×** — drop × max flow gave un-dodgeable boss combat. Switched flow bonus to additive: max 4.8×. (v0.1.20)

### UX / frontend hardening
- **Window resize broke everything** — UI elements stuck at old coords, BG strip / parallax wrong, post-FX rect wrong size, gameplay systems culling at old screen bounds. Full size_changed handlers in UIManager, PostFXController, BackgroundRenderer, Main. (v0.1.21, v0.1.22)
- **Aspect ratio hardcoded `1.77` in post.gdshader** — BH lens and radial-blur masks deformed into ellipses on portrait / square viewports. `uniform float aspect`, set on setup + resize. (v0.1.21)
- **Leaderboard never visible after first game over** — hidden in `_input` on title-leave, only ever un-hidden once. Now shown in `show_game_over`. (v0.1.21)
- **Instant-retry shortcut silently dropped the run's score** — `ui_accept` at game over called `_on_retry_pressed` directly, name input never submitted, save never ran. `auto_save_pending_score` saves with typed text or `"ANON"` before retry. (v0.1.21)
- **No focus-loss pause** — Alt-Tab during gameplay let the world keep running in background, returning to a corpse. Now connected to `Window.focus_exited`, also covers INTRO. (v0.1.22, v0.1.24)
- **Default Godot grey ProgressBar theme on HP / boss HP** clashed with neon HUD. `_apply_neon_progressbar_theme` styles them. (v0.1.21)
- **`KILLS` label was actually composite score** (kills + grazes + top-half bonus). Renamed `SCORE`. (v0.1.21)
- **No control hints on title screen** — new players were guessing bindings. `controls_label` lists WASD/STICK • SPACE/A • SHIFT/B • X/Y • ESC/START. (v0.1.21)
- **Mouse off-screen left ship at max roll forever** — clamp `target_pos` to playable bounds. (v0.1.19)
- **Pause label said `TAP / ESC` only** — joypad players didn't know `START` toggled pause. Updated. (v0.1.21)

### Robustness / persistence
- **`load_highscores` could crash on null `FileAccess.open` or malformed entry** — defensive null guard, per-entry `_is_valid_highscore_entry` validation. (v0.1.22)
- **`save_highscore` could crash on write failure** — null guard. (v0.1.22)
- **Player name not sanitized** — embedded tab/newline/emoji broke fix-width leaderboard layout. `_sanitize_name` filters `[A-Z0-9 ]`, cap 8 chars. (v0.1.22)
- **`crab_line` could call `randf_range(min, max)` with `max < min`** on narrow viewports + high count → garbage spawn position. Clamped. (v0.1.18)
- **BlackHole bullet absorb used a magic-number marker (`pos.y = 9999`) + missed `dist` recompute after `move_toward`** — replaced with direct removal + recompute. (v0.1.20)

### Health / cleanup
- **Per-frame `world_env.environment.glow_intensity = 1.8`** — already set in `_ready`, redundant work every frame. (v0.1.23)
- **Dead `Player.max_speed/acceleration/friction` compat vars** — comment claimed compat but zero call sites. (v0.1.23)
- **Dead `AudioManager.set_pitch_scale/get_pitch_scale`** wrappers — no callers. (v0.1.23)
- **`set_meta("audio_mid")` for inter-method state passing** — replaced with `last_audio_mid` member var. (v0.1.23)
- **Dead `is_playing` flag** — set once, never reset, only reader was redundant with the `game_state == "TITLE"` gate above it. (v0.1.22)
- **Tautological `and game_state != "GAMEOVER"`** in damage_player — already guarded by early-return at top. (v0.1.24)
- **`shake_time` accumulator unbounded** — float32 precision degrades after ~4h. `fmod` wrap. (v0.1.24)

See **v0.1.18 → v0.1.24** below for full per-fix details.

## [0.1.24] - 2026-05-09

A round-6 defensive correctness pass — small, real, no over-engineering.

### Fixed
- **Pause did not work during INTRO.** `toggle_pause` early-returned on `game_state != "PLAYING"` — but INTRO is a 2-second pre-gameplay state where the player can be disoriented if interrupted. Alt-Tab during INTRO let the game run in the background: `intro_timer` ticked down, gameplay started while the window was unfocused, the player came back to a moving ship taking damage. Fix: relax the gate to `PLAYING or INTRO`. The freeze guard (`if is_paused: return` in `_process`) already handles INTRO transparently — `intro_timer` is part of `_tick_intro` which doesn't run during pause, so the countdown is correctly suspended. `_on_focus_lost` extended to match.
- **Intro→PLAYING transition left `target_speed_multiplier = 0.1` for one frame.** `_tick_intro` set `target_speed_multiplier = INTRO_SPEED_MULT (0.1)` every frame. On the frame `intro_timer` reached 0, the function flipped `is_intro = false` and `game_state = "PLAYING"`, but the post-dispatch `gsm = lerp(gsm, target, 4*delta)` still saw `target = 0.1` (set at the start of the same frame's `_tick_intro`). Next frame `_tick_playing` overwrote to 1.0, so the visible effect was tiny — but it was a 1-frame "the world wants to go to 0.1×" lag that didn't need to exist. Fix: explicit `target_speed_multiplier = 1.0` in `_tick_intro`'s end-of-intro block.
- **`shake_time` accumulator could drift float32 precision after long runs.** `shake_time += delta` accumulates without bound. After ~4 hours of uptime, `shake_time` reaches ~14400, and float32 starts losing 1ms of precision per increment — the noise feeding `sin(shake_time * 47)` etc. degrades to step-quantised. Fix: `shake_time = fmod(shake_time + delta, 1000.0)`. The wrap point is far above the lowest noise frequency's period (`2π/19.1 ≈ 0.33s`), so phase-continuity is preserved. Practical impact is for marathon runs only, but defensive cleanup costs nothing.

### Removed
- **Tautological check in `damage_player`.** The function early-returns on `game_state == "GAMEOVER"` at the top, then later did `if player_hp <= 0 and game_state != "GAMEOVER": trigger_game_over()`. The `and game_state != "GAMEOVER"` was always true at that point. Cleanup.

## [0.1.23] - 2026-05-09

A round-5 cleanup pass: dead code, redundant per-frame work, sloppy patterns. No behavioral changes — purely health.

### Removed
- **`Player.max_speed` / `acceleration` / `friction`** instance vars. The comment claimed "Compat: alcuni accessi vengono ancora fatti via `player.max_speed`" but a repo-wide grep found zero call sites. Pure dead vars masquerading as a compatibility shim. The `MAX_SPEED` / `ACCELERATION` / `FRICTION` constants are used directly in `_process`.
- **`AudioManager.set_pitch_scale(scale)` / `get_pitch_scale()`** wrappers. No callers anywhere — `Main.gd` reads and writes `audio_manager.audio_stream_player.pitch_scale` directly (in `_on_retry_pressed` and `_tick_gameover_fx`).
- **`world_env.environment.glow_intensity = 1.8` per-frame assignment** in `Main._process`. The same value is set once in `_ready` and never changed elsewhere — the per-frame line was leftover from when glow was audio-modulated. Pure waste.

### Changed
- **`BackgroundRenderer.audio_mid` plumbing.** `update_background` was passing `audio_mid` to `_draw` via `set_meta("audio_mid", v)` + `get_meta` in `_draw` — using `Object`'s KV store for what is just a member variable. Replaced with `var last_audio_mid: float = 0.0`, written in `update_background`, read in `_draw`. Same pattern as the existing `last_audio_low`.

## [0.1.22] - 2026-05-09

A "round 4" audit covering robustness, persistence, lifecycle, and edge cases not touched by the previous rounds (gameplay backbone, frontend).

### Fixed
- **Window focus loss did not pause the game.** Alt-Tab during gameplay let the game keep running in the background — music, bullets, boss combat, distance accumulating. Player returned to a corpse and a lost score. Fix: connect `get_window().focus_exited` to a `_on_focus_lost` handler that calls `toggle_pause()` if currently in a real PLAYING state.
- **Main camera and gameplay systems didn't follow viewport resize.** UIManager and PostFXController had been wired up to `size_changed` in v0.1.21, but Main itself still cached `screen_size` and `main_camera.position = screen_size / 2.0` from `_ready` only — and the systems (EnemySystem, ProjectileSystem, PowerupSystem) used their own `screen_size` reference set at wiring time, used for cull boundaries and AI movement bounds. On window resize the camera stayed centered on the old viewport and bullets/enemies were culled at the old y coordinates. Fix: connect `get_window().size_changed` in `Main._ready`, propagate the new size to the systems and re-center the camera.
- **BackgroundRenderer didn't follow viewport resize either.** `strip_width` (for the parallax strip), `strip_pad`, `max_player_offset`, and `nebula_bg.size` were all computed once from the initial `screen_size`. After resize, lateral parallax used the wrong strip proportions and the nebula `ColorRect` (overscan = `screen + 400`) left visible black borders on a wider window. Fix: same pattern, `get_window().size_changed` recomputes strip dimensions and resizes `nebula_bg`.
- **`load_highscores` could crash on a corrupt save file.** `FileAccess.open(SAVE_PATH, READ)` can return `null` even when `file_exists()` is true (permissions, locked file, web private mode blocking IndexedDB). The code went straight into `file.get_as_text()` — null deref. Plus: a malformed JSON entry (e.g. `{"name": null}` from a future schema change or a manual edit) would crash `_update_leaderboard_display` later (`entry.name.substr(0,8)` on null). Fix: null-check on `FileAccess.open`; per-entry `_is_valid_highscore_entry` validation before appending to `highscores`. Bad entries are silently dropped (the leaderboard degrades gracefully instead of breaking).
- **`save_highscore` could crash on write failure.** Symmetric to the load path: `FileAccess.open(WRITE)` can return null (disk full, permissions, web private mode). Fix: null-check; if write fails, the in-memory `highscores` is still updated and the leaderboard display refreshes — the player just doesn't persist to disk.
- **Player name was not sanitized.** `_on_name_submitted` did `strip_edges().to_upper()` only. A name with embedded tab, newline, control char, or emoji broke the leaderboard's fix-width layout (`"FOO\tBAR"` shifted the score column for all subsequent entries). Fix: explicit char filter — only `[A-Z0-9 ]`, capped at 8 chars. `_sanitize_name` replaces the inline scrubbing.

### Removed
- **Dead `is_playing` flag.** Set to `true` in `_on_start_pressed`, never reset, only ever read at one early-return that was already redundant with the `if game_state == "TITLE"` gate above it. Pre-start, the TITLE gate already returned. Post-start, `is_playing` was permanently true. Removed both the variable and its sole reader.

## [0.1.21] - 2026-05-09

A frontend-only audit (round 3): UI/UX, graphics, audio, post-FX. Backend gameplay logic out of scope.

### Fixed
- **UI broken on window resize / device rotation.** All position/size assignments in `UIManager._ready` and `PostFXController.setup` cached `screen_size` once. On resize: `pause_dim` no longer covered the viewport (gameplay visible at corners), `bomb_button` floated mid-screen or off-canvas, `pause_label` / `title_label` / `leaderboard_label` / `version_label` / `boss_hp_bar` / `game_over_container` all stuck at old coords, and the post-FX `ColorRect.size` didn't follow either. Fix: extracted screen-dependent positions into `_layout_for_size(s: Vector2)`, connected `get_tree().root.size_changed` in both UIManager and PostFXController. Top-left HUD labels (`dist`/`score`/`hp`/`bomb`) anchored at `(20, …)` are already resize-safe; `flow_label` already recomputed each frame in `update_hud`.
- **Post-FX aspect ratio hardcoded 1.7778 (16:9).** `post.gdshader` did `bh_dir.x *= 1.77` and `from_ship_aspect.x *= 1.77` to keep the BH lens and radial-blur masks circular. On non-16:9 viewports (mobile portrait ~0.56, square ~1.0, ultrawide ~2.4) the mask deformed into stretched ellipses. Fix: added `uniform float aspect`, set from `PostFXController._apply_aspect(s)` at setup and on `size_changed`. Default `1.7778` preserves desktop behaviour.
- **Boss HP bar could show negative value for one frame.** Continuous damage sources (railgun DPS, smart bomb `-50` per loop iteration) push `e.hp` below 0 between damage and the next-frame `handle_enemy_kill` cleanup. `update_boss_hp` set `boss_hp_bar.value = hp` directly — Godot's ProgressBar doesn't auto-clamp `value > 0`. Fix: `boss_hp_bar.value = max(hp, 0.0)`.
- **Leaderboard never visible after first game over.** `leaderboard_label` was hidden in `_input` when leaving TITLE and only un-hidden on first show. After the first game over the player never saw the freshly-saved entry — the social loop ("did I make top 5?") was hidden. Fix: `leaderboard_label.show()` in `show_game_over`, `hide()` in `hide_game_over`. Position remains center+80 (just below the GAME OVER container).
- **Instant-retry shortcut silently dropped the run's score.** Pressing `ui_accept` (Enter / joypad A) at game over with the name input still focused calls `_on_retry_pressed` directly — but `name_input` had not yet emitted its `text_submitted` signal, so `save_highscore` never ran. The player thought they'd hit "quick restart" and lost a high score. Fix: new `auto_save_pending_score()` in UIManager, called by Main's retry path before `hide_game_over`. Saves with the typed name (or `"ANON"` if blank) when name_input is still visible.
- **Boss HP / HP bars used Godot's default gray theme.** The flat-gray ProgressBar fill clashed with the neon aesthetic of the rest of the HUD. Fix: `_apply_neon_progressbar_theme(bar, fill, edge)` helper applies a `StyleBoxFlat` background (dark navy, semi-transparent, bordered) and fill (HDR neon, bordered). Player HP green-cyan, boss HP red-pink.
- **`KILLS` label mislabeled the score.** `score_points` accumulates kills (`+250`/`+5000`), grazes (`+50`, fixed in v0.1.20), and the top-half time bonus (~14 pt/sec, fixed in v0.1.20). Calling it "KILLS" was misleading both before and after the v0.1.20 graze/score fixes. Fix: rename HUD label to `SCORE`, game-over breakdown line to `DIST … + SCORE …`.
- **HUD pulse comment was wrong.** Old comment claimed "ramp-up rapido (lineare) per i primi 30% del timer, poi decay. Picco ~1.6× verso quando il timer è quasi completo (nuovo frame)". Code is just `b = 1.0 + 0.6 * k` where `k` decays from 1 to 0 — pure linear decay, no ramp-up, peak at frame of set. Fix: rewrote comment to match.

### Added
- **Title-screen control hints.** `controls_label` below the leaderboard on TITLE: `WASD / STICK MOVE • SPACE / A FIRE • SHIFT / B DASH • X / Y BOMB • ESC / START PAUSE`. Hidden when game starts (alongside title/leaderboard/version). Pre-fix new players had to guess the bindings or read the README.
- **Pause overlay mentions joypad.** Old text was `TAP / ESC TO RESUME` — joypad players didn't know `START` toggled pause. New: `TAP / ESC / START`.

## [0.1.20] - 2026-05-09

A "round 2" draconian audit of the gameplay backbone — game rules, scoring, hitboxes, state-machine consistency. Eight backend logic bugs found and fixed; UI/audio/graphics out of scope.

### Fixed
- **Graze never fired (CRITICAL).** `ProjectileSystem._tick_enemy_bullets` checked `not b.has("grazed")` to gate the graze branch. `Dictionary.has(key)` returns `true` if the key *exists*, NOT if the value is truthy. Bullets in the pool always have `grazed: false` set in both `_init_pool` and `spawn_enemy_bullet` → key exists → `not b.has("grazed")` was always `false` → **the graze branch never executed**, ever. No `+50` score per graze, no `+0.10` flow per graze, no graze SFX/explosion. The risk/reward "skim past bullets for reward" mechanic was completely dead since whenever it was written. Fix: read the value via `not b.grazed`. One char.
- **Top-half time bonus always zero (CRITICAL).** `_tick_playing` did `score_points += int(15 * delta * (1.0 - player_y_ratio))`. At 60 fps with `delta ≈ 0.0166` and `(1 - y_ratio) ≤ 0.93` (player at top edge), the argument was at most `0.232` → `int(...) = 0`. **Always.** The "DMC risk/reward" comment promised score for staying in the top half; only `flow_state` actually grew. Fix: float accumulator (`score_bonus_accum: float`), flush integer part when ≥ 1. Yields ~14 pt/sec at full top edge, what the constant `15` was originally aiming for.
- **Player bullets phantom-passed boss-class enemies.** Player-bullet vs enemy collision used `distance_squared_to(e.pos) < 35²` — treats the enemy as a point, gives a 35 px circle hit zone around `e.pos`. Correct for scout/fighter/squid (visual extent ≤ 25 px). For mothership (silhouette 300×180, vertices to `Vector2(150, -40)`), only ~15% of the visible silhouette was hittable — bullets visibly hitting the wings did zero damage. Same bug for player vs enemy *body* collision (15 px radius): the player could **park inside the mothership's visible silhouette** without taking body damage. Fix: precompute per-type AABB half-extents (cached, lazy) from `pts`, store on each spawned enemy as `hit_aabb`. Switch both collisions to point-in-box: `abs(dx) < aabb.x + padding`. Bullet padding `20` keeps small enemies' effective area equal to the old 35 px circle (scout AABB 15×15 + 20 → 35×35), boss gets full coverage. Body collision uses `player.HITBOX_RADIUS_BODY (15)` as padding — small enemies stay roughly equivalent, boss becomes correctly impassable.
- **Player powerup timers and dash cooldown decayed with `gsm`.** Mixed regime: `shoot_timer`, `dash_timer`, `hit_iframe_timer`, `hit_flash_timer` used real-time `delta`; `railgun_timer`, `drone_timer`, `drone_shoot_timer`, `drone_angle`, `dash_cooldown` used `engine_delta = delta * gsm`. During drop boost (`gsm = 4×`), engine-time timers ran 4× faster — "10 s railgun" lasted 2.5 s wallclock, "1 s dash cooldown" 0.25 s wallclock (the player was suddenly able to dash 4× more often during the most chaotic moment, an accidental feature). During intro / track transition (`gsm = 0.1-0.5`), the same timers ran 2-10× slower than nominal. Fix: unify to real-time `delta` for all Player timers. The pickup of "10 s" now lasts 10 s of wallclock regardless of `gsm`. `engine_delta` removed entirely from Player.gd.
- **Player moved and fired during hit-stop.** Same pattern as the v0.1.18 pause fix. `Main._process` early-returns on `hit_stop_timer > 0` (freezing all `*_system.tick`), but `Player._process` was not subordinate. During the 1.2 s hit-stop on boss kill, the player kept moving / shooting; bullets accumulated into `player_bullets` while `ProjectileSystem.tick` was frozen → all of them launched in a burst from the spawn point at hit-stop end. Fix: add `hit_stop_timer > 0` to the Player._process freeze guard alongside `is_paused`.
- **Boss could survive a track transition and stack with the next track's boss.** `_tick_track_transition` reset `has_boss_spawned = false` at transition end, but did not clear `enemy_system.enemies`. If the player didn't kill the boss before the track ended (timing edge case), the boss survived the 5 s transition (slow-mo gameplay still ticks enemies), entered the new track with its AI running, and when the new track reached `track_len - 30 s`, `_check_boss_spawn` spawned a *second* boss. Two simultaneous bosses. Fix: at transition end, slate-wipe — clear enemies, projectiles, powerups, railguns, black holes, reset boss HP bar. Explosions intentionally NOT cleared (decay-based; mid-decay cut would look glitchy).
- **`target_speed_multiplier` could reach 7.2× during drop+flow.** Formula was `target = base_target_speed * (1 + flow_state * FLOW_SPEED_BONUS)` — multiplicative. With `base = DROP_SPEED_MULT (4.0)` and max `flow_state (1.0)`: `4.0 × 1.8 = 7.2×`. Boss combat during drop with full flow had bullets at 1440 px/s — physically un-dodgeable. Fix: switch flow bonus to additive: `target = base + flow * FLOW_SPEED_BONUS`. Max during drop is now `4.0 + 0.8 = 4.8×`. Outside drop the difference is negligible (`1 + flow * 0.8 ≈ 1.0 * (1 + flow * 0.8)`).
- **Black hole bullet absorb used a magic-number marker (`pos.y = 9999`).** `BlackHoleSystem.tick` marked absorbed enemy bullets by teleporting them to y=9999 and relying on `ProjectileSystem._tick_enemy_bullets`'s off-screen cull to remove them — one frame later, after the bullet had also wasted a gravity/homing/cull check that frame at its new fake position. Fix: call `projectile_system._remove_enemy_bullet_at(bi)` directly via the existing swap-and-pop helper. Same fix added a `dist` recompute after `move_toward` for both enemies and bullets — without it, the absorb check used a stale pre-move distance, causing 1-frame delay when an enemy/bullet was pulled into the absorb radius (rare but observable on enemies sitting near the gravity boundary).



### Fixed
- **Mouse target left ship banked at max roll when cursor held off-screen.** `Player._process` mouse-control branch computed `target_pos = get_global_mouse_position() - main.main_camera.offset` and added a normalized direction to `input_dir` whenever `distance² > 225` (15 px dead-zone). With the cursor held outside the playable area (web fullscreen, mouse drag past the edge), the ship clamped at the screen border (`position.x = screen_size.x - 80`) but the dead-zone stayed violated (`distance²` against the off-screen target was huge) → input kept pushing into the wall and the silhouette stuck at full roll bank. Fix: clamp `target_pos` to the same `[80, screen-80]` bounds applied to `position` — the dead-zone now disengages as soon as the ship reaches the border, roll returns to 0, no phantom input.
- **`damage_flash_timer` and `heartbeat_timer` not explicitly reset on retry.** In practice both are auto-zeroed before the player notices: `damage_flash_timer` decays in 200 ms while the death scene takes ≥3 s (the GAMEOVER tick keeps the decay running, fixed in v0.1.18), and `heartbeat_timer` is reset to 0 by the gating else-branch on the first PLAYING frame after retry (`player_hp = 100 ≥ 25`). But neither was listed in `_on_retry_pressed`'s explicit reset block alongside `shake_intensity` / `hit_stop_timer` / `boss_lens_timer` / `bomb_buffer_timer` — added now as a backstop, so a future change that keeps `damage_flash` live in GAMEOVER, or alters `player_hp` init at respawn, can't silently break the invariant.

### Polish
- **`_show_play_ui` / `_hide_play_ui` symmetry.** The show-side gated `bomb_button.show()` on `OS.has_feature("mobile") or OS.has_feature("web")`, but the hide-side hid the button unconditionally. Functionally fine (on desktop the button is hidden from init, the unconditional hide is a no-op), but reading the pair gave the wrong impression that the button could appear on desktop in some path. Hide-side now matches the show-side gate.

## [0.1.18] - 2026-05-09

### Fixed
- **Smart bomb bypassed `handle_enemy_kill` → boss kills via bomb were silent.** `Main.trigger_smart_bomb` rolled its own kill loop (`score_points += 100; explosion; remove_at(i)`) instead of calling the centralized `handle_enemy_kill(e)` like every other damage source. Consequences: a boss killed by smart bomb got `+100` instead of `+5000`, no lensing, no `1.2s` hit-stop, no boss SFX, the `boss_hp_bar` stayed visible (because `update_boss_hp(0,100)` was never called), and no powerup drop / flow gain. Fix: replace the inline kill with `handle_enemy_kill(e)` — same path as player bullets, railgun, and BH absorb. The same `Main.gd` comment that already warned about this pattern (vs. railgun and BH) now holds for the bomb too.
- **Player movement, fire, and powerup timers continued during pause.** `Main._process` early-returned on `is_paused` (freezing all `*_system.tick`), but `Player._process` was not subordinate — so position update kept running, `shoot_timer` decayed (bullets pushed into `player_bullets` while `ProjectileSystem.tick` was off → all of them launched in a burst from the spawn point on unpause), and `fire_buff_timer` ticked away (you lost powerups while paused). Fix: `if main.is_paused: return` at the top of `Player._process`.
- **Powerup buffs cannibalised each other (drones + railgun).** A single `fire_buff_timer` was shared between railgun pickup (`= 10.0`) and drones pickup (`= 15.0`). Picking drones (15 s) then railgun 1 s later overwrote to 10 s — losing 4 s of drones. Picking railgun (10 s) then drones (15 s) kept `weapon_type = 1` while extending lifetime to 15 s — you'd shoot the railgun pattern for 15 s after pickup of "drones". Fix: split into `railgun_timer` and `drone_timer`, each independently ticked. Pickup uses `max(timer, duration)` (refresh-not-overwrite). The shoot-path quad-cannon branch was previously gated on `fire_buff_timer > 0.0` — semantically that meant "drones active" → now reads `drone_active` directly.
- **All gameplay systems kept ticking during `GAMEOVER`.** The state-machine dispatch was exclusive (good), but the post-dispatch block ran every system unconditionally. Symptoms: enemies kept moving / shooting / colliding with the (invisible) corpse → body-collision branch fired `add_shake(25)` + `trigger_hit_stop(0.05)` + `damage_player` SFX/flash on top of the death scene; an in-flight heal powerup could touch the corpse and call `main.heal(40)` while still in `GAMEOVER` (resurrected `player_hp` with no state transition); enemy bullets kept colliding and calling `damage_player` rumorously. Fix: in `GAMEOVER` the loop runs `_tick_gameover_fx` + `explosion_system.tick` (final super-explosion must decay) + `_update_post_fx` + `bg_renderer.update_background`, lerps `global_speed_multiplier` toward 0 (death slow-mo), then `return`. Defensive backstop added to `damage_player`: early-return on `game_state == "GAMEOVER"` so any future code path that touches the corpse can't trigger SFX/flash either.
- **Bomb input buffer was too short to cover non-PLAYING states.** `BOMB_INPUT_BUFFER = 0.18s` is correct for the "6-10 frames input lenience" intent, but the timer also decayed during INTRO (2 s), `is_transitioning` (5 s), and `hit_stop_timer` (up to 1.2 s on boss kill) — so a bomb pressed during the intro or right at boss kill got silently dropped. Fix: the buffer now decays only when consumption is actually possible (`game_state == "PLAYING"` and not transitioning and `hit_stop_timer <= 0`). The press survives non-PLAYING states and gets consumed at the first PLAYING frame, as the original comment promised.
- **`crab_line` could call `randf_range(min, max)` with `max < min`.** The wave pattern computed `randf_range(120, screen_size.x - 120 - count * 100)`. With `count` boosted by `density` and a narrow viewport (e.g. 1024 px web), `screen_size.x - 120 - count * 100` can go negative — `randf_range` returns out-of-range garbage and the line spawns somewhere weird (or fully off-screen). Fix: clamp `cmax_x = max(120, ...)` so when the line doesn't fit, it starts at the left margin instead.

## [0.1.17] - 2026-05-08

### Fixed
- **Wing-tip nav lights showed dark square boxes around them.** A user screenshot caught the issue cleanly. The single `draw_circle(WING_TIP_*, 2.5, nav_red * pulse)` with HDR brightness rgb `3.0` was triggering an artefact of Godot's 2D bloom downsample: at the lowest glow mip, a tiny bright HDR point becomes a quantised few-pixel square, visible as a dark-bounded "square box" silhouetted against the black background. Fix: rounded glow via 3 concentric `draw_circle` layers per light — outer halo (8 px, dim alpha 0.18), mid glow (4.5 px, near-bloom-threshold alpha 0.55), core (2 px, moderately HDR rgb `1.3` instead of `3.0`). The geometric multi-circle gradient is bloom-independent, masks any residual bloom blockiness, and the dropped HDR core means the bloom itself is gentler. Pulse animation preserved.

## [0.1.16] - 2026-05-08

### Removed
- **SuperHot velocity coupling.** v0.1.15 reduced the dilation magnitude from `[0.5, 1.0]` to `[0.9, 1.0]` but the user reported that even at 10% the synchronous oscillation was still readable as "il mondo cambia velocità con me" = artificial. Diagnosis: the oscillation is intrinsic to the `player.velocity → gsm` coupling, not to having a global multiplier. Fix: kill the coupling entirely (Opzione α). World now runs at constant rate during `PLAYING`. Speed moments still happen on discrete events: drop boost (4×), hit-stop (frame skip), track transition (0.5×), intro (0.1×), dash (Player boosts its own velocity, gsm stays at 1.0). `flow_state` continues to add a slow-rate bias (0.08/s gain — perceived as a trend, not as oscillation). Trade-off accepted: the "il mondo ha leggero peso da fermo" feel is gone — at `[0.9, 1.0]` it was already ≤10 % effect anyway.

### Fixed
- **Starfield layer 2 too-big stars.** The procedural starfield's second layer had `core_radius = 0.05` and a `× 1.2 × (0.8 + audio_high * 0.5)` brightness multiplier — peak ~1.56 in HDR, well above the bloom threshold (0.9) → constant haloed "big stars" rather than the intended sparse accents. Tuned: density `75 → 55`, core `0.05 → 0.04`, multiplier `1.2 → 0.9`, `appear_thr 0.992 → 0.994` (~25 % fewer stars). Peak now ~1.17 → bloom triggers only on the actual highest twinkle/audio peaks. Layer 1 (the small frequent stars) untouched.
- **Starfield row-aligned columns.** The `starfield_layer` used `floor(uv * density)` for cell placement → axis-aligned grid → vertical scrolling made stars in the same x-cell appear as visible columns/lines. Fix: row-stagger inside `starfield_layer` — alternate rows shift x by half a cell (`grid.x += step(1.0, mod(floor(grid.y), 2.0)) * 0.5`). Brick-pattern grid breaks the column perception while preserving per-cell deterministic randomness. Zero perf cost.

### Documentation
- **README refreshed.** Removed the false SUPERHOT claim; updated enemy count to "twelve enemy variants across six AI patterns" (12 entries in `ENEMY_TYPES` since the wave expansion); added the gamepad/joypad controls section (joypad support shipped in v0.1.15 but was undocumented); added Highlights bullets for the audio-reactive elements that grew over the polish releases (palette tease, powerup ring, lateral parallax, synth audio fallback for web, low-HP heartbeat, damage edge glow, boss telegraph + charge SFX).

## [0.1.15] - 2026-05-08

### Added
- **Joypad / gamepad USB support (Livello A — digital).** Xbox/PS-layout bindings added to `InputMap` alongside the existing keyboard ones. Mapping: D-pad + left stick → `move_*`, A / RB → `fire`, B / LB → `dash`, X / Y → `bomb`, Start → `pause`, any button → title-screen "tap to start", `ui_accept` (A) → game-over retry (Godot built-in, already worked). Player.gd / UIManager.gd code unchanged — the actions feed both keyboard and joypad transparently. Livello A: stick deadzone 0.5 (Godot default) → digital-only (sotto 50% inclinazione = niente, sopra = full speed). Livello B (analogico graduato via `get_action_strength` + `limit_length(1.0)`) deferred — better feel ma più lavoro.

### Changed
- **SuperHot dilation magnitude reduced [0.5, 1.0] → [0.9, 1.0].** User-reported P0: even with the v0.1.6 fix (floor 0.5, lerp 4/s), the gsm still oscillated continuously between ~0.6 and ~0.95 at the rhythm of the player's velocity changes — every gsm-scaled system (enemy bullets, enemies, BG scroll, comets, distance counter) pulsed in lockstep, which the brain reads as "the world is changing speed with me" = artificial, regardless of how smooth the lerp is. Tightening the clamp to `[0.9, 1.0]` drops the oscillation amplitude from 50% to 10% — below the threshold of "the world is visibly cycling speed". SuperHot survives as a subtle *feeling* (the world has slight weight when the player stops) without the synchronised oscillation. The dash still forces `speed_ratio = 1.0`, flow and drop boost unaffected. If further reduction is needed (i.e. user still perceives sync), the escalation is to decouple `BackgroundRenderer`'s scroll from gsm — bigger fix, deferred until needed.

## [0.1.14] - 2026-05-08

A pure-aesthetic polish pass — 9 subliminal touches integrated into existing systems. Each individually adds 2-5% to the perceived "polish"; the cumulative effect shifts the game from "competent prototype" to "someone cared about the corners". No new infrastructure, no AI-slop visual spam.

### Added
- **HUD label brightness pulse on increment.** `KILLS` / `BOMBS` labels brightness-pulse 1.0 → 1.6 × over 100 ms (modulate, multiplicative on font color) when their value changes. `DIST` is excluded (it grows every frame, would be a constant pulse). Sells "this number just changed" without the slop of floating "+250" popups.
- **Powerup spawn ring tell.** When a powerup drops, a 50 px expanding ring at the spawn position, 0.4 s, colored to match powerup type (single source of truth in `PowerupSystem._color_for_type`). New `ExplosionSystem.spawn_ring()` helper — empty shards array, just shockwaves. Sells "qualcosa è apparso" without screen noise.
- **Damage edge glow.** New `damage_flash` uniform in `post.gdshader`, red tint applied via `mask = smoothstep(0.5, 1.0, dist)` — only at screen edges, peak ~17 % mix at corners, centre untouched (ship + bullets remain readable). 200 ms decay from `Main.damage_flash_timer`, set to full on `damage_player`. Soft, leggibile in periferia.
- **Low-HP heartbeat audio.** When `player_hp < 25`, pulse SFX every 0.857 s (~70 bpm), pitch 0.4 (grave), vol −15 dB (quiet, just present). Resets on heal / death / non-PLAYING state. "Il tuo cuore batte, sei ferito" — felt more than heard.
- **Player cockpit calm-breath at low velocity.** Layer added on top of the existing HP-pulse: at velocity = 0 the cockpit gently pulses at ~0.5 Hz, at `MAX_SPEED` the breath fades to zero. 6 % amplitude. Sells "the pilot is breathing" without being twitchy.
- **Vignette bass-breathe in `post.gdshader`.** The inner vignette threshold was a fixed `0.8`; now `0.8 - audio_bass * 0.04`. Imperceptible per-frame but ties post-FX to the music — the screen breathes with the kicks.
- **Rare super-comet variant in `BackgroundRenderer` comet wrap.** 2 % chance on each wrap re-rolls the comet to length × 2 + speed × 1.5. Player sees roughly one super-comet per minute — discoverable, not constant. Matches the spawn distribution otherwise (98 % of wraps stay normal).
- **Track-change palette tease in the last 5 s of the current track.** Soft blend (peak 30 % at the final frame) of the nebula targets toward the next track's palette. `current_c_*` colours (lerp at 0.8/s) reach ~24 % blend before `_tick_track_transition` takes over with the fade-to-black. Sells "the universe feels the impending shift" — subliminal continuity musical↔visual.

### Changed
- **Hit vs kill explosion size differentiation.** Previously every player-bullet hit spawned a 0.3-scale cyan explosion at impact, *plus* a 1.0-scale orange explosion at enemy pos on kill — two explosions on every kill, visually noisy. Now: cyan only on non-lethal hit (scale `0.15`, smaller), nothing on kill (`handle_enemy_kill`'s orange does the work). Reads cleaner: "I hit" vs "I killed" are now visually distinct cues.

### Skipped from the original list
- **Track crossfade cosine ease** — turned out to require retiming the audio handoff (currently at `t=1.0` of the transition; cosine ease wants peak black at `t=0.5`, which means moving the `current_track_idx` switch to mid-transition + extending the `is_transitioning` gate). Not the "1-LOC change" originally estimated. Deferred.

## [0.1.13] - 2026-05-08

### Fixed
- **iOS WebKit: audio + page-reload-on-tap.** User reported on iPhone 16 (Safari, Firefox, Chrome — all WebKit per App Store policy) that audio was completely silent and the page reloaded itself after a few taps. Two distinct iOS WebKit issues, fixed in tandem.
  - **Audio prime** added to `audio-fix.js`. The existing `AudioContext.resume()` was correct on desktop / Android but not sufficient on iOS WebKit, which requires a buffer source to actually start *inside the original user gesture handler* (not in a `.then()` callback, which runs async after the gesture has been consumed). New `primeContext()` queues a 1-sample silent buffer synchronously on the first user gesture; iOS registers it as "audio is playing" and unlocks the pipeline for all subsequent sources. Idempotent via `WeakSet`. No-op on platforms where `resume()` alone already worked.
  - **Viewport meta + iOS-specific CSS** added to `deploy.yml` `html/head_include`. The "page reloads after a few taps" symptom was iOS Safari's double-tap-zoom firing → canvas resize → WebGL context loss in the Compatibility renderer with HDR-2D float framebuffers → engine restart, perceived by the user as a refresh. Fix: explicit `<meta viewport>` with `maximum-scale=1, user-scalable=no, viewport-fit=cover` (kills double-tap zoom, lets the canvas extend under the iPhone notch) plus CSS with `touch-action: manipulation` on body / `none` on canvas (kills the 300 ms tap-delay and any default gesture Safari would hijack), `-webkit-touch-callout: none` (kills the long-press selection menu that interrupts rapid tap input), `position: fixed` on body (kills the rubber-band scroll under the canvas). All no-op on desktop browsers.

## [0.1.12] - 2026-05-08

### Fixed
- **Boss (`MOTHERSHIP`) telegraph extended from 100ms to 350ms + charge SFX.** The previous flash window (`shoot_timer < 0.3 and > 0.2` in `_ai_mothership`) was too short to read; the 16-bullet ring fan felt like cheap chaos that the player either dodged by luck or ate by frame. New window `0.45..0.10` (350ms) + a high-pitch (`pitch=2.5`) "charge" SFX played once on entry to the window — `e.get("telegraph_charging", false)` guard prevents per-frame retrigger. Result: visible warning + audible cue → player has time to position, missed dodge is now skill-based.
- **Intro `5s → 2s`, `WaveDirector.wave_timer 3s → 1s`.** Time to first enemy went from 8s to 3s. The old timing was deadly for a web prototype where "click and immediately see something" is the only way to retain the user past the first second. The intro was originally 5s of cinematic camera pull; 2s is enough to read the title fade-out without overstaying its welcome.
- **Cursor hidden during gameplay (`PLAYING` + `INTRO`); visible in `TITLE` / `GAMEOVER` / `PAUSE`.** Standard arrow cursor was visible during gameplay (annoying on desktop) and during the Game Over screen (anti-aesthetic over the neon UI). New `Main._set_cursor_hidden(bool)` helper called at state transitions. Mouse-driven gameplay still works — Godot tracks `get_global_mouse_position()` regardless of cursor visibility, so the ship continues to follow the (now-invisible) cursor when LMB is held. On touch / mobile the call is a no-op (no system cursor).

## [0.1.11] - 2026-05-08

### Fixed
- **Comet direction randomized on wrap.** A comet that entered moving SW used to re-enter from the top still heading SW — could exit the strip immediately, and its drawn tail (`e.dir`-based) pointed NE while motion was SW (visually contradictory: "tail says it came from the lower-right, but the comet is heading lower-right"). On wrap, `e.dir` is now re-rolled with the same formula as the original spawn (`Vector2(randf_range(-0.5, 0.5), 1.0).normalized()`), so each re-entry reads as a fresh comet with a coherent trajectory.

### Changed
- **`Player.gd` uses a typed `main: Main` ref instead of `get_parent()` defensive checks.** Replaces 9 instances of the prior pattern (`var pn = get_parent(); if pn and pn.get("audio_manager") != null: pn.audio_manager.play_sfx(...)`) with direct typed access (`main.audio_manager.play_sfx(...)`). The `main` ref is set by `Main._ready` immediately after `add_child(player)` — wired before the first `_process` or draw signal fires, so no init-order risk. Net `-40 / +28` in `Player.gd`, `+1` wiring line in `Main._ready`. Behavioural delta: zero. Architectural delta: a future rename of `audio_manager` / `global_speed_multiplier` / `spawn_player_bullet` etc in `Main` now becomes a compile-time error in `Player` instead of silently no-op'ing the call (the prior `if pn.get("X") != null` guard was fail-open — it would have hidden the rename).

## [0.1.10] - 2026-05-08

### Fixed
- **Three correlated kill-flow bugs closed by extracting `Main.handle_enemy_kill(e)`.** Kill FX/score/hit-stop logic was duplicated between `ProjectileSystem._kill_enemy_at` and `RailgunSystem._kill_enemy` (~30 LOC each, already drifting); a third damage source — `BlackHoleSystem` absorption — relied on `EnemySystem`'s `hp<=0` cleanup branch to remove dead enemies, which is a *silent* path (designed for fighters that escape off-top, not for kills). Net player-facing impact: **(1)** boss killed via railgun got normal kill treatment instead of dramatic finish — 250 score instead of 5250 (`SCORE_PER_BOSS + SCORE_PER_KILL`), 0.05 s hit-stop instead of 1.2 s, no boss lensing, no `+100` shake; **(2)** anything killed by black-hole absorption was silently culled — zero score, no explosion, no SFX, so `BH` was effectively a zero-score powerup; **(3)** boss killed by black-hole absorption (rare but reachable since `BH_ABSORB_RADIUS` damage is 100 hp/frame) silently disappeared with no FX at all. The new helper centralises the boss-vs-normal branching: boss path runs the super-explosion + boss-kill SFX + lensing + score, normal path runs the standard explosion + base-hp-bracketed hit-stop. `BlackHoleSystem.tick` was converted from forward to reverse iteration so absorb-kill can `remove_at(ei)` in-place instead of leaving a zombie enemy for one frame; gains a `main` ref wired in `Main._ready`. `RailgunSystem` layers its flavor SFX (pitch 1.5) on top of the centralised kill so the railgun-specific audio cue survives the refactor. Net `-39 LOC`, `+3` bugs closed, `+1` reusable seam.

## [0.1.9] - 2026-05-08

### Added
- **Strip 1.4× + position-keyed lateral parallax (`bg_v2.md` Phase 1.5).** Replaces the velocity-driven `lateral_factor_*` drift in `BackgroundRenderer` (sub-pixel-per-frame, broken when the player held a direction) with a position-keyed model: the universe is now rendered in a strip 1.4× the viewport width; `viewport_offset_x` smoothly tracks `player.position.x` (clamped so the strongest layer never exposes strip edges) and each layer shifts by its own depth factor — nebula shader 0.05 / deep landmarks 0.20 / planets 0.45 / foreground 0.85. CPU layer entries gain a `strip_x` anchor and recompute `pos.x` every frame; planet/deep-landmark sprites store `strip_x` in metadata; `nebula.gdshader` gains a `lateral_offset` uniform applied to all sample UVs (clouds, both starfield layers, streaks). Spawns place bodies across the full strip width, so off-axis composition becomes "discoverable" by leaning sideways — the doc's "explorable on a small scale" payoff. `_has_visible_landmark()` now checks both axes so a body parked off-screen-X (at a strip-edge anchor) doesn't block subsequent on-axis spawns. Skips Phase 1's `BackgroundDirector` / `ChunkProvider` scaffolding by design: that phase is pure refactor for a deferred Phase 2 (hand-authored chunks), and YAGNI applies until a real consumer is greenlit.

## [0.1.8] - 2026-05-08

### Added
- **Perspective fan in `post.gdshader`.** New `perspective_fan` uniform (default `0.05`) that horizontally magnifies the top of the screen by 5 % while leaving the bottom unchanged. Gravity point is bottom-centre — the ship's default position. The warp is applied as the *first* UV transformation in the fragment shader, so the existing lateral pinch then operates on the fan-warped coordinates: the fish-eye underneath gets very slightly deformed by the V, as intended. Cheap (one mul, one add) and fully bypassable by setting the uniform to 0. Sells a subjective / first-person depth without committing to a real perspective rebuild.

## [0.1.7] - 2026-05-08

Closes the background-direction work and lays out the v2 plan.

### Fixed
- **Cloud passes were scrolling up too.** v0.1.6 fixed the starfield and speed-streak passes but left the FBM cloud octaves (n1/n2/n3) on the old direction — they were less visually obvious because clouds are amorphous, but technically still inconsistent with the planets/comets/landmarks moving down. Inverted the base UV scroll (`uv.y -= scroll_time * 0.05`) and flipped the explicit y-component of each octave's time-offset to preserve the differential drift between layers.

### Added
- **`bg_v2.md` — proposal for a chunked, curated, looping universe strip.** Documents the current architecture, three options (extend ad-hoc, hand-authored chunks, generated chunks), the recommended phased path (start with `BackgroundDirector` + `ChunkProvider` interface; ship a single `legacy_random_drift` chunk first to prove the pipeline; layer in hand-composed themed chunks; defer the generator), and asset specs for any new background imagery (PNG sizes, sources, folder layout). Tracked in git so future BG work has a shared reference.

## [0.1.6] - 2026-05-08

The "ship moves forward" pass: stutter loop, reversed starfields, missing player SFX, mobile portrait — all closed in one batch.

### Fixed
- **Sync-stutter loop on all gsm-multiplied elements (bullets, enemies, scroll, comets).** Root cause was *not* a frame-pacing or GC issue. The SuperHot time dilation in `Main._tick_playing` clamped `speed_ratio` at `0.05` (player still ⇒ world at 5 % speed, a 20× slowdown), then `global_speed_multiplier` lerped toward target at only 1.5/s (settling ~1.5 s). Every input cadence (release keys, press keys) drove a slow stop↔move oscillation visible across every system that scales by `gsm`. Tuned to clamp `0.5` (max ×2 dilation) and lerp 4.0/s (settling ~0.5 s). The mechanic still breathes around dash and post-drop, the loop disappears.
- **Three background layers were scrolling in the wrong direction.** `nebula.gdshader`'s starfield 1, starfield 2 and speed-streak passes used `uv.y += scroll_time * X` on a fresh copy of `UV` — which in Godot canvas-item shaders shifts the sample position downward in the texture and makes the *visual* pattern travel **up**. The CPU layers (planets, comets, asteroids, deep landmarks) all use `pos.y += speed * delta` and travel down correctly, so the contradiction was visible: comets going down, stars going up. Inverted the three offsets to `uv.y -= scroll_time * X`. The cloud passes (n1/n2/n3) are intentionally left untouched — they're amorphous, the eye doesn't read direction on them, and they share the base `uv` whose offset is interlocked with the explicit fbm time-offsets at lines 98/99/102. Note: the speed-streak comment already said "scrollano fast verso il basso" — the implementation contradicted the documented intent.

### Added
- **Player shoot SFX.** New `Player._play_shoot_sfx()` — pitch 3.0, volume −10 dB, pan from `position` (same recipe as the graze SFX so it's distinct from kill / boss-kill / pickup / bomb sounds without competing). Called from the buffed and normal fire branches; the railgun branch is intentionally skipped because `RailgunSystem.spawn()` already emits its own SFX (would double up otherwise).
- **Player damage SFX.** `Main.damage_player` now emits `play_sfx(0.4, 0.0, player.position)` right after `trigger_hit_flash()`. Pitch 0.4 = grave / heavy, distinct from kill SFX (0.5/0.8) and from the bomb (0.2). The most important game event was previously silent.
- **Landscape lock on mobile web.** `display/window/handheld/orientation="landscape"` in `project.godot` (hint for native mobile exports), and a CSS-only portrait detector injected via `html/head_include` in the deploy workflow: `@media screen and (orientation: portrait) and (max-width: 1024px)` hides `#canvas`/`#status` and renders a `body::before` "Please rotate your device to landscape" overlay. Pure CSS, no JS, no Screen Orientation API (which Safari iOS won't honour anyway). Desktop browsers are untouched.

## [0.1.5] - 2026-05-08

Hotfix for the boot splash on Pages and a quick warning sweep.

### Fixed
- **Boot splash had white bands top and bottom on Pages.** Root cause: `boot.svg` has `viewBox="0 0 1280 720"` (16:9) but `boot.png` was rasterized at 1280×1280 (1:1) — `qlmanage -t -s 1280` renders into a square canvas, so the SVG content (which fills only the central 16:9 area via the `<rect width="1280" height="720">`) was surrounded by transparent rows 0–280 and 1000–1280. Godot's web shell `<img id="status-splash">` uses `object-fit: contain` over a black `#status` overlay, but the transparent rows let through the underlying browser bg → visible white bands during loading. Fix: center-cropped `boot.png` to 1280×720 (16:9, exact aspect match with the Godot project canvas). With `boot_splash/fullsize=true` the image now covers the splash overlay edge-to-edge.

### Changed
- **GDScript warning sweep.** Removed unused `phase: String` local in `WaveDirector.tick` (it was set in branches but never read; the moltiplicatore lives in `phase_mult`). Annotated `_spawn_pattern` with `@warning_ignore("integer_division")` — the `count / 2` and `w / cols` divisions are intentional integer math for layout offsets. Renamed unused `delta` to `_delta` in `UIManager._process`.

## [0.1.4] - 2026-05-08

Audit pass. Five real issues from a draconian architectural review fixed with rigor, no scope creep.

### Fixed
- **Pause didn't actually freeze gameplay state.** `if is_paused: return` in `Main._process` was placed *after* the camera-shake block, so `shake_intensity` decayed in real-time during the pause. If you paused on a peak hit and waited a second, the unpause resumed with shake already at zero — the moment was lost. Moved the early-return immediately after the pause-toggle input. Now shake, bomb-input buffer, hit-stop and all systems freeze at their exact press-time state and resume seamlessly.
- **`weapon_type == 2` (mirror laser) was unreachable.** The branch existed in `Player._process` and the `SHOOT_RATE_MIRROR_LASER` constant was defined, but no powerup ever set `weapon_type = 2` (`PowerupSystem._apply_pickup` only matches 0–3 with case 2 = drones). Removed the dead branch and the orphan constant; the `# 0=normal, 1=railgun` comment was already accurate.
- **Drone shot was fragile against `spawn_player_bullet` signature drift.** The drone callsite passed `(pos, Vector2.UP, color)` as positional args with a worried "Bug pre-esistente" comment explaining the quirk. Wrapped the callsite in a typed `Main.spawn_drone_bullet(pos, color)` helper that ties the direction to `Vector2.UP` internally — the signature of `spawn_player_bullet` can now evolve without silently breaking the drones. Stale comment removed.
- **Audio synth fallback hardcoded at 130 BPM.** On WebGL Compatibility the spectrum analyzer is muted (Godot bug #115560) and the visual reactivity is carried by a synthesised beat. The synth ran at a fixed `2.17 beats/sec` (130 BPM), so tracks 4–6 (145 BPM per their drop-time annotations) would visibly desync from the music. Added a `bpm` field per playlist entry (130 for tracks 1–3, 145 for 4–6, `DEFAULT_BPM=130` fallback), new `AudioManager.get_current_bpm()`, and the synth derives `bps = bpm/60` from the current track. Magic numbers `12.566` / `25.133` rewritten as `TAU * 2` / `TAU * 4` (mathematically identical at 130 BPM, scale correctly at any BPM).
- **`_drop_force_fired` could get stuck.** The bool one-shot guard for the drop force-spawn had three reset paths but missed edge cases: track change while the flag was still true, song loop / replay, web-export `get_playback_position()` jitter inside the drop window. Replaced with `_drop_fired_for_track: int = -1`, keyed on `audio_manager.current_track_idx`. Auto-invalidates on track change. Reset paths kept for buildup phase, deep-pre (`dt < -BUILDUP_LEAD`) and deep-normal (`dt >= POST_DROP_END`); the transient `[1.0, 3.0)` window deliberately does not reset, so a brief backward jitter into the drop window cannot trigger a re-fire.

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
