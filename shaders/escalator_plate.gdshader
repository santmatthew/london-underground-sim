shader_type spatial;
render_mode diffuse_burley;
// The fixed landing plate at either end of an escalator lane (ribbed steel) and its comb: the last 0.11 m before the steps are teeth that reach into the grooves of the steps, with a yellow line at the edge.
// Model space of the escalator: x runs downhill, z across the lane.
uniform float edge_x = 1.3;        // x of the edge where the steps are
uniform float side = 1.0;          // +1: the plate lies uphill of the edge (top landing), -1: downhill of it (bottom landing)
uniform vec3 plate_color : source_color = vec3(0.55, 0.56, 0.58);
uniform vec3 nose_color : source_color = vec3(0.92, 0.74, 0.06);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float d = (edge_x - lp.x) * side;
	// grooves along the travel (80 to the metre), the same as the steps' that the comb's teeth run in
	float rib = lp.z * 80.0;
	float vis = 1.0 - smoothstep(0.3, 0.85, fwidth(rib));
	float ph = rib * 6.2831853;
	float deep = (0.5 - 0.5 * cos(ph)) * vis;
	vec3 lat = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 col = plate_color * (1.0 - 0.45 * deep);
	float tooth = step(0.5, fract(lp.z / 0.0085));
	col = mix(col, vec3(0.13, 0.13, 0.14), (1.0 - smoothstep(0.105, 0.115, d)) * tooth * 0.9 * vis);
	float line = (1.0 - smoothstep(0.012, 0.018, d)) * smoothstep(-0.02, 0.0, d);
	col = mix(col, nose_color, line);
	ALBEDO = col;
	ROUGHNESS = mix(0.5, 0.75, deep);
	METALLIC = 0.12;
	NORMAL = normalize(NORMAL + lat * (-sin(ph) * vis) * 0.8);
}
