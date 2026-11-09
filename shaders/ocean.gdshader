shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Gerstner ocean on a radial grid centred on the camera (scripts/view/ocean.gd).
// Each wave leaves the displacement once the grid is too coarse to carry it
// and leaves the per-pixel normal once a pixel is too big to show it, so the
// sea stays sharp up close without shimmering at the horizon. Ocean.height()
// mirrors the displacement for everything that floats.
//
// Foam comes from three places: breaking crests (where the waves fold over),
// and the wake map, a top-down render of ship wakes, bow waves, propeller wash
// and splash patches (scripts/view/wakes.gd).

#define NWAVES 12

uniform vec4 waves[NWAVES];     // direction x, direction z, steepness x sea state, wavelength
uniform float t = 0.0;
uniform float amp = 1.0;
uniform vec3 deep : source_color = vec3(0.02, 0.08, 0.11);
uniform vec3 scatter : source_color = vec3(0.05, 0.22, 0.24);
uniform vec3 foam_col : source_color = vec3(0.86, 0.9, 0.9);
uniform vec3 under : source_color = vec3(0.03, 0.12, 0.14);
uniform vec3 sun_dir = vec3(0.45, 0.62, -0.64);
uniform vec3 sun_col : source_color = vec3(1.0, 0.95, 0.86);
uniform float sun_e = 1.0;
uniform vec2 wind = vec2(1.0, 0.0);
uniform float crest_foam = 1.0;
uniform sampler2D detail : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D wake_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec4 wake_rect = vec4(0.0, 0.0, 1024.0, 0.0);  // centre x, centre z, size, on

varying vec2 v_flat;
varying float v_height;
varying float v_jac;

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float dist = length(VERTEX.xz);
	vec3 off = vec3(0.0);
	float jxx = 1.0;
	float jzz = 1.0;
	float jxz = 0.0;
	for (int i = 0; i < NWAVES; i++) {
		vec4 w = waves[i];
		float fade = 1.0 - smoothstep(w.w * 5.0, w.w * 8.0, dist);
		if (fade > 0.0) {
			float k = 6.28318 / w.w;
			float f = k * dot(w.xy, p) - sqrt(9.81 * k) * t;
			float s = w.z * fade;
			float a = s / k;
			float cf = cos(f);
			float sf = sin(f);
			off += vec3(w.x * a * cf, a * sf, w.y * a * cf);
			jxx -= w.x * w.x * s * sf;
			jzz -= w.y * w.y * s * sf;
			jxz -= w.x * w.y * s * sf;
		}
	}
	VERTEX += off;
	v_flat = p;
	v_height = off.y;
	v_jac = jxx * jzz - jxz * jxz;
}

void fragment() {
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = v_flat;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float foot = max(length(dFdx(p)), length(dFdy(p)));
	// Wave normal per pixel, keeping only the waves a pixel can resolve.
	vec3 n = vec3(0.0, 1.0, 0.0);
	for (int i = 0; i < NWAVES; i++) {
		vec4 w = waves[i];
		float fade = 1.0 - smoothstep(w.w * 0.08, w.w * 0.3, foot);
		if (fade > 0.0) {
			float k = 6.28318 / w.w;
			float f = k * dot(w.xy, p) - sqrt(9.81 * k) * t;
			float s = w.z * fade;
			float c = cos(f);
			n.x -= w.x * s * c;
			n.z -= w.y * s * c;
			n.y -= s * sin(f) * 0.5;
		}
	}
	// Capillary ripples from two scrolling normal maps.
	// Two layers at unrelated scales and angles, faded in and out by a very
	// broad third so the tiling never lines up into a visible grid.
	float near_f = 1.0 - smoothstep(60.0, 1200.0, dist);
	vec2 r2 = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8);
	vec2 d1 = texture(detail, p / 41.0 + wind * t * 0.010).xy * 2.0 - 1.0;
	vec2 d2 = texture(detail, r2 / 13.7 + vec2(-wind.y, wind.x) * t * 0.013 + wind * t * 0.016).xy * 2.0 - 1.0;
	float patchy = texture(foam_tex, p / 617.0).r;
	vec2 slope = (d1 * mix(0.06, 0.18, patchy) + d2 * 0.12) * (0.3 + 0.7 * near_f) * clamp(amp * 0.8 + 0.35, 0.4, 1.3);
	// Wakes, bow waves and splash patches from the wake map.
	float wake_foam = 0.0;
	float ripple = 0.0;
	if (wake_rect.w > 0.0) {
		vec2 wuv = (p - wake_rect.xy) / wake_rect.z + 0.5;
		vec2 e = smoothstep(vec2(0.0), vec2(0.07), wuv) * smoothstep(vec2(1.0), vec2(0.93), wuv);
		// The map is stored gamma-encoded; square it back to linear so faint
		// marks stay faint.
		vec4 wk = texture(wake_tex, wuv);
		wk *= wk;
		wake_foam = clamp(wk.r, 0.0, 1.0) * e.x * e.y;
		ripple = clamp(wk.g, 0.0, 1.0) * e.x * e.y;
	}
	vec2 d3 = texture(detail, p / 2.9 + vec2(t * 0.06, -t * 0.045)).xy * 2.0 - 1.0;
	slope += d3 * clamp(ripple * 1.6 + wake_foam, 0.0, 1.0) * 0.7;
	n.x += slope.x;
	n.z += slope.y;
	n = normalize(n);

	// Foam: breaking crests plus the wake map, drawn through a bubbly pattern.
	float crest = v_height / max(amp, 0.2);
	float breaking = clamp((0.64 - v_jac) * 2.4, 0.0, 1.0) * crest_foam * smoothstep(0.2, 0.9, crest);
	float cover = clamp(breaking + wake_foam * 1.15 + ripple * 0.25, 0.0, 1.0);
	float pat = texture(foam_tex, p / 7.0 + wind * t * 0.018).r * 0.62
		+ texture(foam_tex, p / 2.3 - wind * t * 0.011).r * 0.38;
	float foam = smoothstep(1.0 - cover, 1.0 - cover + 0.25, pat) * smoothstep(0.0, 0.12, cover);
	foam = mix(foam, cover * 0.55, smoothstep(120.0, 1000.0, dist));

	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 L = normalize(sun_dir);
	// Light glowing through thin wave crests, strongest looking toward the sun.
	float thin = smoothstep(-0.3, 1.2, crest);
	float toward = pow(clamp(dot(-V, L) * 0.5 + 0.5, 0.0, 1.0), 5.0);
	float facing = clamp(1.0 - dot(n, V), 0.0, 1.0);
	float sss = thin * thin * (0.12 + 1.5 * toward) * (0.4 + 0.6 * facing) * clamp(L.y * 3.0 + 0.15, 0.0, 1.0);
	vec3 body = deep + scatter * (0.08 + 0.22 * thin);
	// Churned, aerated water in a wake turns pale green.
	vec3 aerated = mix(scatter * 1.8, vec3(0.42, 0.6, 0.6), 0.3);
	body = mix(body, aerated, clamp(wake_foam * 0.8 + ripple * 0.12, 0.0, 0.65));

	if (FRONT_FACING) {
		ALBEDO = mix(body, foam_col, foam);
		ROUGHNESS = mix(mix(0.03, 0.2, smoothstep(40.0, 3000.0, dist)), 0.8, foam);
		SPECULAR = mix(0.35, 0.12, foam);
		vec3 nf = normalize(mix(n, vec3(0.0, 1.0, 0.0), foam * 0.6));
		NORMAL = normalize((VIEW_MATRIX * vec4(nf, 0.0)).xyz);
		EMISSION = scatter * sun_col * sss * sun_e * 0.45 * (1.0 - foam);
	} else {
		// Seen from below: dim water, with the bright circle of Snell's window overhead.
		NORMAL = normalize((VIEW_MATRIX * vec4(-n, 0.0)).xyz);
		float up = clamp(-V.y, 0.0, 1.0);
		float snell = smoothstep(0.62, 0.74, up);
		ALBEDO = under;
		ROUGHNESS = 0.35;
		SPECULAR = 0.2;
		EMISSION = mix(under * 0.5, scatter * 2.2 + vec3(0.06, 0.08, 0.08), snell) * (0.5 + 0.5 * sun_e)
			+ foam_col * foam * 0.15;
	}
}
