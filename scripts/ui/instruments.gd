extends Control
## Live instrument faces drawn with the 2D canvas. The same control works as
## a full-screen station overlay and inside a SubViewport textured onto the
## 3D panels in the control room.

const U := preload("res://scripts/util.gd")
const World := preload("res://scripts/sim/world.gd")

const PHOS := Color(0.56, 0.86, 0.66)
const AMBER := Color(0.94, 0.71, 0.30)
const ALARM := Color(0.91, 0.35, 0.25)
const INK := Color(0.13, 0.11, 0.09)
const DIAL := Color(0.91, 0.88, 0.78)
const BRASS := Color(0.79, 0.65, 0.36)
const BRASS_LO := Color(0.47, 0.38, 0.22)
const PAPER := Color(0.81, 0.82, 0.75)
const PAPER_DK := Color(0.74, 0.75, 0.69)
const CHART_INK := Color(0.14, 0.17, 0.19)
const RED_INK := Color(0.61, 0.17, 0.13)

var kind := "gauges"
var world: World
var chart_r := 6000.0
var t := 0.0


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	match kind:
		"sonar":
			draw_rect(r, Color(0.05, 0.07, 0.06))
			draw_sonar(self, r, world, t)
		"chart":
			draw_chart(self, r, world, chart_r)
		"gauges":
			draw_gauges(self, r, world)
		"depth":
			draw_rect(r, Color(0.08, 0.09, 0.09))
			var R := minf(r.size.x, r.size.y) * 0.45
			var N := world.nat
			var vmax := 150.0 if float(N["crush"]) <= 160.0 else 300.0
			draw_dial(self, r.get_center(), R, world.sub.depth, 0.0, vmax, "DEPTH  METRES", "%3.0f" % world.sub.depth,
				25.0 if vmax <= 150.0 else 50.0, 5.0 if vmax <= 150.0 else 10.0, float(N["test"]), world.sub.dep_ord)
		"compass":
			draw_rect(r, Color(0.08, 0.09, 0.09))
			draw_compass(self, r.get_center(), minf(r.size.x, r.size.y) * 0.45, world.sub.hdg, world.sub.rud)
		"tdc":
			draw_tdc(self, r, world)
		"damage":
			draw_damage(self, r, world)
		"tree":
			draw_tree(self, r, world)


static func font() -> Font:
	return ThemeDB.fallback_font


static func text(ci: CanvasItem, s: String, pos: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := font()
	var w := width
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER and width < 0.0:
		w = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		p.x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT and width < 0.0:
		w = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		p.x -= w
	ci.draw_string(f, p + Vector2(0, size * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ------------------------------------------------------------- hydrophones
static func draw_sonar(ci: CanvasItem, rect: Rect2, w: World, t: float) -> void:
	var s := w.sub
	var c := rect.get_center()
	var R := minf(rect.size.x, rect.size.y) * 0.42
	ci.draw_circle(c, R + 10, Color(0.03, 0.04, 0.04))
	ci.draw_arc(c, R + 7, 0, TAU, 64, BRASS_LO, 4.0)
	for i in range(6, 0, -1):
		ci.draw_circle(c, R * i / 6.0, Color(0.02, 0.05, 0.04).lerp(Color(0.04, 0.11, 0.08), i / 6.0))
	var dim := Color(0.14, 0.30, 0.21)
	ci.draw_arc(c, R * 0.33, 0, TAU, 48, dim, 1.0)
	ci.draw_arc(c, R * 0.66, 0, TAU, 48, dim, 1.0)
	for d in range(0, 360, 10):
		var a := deg_to_rad(d)
		var r0 := R - (10.0 if d % 30 == 0 else 5.0)
		ci.draw_line(c + Vector2(sin(a), -cos(a)) * r0, c + Vector2(sin(a), -cos(a)) * R,
			Color(0.3, 0.55, 0.4) if d % 30 == 0 else dim, 1.0)
	for d in range(0, 360, 30):
		var a := deg_to_rad(d)
		var lbl := "BOW" if d == 0 else ("STERN" if d == 180 else "%03d" % d)
		text(ci, lbl, c + Vector2(sin(a), -cos(a)) * (R - 24), 12, Color(0.35, 0.6, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	var ang := fmod(t * 50.0, 360.0)
	for k in 14:
		var a0 := deg_to_rad(ang - k * 2.5)
		var a1 := deg_to_rad(ang - (k + 1) * 2.5)
		ci.draw_colored_polygon(PackedVector2Array([c, c + Vector2(sin(a0), -cos(a0)) * R, c + Vector2(sin(a1), -cos(a1)) * R]),
			Color(0.47, 0.9, 0.63, maxf(0.0, 0.18 - k * 0.013)))
	var hydro: float = s.sys["hydrophones"]
	var own_noise := absf(s.spd) > 6.0 or s.flood < 1.0
	var modern: bool = w.nat.get("nuclear", false)
	if modern:
		own_noise = absf(s.spd) > 12.0
	for sh in w.ships:
		if not sh.heard:
			continue
		var b := U.brg(s.pos, sh.pos)
		var rel := U.adiff(b, s.hdg)
		var strength := w.strobe(sh)
		if own_noise and not modern:
			strength *= 0.55
		var a := deg_to_rad(rel)
		var dv := Vector2(sin(a), -cos(a))
		var col: Color
		if sh.hunting():
			col = Color(0.24, 0.16, 0.04).lerp(AMBER, 0.4 + 0.6 * strength)
		elif sh.struct <= 0.0:
			col = Color(0.2, 0.2, 0.2).lerp(Color(0.8, 0.8, 0.8), strength)
		else:
			col = Color(0.12, 0.27, 0.18).lerp(PHOS, 0.3 + 0.7 * strength)
		var r1 := R * (0.25 + 0.73 * strength)
		ci.draw_line(c + dv * R * 0.12, c + dv * r1, col, 3.0)
		ci.draw_circle(c + dv * r1, 4.0, col)
		if sh.kind == "target" or sh.hunting():
			text(ci, U.p3(b), c + dv * (r1 + 16), 13, col, HORIZONTAL_ALIGNMENT_CENTER)
	for tp in w.torps:
		var a := deg_to_rad(U.adiff(U.brg(s.pos, tp.pos), s.hdg))
		var rr := R * clampf(0.2 + s.pos.distance_to(tp.pos) / (40000.0 if modern else 6000.0), 0.2, 0.95)
		ci.draw_circle(c + Vector2(sin(a), -cos(a)) * rr, 2.5, Color(0.9, 0.5, 0.35))
	# Torpedoes coming for us, heard as a high-pitched whine.
	for tp in w.threats():
		var a := deg_to_rad(U.adiff(U.brg(s.pos, tp.pos), s.hdg))
		var dv := Vector2(sin(a), -cos(a))
		var near := clampf(1.0 - s.pos.distance_to(tp.pos) / 9000.0, 0.15, 1.0)
		ci.draw_line(c + dv * R * 0.12, c + dv * R * (0.3 + 0.68 * near), ALARM, 4.0)
		text(ci, "TORPEDO", c + dv * (R * (0.3 + 0.68 * near) + 16), 13, ALARM, HORIZONTAL_ALIGNMENT_CENTER)
	if w.ping_flash > 0.0:
		ci.draw_arc(c, R * (1.05 - w.ping_flash * 0.5), 0, TAU, 64, Color(0.04, 0.11, 0.08).lerp(AMBER, w.ping_flash), 2.0)
		text(ci, "ACTIVE SONAR ON US", c + Vector2(0, R * 0.5), 14, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -R - 2), c + Vector2(-6, -R - 13), c + Vector2(6, -R - 13)]), BRASS)
	ci.draw_circle(c, 3, PHOS)
	var status := "OWN NOISE HIGH: slow down to listen" if own_noise else "Bearing only. Longer strobe means louder."
	if modern and not own_noise:
		status = "Towed array: bearings only. Change course to let fire control find the range."
	if hydro <= 25.0:
		status = "HYDROPHONES DAMAGED"
	text(ci, status, Vector2(c.x, rect.end.y - 14), 13, AMBER if (own_noise or hydro <= 25.0) else Color(0.5, 0.55, 0.52), HORIZONTAL_ALIGNMENT_CENTER)


# --------------------------------------------------------------- plot table
static func draw_chart(ci: CanvasItem, rect: Rect2, w: World, radius: float) -> void:
	var s := w.sub
	ci.draw_rect(rect, PAPER)
	var c := rect.get_center()
	var ppm := (minf(rect.size.x, rect.size.y) * 0.5 - 8.0) / radius
	var W := func(p: Vector2) -> Vector2: return c + Vector2(p.x - s.pos.x, -(p.y - s.pos.y)) * ppm
	var g := 1000.0 if radius <= 6000.0 else 2000.0
	var x := floorf((s.pos.x - rect.size.x / ppm) / g) * g
	while x < s.pos.x + rect.size.x / ppm:
		var X: float = W.call(Vector2(x, 0)).x
		if X > rect.position.x and X < rect.end.x:
			ci.draw_line(Vector2(X, rect.position.y), Vector2(X, rect.end.y), PAPER_DK, 1.0)
		x += g
	var y := floorf((s.pos.y - rect.size.y / ppm) / g) * g
	while y < s.pos.y + rect.size.y / ppm:
		var Y: float = W.call(Vector2(0, y)).y
		if Y > rect.position.y and Y < rect.end.y:
			ci.draw_line(Vector2(rect.position.x, Y), Vector2(rect.end.x, Y), PAPER_DK, 1.0)
		y += g
	for isl in w.islands:
		var p: Vector2 = W.call(isl["pos"])
		var rr: float = float(isl["r"]) * ppm
		if p.distance_to(c) - rr < rect.size.length():
			ci.draw_circle(p, rr, Color(0.72, 0.68, 0.55))
			ci.draw_arc(p, rr, 0, TAU, 32, Color(0.5, 0.45, 0.35), 1.5)
	var tr: float = float(w.nat["torp"]["range"]) * ppm
	for k in range(0, 72, 2):
		ci.draw_arc(c, tr, deg_to_rad(k * 5), deg_to_rad(k * 5 + 5), 3, Color(0.6, 0.47, 0.38), 1.0)
	var far := radius * 1.6
	for sh in w.ships:
		if sh.heard:
			var b := U.dirv(U.brg(s.pos, sh.pos))
			ci.draw_line(c, c + Vector2(b.x, -b.y) * far * ppm, Color(0.75, 0.47, 0.16) if sh.hunting() else Color(0.5, 0.53, 0.6), 1.0)
	for sh in w.ships:
		if sh.plot == null:
			continue
		var pd: Dictionary = sh.plot
		var age: float = w.t - pd["t"]
		var P: Vector2 = W.call(pd["pos"])
		var col := RED_INK if sh.kind == "target" else CHART_INK
		if sh.dead or sh.struct <= 0.0:
			ci.draw_line(P + Vector2(-6, -6), P + Vector2(6, 6), col, 2.0)
			ci.draw_line(P + Vector2(-6, 6), P + Vector2(6, -6), col, 2.0)
		else:
			var hv := U.dirv(pd["hdg"])
			var vec := Vector2(hv.x, -hv.y) * float(pd["spd"]) * U.KN * 120.0 * ppm
			ci.draw_line(P, P + vec, col, 1.0)
			var pts: PackedVector2Array
			if sh.kind == "target":
				pts = PackedVector2Array([P + Vector2(0, -7), P + Vector2(7, 0), P + Vector2(0, 7), P + Vector2(-7, 0)])
			else:
				var a := deg_to_rad(float(pd["hdg"]))
				pts = PackedVector2Array([P + Vector2(sin(a), -cos(a)) * 7.0, P + Vector2(sin(a + 2.5), -cos(a + 2.5)) * 5.0,
					P + Vector2(sin(a - 2.5), -cos(a - 2.5)) * 5.0])
			if age < 4.0:
				ci.draw_colored_polygon(pts, col)
			else:
				pts.append(pts[0])
				ci.draw_polyline(pts, col, 1.5)
		text(ci, sh.short, P + Vector2(10, -8), 13, col)
		if age >= 4.0:
			text(ci, "seen -%d:%02d" % [int(age) / 60, int(age) % 60], P + Vector2(10, 7), 11, Color(0.43, 0.43, 0.39))
	for p in w.planes:
		if p.dead or not p.spotted:
			continue
		var P: Vector2 = W.call(p.pos)
		ci.draw_line(P + Vector2(-6, 0), P + Vector2(6, 0), Color(0.2, 0.2, 0.5), 2.0)
		ci.draw_line(P + Vector2(0, -3), P + Vector2(0, 5), Color(0.2, 0.2, 0.5), 2.0)
	for tp in w.torps:
		var pts := PackedVector2Array()
		for q in tp.trail:
			pts.append(W.call(q))
		pts.append(W.call(tp.pos))
		if pts.size() > 1:
			ci.draw_polyline(pts, RED_INK, 1.0)
		ci.draw_circle(W.call(tp.pos), 3, RED_INK)
	var a := deg_to_rad(s.hdg)
	for k in range(0, 10, 2):
		var d0 := k * 200.0 * ppm
		var d1 := (k + 1) * 200.0 * ppm
		ci.draw_line(c + Vector2(sin(a), -cos(a)) * d0, c + Vector2(sin(a), -cos(a)) * d1, Color(0.16, 0.31, 0.43), 1.0)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(sin(a), -cos(a)) * 10.0, c + Vector2(sin(a + 2.6), -cos(a + 2.6)) * 7.0,
		c + Vector2(sin(a - 2.6), -cos(a - 2.6)) * 7.0]), Color(0.09, 0.27, 0.39))
	var sol = w.solution()
	if sol != null:
		var b := deg_to_rad(float(sol["hdg"]))
		ci.draw_line(c, c + Vector2(sin(b), -cos(b)) * float(sol["run"]) * ppm, Color(0.16, 0.47, 0.24), 1.0)
	# Where fire control puts the locked target, and how sure it is.
	var est: Array = w.fire_control_estimate()
	if not est.is_empty():
		var P: Vector2 = W.call(est[0])
		ci.draw_arc(P, maxf(float(est[2]) * ppm, 4.0), 0, TAU, 32, RED_INK, 1.0)
		ci.draw_circle(P, 3.0, RED_INK)
		text(ci, "FC", P + Vector2(8, 4), 11, RED_INK)
	text(ci, "N", Vector2(rect.end.x - 16, rect.position.y + 14), 15, CHART_INK, HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, "radius %d km   grid %d km   dashed ring: torpedo range" % [int(radius / 1000.0), int(g / 1000.0)],
		Vector2(rect.position.x + 8, rect.end.y - 12), 12, Color(0.35, 0.36, 0.33))


# --------------------------------------------------------------- dials
static func _bezel(ci: CanvasItem, c: Vector2, R: float) -> void:
	ci.draw_circle(c + Vector2(0, 3), R + 1, Color(0.03, 0.03, 0.03))
	ci.draw_circle(c, R, BRASS_LO)
	ci.draw_circle(c, R - 2, BRASS)
	ci.draw_circle(c, R - 6, BRASS_LO)
	ci.draw_circle(c, R - 8, DIAL)


static func draw_dial(ci: CanvasItem, c: Vector2, R: float, value: float, vmin: float, vmax: float, label: String,
		readout: String, major: float, minor: float, red_from := -1.0, order := -1.0) -> void:
	_bezel(ci, c, R)
	var Rf := R - 8
	var a0 := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	var ang := func(v: float) -> float: return a0 + (clampf(v, vmin, vmax) - vmin) / (vmax - vmin) * sweep
	if red_from >= 0.0:
		ci.draw_arc(c, Rf - 7, ang.call(red_from), ang.call(vmax), 24, Color(0.77, 0.24, 0.16), 8.0)
	var v := vmin
	var fs := maxi(10, int(R * 0.13))
	while v <= vmax + 0.001:
		var a: float = ang.call(v)
		var is_major := absf(fmod(v - vmin, major)) < 0.001 or absf(fmod(v - vmin, major) - major) < 0.001
		var r0 := Rf - (R * 0.16 if is_major else R * 0.09)
		ci.draw_line(c + Vector2(cos(a), sin(a)) * r0, c + Vector2(cos(a), sin(a)) * (Rf - 3), INK, 2.0 if is_major else 1.0)
		if is_major:
			text(ci, "%d" % int(v), c + Vector2(cos(a), sin(a)) * (Rf - R * 0.3), fs, INK, HORIZONTAL_ALIGNMENT_CENTER)
		v += minor
	text(ci, label, c + Vector2(0, R * 0.22), maxi(9, int(R * 0.11)), Color(0.43, 0.38, 0.29), HORIZONTAL_ALIGNMENT_CENTER)
	if order >= 0.0:
		var a: float = ang.call(order)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(cos(a), sin(a)) * (Rf - 2),
			c + Vector2(cos(a - 0.08), sin(a - 0.08)) * (Rf + 6), c + Vector2(cos(a + 0.08), sin(a + 0.08)) * (Rf + 6)]), Color(0.16, 0.43, 0.27))
	var box := Rect2(c + Vector2(-R * 0.36, R * 0.5), Vector2(R * 0.72, R * 0.26))
	ci.draw_rect(box, Color(0.09, 0.09, 0.07))
	text(ci, readout, box.get_center(), maxi(10, int(R * 0.16)), AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	var av: float = ang.call(value)
	var tip := c + Vector2(cos(av), sin(av)) * (Rf - 6)
	var tail := c - Vector2(cos(av), sin(av)) * R * 0.15
	var side := Vector2(cos(av + PI / 2), sin(av + PI / 2)) * maxf(2.0, R * 0.04)
	ci.draw_colored_polygon(PackedVector2Array([tip, tail + side, tail - side]), Color(0.09, 0.09, 0.08))
	ci.draw_circle(c, maxf(4.0, R * 0.07), BRASS)


static func draw_compass(ci: CanvasItem, c: Vector2, R: float, hdg: float, rudder: float) -> void:
	_bezel(ci, c, R)
	var Rf := R - 8
	var fs := maxi(10, int(R * 0.14))
	for d in range(0, 360, 5):
		var a := deg_to_rad(d - hdg - 90.0)
		var big := d % 30 == 0
		var r0 := Rf - (R * 0.17 if big else (R * 0.08 if d % 10 == 0 else R * 0.05))
		ci.draw_line(c + Vector2(cos(a), sin(a)) * r0, c + Vector2(cos(a), sin(a)) * (Rf - 2), INK, 2.0 if big else 1.0)
		if big:
			var lbl: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(d, str(d / 10))
			text(ci, lbl, c + Vector2(cos(a), sin(a)) * (Rf - R * 0.32), fs, Color(0.67, 0.16, 0.12) if d == 0 else INK, HORIZONTAL_ALIGNMENT_CENTER)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -Rf + 1), c + Vector2(-5, -Rf - 7), c + Vector2(5, -Rf - 7)]), Color(0.7, 0.2, 0.14))
	var ra := deg_to_rad(90.0 - rudder * 1.6)
	ci.draw_arc(c, R * 0.38, deg_to_rad(30), deg_to_rad(150), 16, Color(0.47, 0.42, 0.34), 1.0)
	ci.draw_line(c, c + Vector2(cos(ra), sin(ra)) * R * 0.38, Color(0.16, 0.43, 0.27), 3.0)
	ci.draw_circle(c, maxf(4.0, R * 0.07), BRASS)
	var box := Rect2(c + Vector2(-R * 0.3, -R * 0.42), Vector2(R * 0.6, R * 0.24))
	ci.draw_rect(box, Color(0.09, 0.09, 0.07))
	text(ci, U.p3(hdg), box.get_center(), maxi(10, int(R * 0.15)), AMBER, HORIZONTAL_ALIGNMENT_CENTER)


static func draw_gauges(ci: CanvasItem, rect: Rect2, w: World) -> void:
	ci.draw_rect(rect, Color(0.08, 0.09, 0.09))
	var s := w.sub
	var N := w.nat
	var R := minf(rect.size.x / 3.3, rect.size.y * 0.42) * 0.5 * 1.6
	var y := rect.position.y + R + 10
	var vmax := 150.0 if float(N["crush"]) <= 160.0 else 300.0
	draw_dial(ci, Vector2(rect.position.x + rect.size.x * 0.18, y), R, s.depth, 0.0, vmax, "DEPTH M", "%3.0f" % s.depth,
		25.0 if vmax <= 150.0 else 50.0, 5.0 if vmax <= 150.0 else 10.0, float(N["test"]), s.dep_ord)
	draw_dial(ci, Vector2(rect.position.x + rect.size.x * 0.5, y), R, absf(s.spd), 0.0, 25.0, "KNOTS" if s.spd >= -0.05 else "ASTERN",
		"%4.1f" % absf(s.spd), 5.0, 1.0)
	draw_compass(ci, Vector2(rect.position.x + rect.size.x * 0.82, y), R, s.hdg, s.rud)
	var by := y + R + 24
	var bw := rect.size.x * 0.27
	_bar(ci, Rect2(rect.position.x + rect.size.x * 0.04, by, bw, 26), s.hull / 100.0, "HULL", "%d%%" % int(s.hull),
		PHOS if s.hull > 60 else (AMBER if s.hull > 30 else ALARM))
	_bar(ci, Rect2(rect.position.x + rect.size.x * 0.365, by, bw, 26), s.bat / 100.0, "BATTERY", "%d%%" % int(s.bat),
		PHOS if s.bat > 25 else (AMBER if s.bat > 8 else ALARM))
	_bar(ci, Rect2(rect.position.x + rect.size.x * 0.69, by, bw, 26), s.air / 100.0, "AIR", "%d%%" % int(s.air),
		PHOS if s.air > 30 else AMBER)


static func _bar(ci: CanvasItem, r: Rect2, frac: float, label: String, value: String, col: Color) -> void:
	text(ci, label, r.position + Vector2(0, 6), 13, Color(0.6, 0.62, 0.58))
	text(ci, value, Vector2(r.end.x, r.position.y + 6), 13, col, HORIZONTAL_ALIGNMENT_RIGHT)
	var bar := Rect2(r.position + Vector2(0, 16), Vector2(r.size.x, 10))
	ci.draw_rect(bar, Color(0.04, 0.04, 0.04))
	ci.draw_rect(Rect2(bar.position + Vector2(1, 1), Vector2((bar.size.x - 2) * clampf(frac, 0.0, 1.0), bar.size.y - 2)), col)


# -------------------------------------------------------------- TDC
static func draw_tdc(ci: CanvasItem, rect: Rect2, w: World) -> void:
	if w.nat.get("nuclear", false):
		draw_fire_control(ci, rect, w)
		return
	ci.draw_rect(rect, Color(0.11, 0.12, 0.11))
	var s := w.sub
	var x := rect.position.x + 24
	var y := rect.position.y + 30
	text(ci, "TORPEDO DATA COMPUTER", Vector2(x, y), 20, BRASS)
	y += 34
	var tl := w.lock
	var sol = w.solution()
	if tl != null and tl.alive():
		var r := s.pos.distance_to(tl.pos)
		var aob := U.adiff(U.brg(tl.pos, s.pos), tl.hdg)
		var rows := [["TARGET", tl.name], ["RANGE", "%d m" % int(r)], ["ANGLE ON BOW", "%d %s" % [int(absf(aob)), "STBD" if aob > 0 else "PORT"]],
			["TARGET SPEED", "%d kn" % int(round(tl.spd))], ["SOLUTION", "%d%%" % int((sol["q"] if sol != null else 0.0) * 100.0)]]
		if sol != null:
			rows.append(["GYRO ANGLE", "%d %s" % [int(absf(sol["gyro"])), "R" if sol["gyro"] >= 0 else "L"]])
			rows.append(["RUN / TIME", "%d m / %d s" % [int(sol["run"]), int(sol["t"])]])
			rows.append(["STATUS", "IN RANGE" if sol["in_range"] else "OUT OF RANGE"])
		for row in rows:
			text(ci, row[0], Vector2(x, y), 15, Color(0.6, 0.62, 0.58))
			text(ci, str(row[1]), Vector2(x + 210, y), 16, AMBER)
			y += 26
	else:
		text(ci, "No target locked. Use the periscope and press L.", Vector2(x, y), 15, Color(0.6, 0.62, 0.58))
		y += 26
	y += 16
	text(ci, "RUNNING DEPTH  %d m      ( [ and ] to change )" % int(s.torp_depth), Vector2(x, y), 15, PHOS)
	y += 26
	if tl != null and tl.alive():
		var ok: bool = s.torp_depth <= tl.draft + 1.5
		text(ci, "Target draft about %d m: %s" % [int(tl.draft), "will hit" if ok else "TOO DEEP, will run under"], Vector2(x, y), 14,
			PHOS if ok else ALARM)
		y += 26
	y += 10
	text(ci, "TUBES", Vector2(x, y), 15, Color(0.6, 0.62, 0.58))
	y += 22
	for i in s.tubes.size():
		var v: float = s.tubes[i]
		var col := Color(0.3, 0.6, 0.35) if v == 0.0 else (Color(0.5, 0.38, 0.15) if v > 0.0 else Color(0.2, 0.2, 0.2))
		var r := Rect2(x + i * 46, y, 40, 40)
		ci.draw_rect(r, col)
		if v > 0.0:
			ci.draw_rect(Rect2(r.position + Vector2(0, 40 * (v / World.RELOAD)), Vector2(40, 40 * (1.0 - v / World.RELOAD))), Color(0.75, 0.55, 0.2))
		text(ci, str(i + 1), r.get_center(), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, "%d spare torpedoes" % s.spares, Vector2(x + s.tubes.size() * 46 + 12, y + 20), 14, Color(0.6, 0.62, 0.58))


## The near-future boats' fire control: the solution from sonar or the mast,
## and every Mk 48 in the water with its wire and seeker.
static func draw_fire_control(ci: CanvasItem, rect: Rect2, w: World) -> void:
	ci.draw_rect(rect, Color(0.06, 0.08, 0.09))
	var s := w.sub
	var x := rect.position.x + 24
	var y := rect.position.y + 30
	var cyan := Color(0.45, 0.85, 0.9)
	var grey := Color(0.55, 0.6, 0.62)
	text(ci, "FIRE CONTROL   MK 48 ADCAP", Vector2(x, y), 20, cyan)
	y += 34
	var tl := w.lock
	var sol = w.solution()
	var est: Array = w.fire_control_estimate()
	if tl != null and tl.alive() and not est.is_empty():
		var r: float = s.pos.distance_to(est[0])
		var rows := [["TRACK", tl.name], ["BEARING", U.p3(U.brg(s.pos, tl.pos))],
			["RANGE (EST)", "%.1f km  +/- %.1f" % [r / 1000.0, float(est[2]) / 1000.0]],
			["SOLUTION", "%d%%" % int((sol["q"] if sol != null else 0.0) * 100.0)]]
		if sol != null:
			rows.append(["FIRING COURSE", U.p3(sol["hdg"])])
			rows.append(["RUN / TIME", "%.1f km / %d:%02d" % [float(sol["run"]) / 1000.0, int(sol["t"]) / 60, int(sol["t"]) % 60]])
			rows.append(["STATUS", "IN RANGE" if sol["in_range"] else "OUT OF RANGE"])
		for row in rows:
			text(ci, row[0], Vector2(x, y), 15, grey)
			text(ci, str(row[1]), Vector2(x + 210, y), 16, AMBER)
			y += 26
	else:
		text(ci, "No track. Press L to track the strongest sonar contact,", Vector2(x, y), 15, grey)
		y += 22
		text(ci, "or lock one through the photonics mast.", Vector2(x, y), 15, grey)
		y += 26
	y += 14
	text(ci, "UNITS IN THE WATER", Vector2(x, y), 15, grey)
	y += 24
	if w.torps.is_empty():
		text(ci, "none", Vector2(x, y), 15, Color(0.4, 0.45, 0.46))
		y += 24
	for tp in w.torps:
		var st: String = str(tp.get("state")).to_upper()
		var wired: bool = bool(tp.get("wire"))
		text(ci, "UNIT %d   %-8s %-5s  run %.1f km" % [int(tp.get("unit")), st, "WIRE" if wired else "CUT", tp.run / 1000.0],
			Vector2(x, y), 15, PHOS if st == "HOME" else AMBER)
		y += 22
	y += 12
	text(ci, "TUBES", Vector2(x, y), 15, grey)
	y += 22
	for i in s.tubes.size():
		var v: float = s.tubes[i]
		var col := Color(0.25, 0.55, 0.6) if v == 0.0 else (Color(0.5, 0.38, 0.15) if v > 0.0 else Color(0.2, 0.2, 0.2))
		var r := Rect2(x + i * 46, y, 40, 40)
		ci.draw_rect(r, col)
		if v > 0.0:
			ci.draw_rect(Rect2(r.position + Vector2(0, 40 * (v / World.RELOAD)), Vector2(40, 40 * (1.0 - v / World.RELOAD))), Color(0.75, 0.55, 0.2))
		text(ci, str(i + 1), r.get_center(), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, "%d Mk 48s in the racks   %d decoys" % [s.spares, s.decoys], Vector2(x + s.tubes.size() * 46 + 12, y + 20), 14, grey)
	y += 60
	text(ci, "Space: fire one   X: two, diverging   G: cut wires   N: decoy", Vector2(x, y), 13, Color(0.4, 0.45, 0.46))


# ------------------------------------------------------------- damage
static func draw_damage(ci: CanvasItem, rect: Rect2, w: World) -> void:
	ci.draw_rect(rect, Color(0.11, 0.12, 0.11))
	var s := w.sub
	var x := rect.position.x + 24
	var y := rect.position.y + 30
	text(ci, "DAMAGE CONTROL", Vector2(x, y), 20, BRASS)
	y += 34
	_bar(ci, Rect2(x, y, rect.size.x - 48, 26), s.hull / 100.0, "PRESSURE HULL", "%d%%" % int(s.hull),
		PHOS if s.hull > 60 else (AMBER if s.hull > 30 else ALARM))
	y += 40
	_bar(ci, Rect2(x, y, rect.size.x - 48, 26), s.water / 100.0, "WATER IN THE BOAT", "%d%%" % int(s.water),
		PHOS if s.water < 10 else (AMBER if s.water < 40 else ALARM))
	y += 40
	if s.leak > 0.01:
		text(ci, "LEAKS: crews working on them", Vector2(x, y), 14, AMBER)
		y += 24
	for k in World.SYSTEMS:
		var v: float = s.sys[k]
		_bar(ci, Rect2(x, y, rect.size.x - 48, 26), v / 100.0, World.SYS_NAMES[k].to_upper(),
			"OUT" if v <= 25.0 else "%d%%" % int(v), PHOS if v > 60 else (AMBER if v > 25 else ALARM))
		y += 36


static func draw_tree(ci: CanvasItem, rect: Rect2, w: World) -> void:
	ci.draw_rect(rect, Color(0.06, 0.06, 0.06))
	text(ci, "HULL OPENINGS", Vector2(rect.get_center().x, rect.position.y + 18), 15, Color(0.7, 0.7, 0.65), HORIZONTAL_ALIGNMENT_CENTER)
	var sealed := w.sub.flood >= 1.0
	var n := 10
	for i in n:
		var row := i / 2
		var col := i % 2
		var c := Vector2(rect.get_center().x + (col - 0.5) * rect.size.x * 0.4, rect.position.y + 50 + row * (rect.size.y - 70) / 5.0)
		var on := sealed or (w.sub.flood > float(i) / n and w.sub.dep_ord > 0.0)
		ci.draw_circle(c, rect.size.x * 0.07, Color(0.1, 0.8, 0.25) if on else Color(0.9, 0.12, 0.1))
	text(ci, "GREEN BOARD" if sealed else "RED: VENTS OR HATCHES OPEN", Vector2(rect.get_center().x, rect.end.y - 12), 13,
		Color(0.4, 0.85, 0.5) if sealed else ALARM, HORIZONTAL_ALIGNMENT_CENTER)
