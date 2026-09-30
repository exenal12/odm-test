shader_type spatial;
#include "res://scenes/world/shaders/noise.gdshaderinc"

uniform vec3 leaf_dark : source_color = vec3(0.07, 0.16, 0.07);
uniform vec3 leaf_light : source_color = vec3(0.3, 0.45, 0.14);
// Lumps pushed out of the base sphere, as a fraction of its radius.
uniform float lumpiness = 0.32;
uniform float sway = 0.04;
instance uniform float seed = 0.0;

varying vec3 sphere_pos;
varying float bulge;

void vertex() {
	sphere_pos = VERTEX;
	vec3 p = VERTEX * 1.7 + vec3(seed * 13.1, seed * 7.3, seed * 3.7);
	bulge = fbm(p);
	VERTEX += NORMAL * (bulge - 0.45) * lumpiness * 2.0;
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	float t = TIME * 0.7 + world_origin.x * 0.05 + world_origin.z * 0.07;
	VERTEX.xz += vec2(sin(t), cos(t * 0.8)) * sway * max(VERTEX.y + 1.0, 0.0);
}

void fragment() {
	vec3 p = sphere_pos * 9.0 + seed * 5.0;
	// Small dark gaps between leaf clusters.
	float clusters = smoothstep(0.3, 0.7, value_noise(p) * 0.6 + value_noise(p * 2.7) * 0.4);
	float top = smoothstep(-0.4, 0.9, sphere_pos.y);
	vec3 color = mix(leaf_dark, leaf_light, clamp(top * 0.65 + bulge * 0.5 - 0.15, 0.0, 1.0));
	ALBEDO = color * mix(0.45, 1.05, clusters);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = leaf_light * 0.35;
	AO = mix(0.5, 1.0, clusters * (0.4 + 0.6 * top));
	AO_LIGHT_AFFECT = 0.4;
}
