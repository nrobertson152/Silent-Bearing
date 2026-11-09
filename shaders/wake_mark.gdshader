shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled, shadows_disabled;
// Soft blobs drawn into the top-down wake map (scripts/view/wakes.gd), never
// seen by the main camera. Red is churned foam, green is the wave lines of a
// Kelvin wake. The particle colour ramp fades each blob as it ages.

uniform vec3 channel = vec3(1.0, 0.0, 0.0);
uniform float strength = 1.0;
uniform float ring = 0.0;   // 0 solid blob, 1 thin ring (for shock rings)

varying float v_seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	v_seed = float(INSTANCE_ID);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float blob = smoothstep(1.0, 0.15, r);
	float band = smoothstep(0.62, 0.86, r) * smoothstep(1.0, 0.88, r);
	float a = mix(blob, band, ring);
	// Break the edge up a little so overlapping blobs don't read as circles.
	a *= 0.75 + 0.25 * hash(floor(UV * 9.0) + vec2(v_seed * 3.7));
	ALBEDO = channel * strength;
	ALPHA = clamp(a * COLOR.r * COLOR.a, 0.0, 1.0);
}
