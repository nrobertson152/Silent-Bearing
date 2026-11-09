shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// Billboard flame and fireball puffs. Colour follows how hot each bit is:
// white-yellow at the core, through orange to dull red, then the puff burns
// out to soot. Values above 1 bloom through the glow pass.

uniform float heat = 1.0;       // overall brightness
uniform float churn = 3.0;
uniform float soot = 0.35;      // how much the cooling flame darkens to smoke
uniform float soft = 2.0;
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
		p = p * 2.07 + vec3(4.1, 1.3, 7.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	mw = mw * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_seed = fract(float(INSTANCE_ID) * 0.618034) * 40.0;
	v_age = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	// Flames lick upward: stretch the noise and pull it up over time.
	vec3 np = vec3(q.x * 1.8, q.y * 1.2 + v_age * churn, v_seed + v_age * churn * 0.6);
	float n = fbm(np);
	float r = length(q * vec2(1.0, 0.85) + vec2(0.0, 0.12));
	float body = smoothstep(0.0, 0.5, 1.0 - r + (n - 0.5) * 1.1);
	float t = clamp((1.0 - r * 0.9) * (0.55 + n) * (1.15 - v_age * 0.9), 0.0, 1.0) * COLOR.r;
	vec3 hot = mix(vec3(0.55, 0.06, 0.01), vec3(1.0, 0.38, 0.06), smoothstep(0.15, 0.45, t));
	hot = mix(hot, vec3(1.0, 0.82, 0.45), smoothstep(0.5, 0.8, t));
	hot = mix(hot, vec3(1.0, 0.97, 0.88), smoothstep(0.82, 1.0, t));
	float burn = smoothstep(0.08, 0.3, t);
	vec3 smoke = vec3(0.06, 0.05, 0.045);
	ALBEDO = mix(smoke, hot * (1.0 + 4.0 * t) * heat, mix(burn, 1.0, 1.0 - soot));
	float alpha = body * COLOR.a * mix(1.0, burn, 1.0 - soot);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	float zs = texture(depth_tex, SCREEN_UV).r;
	vec4 sp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zs, 1.0);
	float scene_z = -sp.z / sp.w;
	alpha *= clamp((scene_z + VERTEX.z) / soft, 0.0, 1.0);
#endif
	ALPHA = clamp(alpha, 0.0, 1.0);
}
