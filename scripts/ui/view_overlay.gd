extends Control
## Lens masks and sights drawn over the 3D view: periscope reticle and
## bearing tape, binoculars, the deck gun's layer sight and the AA ring sight.

const Instruments := preload("res://scripts/ui/instruments.gd")
const Style := preload("res://scripts/ui/style.gd")
const U := preload("res://scripts/util.gd")
const World := preload("res://scripts/sim/world.gd")

var game
var flash := 0.0
var flash_col := Color(1, 1, 1)


func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 2.5)
	queue_redraw()


func _draw() -> void:
	if game == null or game.world == null:
		return
	var w: World = game.world
	var mode: String = game.mode
	var sz := size
	var c := sz * 0.5
	match mode:
		"periscope":
			_periscope(w, c, minf(sz.x, sz.y) * 0.47)
		"deck":
			if game.zoomed:
				_binoculars(c, sz)
			else:
				draw_circle(c, 2.0, Color(1, 1, 1, 0.5))
			_bridge_info(w, sz)
		"gun":
			_gun(w, c, sz)
		"aa":
			_aa(w, c, sz)
		"interior":
			draw_circle(c, 2.5, Color(1, 1, 1, 0.55))
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(flash_col.r, flash_col.g, flash_col.b, flash * 0.35))


func _mask_circle(c: Vector2, r: float, sz: Vector2) -> void:
	var big := sz.length()
	draw_arc(c, r + big * 0.5, 0, TAU, 96, Color(0.01, 0.012, 0.014), big)
	draw_arc(c, r + 3, 0, TAU, 96, Color(0, 0, 0), 8.0)


func _periscope(w: World, c: Vector2, r: float) -> void:
	var s := w.sub
	var fov: float = game.scope_fov()
	var view: float = game.view_brg()
	var ppd := (r * 2.0) / fov
	if game.scope_wash > 0.0:
		draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), Color(0.08, 0.22, 0.24, game.scope_wash * 0.85))
	var col := Color(0.05, 0.05, 0.05, 0.85) if w.tod == "day" else Color(0.55, 0.8, 0.65, 0.8)
	draw_line(c - Vector2(r, 0), c - Vector2(14, 0), col, 1.5)
	draw_line(c + Vector2(14, 0), c + Vector2(r, 0), col, 1.5)
	draw_line(c - Vector2(0, r), c - Vector2(0, 14), col, 1.5)
	draw_line(c + Vector2(0, 14), c + Vector2(0, r * 0.55), col, 1.5)
	var unit := 1 if s.zoom else 2
	var span := int(fov / 2.0) + 1
	for d in range(-span, span + 1):
		if d % unit != 0:
			continue
		var x := c.x + d * ppd
		var big := d % (unit * 5) == 0
		var ln := 9.0 if big else 5.0
		draw_line(Vector2(x, c.y - ln), Vector2(x, c.y + ln), col, 1.0)
	for i in range(1, 7):
		var y := c.y + i * 14.0
		draw_line(Vector2(c.x - 4, y), Vector2(c.x + 4, y), col, 1.0)
	var ty := c.y - r * 0.8
	var stepd := 2 if s.zoom else 10
	var d0 := int(floor((view - fov / 2.0) / stepd)) * stepd
	var dd := d0
	while dd <= view + fov / 2.0 + stepd:
		var x := c.x + U.adiff(dd, view) * ppd
		if absf(x - c.x) < r * 0.9:
			draw_line(Vector2(x, ty), Vector2(x, ty + 8), col, 1.0)
			Instruments.text(self, U.p3(dd), Vector2(x, ty - 10), 13, col, HORIZONTAL_ALIGNMENT_CENTER)
		dd += stepd
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - 6, ty + 18), Vector2(c.x + 6, ty + 18), Vector2(c.x, ty + 10)]), Style.AMBER)
	# Lock bracket on the target.
	var cam: Camera3D = game.world_cam
	if w.lock != null and w.lock.alive():
		var p := Vector3(w.lock.pos.x, 10.0, -w.lock.pos.y)
		if not cam.is_position_behind(p):
			var sp := cam.unproject_position(p) - get_global_rect().position + get_global_rect().position
			var half := clampf(w.lock.length / w.sub.pos.distance_to(w.lock.pos) * 57.3 * ppd * 0.5, 12.0, r * 0.6)
			var br := Rect2(sp - Vector2(half, half * 0.5), Vector2(half * 2, half))
			_bracket(br, Style.AMBER)
	_mask_circle(c, r, size)
	# Data strip under the lens.
	var lines := []
	lines.append(["SCOPE  TRUE %s  REL %s  %s  %s" % [U.p3(view), U.p3(s.scope_rel), "x6 HIGH" if s.zoom else "x1.5 LOW",
		"ELEV %+d" % int(s.scope_elev) if absf(s.scope_elev) > 1.0 else ""], Style.TEXT])
	_target_lines(w, lines)
	var y := c.y + r * 0.86 - lines.size() * 20
	for ln in lines:
		var f := Instruments.font()
		var wd := f.get_string_size(ln[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_rect(Rect2(Vector2(c.x - wd * 0.5 - 8, y - 11), Vector2(wd + 16, 22)), Color(0, 0, 0, 0.5))
		Instruments.text(self, ln[0], Vector2(c.x, y), 15, ln[1], HORIZONTAL_ALIGNMENT_CENTER)
		y += 22
	if game.scope_wash > 0.6:
		Instruments.text(self, "WASHED OVER", c + Vector2(0, -40), 22, Color(0.7, 0.9, 0.9), HORIZONTAL_ALIGNMENT_CENTER)


func _target_lines(w: World, lines: Array) -> void:
	var s := w.sub
	if w.lock == null or not w.lock.alive():
		lines.append(["L or click: lock a ship on the TDC", Style.MUTED])
		return
	var tg := w.lock
	var r := s.pos.distance_to(tg.pos)
	var aob := U.adiff(U.brg(tg.pos, s.pos), tg.hdg)
	var sol = w.solution()
	var q := int((sol["q"] if sol != null else 0.0) * 100.0)
	lines.append(["TGT %s  RNG %d m  AOB %d %s  SPD %d kn  SOLN %d%%" % [tg.short.to_upper(), int(r), int(absf(aob)),
		"STBD" if aob > 0 else "PORT", int(round(tg.spd)), q], Style.AMBER])
	if sol != null:
		var g: float = sol["gyro"]
		var ok: bool = sol["in_range"] and absf(g) <= 90.0 and sol["run"] > World.ARM_DIST
		var msg := "READY" if ok else ("OUT OF RANGE" if not sol["in_range"] else ("GYRO > 90" if absf(g) > 90.0 else "TOO CLOSE TO ARM"))
		var deep: bool = s.torp_depth > tg.draft + 1.5
		if deep:
			msg += "  DEPTH TOO DEEP"
		lines.append(["GYRO %d %s  RUN %d m  TIME %d s  DEPTH %d m  %s" % [int(absf(g)), "R" if g >= 0 else "L", int(sol["run"]),
			int(sol["t"]), int(s.torp_depth), msg], Style.GOOD if ok and not deep else Style.ALARM])
	else:
		lines.append(["NO SOLUTION: she's too fast to catch from here", Style.ALARM])


func _bracket(r: Rect2, col: Color) -> void:
	var a := 10.0
	for corner in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)],
			[Vector2(r.position.x, r.end.y), Vector2(1, -1)], [r.end, Vector2(-1, -1)]]:
		var p: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		draw_line(p, p + Vector2(a * d.x, 0), col, 2.0)
		draw_line(p, p + Vector2(0, a * d.y), col, 2.0)


func _binoculars(c: Vector2, sz: Vector2) -> void:
	var r := minf(sz.x, sz.y) * 0.36
	var off := r * 0.62
	var big := sz.length()
	# Mask everything outside two overlapping circles.
	var img_rect := Rect2(Vector2.ZERO, sz)
	for y in range(0, int(sz.y), 4):
		var segs := []
		for cx in [c.x - off, c.x + off]:
			var dy := absf(y - c.y)
			if dy < r:
				var hw := sqrt(r * r - dy * dy)
				segs.append([cx - hw, cx + hw])
		if segs.is_empty():
			draw_rect(Rect2(0, y, sz.x, 4), Color.BLACK)
			continue
		var lo: float = segs[0][0]
		var hi: float = segs[-1][1]
		if segs.size() == 2 and segs[0][1] < segs[1][0]:
			draw_rect(Rect2(segs[0][1], y, segs[1][0] - segs[0][1], 4), Color.BLACK)
		draw_rect(Rect2(0, y, lo, 4), Color.BLACK)
		draw_rect(Rect2(hi, y, sz.x - hi, 4), Color.BLACK)
	draw_line(c - Vector2(30, 0), c + Vector2(30, 0), Color(0, 0, 0, 0.6), 1.0)
	draw_line(c - Vector2(0, 12), c + Vector2(0, 12), Color(0, 0, 0, 0.6), 1.0)


func _bridge_info(w: World, sz: Vector2) -> void:
	var lines := ["ON DECK  looking %s" % U.p3(game.view_brg()), "WASD walk   E use   RMB binoculars   L lock   Space fire torpedo   V outside view"]
	var y := sz.y - 70.0
	for ln in lines:
		Instruments.text(self, ln, Vector2(sz.x * 0.5, y), 15, Style.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		y += 22
	var tl := []
	_target_lines(w, tl)
	y = sz.y - 140.0
	for ln in tl:
		Instruments.text(self, ln[0], Vector2(sz.x * 0.5, y), 15, ln[1], HORIZONTAL_ALIGNMENT_CENTER)
		y += 22


func _gun(w: World, c: Vector2, sz: Vector2) -> void:
	var s := w.sub
	if game.zoomed:
		_mask_circle(c, minf(sz.x, sz.y) * 0.42, sz)
	var col := Color(0.1, 0.1, 0.1, 0.9) if w.tod == "day" else Color(0.6, 0.85, 0.7, 0.9)
	draw_arc(c, 30, 0, TAU, 32, col, 1.5)
	draw_line(c - Vector2(80, 0), c - Vector2(34, 0), col, 1.5)
	draw_line(c + Vector2(34, 0), c + Vector2(80, 0), col, 1.5)
	draw_line(c + Vector2(0, 34), c + Vector2(0, 90), col, 1.5)
	for i in range(1, 6):
		draw_line(c + Vector2(-6, 30 + i * 12), c + Vector2(6, 30 + i * 12), col, 1.0)
	var g: Dictionary = w.nat["gun"]
	var rng := U.range_for_elev(maxf(s.gun_elev, 0.0), float(g["v"]), float(g["cal"]))
	var st := w.gun_ready()
	var blocked := w.gun_blocked(s.gun_trav)
	var lines := [
		["%s   %d rounds" % [g["name"], s.gun_ammo], Style.TEXT],
		["TRAIN %s %s   ELEVATION %.1f   RANGE %d m" % [str(int(absf(s.gun_trav))), "R" if s.gun_trav >= 0 else "L", s.gun_elev, int(rng)], Style.AMBER],
		["BLOCKED BY CONNING TOWER" if blocked else st.to_upper(), Style.ALARM if (blocked or st != "ready") else Style.GOOD],
		["Mouse to aim   LMB fire   RMB sight   E or Esc to step away from the mount", Style.MUTED],
	]
	if w.lock != null and w.lock.alive():
		var r := s.pos.distance_to(w.lock.pos)
		lines.insert(2, ["Lookout: %s at about %d m" % [w.lock.short, int(snappedf(r * (1.0 + game.range_err), 50.0))], Style.TEXT])
	var y := sz.y - 30.0 - lines.size() * 22
	for ln in lines:
		Instruments.text(self, ln[0], Vector2(sz.x * 0.5, y), 16, ln[1], HORIZONTAL_ALIGNMENT_CENTER)
		y += 22


func _aa(w: World, c: Vector2, sz: Vector2) -> void:
	var col := Color(0.15, 0.15, 0.15, 0.9) if w.tod == "day" else Color(0.6, 0.85, 0.7, 0.9)
	draw_arc(c, 45, 0, TAU, 48, col, 1.5)
	draw_arc(c, 95, 0, TAU, 64, col, 1.5)
	draw_circle(c, 3, col)
	for a in [0.0, PI / 2, PI, PI * 1.5]:
		draw_line(c + Vector2(cos(a), sin(a)) * 95, c + Vector2(cos(a), sin(a)) * 120, col, 1.5)
	var st := "READY" if w.sub.surfaced() and w.sub.crew_ready <= 0.0 else ("MANNING" if w.sub.surfaced() else "SUBMERGED")
	var lines := [["%s   %s" % [w.nat["aa"]["name"], st], Style.TEXT],
		["Lead the aircraft: inner ring for slow planes, outer ring for fast ones", Style.MUTED],
		["Hold LMB to fire   E or Esc to step away from the mount", Style.MUTED]]
	var y := sz.y - 90.0
	for ln in lines:
		Instruments.text(self, ln[0], Vector2(sz.x * 0.5, y), 16, ln[1], HORIZONTAL_ALIGNMENT_CENTER)
		y += 22
