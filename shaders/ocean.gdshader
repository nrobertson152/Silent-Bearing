shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Gerstner-wave ocean. Waves are evaluated in world space so the grid can
// follow the camera without the surface swimming. Ocean.height() in
// scripts/view/ocean.gd mirrors these waves for bobbing ships.

uniform vec4 deep : source_color = vec4(0.02, 0.08, 0.11, 1.0);
uniform vec4 shallow : source_color = vec4(0.07, 0.22, 0.25, 1.0);
uniform vec4 foam : source_color = vec4(0.82, 0.88, 0.88, 1.0);
uniform vec4 under : source_color = vec4(0.03, 0.12, 0.14, 1.0);
uniform float amp = 1.0;
uniform float t = 0.0;
uniform float flat_far = 0.0;
uniform vec2 center = vec2(0.0);

varying vec3 wnorm;
varying float crest;

vec3 wave(vec2 p, vec2 dir, float steep, float wl, inout vec3 tan, inout vec3 bin) {
	float k = 6.28318 / wl;
	float c = sqrt(9.81 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float a = steep * amp / k;
	float s = steep * amp;
	tan += vec3(-d.x * d.x * s * sin(f), d.x * s * cos(f), -d.x * d.y * s * sin(f));
	bin += vec3(-d.x * d.y * s * sin(f), d.y * s * cos(f), -d.y * d.y * s * sin(f));
	return vec3(d.x * a * cos(f), a * sin(f), d.y * a * cos(f));
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz;
	vec3 tan = vec3(1.0, 0.0, 0.0);
	vec3 bin = vec3(0.0, 0.0, 1.0);
	vec3 off = vec3(0.0);
	float fade = (1.0 - flat_far) * (1.0 - smoothstep(520.0, 760.0, distance(p, center)));
	off += wave(p, vec2(1.0, 0.3), 0.15, 71.0, tan, bin);
	off += wave(p, vec2(0.6, 1.0), 0.12, 37.0, tan, bin);
	off += wave(p, vec2(-0.45, 1.0), 0.10, 21.0, tan, bin);
	off += wave(p, vec2(1.0, -0.7), 0.08, 12.7, tan, bin);
	off += wave(p, vec2(-0.9, -0.35), 0.06, 7.3, tan, bin);
	off += wave(p, vec2(0.2, -1.0), 0.05, 4.9, tan, bin);
	VERTEX += off * fade;
	crest = off.y * fade;
	wnorm = normalize(cross(bin, tan));
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Small ripples on top of the big waves.
	float r1 = sin(wp.x * 0.37 + wp.z * 0.21 + t * 1.1) * cos(wp.z * 0.43 - wp.x * 0.13 - t * 0.9);
	float r2 = sin(wp.x * 1.13 - wp.z * 0.71 + t * 1.9) * sin(wp.z * 0.97 + wp.x * 0.31 - t * 1.4);
	float dist_f = clamp(length(wp - CAMERA_POSITION_WORLD) / 400.0, 0.0, 1.0);
	vec3 n = normalize(wnorm + vec3(r1 * 0.035 + r2 * 0.02, 0.0, r2 * 0.03 - r1 * 0.015) * (1.0 - dist_f) * mix(1.0, 0.2, flat_far));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 col = mix(deep.rgb, shallow.rgb, clamp(crest * 0.25 + 0.35, 0.0, 1.0));
	float f = smoothstep(1.7, 2.6, crest / max(amp, 0.05)) * (0.6 + 0.4 * r2);
	col = mix(col, foam.rgb, clamp(f, 0.0, 1.0) * 0.7);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		ALBEDO = under.rgb;
		EMISSION = under.rgb * 0.6;
		ROUGHNESS = 0.4;
	} else {
		ALBEDO = col;
		ROUGHNESS = mix(0.08, 0.3, fres);
		SPECULAR = 0.4;
	}
}
