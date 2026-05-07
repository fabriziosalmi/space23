// SPACE23 — Procedural Engine Flame
// Forma a fiamma + noise scroll verso il basso. `power` controlla la lunghezza
// (alza il fuoco quando il giocatore accelera in avanti).
// Colori HDR pensati per il bloom (ACES tonemap a valle).
shader_type canvas_item;

uniform float power = 1.0;

float noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float smooth_noise(vec2 uv) {
	vec2 lv = fract(uv);
	vec2 id = floor(uv);
	lv = lv * lv * (3.0 - 2.0 * lv);
	return mix(mix(noise(id), noise(id + vec2(1, 0)), lv.x),
	           mix(noise(id + vec2(0, 1)), noise(id + vec2(1, 1)), lv.x), lv.y);
}

void fragment() {
	vec2 uv = UV;

	// Forma della fiamma: spessa sopra, fine sotto
	float x_dist = abs(uv.x - 0.5);
	float width = 0.5 - (uv.y * 0.4);

	// Scorrimento veloce verso il basso
	vec2 nuv = uv * vec2(3.0, 6.0) - vec2(0.0, TIME * 15.0);
	float n = smooth_noise(nuv) * smooth_noise(nuv * 2.0);

	float edge_fade = smoothstep(width, width * 0.2, x_dist);
	float y_fade = smoothstep(1.0, 0.1, uv.y / max(0.1, power));

	float intensity = n * edge_fade * y_fade * 3.0;

	// Colori HDR (≥1.0 → bloom)
	vec3 col_core = vec3(2.5, 2.0, 1.5); // Bianco caldissimo
	vec3 col_mid  = vec3(2.0, 0.8, 0.0); // Arancio esplosivo
	vec3 col_edge = vec3(0.0, 1.0, 2.5); // Base blu ionico

	vec3 color = mix(col_edge, col_mid, smoothstep(0.1, 0.6, intensity));
	color = mix(color, col_core, smoothstep(0.6, 0.9, intensity));

	COLOR = vec4(color, intensity * 1.5);
}
