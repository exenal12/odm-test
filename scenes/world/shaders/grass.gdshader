shader_type spatial;
render_mode cull_disabled;
#include "res://scenes/world/shaders/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.08, 0.14, 0.05);
uniform vec3 tip_color : source_color = vec3(0.36, 0.48, 0.16);
uniform float wind_strength = 0.12;

varying float height;

void vertex() {
	// UV.y runs 0 at the root to 1 at the tip.
	height = UV.y;
	vec3 world_origin = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = value_noise(vec3(world_origin.xz * 0.08 + TIME * 0.3, 0.0));
	float bend = sin(TIME * 1.8 + world_origin.x * 0.4 + world_origin.z * 0.3) * 0.5 + gust;
	VERTEX.xz += vec2(bend, bend * 0.6) * wind_strength * height * height;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = mix(base_color, tip_color * COLOR.rgb, height);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = tip_color * 0.3 * height;
	AO = mix(0.4, 1.0, height);
}
