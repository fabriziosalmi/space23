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

		// 1. Aberrazione Cromatica Progressiva (Flow + Bass) — dimezzata.
		// Era 0.006 + 0.015 + 0.015 = max 0.036 = 46px shift sui peak: faceva
		// apparire ogni stella come triplet R/G/B chunky. Adesso max 0.018.
		float shift = dist * (0.003 + flow_state * 0.008 + audio_bass * 0.007);
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

		COLOR = vec4(color, 1.0);
	}
}
