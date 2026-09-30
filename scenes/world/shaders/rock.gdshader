shader_type spatial;
#include "res://scenes/world/shaders/noise.gdshaderinc"

uniform vec3 rock_color : source_color = vec3(0.36, 0.36, 0.33);
uniform vec3 moss_color : source_color = vec3(0.2, 0.31, 0.1);
uniform float lumpiness = 0.28;
instance uniform float seed = 0.0;

varying vec3 sphere_pos;
varying vec3 world_normal;

void vertex() {
	sphere_pos = VERTEX;
	float n = fbm(VERTEX * 1.4 + seed * 9.0);
	VERTEX += NORMAL * (n - 0.45) * lumpiness * 2.0;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float detail = fbm(sphere_pos * 6.0 + seed * 3.0);
	vec3 stone = rock_color * (0.7 + 0.5 * detail);
	float moss = smoothstep(0.2, 0.75, world_normal.y + (detail - 0.5) * 0.8);
	ALBEDO = mix(stone, moss_color * (0.8 + 0.4 * detail), moss);
	ROUGHNESS = mix(0.8, 0.9, moss);
}
