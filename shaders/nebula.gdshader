// SPACE23 — Nebula Background
// FBM noise procedurale a 5 ottave, mix di tre colori (sfondo + 2 nubi),
// strobe additivo audio-reattivo (cassa).
shader_type canvas_item;

uniform vec3 c_bg = vec3(0.005, 0.0, 0.015);
uniform vec3 c_neb1 = vec3(0.05, 0.01, 0.1);
uniform vec3 c_neb2 = vec3(0.0, 0.05, 0.15);
uniform float scroll_time = 0.0;
uniform float audio_bass = 0.0;

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

// FBM (Fractal Brownian Motion)
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

void fragment() {
	vec2 uv = UV;
	uv.y += scroll_time * 0.05;

	float n1 = fbm(uv * 3.0 + vec2(scroll_time * 0.02, scroll_time * 0.05));
	float n2 = fbm(uv * 6.0 - vec2(scroll_time * 0.01, scroll_time * 0.03));

	vec3 color = c_bg;
	color = mix(color, c_neb1, smoothstep(0.1, 0.8, n1));
	color = mix(color, c_neb2, smoothstep(0.2, 0.9, n2));

	// Strobe elegante a tempo di cassa (audio_bass arriva già lerpato)
	float strobe = audio_bass * 8.0;
	color += c_neb1 * n1 * strobe;
	color += c_neb2 * n2 * strobe * 0.5;

	COLOR = vec4(color, 1.0);
}
