shader_type spatial;
#include "res://scenes/world/shaders/noise.gdshaderinc"

uniform vec3 wood_color : source_color = vec3(0.5, 0.34, 0.19);
uniform vec3 wood_dark : source_color = vec3(0.24, 0.15, 0.08);
uniform float plank_width = 0.32;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float row = floor(local_pos.x / plank_width);
	float across = fract(local_pos.x / plank_width);
	float offset = hash31(vec3(row, 1.0, 2.0));
	// Staggered butt joints along each plank.
	float along = fract(local_pos.z / 2.4 + offset);
	float seam = min(smoothstep(0.0, 0.04, across) * smoothstep(1.0, 0.96, across),
		smoothstep(0.0, 0.01, along) * smoothstep(1.0, 0.99, along));
	float grain = fbm(vec3(local_pos.x * 18.0, local_pos.z * 1.2, row));
	vec3 tint = wood_color * (0.8 + 0.35 * offset);
	vec3 color = mix(wood_dark, tint, 0.55 + 0.45 * grain);
	ALBEDO = mix(wood_dark * 0.5, color, seam);
	ROUGHNESS = 0.8;
	AO = mix(0.4, 1.0, seam);
}
