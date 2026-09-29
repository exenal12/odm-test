shader_type spatial;

uniform vec3 skin_color : source_color = vec3(0.86, 0.66, 0.55);
uniform vec3 nape_color : source_color = vec3(0.72, 0.06, 0.05);
uniform vec3 nape_position = vec3(0.0);
uniform float nape_radius = 0.9;
uniform float nape_softness = 0.5;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float paint = 1.0 - smoothstep(nape_radius, nape_radius + nape_softness, distance(world_pos, nape_position));
	ALBEDO = mix(skin_color, nape_color, paint);
	ROUGHNESS = 0.85;
	EMISSION = mix(vec3(0.0), nape_color * 0.6, paint) + vec3(flash);
}
