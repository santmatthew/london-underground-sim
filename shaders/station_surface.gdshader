shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// PBR surface with procedural grime. Mesh UVs are in metres (see MeshKit); vertex COLOR.r = height above floor,
// COLOR.g = per-face random, COLOR.b = user value.
uniform sampler2D tex_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_rough : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_ao : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_metal : hint_default_black, repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_grime : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(0.8333, 0.8333);   // texture repeats per metre
uniform float normal_scale = 1.0;
uniform float rough_mul = 1.0;
uniform float rough_add = 0.0;
uniform float metallic_amount = 0.0;
uniform float dirt = 0.6;                       // overall grime strength 0..1
uniform float floor_dirt_height = 0.5;          // grubby band above the floor (m)
uniform float ceiling_soot = 0.0;               // extra darkening of upward-facing-down surfaces
uniform vec3 dirt_color : source_color = vec3(0.14, 0.125, 0.10);
uniform float grime_scale = 0.11;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 world_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y > 0.7) return p.xz;
	if (a.x > a.z) return vec2(p.z, -p.y);
	return vec2(p.x, -p.y);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 alb = texture(tex_albedo, uv).rgb * tint.rgb;
	float ao = texture(tex_ao, uv).r;
	float rough = texture(tex_rough, uv).r * rough_mul + rough_add;
	float met = texture(tex_metal, uv).r * metallic_amount;

	float h = COLOR.r;
	float rnd = COLOR.g;
	vec2 wuv = world_uv(wpos, wnrm);
	float g1 = texture(tex_grime, wuv * grime_scale).r;
	float g2 = texture(tex_grime, wuv * grime_scale * 3.7 + vec2(0.31, 0.77)).r;
	float band = 1.0 - smoothstep(0.0, floor_dirt_height, h);
	float d = dirt * (0.04 + 0.42 * g1 * g2) + dirt * band * (0.30 + 0.45 * g1);
	// downward-facing (ceiling) surfaces collect soot
	float ceil_f = clamp(-NORMAL.y, 0.0, 1.0);
	d += ceiling_soot * ceil_f * (0.10 + 0.35 * g1);
	d = clamp(d, 0.0, 0.85);

	ALBEDO = mix(alb, alb * dirt_color * 3.2, d * 0.75);
	ROUGHNESS = clamp(mix(rough, 0.92, d * 0.8), 0.04, 1.0);
	METALLIC = met * (1.0 - d);
	AO = ao;
	AO_LIGHT_AFFECT = 0.6;
	NORMAL_MAP = texture(tex_normal, uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	EMISSION = emission_color * emission_energy;
}
