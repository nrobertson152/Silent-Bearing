shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled, shadows_disabled;
// Bow wave and hull wash under a moving ship, drawn into the wake map on a quad
// that rides with the hull (scripts/view/wakes.gd). The quad spans 2.6 beams
// by 1.3 lengths; the bow points toward -Z (UV.y = 0).

uniform float beam = 10.0;
uniform float hull_len = 100.0;
uniform float speed = 0.0;     // 0 stopped .. 1 at about 25 knots
uniform float chop = 0.15;     // white water slapping the hull even when stopped

void fragment() {
	// Position in metres from the hull's centre, bow toward -z.
	vec2 m = (UV - 0.5) * vec2(beam * 2.6, hull_len * 1.3);
	float u = m.y / (hull_len * 0.5);             // -1 at the bow, +1 at the stern
	float half_w = beam * 0.5 * pow(clamp(1.0 - pow(max(-u, 0.0), 2.2), 0.0, 1.0), 0.55)
		* (u > 0.6 ? mix(1.0, 0.75, (u - 0.6) / 0.4) : 1.0);
	float d = abs(m.x) - half_w;                // metres outside the hull side
	float side = exp(-max(d, 0.0) / (beam * 0.22)) * step(-beam * 0.3, d) * step(u, 1.02);
	// Bow wave: a rolling white wave thrown off both sides of the stem.
	float bow = smoothstep(-0.2, -0.85, u) * exp(-max(d, 0.0) / (beam * 0.45)) * step(-beam * 0.2, d);
	float stem = exp(-length(m - vec2(0.0, -hull_len * 0.5)) / (beam * 0.5));
	// Propeller wash boiling up just astern.
	float wash = smoothstep(0.85, 1.0, u) * smoothstep(1.3, 1.0, u) * exp(-abs(m.x) / (beam * 0.45));
	float s = clamp(speed, 0.0, 1.3);
	float foam = side * (chop + 0.45 * s) + bow * 1.1 * s + stem * 0.9 * s + wash * (0.15 + 0.9 * s);
	// Fade out well inside the quad so its edges never show.
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.12, min(e.x, e.y));
	ALBEDO = vec3(1.0, 0.35 * s, 0.0);
	ALPHA = clamp(foam * edge, 0.0, 1.0);
}
