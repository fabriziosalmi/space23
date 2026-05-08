// SPACE23 — Planet landmark
// Real planet textures get a gentle palette tint + atmospheric rim glow so
// they sit inside the neon nebula instead of looking like pasted-on photos.
shader_type canvas_item;

// Palette pulled from the current track's nebula colors.
uniform vec3 tint = vec3(0.5, 0.3, 0.8);
// 0..1 — how much of the original color is replaced by the tint. Kept low so
// surface features stay readable (Earth is still blue-ish, Mars red-ish, etc).
uniform float tint_strength = 0.18;
// Bass-driven subtle pulse on overall brightness.
uniform float audio_low = 0.0;
// Rim glow intensity at the silhouette.
uniform float rim_strength = 0.55;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	if (tex.a < 0.02) {
		COLOR = vec4(0.0);
	} else {
		vec3 col = tex.rgb;

		// Gentle multiplicative tint that pulls the palette into the highlights.
		col = mix(col, col * (tint * 2.5), tint_strength);

		// Distance from center → assume roughly circular planet centered in UV.
		// Saturn's rings push UV further from center; the rim then tints them
		// too, which integrates the rings into the nebula palette.
		float d = length(UV - vec2(0.5)) * 2.0; // 0..~1.4
		float rim = smoothstep(0.55, 1.0, d) * tex.a;
		col += tint * 3.0 * rim * rim_strength;

		// Audio-reactive subtle pulse on the bass kick.
		col *= 1.0 + audio_low * 0.18;

		COLOR = vec4(col, tex.a);
	}
}
