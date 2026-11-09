shader_type spatial;
render_mode cull_disabled;
// Plain paint for the small fittings (windows, boats, aircraft spotted on
// deck), with the same break-in-two clip as the painted hull.

uniform vec3 albedo : source_color = vec3(0.5);
uniform float rough = 0.85;
uniform float metal = 0.0;

#include "res://shaders/clip.gdshaderinc"

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float edge = clip_ship(v_obj);
	vec3 col = albedo;
	if (!FRONT_FACING && cut.y != 0.0) {
		col *= 0.15;
	}
	col *= mix(0.25, 1.0, smoothstep(0.0, 4.0, edge));
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
}
