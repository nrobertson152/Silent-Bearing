shader_type spatial;
render_mode cull_disabled;
// Decks: laid planks with tarred seams, staggered butt joints and per-plank
// colour and grain (bleached teak, pine, or US decks and flight decks stained
// blue), or steel plating and linoleum for destroyers and casings. Seams fade
// to their average tone once they are smaller than a pixel, so distant decks
// don't shimmer. Works in model space like shaders/paint.gdshader.

uniform vec3 wood : source_color = vec3(0.48, 0.39, 0.29);
uniform vec3 seam : source_color = vec3(0.07, 0.06, 0.05);
uniform vec3 stain : source_color = vec3(0.17, 0.2, 0.25);
uniform float stained = 0.0;    // 1 = painted or stained over the planks
uniform float plank = 0.15;     // plank width (m)
uniform float plank_len = 7.5;
uniform float across = 0.0;     // 1 = planks laid athwartships (US flight decks)
uniform float steel = 0.0;      // 1 = steel plates or linoleum instead of planks
uniform vec3 steel_col : source_color = vec3(0.32, 0.33, 0.34);
uniform float wear = 0.5;
uniform float rust = 0.3;
uniform float seed = 0.0;

varying vec3 v_obj;
varying vec3 v_n;

float hash1(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Filtered line: 1 on a seam of half-width `hw` (in cell units), fading to its
// average coverage when the pixel footprint `fp` (cell units) grows.
float seam_line(float f, float hw, float fp) {
	float d = min(f, 1.0 - f);
	float l = 1.0 - smoothstep(hw, hw + fp, d);
	return mix(l, hw * 2.0, smoothstep(0.25, 0.6, fp));
}

void vertex() {
	v_obj = VERTEX;
	v_n = NORMAL;
}

void fragment() {
	vec3 p = v_obj;
	vec3 n = normalize(v_n);
	vec3 col;
	float rough = 0.85;
	if (abs(n.y) < 0.6) {
		// Deck edges and the sides of deck blocks: plain weathered paint.
		col = mix(steel_col, stain, stained) * (0.9 + 0.15 * noise2(p.zy * 0.8));
	} else if (steel > 0.5) {
		// Steel plates welded in a staggered grid, with non-skid grit, scuffs and rust.
		vec2 g = vec2(p.x / 1.8, p.z / 6.0);
		float row = floor(g.x);
		vec2 f = vec2(fract(g.x), fract(g.y + hash1(row + seed) * 0.5));
		float fpx = fwidth(g.x);
		float fpz = fwidth(g.y);
		float weld = max(seam_line(f.x, 0.01, fpx), seam_line(f.y, 0.004, fpz));
		col = steel_col * (0.9 + 0.12 * hash2(vec2(row, floor(g.y + hash1(row + seed) * 0.5))));
		col *= 0.92 + 0.12 * noise2(p.xz * 6.0);
		col *= 1.0 - weld * 0.25;
		float scuff = fbm2(p.xz * 0.35 + seed);
		col = mix(col, col * 1.18, smoothstep(0.55, 0.75, scuff) * wear * 0.6);
		float rs = smoothstep(0.66, 0.82, fbm2(p.xz * 0.6 + seed * 3.0)) * rust;
		col = mix(col, vec3(0.3, 0.15, 0.07), rs * 0.7);
		rough = 0.8;
	} else {
		vec2 uv = across > 0.5 ? vec2(p.z, p.x) : vec2(p.x, p.z);
		float row = floor(uv.x / plank);
		float fx = fract(uv.x / plank);
		float off = hash1(row + seed) * plank_len;
		float seg = floor((uv.y + off) / plank_len);
		float fy = fract((uv.y + off) / plank_len);
		float id = hash2(vec2(row, seg) + seed);
		float fpx = fwidth(uv.x) / plank;
		float fpy = fwidth(uv.y) / plank_len;
		// Planks lose their individual colour once they are smaller than a pixel.
		float detail = 1.0 - smoothstep(0.3, 1.0, fpx);
		vec3 c = wood * mix(1.0, 0.8 + 0.4 * id, detail);
		float grain = noise2(vec2(uv.x * 45.0, uv.y * 1.2) + id * 17.0);
		c *= mix(1.0, 0.9 + 0.2 * grain, detail * (1.0 - smoothstep(0.02, 0.06, fwidth(uv.x * 45.0) / 45.0)));
		// Butt joints vanish with the planks' own detail, or they alias into specks.
		float butt = seam_line(fy, 0.003, fpy) * detail * (1.0 - smoothstep(0.05, 0.3, fpy));
		float sm = max(seam_line(fx, 0.06, fpx), butt);
		c = mix(c, seam, sm * 0.85);
		// Weathering: sun-bleached in the open, darker where feet and fittings scuff it.
		float bleach = fbm2(p.xz * 0.08 + seed * 2.0);
		c = mix(c, c * 1.15 + vec3(0.03), smoothstep(0.45, 0.8, bleach) * wear * 0.5);
		c = mix(c, c * 0.75, smoothstep(0.6, 0.85, fbm2(p.xz * 0.3 + 7.0 + seed)) * wear * 0.5);
		// Stain or paint laid over the wood, worn through in places.
		float worn = smoothstep(0.62, 0.8, fbm2(p.xz * 0.25 + seed * 4.0)) * wear;
		vec3 painted = stain * (0.92 + 0.16 * id * detail) * mix(1.0, 0.75, sm * 0.6);
		col = mix(c, painted, stained * (1.0 - worn * 0.7));
		rough = mix(0.9, 0.8, stained);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
