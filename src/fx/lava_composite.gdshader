shader_type canvas_item;
// Turns the soft lava density field into one smooth, viscous molten body:
// threshold (no cell edges), a bright skin along the surface, deeper red below,
// slowly drifting dark crust plates with glowing seams between them.
uniform float opacity = 1.0;
varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float d = texture(TEXTURE, UV).r;
	float a = smoothstep(0.45, 0.55, d);
	if (a < 0.01) {
		discard;
	}
	// how far below the surface this pixel is
	float up_s = smoothstep(0.45, 0.55, texture(TEXTURE, UV - vec2(0.0, 3.0 * px.y)).r);
	float up_d = smoothstep(0.4, 0.6, texture(TEXTURE, UV - vec2(0.0, 14.0 * px.y)).r);
	vec2 p = world_pos * 0.055 + vec2(TIME * 0.045, TIME * 0.018);
	float n = vnoise(p) * 0.62 + vnoise(p * 2.3 + vec2(-TIME * 0.07, TIME * 0.03)) * 0.38;
	vec3 deep = vec3(0.42, 0.05, 0.02);
	vec3 hot = vec3(1.0, 0.4, 0.07);
	vec3 white = vec3(1.0, 0.86, 0.48);
	vec3 col = mix(hot, deep, up_d * 0.75);
	// crust plates ride the surface layers; seams between them glow
	float crust = smoothstep(0.56, 0.64, n) * (1.0 - up_d * 0.6);
	col = mix(col, vec3(0.15, 0.05, 0.035), crust * 0.8);
	float seam = 1.0 - smoothstep(0.0, 0.05, abs(n - 0.6));
	col += white * seam * 0.35 * (1.0 - up_d * 0.5);
	// a thin incandescent skin along the top
	float surf = 1.0 - up_s;
	col = mix(col, white, surf * 0.75);
	COLOR = vec4(col, a * opacity);
}
