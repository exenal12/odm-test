shader_type spatial;
render_mode cull_disabled;

uniform vec3 stem_color : source_color = vec3(0.12, 0.2, 0.06);
uniform vec3 leaf_color : source_color = vec3(0.24, 0.4, 0.11);
uniform float leaflets = 14.0;
uniform float wind_strength = 0.05;

void vertex() {
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	float t = TIME * 1.3 + world_origin.x * 0.3 + world_origin.z * 0.2;
	VERTEX.y += sin(t + UV.y * 3.0) * wind_strength * UV.y;
}

void fragment() {
	// UV.x across the frond (0.5 is the stem), UV.y from base to tip.
	float across = abs(UV.x - 0.5) * 2.0;
	float taper = sin(UV.y * 3.14159) * (1.0 - UV.y * 0.35);
	float cell = fract(UV.y * leaflets);
	// Each leaflet is a pointed lobe that sweeps toward the tip.
	float lobe = 1.0 - abs(cell - 0.5 + across * 0.35) * 2.0;
	float width = taper * clamp(lobe * 1.6, 0.0, 1.0);
	if (across > width + 0.04 && across > 0.06) {
		discard;
	}
	float stem = 1.0 - smoothstep(0.03, 0.08, across);
	ALBEDO = mix(leaf_color * COLOR.rgb * (0.75 + 0.35 * UV.y), stem_color, stem);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = leaf_color * 0.4;
}
