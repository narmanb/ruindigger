shader_type canvas_item;
// Water body: vertices with UV.y == 1 sit on the surface and roll as waves;
// a gentle caustic shimmer plays through the whole volume.
uniform float wave_amp = 1.3;
varying vec2 world_pos;
varying float surface;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	surface = UV.y;
	float w = sin(world_pos.x * 0.21 + TIME * 2.6) * 0.6 + sin(world_pos.x * 0.083 - TIME * 1.4) * 0.4;
	VERTEX.y += UV.y * w * wave_amp;
}

void fragment() {
	vec4 c = COLOR;
	float caustic = sin(world_pos.x * 0.17 + TIME * 1.7) * sin(world_pos.y * 0.23 - TIME * 1.1);
	caustic += 0.5 * sin((world_pos.x + world_pos.y) * 0.11 + TIME * 2.3);
	c.rgb += vec3(0.05, 0.08, 0.1) * caustic;
	COLOR = c;
}
