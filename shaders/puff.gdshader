shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
// Lit billboard puffs for smoke, steam and spray. Each puff has a billowing,
// noise-cut edge that churns as it ages, a rounded fake normal so the sun
// lights one side, and (on Forward+) a soft fade where it meets the water or
// a hull instead of a hard line. Particle colour and alpha come from the
// emitter's colour ramp; INSTANCE_CUSTOM.y is the particle's age (0..1).

uniform vec4 tint : source_color = vec4(1.0);
uniform float churn = 1.5;      // how fast the edge boils
uniform float lumpy = 0.9;      // how ragged the edge is
uniform float thin = 0.0;       // 1 = wispy (steam, spray mist)
uniform float soft = 3.0;       // soft-particle fade distance (m)
uniform float self_shadow = 0.5;
uniform float scatter = 0.2;    // forward scattering: thin spray and steam glow with the sun behind
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
#endif

varying float v_seed;
varying float v_age;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	// Face the camera, keep the particle's own spin and size.
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	mw = mw * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_seed = fract(float(INSTANCE_ID) * 0.618034) * 40.0;
	v_age = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float n = fbm(vec3(q * 1.6, v_seed + v_age * churn));
	float n2 = noise3(vec3(q * 5.0, v_seed * 1.3 + v_age * churn * 2.0));
	float edge = 1.0 - r + (n - 0.5) * lumpy + (n2 - 0.5) * 0.18;
	float dens = smoothstep(0.0, mix(0.5, 0.9, thin), edge) * mix(1.0, 0.45 + 0.8 * n, thin);
	// A rounded normal (view space) so the sunny side of each puff is brighter.
	vec3 nv = normalize(vec3(q.x * 1.1, -q.y * 1.1, sqrt(max(0.0, 1.0 - min(r * r, 1.0))) + 0.25));
	NORMAL = normalize(mix(nv, vec3(0.0, 0.0, 1.0), 1.0 - self_shadow));
	ALBEDO = COLOR.rgb * tint.rgb * (0.82 + 0.36 * n);
	ROUGHNESS = 1.0;
	float alpha = dens * COLOR.a * tint.a;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	float zs = texture(depth_tex, SCREEN_UV).r;
	vec4 sp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zs, 1.0);
	float scene_z = -sp.z / sp.w;
	alpha *= clamp((scene_z + VERTEX.z) / soft, 0.0, 1.0);
#endif
	ALPHA = clamp(alpha, 0.0, 1.0);
}

void light() {
	// Soft wrapped diffuse, plus light scattered forward through the puff when
	// you look toward the sun (or a fire) through it.
	float wrap = clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0);
	float fwd = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 6.0) * scatter;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (wrap + fwd * 2.5) / PI;
}
