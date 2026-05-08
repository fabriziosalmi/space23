// SPACE23 — Post-Processing Pass
// Pinch laterale, lensing del buco nero, aberrazione cromatica audio-reattiva,
// scanline CRT sottilissime, vignette, zoom-blur (esplosioni / fotofinish), grayscale.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float zoom_blur = 0.0;
uniform float grayscale = 0.0;
uniform vec2 bh_pos = vec2(0.5);
uniform float bh_intensity = 0.0;
uniform float flow_state = 0.0;
uniform float audio_bass = 0.0;
// Radial blur from ship — replaces brute camera shake with a screen-space
// distortion that's centred on the ship (calm) and pulls the edges. Sells
// "punch" without inducing motion sickness.
uniform vec2 ship_uv = vec2(0.5, 0.85);
uniform float radial_blur = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;

	// --- Distorsione a Clessidra (Pinch Laterale) ---
	// Tira le UV verso il centro lungo l'asse X in base all'altezza Y
	vec2 center_dist = uv - vec2(0.5);
	float pinch = sin(uv.y * 3.14159) * 0.06;
	uv.x -= center_dist.x * pinch;

	// --- Buco Nero (Gravitational Lensing) ---
	bool in_bh = false;
	if (bh_intensity > 0.0) {
		vec2 bh_dir = uv - bh_pos;
		bh_dir.x *= 1.77; // Correzione aspect ratio
		float bh_dist = length(bh_dir);
		if (bh_dist < 0.5) {
			float pull = smoothstep(0.5, 0.0, bh_dist);
			uv -= bh_dir * (pull * pull) * bh_intensity * 0.8;
			if (bh_dist < 0.02 * bh_intensity) {
				COLOR = vec4(0.0, 0.0, 0.0, 1.0);
				in_bh = true;
			}
		}
	}

	if (!in_bh) {
		// Ricalcola dopo distorsione per aberrazione e vignettatura
		vec2 dir = uv - vec2(0.5);
		float dist = length(dir);

		// 1. Aberrazione Cromatica Progressiva (Flow + Bass) — molto soft.
		// Era 0.006 + 0.015 + 0.015 = max 0.036 = 46px shift sui peak: ogni
		// stella diventava un triplet RGB chunky e creava "rain" di puntini
		// colorati. Adesso 0.0015 + 0.005 + 0.004 = max ~13px sul bordo a
		// peak audio: percepibile come effetto cinematografico ma le stelle
		// restano bianche e crisp.
		float shift = dist * (0.0015 + flow_state * 0.005 + audio_bass * 0.004);
		float r = texture(screen_tex, uv + dir * shift).r;
		float g = texture(screen_tex, uv).g;
		float b = texture(screen_tex, uv - dir * shift).b;
		vec3 color = vec3(r, g, b);

		// 2. Vignettatura cinematografica
		float vignette = smoothstep(0.8, 0.2, dist);
		color *= mix(0.4, 1.0, vignette);

		// 3. Scanlines CRT sottilissime
		float scanline = sin(uv.y * 1000.0) * 0.03;
		color -= scanline;

		// 4. Zoom Blur FX (Esplosioni / Fotofinish)
		if (zoom_blur > 0.0) {
			vec3 b_color = vec3(0.0);
			float tot = 0.0;
			for (int i = 0; i < 12; i++) {
				float f = float(i) / 12.0;
				float w = 1.0 - f;
				vec2 s_uv = uv + center_dist * f * zoom_blur;
				b_color += texture(screen_tex, s_uv).rgb * w;
				tot += w;
			}
			color = mix(color, b_color / tot, min(zoom_blur * 4.0, 1.0));
		}

		// 5. Grayscale FX (Game Over)
		if (grayscale > 0.0) {
			float gray = dot(color, vec3(0.299, 0.587, 0.114));
			color = mix(color, vec3(gray), grayscale);
		}

		// 6. Radial blur from ship (replaces shake punch). Mask: full effect at
		// edges, zero around the ship (radius 0.18..0.55 with aspect correction).
		// Driven by add_shake → shake_intensity → radial_blur. So every existing
		// add_shake call site (kill, hit, bomb, drop) gets the blur for free,
		// while the camera's physical shake is now small and gentle.
		if (radial_blur > 0.0) {
			vec2 from_ship = uv - ship_uv;
			vec2 from_ship_aspect = from_ship;
			from_ship_aspect.x *= 1.77;  // 16:9 → make mask circular
			float dist_ship = length(from_ship_aspect);
			float mask = smoothstep(0.18, 0.55, dist_ship);
			if (mask > 0.0) {
				vec3 rb = vec3(0.0);
				for (int i = 1; i <= 5; i++) {
					float t = float(i) / 5.0;
					vec2 s_uv = uv + from_ship * t * 0.045 * radial_blur * mask;
					rb += texture(screen_tex, s_uv).rgb;
				}
				rb *= 0.2;
				color = mix(color, rb, radial_blur * mask);
			}
		}

		COLOR = vec4(color, 1.0);
	}
}
