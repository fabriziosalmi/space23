// SPACE23 — Planet & Deep-Space Landmark Shader v2
//
// - Planets (`is_planet = 1.0`): directional 3D day/night terminator + sunlit
//   atmospheric Fresnel rim glow + subtle bass shimmer.
// - Deep landmarks (`is_planet = 0.0`): soft radial vignette so PNG bounds
//   never show hard edges + palette tint + audio-reactive core pulse.
shader_type canvas_item;

uniform vec3 tint = vec3(0.5, 0.3, 0.8);
uniform float tint_strength = 0.18;
uniform float audio_low = 0.0;
uniform float rim_strength = 0.55;
uniform vec2 light_dir = vec2(-0.7, -0.5);
uniform float is_planet = 1.0;

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	if (tex.a < 0.02) {
		COLOR = vec4(0.0);
	} else {
		vec3 col = tex.rgb;
		vec2 centered = (UV - vec2(0.5)) * 2.0; // -1..1
		float d = length(centered);

		// Gentle multiplicative tint that pulls the sector palette into highlights.
		col = mix(col, col * (tint * 2.5), tint_strength);

		if (is_planet > 0.5) {
			// Directional 3D lighting: sunlit hemisphere + soft night terminator.
			vec2 ldir = normalize(light_dir);
			float ndotl = dot(centered, ldir);
			float daylight = smoothstep(-0.65, 0.55, ndotl);
			// Keep night side gently readable (0.28 ambient) with subtle nebula tint.
			col *= mix(0.28, 1.12, daylight);
			col += tint * 0.12 * (1.0 - daylight);

			// Atmospheric Fresnel rim biased strongly toward the sunlit limb.
			float rim = smoothstep(0.58, 1.0, d) * tex.a;
			float sunlit_rim = rim * mix(0.18, 1.35, smoothstep(-0.2, 0.7, ndotl));
			col += tint * 3.0 * sunlit_rim * rim_strength;
		} else {
			// Deep-space landmarks (galaxies, nebulae, clusters, black hole):
			// soft radial edge fade prevents any rectangular sprite boundary.
			float edge_soft = 1.0 - smoothstep(0.72, 1.05, d);
			float rim = smoothstep(0.45, 0.95, d) * tex.a * edge_soft;
			col += tint * 2.4 * rim * rim_strength;
			tex.a *= edge_soft;
		}

		// Audio-reactive subtle pulse on the bass kick.
		col *= 1.0 + audio_low * 0.18;

		COLOR = vec4(col * v_modulate.rgb, tex.a * v_modulate.a);
	}
}
