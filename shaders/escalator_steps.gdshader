shader_type spatial;
render_mode diffuse_burley, cull_disabled;
// The moving steps of one escalator lane. The mesh holds N steps (Escalator._steps_mesh); each is a tread (kind 0) and the riser under its front edge (kind 1) whose vertices only carry
// local coordinates: VERTEX = (u along the tread 0 back .. 1 front, w down the riser 0 top .. 1 bottom, lateral z), UV2 = (step index, kind). Here the steps are put on the track:
// a path of arc length c (0 at the corner where the slope begins, l_vis at the corner where it ends; flat before and after, under the comb plates), steps `pitch` apart, all travelling along it.
// A tread is horizontal at the height of the path at its middle, from the x of its back edge to the x of its front edge; the riser drops from there to the next step's tread: the steps open into
// a staircase over the first step of the slope and close up again over the last, as the real ones do. The collision slab under the player is the line through the middles of the treads.
uniform float speed = 0.75;        // m/s along the path; +ve: steps go down the slope, -ve: up
uniform float pitch = 0.4;         // arc length between steps (m)
uniform float loop_len = 28.0;     // pitch * number of steps in the mesh (the loop the steps wrap round, out of sight under the plates)
uniform float x0 = 1.3;            // x of the corner at the top of the slope
uniform float run = 20.0;          // horizontal length of the slope
uniform float rise = 11.5;         // height of the slope
uniform float cos_t = 0.866;
uniform float sin_t = 0.5;
uniform float l_vis = 23.0;        // length of the slope
uniform float sink = 0.07;         // how far a step dips under the plate as it goes in or comes out
uniform float fillet = 1.5;        // radius of the arcs that round the two corners of the track (the real ones turn over about this wide: 1.2 - 2.5 m); 0 = sharp corners
uniform vec3 tread_color : source_color = vec3(0.62, 0.63, 0.65);
uniform vec3 riser_color : source_color = vec3(0.46, 0.47, 0.49);
uniform vec3 nose_color : source_color = vec3(0.92, 0.74, 0.06);

varying vec2 v_uv;
varying float v_kind;

vec2 path(float c) {
	if (fillet <= 0.001) {
		if (c <= 0.0) {
			return vec2(x0 + c, 0.0);
		}
		if (c >= l_vis) {
			return vec2(x0 + run + (c - l_vis), -rise);
		}
		return vec2(x0 + c * cos_t, -c * sin_t);
	}
	// the track with its corners rounded: arcs of radius `fillet` centred on the two corners (c = 0 and c = l_vis), joined by the straight slope; the flat under the plates before and after.
	// The arcs cut the corners by a tangent length t on each side, so the track is a couple of centimetres shorter than the sharp one (l_vis, the steps' pitch: nothing else changes).
	float th = atan(sin_t, cos_t);
	float t = fillet * tan(0.5 * th);
	float la = fillet * th;
	vec2 dir = vec2(cos_t, -sin_t);
	if (c <= -0.5 * la) {
		return vec2(x0 - t + (c + 0.5 * la), 0.0);
	}
	if (c < 0.5 * la) {
		float s = (c + 0.5 * la) / fillet;
		return vec2(x0 - t + fillet * sin(s), -fillet * (1.0 - cos(s)));
	}
	float c1 = 0.5 * la + (l_vis - 2.0 * t);          // where the straight slope ends and the lower arc begins
	if (c <= c1) {
		vec2 e1 = vec2(x0 - t + fillet * sin(th), -fillet * (1.0 - cos(th)));
		return e1 + (c - 0.5 * la) * dir;
	}
	vec2 b0 = vec2(x0 + run, -rise) - t * dir;          // the lower arc starts here, centred above the track
	vec2 ctr = b0 + fillet * vec2(sin_t, cos_t);
	if (c < c1 + la) {
		float s2 = (c - c1) / fillet;
		vec2 v = -fillet * vec2(sin_t, cos_t);
		return ctr + vec2(v.x * cos(s2) - v.y * sin(s2), v.x * sin(s2) + v.y * cos(s2));
	}
	return vec2(x0 + run + t + (c - c1 - la), -rise);
}

void vertex() {
	float k = UV2.x;
	float kind = UV2.y;
	// where this step's back edge is on the path now (the loop runs from -pitch, fully under the top plate, round to just before it again)
	float c = mod(k * pitch + speed * TIME + pitch, loop_len) - pitch;
	vec2 pb = path(c);
	vec2 pf = path(c + pitch);
	float y_tread = path(c + 0.5 * pitch).y;
	float y_next = path(c + 1.5 * pitch).y;
	// going in under the bottom plate / coming out from under the top one: dip below the plate (the plates are opaque from above)
	float dip = -sink * max(clamp(-c / pitch, 0.0, 1.0), clamp((c + pitch - l_vis) / pitch, 0.0, 1.0));
	vec3 p;
	if (kind < 0.5) {
		p = vec3(mix(pb.x, pf.x, VERTEX.x), y_tread + dip, VERTEX.z);
		NORMAL = vec3(0.0, 1.0, 0.0);
	} else {
		p = vec3(pf.x, mix(y_tread, y_next, VERTEX.y) + dip, VERTEX.z);
		NORMAL = vec3(1.0, 0.0, 0.0);
	}
	VERTEX = p;
	v_uv = UV;
	v_kind = kind;
}

// Grooves: the treads are cut with grooves along the travel and the risers carry matching cleats (vertical), which is what the steps and the comb plates interlock with. `x` counts grooves across the lane;
// returns how deep into a groove this point is (0 on the ridge, 1 at the bottom) and tilts the normal across the groove so the light shows them. They fade out where they would only shimmer.
const float GROOVES_PER_M = 80.0;

float groove(float across_m, out float vis, out float slope) {
	float x = across_m * GROOVES_PER_M;
	vis = 1.0 - smoothstep(0.3, 0.85, fwidth(x));
	float ph = x * 6.2831853;
	slope = -sin(ph) * vis;
	return (0.5 - 0.5 * cos(ph)) * vis;
}

void fragment() {
	vec3 lat = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	float vis;
	float slope;
	float deep = groove(v_uv.x, vis, slope);          // (uv.x is across the lane, one unit = the lane's width, 1 m)
	if (v_kind < 0.5) {
		// the tread: grooved, darker where it tucks under the step above, the yellow edge at the front
		float tuck = mix(0.7, 1.0, smoothstep(0.0, 0.12, v_uv.y));
		float nose = smoothstep(0.84, 0.86, v_uv.y);
		vec3 col = tread_color * mix(1.0, 1.0 - 0.45 * deep, 1.0) * tuck;
		col = mix(col, nose_color * (1.0 - 0.3 * deep), nose);
		ALBEDO = col;
		ROUGHNESS = mix(0.5, 0.75, deep);
		METALLIC = 0.12 * (1.0 - nose);
		NORMAL = normalize(NORMAL + lat * slope * 0.8);
	} else {
		// the riser: the cleats
		ALBEDO = riser_color * (1.0 - 0.5 * deep);
		ROUGHNESS = mix(0.55, 0.75, deep);
		METALLIC = 0.05;
		NORMAL = normalize(NORMAL + lat * slope * 0.8);
	}
}
