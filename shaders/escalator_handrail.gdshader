shader_type spatial;
render_mode diffuse_burley, cull_disabled;
// The moving handrail of one lane's side: black rubber on a ribbon that follows the balustrade (Escalator._handrails_mesh). UV.x = across the rail (0..1), UV.y = metres along it from the top end.
// The rubber carries a faint knurl pattern, a centre seam and a joint every 6 m, which slide along it at the speed of the steps (the periods are whole divisors of what the rail travels in the 3600 s
// after which TIME starts again, so nothing jumps).
uniform float speed = 0.75;          // m/s along the rail; +ve: toward the bottom end
uniform vec3 rubber : source_color = vec3(0.045, 0.045, 0.05);

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	float s = v_uv.y - speed * TIME;
	vec3 col = rubber;
	float across = v_uv.x - 0.5;
	// the knurl: slanted lines, every 0.375 m
	float k = abs(fract((s + across * 0.45) / 0.375) - 0.5);
	float kv = 1.0 - smoothstep(0.03, 0.07, k);
	col += vec3(0.05) * kv;
	// the seam along the top, and the joint of the loop every 6 m
	col += vec3(0.03) * (1.0 - smoothstep(0.03, 0.08, abs(across)));
	float j = abs(fract(s / 6.0) - 0.5);
	col += vec3(0.07) * (1.0 - smoothstep(0.490, 0.498, j + 0.0)) * 0.0 + vec3(0.07) * smoothstep(0.494, 0.499, j);
	ALBEDO = col;
	ROUGHNESS = mix(0.5, 0.7, kv);
	METALLIC = 0.0;
}
