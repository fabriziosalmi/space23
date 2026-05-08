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

void fragment() {
	vec2 uv = UV;
	uv.y += scroll_time * 0.05;

	// Two main cloud octaves (bass-driven)
	float n1 = fbm(uv * 3.0 + vec2(scroll_time * 0.02, scroll_time * 0.05));
	float n2 = fbm(uv * 6.0 - vec2(scroll_time * 0.01, scroll_time * 0.03));

	// Faster/finer sub-cloud (mid-driven, gives texture even in bass-less sections)
	float n3 = fbm(uv * 12.0 + vec2(scroll_time * 0.08, -scroll_time * 0.04));

	vec3 color = c_bg;
	color = mix(color, c_neb1, smoothstep(0.1, 0.8, n1));
	color = mix(color, c_neb2, smoothstep(0.2, 0.9, n2));

	// --- BASS — pump c_neb1 (violet) on the kick, light touch on c_neb2 ---
	// Bands deliberately split visually: bass dominates c_neb1, mid dominates
	// c_neb2 (below). This way a kick-heavy section reads as "violet pulse"
	// while a synth/pad section reads as "blue surge" — each band has its own
	// visible signature instead of all of them just brightening everything.
	//
	// bass_baseline alto (1.5) = nebula sempre visibile anche con audio_low=0,
	// così le sezioni quiete tra una cassa e l'altra non spegnono il cielo.
	// Era 0.6: troppo basso con la palette scura (c_neb1 ≈ 0.15-0.3 max channel),
	// risultato visivo "nebula scompare quando il bass cala".
	float bass_baseline = 1.5;
	float bass_kick = audio_low * audio_low * 16.0;
	color += c_neb1 * n1 * (bass_baseline + bass_kick);
	color += c_neb2 * n2 * (bass_baseline * 0.4 + bass_kick * 0.15);

	// --- MID — pump c_neb2 + the fine n3 sub-cloud ---
	// Linear gain on the main n2 cloud (more reactive than just the n3 micro-
	// texture) plus the n3 detail tinted toward c_neb2.
	float mid_glow = audio_mid * 2.5;
	color += c_neb2 * n2 * mid_glow;
	vec3 mid_tint = mix(c_neb1, c_neb2, 0.7);
	color += mid_tint * n3 * (audio_mid * 3.5);

	// --- HIGH — sparkle + bright cloud rim on percussion/hats ---
	// 5x more sparkle coverage than before (was 0.06 → invisible at typical
	// audio_high ≈ 0.3 levels). Plus a white rim that lights the brightest
	// noise peaks: gives a "snare flash" feel on hits.
	float sparkle_seed = hash21(floor(uv * 400.0) + floor(scroll_time * 3.0));
	float sparkle = step(1.0 - audio_high * 0.30, sparkle_seed);
	color += vec3(1.5, 1.4, 1.8) * sparkle;
	color += vec3(1.0) * smoothstep(0.55, 0.85, n2) * audio_high * 0.8;

	COLOR = vec4(color, 1.0);
}
