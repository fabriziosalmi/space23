// SPACE23 — Nebula Background v2 (Domain-Warped Hubble/JWST + Hyperspace Warp)
//
// - IQ-style domain-warped FBM + dark cosmic dust lanes for volumetric depth.
// - Band-specific audio reactivity (low/mid/high) kept below bullet-hell contrast ceiling.
// - Dynamic `warp_factor` stretches speed streaks and near stars during Drops & Overdrive.
// - Per-sector `nebula_density` adapts cloud presence to each sector's theme.
shader_type canvas_item;

uniform vec3 c_bg = vec3(0.005, 0.0, 0.015);
uniform vec3 c_neb1 = vec3(0.05, 0.01, 0.1);
uniform vec3 c_neb2 = vec3(0.0, 0.05, 0.15);
uniform float scroll_time = 0.0;
uniform float audio_low = 0.0;
uniform float audio_mid = 0.0;
uniform float audio_high = 0.0;
uniform float lateral_offset = 0.0;
uniform float warp_factor = 0.0;
uniform float nebula_density = 1.0;

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

float fbm4(vec2 p) {
	float f = 0.0;
	float w = 0.5;
	for (int i = 0; i < 4; i++) {
		f += w * noise(p);
		p *= 2.02;
		w *= 0.5;
	}
	return f;
}

float fbm3(vec2 p) {
	float f = 0.0;
	float w = 0.5;
	for (int i = 0; i < 3; i++) {
		f += w * noise(p);
		p *= 2.05;
		w *= 0.5;
	}
	return f;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Procedural starfield with brick-stagger anti-column alignment and warp elongation.
vec3 starfield_layer(vec2 uv, float density, float appear_thr, float core_radius, float twinkle_hz, float stretch_y) {
	vec2 grid = uv * density;
	grid.x += step(1.0, mod(floor(grid.y), 2.0)) * 0.5;
	vec2 cell = floor(grid);
	float h = hash21(cell);
	float visible = step(appear_thr, h);

	vec2 cell_uv = fract(grid);
	vec2 jitter = vec2(hash21(cell + 1.7), hash21(cell + 7.3)) * 0.7 + 0.15;
	vec2 diff = cell_uv - jitter;
	// Elongate star vertically during hyperspace warp (Drop / Overdrive).
	diff.y /= (1.0 + stretch_y);
	float d = length(diff);
	float core = smoothstep(core_radius, 0.0, d);

	float phase = h * 31.4;
	float twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(scroll_time * twinkle_hz + phase));

	float color_seed = hash21(cell + 13.7);
	vec3 tint;
	if      (color_seed < 0.52) tint = vec3(1.00, 0.98, 0.95);  // warm white
	else if (color_seed < 0.76) tint = vec3(0.80, 0.91, 1.00);  // hot blue OB star
	else if (color_seed < 0.92) tint = vec3(1.00, 0.93, 0.74);  // gold giant
	else                         tint = vec3(1.00, 0.78, 0.92); // rose star

	return tint * core * twinkle * visible;
}

void fragment() {
	float lat = lateral_offset * 0.05;

	vec2 uv = UV;
	uv.y -= scroll_time * 0.045;
	uv.x += lat;

	// --- DOMAIN-WARPED FBM (organic swirling cosmic gas) ---
	vec2 q = vec2(
		fbm3(uv * 2.4 + vec2(0.0, -scroll_time * 0.025)),
		fbm3(uv * 2.4 + vec2(5.2, 1.3 + scroll_time * 0.018))
	);
	float n1 = fbm4(uv * 2.8 + q * 1.15 + vec2(scroll_time * 0.015, -scroll_time * 0.035));
	float n2 = fbm3(uv * 5.8 - q * 0.75 + vec2(-scroll_time * 0.01, scroll_time * 0.025));

	// Dark cosmic dust lanes: carved filaments that absorb background light,
	// giving true 3D depth AND darker pockets so neon enemy bullets pop harder.
	float dust = smoothstep(0.18, 0.62, fbm3(uv * 4.2 + q * 0.9 + vec2(2.7, -scroll_time * 0.02)));

	vec3 color = c_bg;
	float cloud1 = smoothstep(0.05, 0.78, n1) * nebula_density;
	float cloud2 = smoothstep(0.15, 0.85, n2) * nebula_density;
	color = mix(color, c_neb1, clamp(cloud1, 0.0, 1.0));
	color = mix(color, c_neb2, clamp(cloud2 * 0.85, 0.0, 1.0));

	// Carve dark dust lanes into the base clouds
	color *= mix(1.0, 0.42, dust * 0.75);

	// --- BASS — warm volumetric glow on warped filaments ---
	float bass_baseline = 1.8;
	float bass_kick = audio_low * audio_low * 13.0;
	color += c_neb1 * max(n1, 0.0) * (bass_baseline + bass_kick) * nebula_density * (1.0 - dust * 0.55);
	color += c_neb2 * max(n2, 0.0) * (bass_baseline * 0.45 + bass_kick * 0.12) * nebula_density;
	color += vec3(0.85, 0.32, 0.14) * audio_low * audio_low * smoothstep(0.32, 0.82, n1) * 1.05 * nebula_density;

	// --- MID — cool cyan filaments along warp ridges ---
	float ridge = 1.0 - abs(n2);
	float mid_glow = audio_mid * 2.2 * nebula_density;
	color += c_neb2 * ridge * ridge * mid_glow * 0.55;
	color += vec3(0.14, 0.52, 0.92) * audio_mid * smoothstep(0.38, 0.85, n2) * 0.75 * nebula_density;

	// --- HIGH — fine stardust sparkle + magenta edge shimmer ---
	float sparkle_seed = hash21(floor(uv * 400.0) + floor(scroll_time * 2.0));
	float sparkle = step(1.0 - audio_high * 0.003, sparkle_seed);
	color += vec3(1.0, 0.88, 1.15) * sparkle;
	color += vec3(0.90, 0.45, 1.0) * audio_high * smoothstep(0.62, 0.9, n2) * 0.6 * nebula_density;

	// --- STARFIELD (2 layers; near layer elongates slightly with warp_factor) ---
	vec2 star_uv1 = UV;
	star_uv1.y -= scroll_time * 0.038;
	star_uv1.x += lat;
	color += starfield_layer(star_uv1, 145.0, 0.985, 0.035, 3.5, warp_factor * 0.4) * (0.72 + audio_mid * 0.35);

	vec2 star_uv2 = UV;
	star_uv2.y -= scroll_time * 0.095;
	star_uv2.x += lat * 1.4;
	color += starfield_layer(star_uv2, 58.0, 0.993, 0.04, 5.0, warp_factor * 2.2) * 0.92 * (0.8 + audio_high * 0.45);

	// --- HYPERSPACE SPEED STREAKS (scale length & density with warp_factor) ---
	vec2 streak_uv = UV;
	streak_uv.y -= scroll_time * (0.18 + warp_factor * 0.22);
	streak_uv.x += lat * 1.8;
	vec2 streak_scale = vec2(160.0, mix(35.0, 14.0, warp_factor));
	vec2 streak_cell = floor(streak_uv * streak_scale);
	float streak_h = hash21(streak_cell + 5.7);
	float streak_thr = mix(0.992, 0.976, warp_factor);
	float streak_visible = step(streak_thr, streak_h);
	vec2 streak_local = fract(streak_uv * streak_scale);
	float streak_jx = hash21(streak_cell + 11.3);
	float streak_bar = smoothstep(0.055, 0.0, abs(streak_local.x - streak_jx));
	float streak_vfade = smoothstep(0.0, 0.22, streak_local.y) * (1.0 - smoothstep(0.72, 1.0, streak_local.y));
	float streak_intensity = (0.16 + audio_low * 0.40 + warp_factor * 0.55);
	vec3 streak_col = mix(vec3(0.82, 0.90, 1.0), vec3(0.65, 0.95, 1.2), warp_factor);
	color += streak_col * streak_bar * streak_vfade * streak_intensity * streak_visible;

	COLOR = vec4(color, 1.0);
}
