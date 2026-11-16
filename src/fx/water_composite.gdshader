shader_type canvas_item;
// Turns the soft water density field (red channel of the water buffer) into a
// single smooth liquid shape: threshold, rolling surface, depth shading,
// surface highlight and caustic shimmer. Used twice: a full-strength copy behind
// the rock tiles, and a faint copy in front of the player (masked out of rock)
// so swimmers look submerged.
uniform vec4 shallow_color : source_color = vec4(0.22, 0.55, 0.85, 0.72);
uniform vec4 deep_color : source_color = vec4(0.07, 0.24, 0.52, 0.88);
uniform vec4 surface_color : source_color = vec4(0.72, 0.92, 1.0, 0.95);
uniform float opacity = 1.0;
uniform bool use_mask = false;
uniform sampler2D solid_mask : filter_nearest;
uniform vec2 grid_size = vec2(72.0, 214.0);
uniform float wave_amp = 0.9;
varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float wave = sin(world_pos.x * 0.21 + TIME * 2.6) * 0.6 + sin(world_pos.x * 0.083 - TIME * 1.4) * 0.4;
	vec2 uv = UV + vec2(0.0, wave * wave_amp * px.y);
	float d = texture(TEXTURE, uv).r;
	float a = smoothstep(0.44, 0.56, d);
	if (a < 0.01) {
		discard;
	}
	if (use_mask) {
		vec2 c = floor(world_pos / 16.0);
		if (texture(solid_mask, (c + 0.5) / grid_size).r > 0.5) {
			discard;
		}
	}
	float up_s = smoothstep(0.44, 0.56, texture(TEXTURE, uv - vec2(0.0, 2.5 * px.y)).r);
	float up_a = smoothstep(0.4, 0.6, texture(TEXTURE, uv - vec2(0.0, 9.0 * px.y)).r);
	float up_b = smoothstep(0.4, 0.6, texture(TEXTURE, uv - vec2(0.0, 24.0 * px.y)).r);
	float depth = (up_a + up_b) * 0.5;
	vec4 col = mix(shallow_color, deep_color, depth);
	float caust = sin(world_pos.x * 0.17 + TIME * 1.7) * sin(world_pos.y * 0.23 - TIME * 1.1)
		+ 0.5 * sin((world_pos.x + world_pos.y) * 0.11 + TIME * 2.3);
	col.rgb += vec3(0.04, 0.07, 0.09) * caust * (1.0 - depth * 0.5);
	float surf = 1.0 - up_s;
	col = mix(col, surface_color, surf * 0.9);
	COLOR = vec4(col.rgb, col.a * a * opacity);
}
