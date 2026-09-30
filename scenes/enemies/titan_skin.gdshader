shader_type spatial;

uniform vec3 skin_color : source_color = vec3(0.86, 0.66, 0.55);
// Blotchy flush mixed into the skin so it reads as flesh rather than plastic.
uniform vec3 flush_color : source_color = vec3(0.84, 0.5, 0.45);
uniform vec3 nape_color : source_color = vec3(0.72, 0.06, 0.05);
uniform vec3 nape_muscle_color : source_color = vec3(0.36, 0.05, 0.05);
// Nape patch frame in world space, updated by the titan every frame.
uniform vec3 nape_position = vec3(0.0);
uniform vec3 nape_up = vec3(0.0, 1.0, 0.0);
uniform vec3 nape_back = vec3(0.0, 0.0, -1.0);
// Half width, half height above and half height below the centre, in metres.
uniform vec3 nape_size = vec3(0.55, 0.75, 0.35);
uniform float nape_softness : hint_range(0.01, 1.0) = 0.22;
uniform float nape_strength : hint_range(0.0, 1.0) = 1.0;
uniform float nape_pulse_speed = 2.6;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 local_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local_pos = VERTEX;
}

void fragment() {
	float blotch = value_noise(local_pos * 9.0) * 0.6 + value_noise(local_pos * 23.0) * 0.4;
	vec3 skin = mix(skin_color * 0.9, flush_color, smoothstep(0.45, 0.85, blotch));
	skin *= 0.94 + 0.08 * value_noise(local_pos * 70.0);

	vec3 offset = world_pos - nape_position;
	vec3 right = normalize(cross(nape_up, nape_back));
	float along = dot(offset, nape_up);
	vec2 patch_uv = vec2(dot(offset, right) / nape_size.x, along / (along > 0.0 ? nape_size.y : nape_size.z));
	float radius = length(patch_uv);
	// Keeps the patch on the back of the neck instead of bleeding through to the throat.
	float facing = smoothstep(0.05, 0.45, dot(normalize(world_normal), nape_back));
	float inside = (1.0 - smoothstep(1.0 - nape_softness, 1.0, radius)) * facing * nape_strength;
	float rim = smoothstep(0.62, 0.86, radius) * inside;
	// Vertical muscle fibres, slightly wavy so they don't look ruled.
	float fibres = 0.5 + 0.5 * sin(patch_uv.x * 26.0 + value_noise(local_pos * 45.0) * 3.0);
	vec3 muscle = mix(nape_muscle_color, nape_color, 0.35 + 0.45 * fibres);
	vec3 patch = mix(muscle, nape_color * 1.15, rim);
	float pulse = 0.7 + 0.3 * sin(TIME * nape_pulse_speed);

	ALBEDO = mix(skin, patch, inside);
	ROUGHNESS = mix(0.6 + 0.2 * blotch, 0.45, inside);
	SPECULAR = mix(0.35, 0.42, inside);
	SSS_STRENGTH = 0.35;
	RIM = 0.2;
	RIM_TINT = 0.6;
	EMISSION = nape_color * (0.18 * inside + 0.85 * rim) * pulse + vec3(flash);
}
