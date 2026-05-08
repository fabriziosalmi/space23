// SPACE23 — Nebula Background (audio-reactive on low/mid/high)
//
// - 5-octave FBM mixed onto two cloud bands.
// - Bass (low): drives a *dramatic* pulsation of the violet clouds. Baseline
//   keeps the universe non-black between beats; a multiplicative "kick" punches
//   the clouds bright on each cassa.
// - Mid: modulates a finer, faster sub-cloud (smaller octave) so the nebula
//   has texture even in mid-only sections (intros without bass).
// - High: drives a sparse star-field sparkle on top — micro flicker on hats /
//   percussion.
shader_type canvas_item;

uniform vec3 c_bg = vec3(0.005, 0.0, 0.015);
uniform vec3 c_neb1 = vec3(0.05, 0.01, 0.1);
uniform vec3 c_neb2 = vec3(0.0, 0.05, 0.15);
uniform float scroll_time = 0.0;
uniform float audio_low = 0.0;
uniform float audio_mid = 0.0;
uniform float audio_high = 0.0;
// Lateral parallax: viewport_offset_x / screen_width passed by GDScript.
// Multiplied by 0.05 (DEPTH_NEBULA) before being applied to sample UVs — the
// nebula is the deepest layer, so the shift is barely perceptible (max ~1.2%
// of UV at full player extension). Matches the position-keyed parallax of the
// CPU layers and sprites; without this the nebula would feel locked to the
// camera while everything in front slid past.
uniform float lateral_offset = 0.0;

vec2 random2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(random2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
	               dot(random2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
	           mix(dot(random2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
	               dot(random2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float f = 0.0;
	float w = 0.5;
	for (int i = 0; i < 5; i++) {
		f += w * noise(p);
		p *= 2.0;
		w *= 0.5;
	}
	return f;
}

// Cheap hash for sparkle pixels
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Procedural starfield: layer di stelle su griglia, scrolla verticalmente in
// modo perfettamente loopabile (modulo nelle UV), twinkla con sin sul time
// usando una phase per-stella, ogni stella ha una tinta leggera variata.
//
// Args:
//   uv          : UV già "scrollate" dal caller
//   density     : celle/UV (più alto = più piccole + più dense)
//   appear_thr  : soglia hash sopra cui la cella ha una stella (es 0.985 = ~1.5%)
//   core_radius : dimensione "punto" stella nella cella
//   twinkle_hz  : frequenza twinkle in cicli/sec
vec3 starfield_layer(vec2 uv, float density, float appear_thr, float core_radius, float twinkle_hz) {
	// Single-return path (WebGL 2 / GLSL ES 3 driver-safe: alcuni driver
	// hanno problemi con early-return in fragment shader, soprattutto se
	// seguiti da texture sampling). Visibility = step() · core, moltiplica
	// invece di branchare.
	vec2 cell = floor(uv * density);
	float h = hash21(cell);
	float visible = step(appear_thr, h);

	vec2 cell_uv = fract(uv * density);
	vec2 jitter = vec2(hash21(cell + 1.7), hash21(cell + 7.3)) * 0.7 + 0.15;
	float d = length(cell_uv - jitter);
	float core = smoothstep(core_radius, 0.0, d);

	// Twinkle per-stella (phase = h * 31.4). 0.45-1.0 amp così non spengono mai.
	float phase = h * 31.4;
	float twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(scroll_time * twinkle_hz + phase));

	// Tinta variata per stella: white / pale-blue / pale-yellow / pale-pink.
	// La cascata if/else senza early-return è OK in qualsiasi GLSL.
	float color_seed = hash21(cell + 13.7);
	vec3 tint;
	if      (color_seed < 0.55) tint = vec3(1.00, 0.98, 0.95);  // white-warm (most common)
	else if (color_seed < 0.78) tint = vec3(0.85, 0.92, 1.00);  // pale blue
	else if (color_seed < 0.93) tint = vec3(1.00, 0.95, 0.78);  // pale yellow
	else                         tint = vec3(1.00, 0.82, 0.95); // pink

	return tint * core * twinkle * visible;
}

void fragment() {
	// Lateral shift applied uniformly to all sample UVs (clouds, starfields,
	// streaks). Positive `lateral_offset` (player right of centre) → sample
	// further right in the texture → cloud appears to drift left on screen,
	// matching the parallax of layers in front.
	float lat = lateral_offset * 0.05;

	vec2 uv = UV;
	// Direzione: `-= scroll_time` shifta il sample DOWN ⇒ pattern visibile
	// si muove DOWN (illusione "ship moves forward"). Stessa correzione
	// applicata anche a starfield/streak. Le explicit y-offsets nelle
	// fbm() sotto sono state flippate per mantenere la differential drift
	// inter-octave senza riportare le nuvole nella vecchia direzione UP.
	uv.y -= scroll_time * 0.05;
	uv.x += lat;

	// Two main cloud octaves (bass-driven). Y-component delle additional
	// time-offsets invertita rispetto alla vecchia versione: n1 add `-0.05`,
	// n2 add `+0.03`, n3 add `+0.04` (era +0.05/-0.03/-0.04).
	float n1 = fbm(uv * 3.0 + vec2(scroll_time * 0.02, -scroll_time * 0.05));
	float n2 = fbm(uv * 6.0 + vec2(-scroll_time * 0.01, scroll_time * 0.03));

	// Faster/finer sub-cloud (mid-driven, gives texture even in bass-less sections)
	float n3 = fbm(uv * 12.0 + vec2(scroll_time * 0.08, scroll_time * 0.04));

	vec3 color = c_bg;
	color = mix(color, c_neb1, smoothstep(0.1, 0.8, n1));
	color = mix(color, c_neb2, smoothstep(0.2, 0.9, n2));

	// --- BASS — palette glow on c_neb1 + WARM RED tint band-specific ---
	float bass_baseline = 2.0;
	float bass_kick = audio_low * audio_low * 14.0;
	color += c_neb1 * n1 * (bass_baseline + bass_kick);
	color += c_neb2 * n2 * (bass_baseline * 0.5 + bass_kick * 0.10);

	// Tinta WARM ROSSO/ARANCIO band-specific: ogni cassa "stinge" la nebula
	// di rosso. Indipendente dal palette, così è SEMPRE riconoscibile come
	// "questo è bass" anche su track con palette già viola.
	color += vec3(0.9, 0.35, 0.15) * audio_low * audio_low * smoothstep(0.35, 0.85, n1) * 1.2;

	// --- MID — palette glow on c_neb2 + COOL CYAN/BLUE tint band-specific ---
	float mid_glow = audio_mid * 2.5;
	color += c_neb2 * n2 * mid_glow;
	vec3 mid_tint_palette = mix(c_neb1, c_neb2, 0.7);
	color += mid_tint_palette * n3 * (audio_mid * 2.5);

	// Tinta COOL CIANO band-specific: synth/pad alzano una nube blu
	// indipendente dal palette. Distintiva rispetto al bass red.
	color += vec3(0.15, 0.55, 0.95) * audio_mid * smoothstep(0.4, 0.85, n2) * 0.85;

	// --- HIGH — sparkle + PINK/MAGENTA shimmer band-specific ---
	float sparkle_seed = hash21(floor(uv * 400.0) + floor(scroll_time * 2.0));
	float sparkle = step(1.0 - audio_high * 0.003, sparkle_seed);
	color += vec3(1.0, 0.85, 1.15) * sparkle;

	// Shimmer ROSA/MAGENTA band-specific su hi-hats: tocco di pink sui peak
	// del rumore, riconoscibile come "highs" indipendente dal palette.
	color += vec3(0.95, 0.5, 1.0) * audio_high * smoothstep(0.65, 0.9, n2) * 0.7;

	// --- STARFIELD — 2 layer procedurali in loop, twinkle per-stella ---
	// Density bumped + core_radius reduced: stelle più piccole (puntiformi)
	// mantenendo lo stesso pattern e densità visiva. Era 90/0.05 e 50/0.08
	// → user vedeva stelle "troppo grandi". Adesso 140/0.035 e 75/0.05.
	// Direzione: `-= scroll_time` ⇒ in Godot canvas_item le UV.y crescono
	// verso il basso, quindi sottrarre nel sample shifta il pattern visivo
	// VERSO IL BASSO (illusione "ship moving forward"). Prima era += →
	// stelle salivano verso l'alto, contraddicendo lo scroll dei pianeti
	// e delle comete (che vanno giù).
	vec2 star_uv1 = UV;
	star_uv1.y -= scroll_time * 0.04;
	star_uv1.x += lat;
	color += starfield_layer(star_uv1, 140.0, 0.985, 0.035, 3.5) * (0.7 + audio_mid * 0.4);

	vec2 star_uv2 = UV;
	star_uv2.y -= scroll_time * 0.10;
	star_uv2.x += lat;
	color += starfield_layer(star_uv2, 75.0, 0.992, 0.05, 5.0) * 1.2 * (0.8 + audio_high * 0.5);

	// --- SPEED STREAKS — sottili linee verticali "warp" che vendono velocità ---
	// Pochissime, sottili, scrollano fast verso il basso, intensità modulata
	// dal bass: kick → streak più visibili. "Quasi impercettibili" ma il
	// cervello le legge come "stiamo viaggiando fast". (Stessa correzione
	// di direzione delle starfield: `-=` per scrollare DOWN.)
	vec2 streak_uv = UV;
	streak_uv.y -= scroll_time * 0.18;
	streak_uv.x += lat;
	vec2 streak_cell = floor(streak_uv * vec2(160.0, 35.0));
	float streak_h = hash21(streak_cell + 5.7);
	float streak_visible = step(0.992, streak_h);
	vec2 streak_local = fract(streak_uv * vec2(160.0, 35.0));
	float streak_jx = hash21(streak_cell + 11.3);
	float streak_bar = smoothstep(0.05, 0.0, abs(streak_local.x - streak_jx));
	float streak_vfade = smoothstep(0.0, 0.25, streak_local.y) * (1.0 - smoothstep(0.7, 1.0, streak_local.y));
	float streak_intensity = (0.18 + audio_low * 0.45);
	color += vec3(0.85, 0.9, 1.0) * streak_bar * streak_vfade * streak_intensity * streak_visible;

	COLOR = vec4(color, 1.0);
}
