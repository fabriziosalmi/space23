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

	// --- BASS PULSE (the violet clouds the player remembers) ---
	// Soft baseline (so the nebula never goes black) + dramatic kick on each beat.
	// audio_low ranges [0..1]; on a strong cassa it lights everything up.
	float bass_baseline = 0.6;
	float bass_kick = audio_low * audio_low * 14.0;  // squared for snappier transient
	float bass_glow = bass_baseline + bass_kick;
	color += c_neb1 * n1 * bass_glow;
	color += c_neb2 * n2 * bass_glow * 0.5;

	// --- MID TEXTURE ---
	// Adds the fine sub-cloud only when mids are present. Tinted halfway between
	// the two main colors so it integrates rather than competing.
	vec3 mid_tint = mix(c_neb1, c_neb2, 0.5);
	color += mid_tint * n3 * audio_mid * 2.0;

	// --- HIGH SPARKLE ---
	// Star-like single-pixel sparkle that animates on hats. Tied to scroll_time
	// so the sparkle pattern slowly drifts with the rest of the universe.
	float sparkle_seed = hash21(floor(uv * 400.0) + floor(scroll_time * 3.0));
	float sparkle = step(1.0 - audio_high * 0.06, sparkle_seed);
	color += vec3(1.5, 1.4, 1.8) * sparkle;

	COLOR = vec4(color, 1.0);
}
