shader_type sky;
// Gradient sky with sun glow, moon, stars and a drifting cloud layer.

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
uniform float t = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(hor_col, top_col, pow(clamp(h, 0.0, 1.0), 0.5));
	if (h < 0.0) {
		col = mix(hor_col, ground_col, clamp(-h * 6.0, 0.0, 1.0));
	}
	vec3 sd = normalize(sun_dir);
	float s = max(dot(d, sd), 0.0);
	col += sun_col * (pow(s, 900.0) * 8.0 + pow(s, 12.0) * 0.18 + pow(s, 3.0) * 0.06);
	if (stars > 0.0 && h > 0.0) {
		vec3 q = floor(d * 380.0);
		float r = fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		col += vec3(step(0.9986, r)) * stars * smoothstep(0.0, 0.2, h);
	}
	if (moon > 0.0) {
		float m = dot(d, normalize(moon_dir));
		col += vec3(0.92, 0.93, 0.86) * smoothstep(0.99955, 0.99975, m) * moon;
		col += vec3(0.10, 0.12, 0.15) * pow(max(m, 0.0), 40.0) * moon;
	}
	if (h > 0.01) {
		vec2 uv = d.xz / (h + 0.08) * 1.4 + vec2(t * 0.004, t * 0.002);
		float c = fbm(uv);
		float cover = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.25, c);
		vec3 cc = cloud_col * (0.75 + 0.35 * fbm(uv * 1.7 + 3.0));
		col = mix(col, cc, cover * smoothstep(0.01, 0.12, h) * 0.9);
	}
	COLOR = col;
}
