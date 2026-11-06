shader_type canvas_item;
render_mode blend_add;
// Additive emissive layer: gentle per-position shimmer so ore seams breathe.
uniform float strength = 1.0;
varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float p = 0.72 + 0.28 * sin(TIME * 2.2 + world_pos.x * 0.07 + world_pos.y * 0.05);
	COLOR = vec4(c.rgb * p * strength, c.a * p);
}
