shader_type spatial;
render_mode diffuse_burley;
// Moving escalator treads. UV.x = across (m), UV.y = along the slope (m, growing UPHILL: the tread quad is built bottom -> top).
uniform float speed = 0.75;      // m/s; +ve moves the pattern downhill, -ve uphill
uniform float pitch = 0.4;       // tread pitch (m)
uniform vec3 base_color : source_color = vec3(0.16, 0.16, 0.17);
uniform vec3 nose_color : source_color = vec3(0.90, 0.72, 0.05);

void fragment() {
	float s = UV.y + TIME * speed;      // UV.y grows uphill, so a pattern that moves downhill has to scroll toward smaller UV.y
	float f = fract(s / pitch);
	// yellow demarcation on the leading edge of each step
	float nose = smoothstep(0.0, 0.02, f) * (1.0 - smoothstep(0.075, 0.095, f));
	// shallow grooves running along the direction of travel
	float g = 0.5 + 0.5 * sin(UV.x * 300.0);
	float groove = mix(0.75, 1.0, g);
	// riser shading toward the back of each step
	float shade = mix(1.0, 0.72, smoothstep(0.55, 1.0, f));
	vec3 col = base_color * groove * shade;
	col = mix(col, nose_color, nose);
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.7, g);
	METALLIC = 0.35 * (1.0 - nose);
}
