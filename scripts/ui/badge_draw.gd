extends Control
## Period national markings, drawn rather than imported.

var nation := "us"


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	match nation:
		"us":
			draw_circle(c, r, Color(0.13, 0.2, 0.41))
			var pts := PackedVector2Array()
			for i in 10:
				var rr := r * (0.86 if i % 2 == 0 else 0.35)
				var a := -PI / 2 + i * PI / 5
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(pts, Color(0.94, 0.94, 0.92))
		"uk":
			draw_circle(c, r, Color(0.13, 0.2, 0.41))
			draw_circle(c, r * 0.66, Color(0.93, 0.93, 0.9))
			draw_circle(c, r * 0.34, Color(0.73, 0.16, 0.14))
		"de":
			draw_circle(c, r, Color(0.26, 0.27, 0.26))
			var w := r * 0.86
			var a := r * 0.3
			draw_rect(Rect2(c - Vector2(a + 3, w + 3), Vector2(2 * a + 6, 2 * w + 6)), Color(0.93, 0.93, 0.9))
			draw_rect(Rect2(c - Vector2(w + 3, a + 3), Vector2(2 * w + 6, 2 * a + 6)), Color(0.93, 0.93, 0.9))
			draw_rect(Rect2(c - Vector2(a, w), Vector2(2 * a, 2 * w)), Color(0.08, 0.08, 0.08))
			draw_rect(Rect2(c - Vector2(w, a), Vector2(2 * w, 2 * a)), Color(0.08, 0.08, 0.08))
		"jp":
			draw_circle(c, r, Color(0.93, 0.93, 0.9))
			draw_circle(c, r * 0.6, Color(0.74, 0.13, 0.16))
	draw_arc(c, r, 0, TAU, 48, Color(0.79, 0.65, 0.36), 2.0)
