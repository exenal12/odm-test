shader_type spatial;
#include "res://scenes/world/shaders/noise.gdshaderinc"

uniform vec3 bark_color : source_color = vec3(0.3, 0.21, 0.14);
uniform vec3 groove_color : source_color = vec3(0.1, 0.07, 0.05);
uniform vec3 moss_color : source_color = vec3(0.23, 0.33, 0.12);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.45;
// Ridges around the mesh's local Y axis; one full turn has this many grooves.
uniform float ridges = 22.0;

varying vec3 local_pos;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float angle = atan(local_pos.x, local_pos.z);
	// Sampled on a circle so the pattern has no seam where the angle wraps.
	float wobble = fbm(vec3(sin(angle) * 1.5, local_pos.y * 0.25, cos(angle) * 1.5)) * 3.0;
	float groove = pow(abs(sin(angle * ridges * 0.5 + wobble)), 0.6);
	float grain = fbm(world_pos * vec3(1.5, 0.35, 1.5));
	vec3 bark = mix(groove_color, bark_color * (0.8 + 0.4 * grain), groove);

	// Moss gathers on upward faces and around the base of trunks.
	float up = smoothstep(0.1, 0.7, world_normal.y);
	float base = 1.0 - smoothstep(0.0, 5.0, world_pos.y);
	float patches = smoothstep(0.35, 0.65, fbm(world_pos * 0.35));
	float moss = clamp((up * 0.9 + base * 0.7) * patches * moss_amount * 2.0, 0.0, 1.0);
	vec3 moss_tint = moss_color * (0.75 + 0.5 * value_noise(world_pos * 4.0));

	ALBEDO = mix(bark, moss_tint, moss);
	ROUGHNESS = mix(0.9, 0.8, moss);
	AO = mix(0.55, 1.0, groove);
	AO_LIGHT_AFFECT = 0.5;
}
