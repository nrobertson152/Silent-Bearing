shader_type spatial;
render_mode cull_disabled;
// Painted steel for warships and submarines, all procedural: period
// camouflage (graded bands, splotches, splinter and Baltic stripes),
// faded and chalky paint, hull plating, portholes, rust streaks running down
// from the deck edge and the hawse pipes, and grime at the waterline.
//
// Works in the model's own space (bow toward -Z, waterline at y = 0), so the
// pattern stays painted on as the ship moves and rolls. scripts/build/paint.gd
// sets the scheme and colours for each ship.

uniform int part = 0;          // 0 hull side, 1 superstructure, 2 fittings, 3 bottom, 4 boot topping
uniform int scheme = 0;        // 0 plain, 1 two bands, 2 three bands, 3 splotch, 4 splinter, 5 Baltic stripes, 6 light disruptive
uniform vec3 c0 : source_color = vec3(0.45, 0.47, 0.49);  // base, or the lowest band
uniform vec3 c1 : source_color = vec3(0.5, 0.52, 0.54);
uniform vec3 c2 : source_color = vec3(0.6, 0.62, 0.63);
uniform vec3 c3 : source_color = vec3(0.07, 0.07, 0.08);  // stripes
uniform vec3 top_col : source_color = vec3(0.32, 0.34, 0.36);  // horizontal surfaces
uniform float y0 = 8.0;        // band boundaries (model-space height, m)
uniform float y1 = 22.0;
uniform float hull_len = 200.0;
uniform float fb = 8.0;        // deck height amidships and at the bow
uniform float fb_bow = 11.0;
uniform float scuttle_y = -1.0;  // porthole row height, negative for none
uniform float seed = 0.0;
uniform float rust = 0.4;
uniform float grime = 0.5;
uniform float rough = 0.78;
uniform float metal = 0.0;
uniform float scale = 1.0;     // camouflage pattern size
uniform float band = 2.0;      // height of the grimy band above the waterline

#include "res://shaders/clip.gdshaderinc"

varying vec3 v_obj;
varying vec3 v_n;

float hash1(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash22(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}
float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash1(i), hash1(i + 1.0), f * f * (3.0 - 2.0 * f));
}
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
		p = p * 2.07 + vec2(5.3, 1.9);
		a *= 0.5;
	}
	return v;
}
// Nearest cell of a jittered grid: returns the cell id hash (for splinter patterns).
float cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 9.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g) * 0.85;
			float d = dot(g + o - f, g + o - f);
			if (d < best) {
				best = d;
				id = hash2(i + g + 3.7);
			}
		}
	}
	return id;
}

// Deck height along the hull, matching ShipBuilder.deck_h for the common case.
float deck_at(float u) {
	return fb + (fb_bow - fb) * pow(max(0.0, 1.0 - u / 0.32), 1.6);
}

vec3 bands(float y) {
	if (scheme == 1) {
		return y < y0 ? c0 : c1;
	}
	return y < y0 ? c0 : (y < y1 ? c1 : c2);
}

vec3 camo(vec3 p, vec2 uv, float side, float u) {
	if (scheme == 1 || scheme == 2) {
		return bands(p.y);
	} else if (scheme == 3) {
		// US Measure 12 (Modified): splotches of one band's colour laid over the next.
		vec3 base = bands(p.y);
		vec2 q = vec2(uv.x * 0.055, uv.y * 0.09) / scale + vec2(seed * 7.0 + side * 19.0, seed * 3.0);
		float a = fbm2(q);
		float m = smoothstep(0.56, 0.58, a);
		vec3 over = p.y < y0 ? c2 : (p.y < y1 ? c0 : c1);
		return mix(base, over, m);
	} else if (scheme == 4 || scheme == 6) {
		// Splinter / Admiralty disruptive: hard-edged angular patches.
		vec2 q = vec2(uv.x / 13.0, uv.y / 6.5) / scale + vec2(seed * 11.0 + side * 23.0, 0.0);
		// Shear the grid so the patches run at angles rather than along the decks.
		q.x += q.y * 0.45;
		float id = cells(q);
		if (scheme == 6) {
			return id < 0.5 ? c0 : (id < 0.78 ? c1 : c2);
		}
		return id < 0.42 ? c1 : (id < 0.75 ? c0 : c2);
	} else if (scheme == 5) {
		// Baltic stripes: black and white bands slanted across hull and superstructure,
		// one group toward the bow and one toward the stern, on light grey.
		float sw = hull_len * 0.034;
		float s = (p.z + p.y * 0.32) / sw;
		float zb = (-0.5 + 0.1) * hull_len / sw;
		float zs = (-0.5 + 0.78) * hull_len / sw;
		vec3 col = c0;
		if (s > zb && s < zb + 3.0) {
			col = mod(floor(s - zb), 2.0) < 0.5 ? c3 : c2;
		}
		if (s > zs && s < zs + 3.0) {
			col = mod(floor(s - zs), 2.0) < 0.5 ? c3 : c2;
		}
		return col;
	}
	return c0;
}

void vertex() {
	v_obj = VERTEX;
	v_n = NORMAL;
}

void fragment() {
	float edge = clip_ship(v_obj);
	vec3 p = v_obj;
	vec3 n = normalize(v_n);
	vec3 an = abs(n);
	float side = n.x >= 0.0 ? 1.0 : -1.0;
	bool top = an.y > max(an.x, an.z) && n.y > 0.0;
	vec2 uv = an.x >= an.z ? vec2(p.z, p.y) : vec2(p.x + 400.0, p.y);
	float u = clamp(p.z / hull_len + 0.5, 0.0, 1.0);
	float fw = max(length(fwidth(p)), 1e-4);   // metres per pixel
	vec3 col;
	if (part == 3) {
		col = c0;
	} else if (part == 4) {
		col = c0;
	} else if (part == 2) {
		col = c0;
	} else {
		col = top ? top_col : camo(p, uv, side, u);
	}

	// Faded, chalky paint and touch-up patches.
	float mott = fbm2(vec2(p.z * 0.11 + p.x * 0.07, p.y * 0.21) + seed * 5.0);
	col *= 0.9 + 0.2 * mott;
	float patchy = smoothstep(0.62, 0.66, noise2(vec2(p.z * 0.09, p.y * 0.2) + seed * 9.0));
	col = mix(col, col * 0.86, patchy * grime * 0.6);

	float rs = 0.0;   // how much rust shows here
	float dirt = 0.0; // how much grime
	if (part == 0) {
		// Plating: strakes every 2.4 m and staggered butts every 9 m, faded out with distance.
		float lines_k = 1.0 - smoothstep(0.05, 0.25, fw);
		float sy = abs(fract(p.y / 2.4) - 0.5) * 2.4;
		float strake = floor(p.y / 2.4);
		float sz = abs(fract(p.z / 9.0 + strake * 0.37) - 0.5) * 9.0;
		float seam = (1.0 - smoothstep(0.02, 0.02 + fw * 1.5, abs(sy - 1.2)))
			+ (1.0 - smoothstep(0.02, 0.02 + fw * 1.5, abs(sz - 4.5)));
		col *= 1.0 - 0.07 * clamp(seam, 0.0, 1.0) * lines_k;
		// Frames show through the plating as faint dished panels ("hungry horse").
		col *= 1.0 - 0.025 * lines_k * pow(abs(sin(p.z / 1.2 * 3.14159)), 6.0);
		// Rust weeping down from the deck edge and scuppers: thin, sparse runs of
		// different lengths, with fainter grime streaks between them.
		float below = deck_at(u) - p.y;
		float zc = p.z * 3.3 + seed * 13.0 + side * 31.0;
		float colm = noise1(zc);
		float run = (0.5 + 3.5 * noise1(p.z * 0.71 + seed * 7.0 + side * 3.0)) * (0.5 + rust);
		float fall = exp(-max(below, 0.0) / run) * step(-0.2, below);
		float streak = smoothstep(0.8, 0.95, colm) * fall;
		streak *= 0.5 + 0.5 * noise2(vec2(p.z * 4.0, p.y * 0.6) + seed);
		float smear = smoothstep(0.55, 0.8, noise1(zc * 0.37 + 5.0)) * exp(-max(below, 0.0) / (run * 1.8)) * step(-0.2, below);
		dirt = max(dirt, smear * 0.5);
		// The anchors' hawse pipes leave long red-brown tears.
		float za = (-0.5 + 0.034) * hull_len + 1.0;
		float hawse = exp(-pow((p.z - za) / 0.9, 2.0)) * smoothstep(fb_bow, fb_bow - 2.5, p.y) * smoothstep(0.0, 2.0, p.y);
		rs = max(rs, streak * 0.9 + hawse * 0.8);
		// Salt-grey scum and oily grime just above the waterline.
		dirt = max(dirt, smoothstep(band, band * 0.3, p.y) * (0.6 + 0.4 * noise2(vec2(p.z * 0.6, p.y * 3.0))));
		// Portholes.
		if (scuttle_y > 0.0 && u > 0.1 && u < 0.86) {
			vec2 g = vec2(mod(p.z + 1.5, 3.0) - 1.5, p.y - scuttle_y);
			float d = length(g);
			float hole = (1.0 - smoothstep(0.16, 0.16 + fw, d)) * (1.0 - smoothstep(0.08, 0.3, fw));
			float ring = (1.0 - smoothstep(0.2, 0.2 + fw, d)) * (1.0 - smoothstep(0.08, 0.3, fw)) - hole;
			col = mix(col, vec3(0.03, 0.035, 0.04), hole * an.x);
			col = mix(col, col * 0.7, ring * an.x * 0.5);
		}
	} else if (part == 1) {
		// Superstructure: panel seams, streaks of soot and rust down the walls.
		float lines_k = 1.0 - smoothstep(0.04, 0.2, fw);
		float sz = abs(fract((an.x >= an.z ? p.z : p.x) / 1.8) - 0.5) * 1.8;
		col *= 1.0 - 0.06 * (1.0 - smoothstep(0.015, 0.015 + fw * 1.5, abs(sz - 0.9))) * lines_k;
		float colm = noise1((an.x >= an.z ? p.z : p.x) * 2.3 + seed * 17.0);
		float streak = smoothstep(0.62, 0.9, colm) * noise2(vec2((an.x >= an.z ? p.z : p.x) * 3.0, p.y * 0.25) + seed);
		rs = max(rs, streak * smoothstep(0.85, 0.95, colm) * 0.6);
		dirt = max(dirt, streak * 0.45);
	} else if (part == 2) {
		float spots = smoothstep(0.6, 0.85, fbm2(vec2(p.x + p.z, p.y) * 0.9 + seed));
		rs = max(rs, spots * 0.8);
		col *= 0.9 + 0.2 * noise2(p.xz * 2.0 + p.y);
	} else if (part == 3) {
		// Antifouling red below the waterline, slimy green toward the top.
		float slime = smoothstep(-2.0, 0.0, p.y);
		col = mix(col, vec3(0.10, 0.13, 0.07), slime * 0.6);
		col *= 0.85 + 0.3 * noise2(vec2(p.z * 0.5, p.y * 2.0) + seed);
	} else if (part == 4) {
		float algae = smoothstep(0.6, 0.0, p.y);
		col = mix(col, vec3(0.08, 0.11, 0.06), algae * 0.45 * grime);
		rs = max(rs, smoothstep(0.7, 0.9, noise1(p.z * 1.3 + seed)) * smoothstep(0.0, 0.7, p.y) * 0.5);
	}
	vec3 rust_c = mix(vec3(0.24, 0.12, 0.06), vec3(0.38, 0.2, 0.09), noise2(p.zy * 3.0));
	rs = clamp(rs * rust * 1.1, 0.0, 0.7);
	col = mix(col, col * vec3(0.72, 0.74, 0.7) + vec3(0.02, 0.025, 0.015), dirt * grime * 0.7);
	col = mix(col, rust_c, rs);
	// A torn-open hull: dark inside, scorched along the break.
	if (!FRONT_FACING && cut.y != 0.0) {
		col *= 0.12;
	}
	col *= mix(0.15, 1.0, smoothstep(0.0, 4.0, edge));
	ALBEDO = col;
	ROUGHNESS = clamp(rough + rs * 0.15 - mott * 0.08, 0.3, 1.0);
	METALLIC = metal * (1.0 - rs);
	SPECULAR = 0.4;
}
