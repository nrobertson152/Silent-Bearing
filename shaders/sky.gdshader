shader_type sky;
// Sky: a graded dome with horizon haze, a sun with a bright halo, moon and
// stars at night, and a drifting layer of cumulus lit from the sun's side,
// dark underneath and silver-edged when the sun is behind them.

uniform vec3 top_col : source_color = vec3(0.30, 0.48, 0.66);
uniform vec3 hor_col : source_color = vec3(0.72, 0.78, 0.80);
uniform vec3 ground_col : source_color = vec3(0.10, 0.14, 0.16);
uniform vec3 sun_dir = vec3(0.3, 0.5, -0.8);
uniform vec3 sun_col : source_color = vec3(1.0, 0.92, 0.80);
uniform float stars = 0.0;
uniform vec3 moon_dir = vec3(-0.4, 0.25, 0.8);
uniform float moon = 0.0;
uniform vec3 cloud_col : source_color = vec3(0.85, 0.87, 0.88);
uniform float cloud_cover = 0.45;
uniform vec2 wind = vec2(1.0, 0.0);
uniform float t = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v;
}

float clouds(vec2 uv, int oct) {
	float c = fbm(uv, oct);
	return smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, c);
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 sd = normalize(sun_dir);
	float s = max(dot(d, sd), 0.0);
	// Dome: deep overhead, pale and hazy at the horizon, warmer toward the sun.
	vec3 col = mix(hor_col, top_col, pow(clamp(h, 0.0, 1.0), 0.45));
	col = mix(col, hor_col * 1.05, pow(1.0 - clamp(h, 0.0, 1.0), 10.0) * 0.6);
	col += sun_col * hor_col * pow(s, 6.0) * 0.25 * (1.0 - clamp(h, 0.0, 1.0));
	if (h < 0.0) {
		col = mix(hor_col, ground_col, clamp(-h * 6.0, 0.0, 1.0));
	}
	// Sun disc and halo (the disc is skipped in reflections to avoid fireflies).
	col += sun_col * (pow(s, 12.0) * 0.22 + pow(s, 3.0) * 0.06);
	if (!AT_CUBEMAP_PASS) {
		col += sun_col * smoothstep(0.99955, 0.99975, s) * 14.0 * clamp(sd.y * 8.0 + 0.4, 0.0, 1.0);
		col += sun_col * pow(s, 400.0) * 3.0;
	}
	if (stars > 0.0 && h > 0.0 && !AT_CUBEMAP_PASS) {
		vec3 q = floor(d * 380.0);
		float r = fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float tw = 0.7 + 0.3 * sin(t * 3.0 + r * 60.0);
		col += vec3(step(0.9986, r)) * stars * smoothstep(0.0, 0.2, h) * tw;
	}
	if (moon > 0.0) {
		float m = dot(d, normalize(moon_dir));
		col += vec3(0.92, 0.93, 0.86) * smoothstep(0.99955, 0.99975, m) * moon * 1.6;
		col += vec3(0.10, 0.12, 0.15) * pow(max(m, 0.0), 40.0) * moon;
	}
	if (h > 0.005) {
		int oct = AT_CUBEMAP_PASS ? 3 : 5;
		vec2 uv = d.xz / (h + 0.06) * 1.3 + wind * t * 0.004;
		float c = clouds(uv, oct);
		// Self-shadowing: step toward the sun and see how much cloud is in the way.
		vec2 step_uv = normalize(sd.xz + vec2(1e-4)) * 0.18;
		float shade = clouds(uv + step_uv, oct);
		float lit = clamp(1.0 - shade * 0.75, 0.0, 1.0);
		vec3 dark = cloud_col * mix(vec3(0.5, 0.53, 0.58), hor_col, 0.25);
		vec3 cc = mix(dark, cloud_col * (1.0 + 0.25 * sun_col), lit);
		// Silver lining around clouds in front of the sun.
		cc += sun_col * pow(s, 8.0) * (1.0 - c) * 1.5;
		cc *= 0.85 + 0.3 * fbm(uv * 2.7 + 5.0, oct - 1);
		float fade = smoothstep(0.005, 0.12, h);
		col = mix(col, cc, c * fade * 0.92);
	}
	COLOR = col;
}
