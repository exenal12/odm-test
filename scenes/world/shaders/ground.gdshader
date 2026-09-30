shader_type spatial;
#include "res://scenes/world/shaders/noise.gdshaderinc"

uniform vec3 grass_color : source_color = vec3(0.2, 0.3, 0.11);
uniform vec3 moss_color : source_color = vec3(0.13, 0.22, 0.08);
uniform vec3 dirt_color : source_color = vec3(0.25, 0.19, 0.12);
uniform vec3 litter_color : source_color = vec3(0.4, 0.27, 0.13);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = vec3(world_pos.x, 0.0, world_pos.z);
	float large = fbm(p * 0.03);
	float medium = fbm(p * 0.15);
	float fine = value_noise(p * 2.5);
	vec3 color = mix(moss_color, grass_color, smoothstep(0.35, 0.65, large));
	color = mix(color, dirt_color, smoothstep(0.58, 0.75, medium) * 0.8);
	// Specks of fallen leaves.
	float litter = smoothstep(0.72, 0.8, value_noise(p * 1.3 + 7.0)) * smoothstep(0.4, 0.6, medium);
	color = mix(color, litter_color, litter * 0.7);
	ALBEDO = color * (0.85 + 0.3 * fine);
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
}
