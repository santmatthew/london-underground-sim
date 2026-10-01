shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled;
// The sky seen from open-air platforms: a vertical gradient with soft noise clouds. The dome is a big sphere (inside faces), so VERTEX is the view direction.
uniform vec3 top_color : source_color = vec3(0.28, 0.5, 0.84);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.88, 0.95);
uniform vec3 ground_color : source_color = vec3(0.36, 0.4, 0.43);
uniform vec3 cloud_color : source_color = vec3(0.96, 0.96, 0.97);
uniform float cloud_amount = 0.55;
uniform float star_amount = 0.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
varying vec3 dir;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(dir);
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.7, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.12, h));
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.18) * 0.45;
		float n = texture(noise_tex, uv).r;
		float c = smoothstep(1.0 - cloud_amount, 1.0, n) * smoothstep(0.0, 0.2, h);
		col = mix(col, cloud_color, c * 0.85);
	}
	if (h > 0.03 && star_amount > 0.0) {
		float st = step(0.9975, hash3(floor(d * 700.0)));
		col += vec3(st) * star_amount * smoothstep(0.03, 0.25, h);
	}
	ALBEDO = col;
}
