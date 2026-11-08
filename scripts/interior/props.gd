## Interior props drawn into a MeshKit in local space. Each function takes a
## Transform3D that places the prop; local +Z faces toward the viewer (the
## front of a panel, the face of a gauge or valve wheel), +Y is up.


static func _at(k, t: Transform3D) -> Transform3D:
	var old: Transform3D = k.xf
	k.xf = t
	return old


static func face(pos: Vector3, normal: Vector3, up := Vector3.UP) -> Transform3D:
	var n := normal.normalized()
	var u := up if absf(n.dot(up)) < 0.95 else Vector3.FORWARD
	var x := u.cross(n).normalized()
	var y := n.cross(x).normalized()
	return Transform3D(Basis(x, y, n), pos)


## Handwheel valve with stem and body. r is the wheel radius.
static func valve(k, t: Transform3D, r := 0.12, col := "red", spokes := 4, stem := 0.18) -> void:
	var old = _at(k, t)
	k.box("brass" if r < 0.1 else "steel", Vector3(0, 0, -stem - 0.04), Vector3(r * 0.9, r * 0.9, 0.08))
	k.cyl("steel", Vector3(0, 0, -stem), Vector3(0, 0, 0.02), 0.012 + r * 0.06, 0.012 + r * 0.06, 6)
	var segs := 14
	var tr := maxf(0.008, r * 0.12)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		k.cyl(col, Vector3(cos(a0) * r, sin(a0) * r, 0), Vector3(cos(a1) * r, sin(a1) * r, 0), tr, tr, 5, false)
	for i in spokes:
		var a := TAU * i / spokes + 0.3
		k.cyl(col, Vector3.ZERO, Vector3(cos(a) * r, sin(a) * r, 0), tr * 0.7, tr * 0.7, 4, false)
	k.cyl(col, Vector3(0, 0, -0.01), Vector3(0, 0, 0.03), r * 0.18, r * 0.18, 8)
	k.xf = old


## Round gauge with bezel, face and needle. Faces +Z.
static func gauge(k, t: Transform3D, r := 0.07, black := false, needle := -1.0) -> void:
	var old = _at(k, t)
	k.cyl("black" if black else "brass", Vector3(0, 0, -0.05), Vector3(0, 0, 0.012), r * 1.12, r * 1.08, 14)
	k.disc_uv("dial_black" if black else "dial", Vector3(0, 0, 0.014), Vector3(0, 0, 1), r, 16)
	var a := needle if needle >= 0.0 else randf_range(-2.0, 2.0)
	var tip := Vector3(sin(a), cos(a), 0) * r * 0.78
	k.cyl("red" if not black else "white", Vector3(0, 0, 0.018), tip + Vector3(0, 0, 0.018), r * 0.035, r * 0.015, 3, false)
	k.cyl("black", Vector3(0, 0, 0.012), Vector3(0, 0, 0.024), r * 0.08, r * 0.08, 6)
	k.xf = old


static func label(k, t: Transform3D, w := 0.14, h := 0.04) -> void:
	var old = _at(k, t)
	k.rect_uv("label", Vector3(0, 0, 0.004), Vector3(0, 0, 1), Vector3.UP, Vector2(w, h))
	k.xf = old


## Straight pipe with flanges.
static func pipe(k, a: Vector3, b: Vector3, r: float, mat := "steel", flange_every := 1.6) -> void:
	k.cyl(mat, a, b, r, r, 8, false)
	var L := a.distance_to(b)
	if flange_every <= 0.0 or L < 0.5:
		return
	var d := (b - a).normalized()
	var s := flange_every * 0.5
	while s < L:
		var p := a + d * s
		k.cyl(mat, p - d * 0.025, p + d * 0.025, r * 1.6, r * 1.6, 8)
		s += flange_every


## Pipe through a list of points, with rounded joints.
static func pipe_path(k, pts: Array, r: float, mat := "steel") -> void:
	for i in pts.size() - 1:
		pipe(k, pts[i], pts[i + 1], r, mat, 0.0)
	for i in range(1, pts.size() - 1):
		k.sphere(mat, pts[i], r * 1.15, 8, 4)


## Rectangular ventilation duct with flange rings.
static func duct(k, a: Vector3, b: Vector3, w: float, h: float) -> void:
	var d := b - a
	var L := d.length()
	var basis := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.9 else Vector3.RIGHT)
	k.box("paint", (a + b) * 0.5, Vector3(w, h, L), basis)
	var s := 0.6
	while s < L:
		k.box("steel", a + d.normalized() * s, Vector3(w + 0.04, h + 0.04, 0.04), basis)
		s += 1.2


## Caged incandescent lamp hanging from a ceiling point, pointing down.
static func lamp(k, pos: Vector3) -> void:
	k.cyl("steel", pos, pos + Vector3(0, -0.06, 0), 0.09, 0.09, 10)
	k.cyl("white", pos + Vector3(0, -0.06, 0), pos + Vector3(0, -0.14, 0), 0.07, 0.11, 10, false)
	k.sphere("lamp", pos + Vector3(0, -0.17, 0), 0.055, 8, 5)
	for i in 4:
		var a := TAU * i / 4.0
		var o := Vector3(cos(a), 0, sin(a)) * 0.1
		k.cyl("black", pos + Vector3(0, -0.12, 0) + o, pos + Vector3(0, -0.25, 0) + o * 0.5, 0.006, 0.006, 3, false)
	k.cyl("black", pos + Vector3(0, -0.25, 0), pos + Vector3(0, -0.24, 0), 0.06, 0.06, 6, false)


## Bunk: tube frame, mattress, rumpled blanket and pillow. Long axis along local Z.
static func bunk(k, t: Transform3D, length := 1.9, width := 0.62, blanket := "blanket0", made := true) -> void:
	var old = _at(k, t)
	var hl := length * 0.5
	var hw := width * 0.5
	for s in [-1.0, 1.0]:
		k.cyl("steel", Vector3(s * hw, 0, -hl), Vector3(s * hw, 0, hl), 0.018, 0.018, 6, false)
	for z in [-hl, hl]:
		k.cyl("steel", Vector3(-hw, 0, z), Vector3(hw, 0, z), 0.018, 0.018, 6, false)
	k.box("canvas", Vector3(0, -0.01, 0), Vector3(width - 0.04, 0.02, length - 0.04))
	k.box("mattress", Vector3(0, 0.06, 0), Vector3(width - 0.06, 0.1, length - 0.08))
	var bl := length * (0.62 if made else 0.5)
	var bz := hl - bl * 0.5 - 0.05
	k.hexa(blanket, [Vector3(-hw + 0.02, 0.1, bz - bl * 0.5), Vector3(hw - 0.02, 0.1, bz - bl * 0.5),
		Vector3(hw - 0.02, 0.1, bz + bl * 0.5), Vector3(-hw + 0.02, 0.1, bz + bl * 0.5),
		Vector3(-hw + 0.04, 0.16, bz - bl * 0.5 + 0.06), Vector3(hw - 0.06, 0.15 + randf() * 0.03, bz - bl * 0.5 + 0.03),
		Vector3(hw - 0.03, 0.15, bz + bl * 0.5), Vector3(-hw + 0.03, 0.14, bz + bl * 0.5)])
	if not made:
		k.sphere(blanket, Vector3(randf_range(-0.1, 0.1), 0.17, -0.1), 0.18, 8, 4, Vector3(1.2, 0.35, 1.0))
	k.sphere("mattress", Vector3(0, 0.15, -hl + 0.22), 0.16, 8, 4, Vector3(1.5, 0.45, 0.8))
	k.xf = old


## Steel locker or cabinet with doors, handles and louvres. Front faces +Z.
static func locker(k, t: Transform3D, w := 0.5, h := 1.6, d := 0.45, doors := 1, mat := "paint") -> void:
	var old = _at(k, t)
	k.box(mat, Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, d))
	var dw := w / doors
	for i in doors:
		var x := -w * 0.5 + dw * (i + 0.5)
		k.box("black", Vector3(x - dw * 0.5 + 0.005, h * 0.5, 0.002), Vector3(0.008, h - 0.06, 0.006))
		k.box("chrome", Vector3(x + dw * 0.3, h * 0.55, 0.02), Vector3(0.02, 0.12, 0.03))
		for j in 4:
			k.box("black", Vector3(x, h - 0.15 - j * 0.04, 0.003), Vector3(dw * 0.5, 0.012, 0.004))
		label(k, t * Transform3D(Basis.IDENTITY, Vector3(x, h - 0.4, 0.002)), dw * 0.5, 0.05)
	k.xf = old


static func table(k, t: Transform3D, w := 0.8, l := 1.6, h := 0.76, top := "linoleum") -> void:
	var old = _at(k, t)
	k.box(top, Vector3(0, h, 0), Vector3(w, 0.04, l))
	k.box("steel", Vector3(0, h - 0.04, 0), Vector3(w - 0.04, 0.05, l - 0.04))
	for x in [-w * 0.4, w * 0.4]:
		for z in [-l * 0.42, l * 0.42]:
			k.cyl("steel", Vector3(x, 0, z), Vector3(x, h - 0.05, z), 0.022, 0.022, 6)
	k.box("chrome", Vector3(0, h + 0.03, l * 0.5 - 0.01), Vector3(w, 0.02, 0.015))
	k.box("chrome", Vector3(0, h + 0.03, -l * 0.5 + 0.01), Vector3(w, 0.02, 0.015))
	k.xf = old


static func bench(k, t: Transform3D, l := 1.6, h := 0.45, w := 0.36) -> void:
	var old = _at(k, t)
	k.box("blanket1", Vector3(0, h, 0), Vector3(w, 0.08, l))
	k.box("wood", Vector3(0, h * 0.5, 0), Vector3(w, h - 0.05, l), Basis.IDENTITY)
	k.xf = old


static func stool(k, pos: Vector3, h := 0.55) -> void:
	k.cyl("steel", pos, pos + Vector3(0, h, 0), 0.025, 0.025, 6)
	k.cyl("steel", pos, pos + Vector3(0, 0.02, 0), 0.18, 0.18, 10)
	k.cyl("cloth", pos + Vector3(0, h, 0), pos + Vector3(0, h + 0.06, 0), 0.17, 0.17, 12)


## Vertical ladder from base to top, rungs every 0.3 m. Faces +Z.
static func ladder(k, t: Transform3D, h: float, w := 0.42) -> void:
	var old = _at(k, t)
	for s in [-1.0, 1.0]:
		k.cyl("steel", Vector3(s * w * 0.5, 0, 0), Vector3(s * w * 0.5, h, 0), 0.022, 0.022, 6)
	var y := 0.3
	while y < h:
		k.cyl("steel", Vector3(-w * 0.5, y, 0), Vector3(w * 0.5, y, 0), 0.016, 0.016, 5, false)
		y += 0.3
	k.xf = old


## Torpedo lying along local Z, nose toward -Z.
static func torpedo(k, t: Transform3D, length := 7.0, r := 0.27) -> void:
	var old = _at(k, t)
	var h := length * 0.5
	k.sphere("warhead", Vector3(0, 0, -h + r * 1.2), r, 12, 6, Vector3(1, 1, 1.5))
	k.cyl("warhead", Vector3(0, 0, -h + r * 1.2), Vector3(0, 0, -h + 1.5), r, r, 14, false)
	k.cyl("black", Vector3(0, 0, -h + 1.5), Vector3(0, 0, -h + 1.53), r * 1.01, r * 1.01, 14, false)
	k.cyl("torp", Vector3(0, 0, -h + 1.53), Vector3(0, 0, h - 1.2), r, r, 14, false)
	k.cyl("torp", Vector3(0, 0, h - 1.2), Vector3(0, 0, h - 0.25), r, r * 0.3, 14, false)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var dv := Vector3(cos(a), sin(a), 0)
		k.hexa("torp", [Vector3(0, 0, h - 0.75) + dv * r * 0.4, Vector3(0, 0, h - 0.75) + dv * r * 0.4 + Vector3(0, 0, 0.01),
			Vector3(0, 0, h - 0.2) + dv * r * 0.3 + Vector3(0, 0, 0.01), Vector3(0, 0, h - 0.2) + dv * r * 0.3,
			Vector3(0, 0, h - 0.55) + dv * r * 1.05, Vector3(0, 0, h - 0.55) + dv * r * 1.05 + Vector3(0, 0, 0.01),
			Vector3(0, 0, h - 0.25) + dv * r * 1.05 + Vector3(0, 0, 0.01), Vector3(0, 0, h - 0.25) + dv * r * 1.05])
	for zz in [h - 0.18, h - 0.06]:
		for i in 4:
			var a := TAU * i / 4.0 + (0.4 if zz > h - 0.1 else 0.0)
			k.box("brass", Vector3(cos(a), sin(a), 0) * r * 0.32 + Vector3(0, 0, zz), Vector3(0.05, 0.05, 0.03),
				Basis(Vector3(0, 0, 1), a))
	k.cyl("brass", Vector3(0, 0, h - 0.25), Vector3(0, 0, h), 0.04, 0.03, 6)
	k.box("brass", Vector3(0, r, -h + 2.6), Vector3(0.05, 0.05, 0.12))
	for zz in [-h + 2.0, h - 2.0]:
		k.cyl("dark", Vector3(0, 0, zz - 0.04), Vector3(0, 0, zz + 0.04), r * 1.03, r * 1.03, 14, false)
	k.xf = old


## Electrical or instrument panel with gauges, switches, lamps and labels. Faces +Z.
static func panel(k, t: Transform3D, w: float, h: float, d := 0.25, gauges := 4, switches := 6, mat := "dark") -> void:
	var old = _at(k, t)
	k.box(mat, Vector3(0, 0, -d * 0.5), Vector3(w, h, d))
	k.box("steel", Vector3(0, h * 0.5, -d * 0.5), Vector3(w + 0.02, 0.03, d + 0.02))
	k.box("steel", Vector3(0, -h * 0.5, -d * 0.5), Vector3(w + 0.02, 0.03, d + 0.02))
	k.xf = old
	var gx := maxi(1, mini(gauges, int(w / 0.2)))
	var rows := int(ceil(float(gauges) / gx))
	var gi := 0
	for r in rows:
		for c in gx:
			if gi >= gauges:
				break
			var x := -w * 0.5 + w * (c + 0.5) / gx
			var y := h * 0.5 - 0.14 - r * 0.2
			gauge(k, t * Transform3D(Basis.IDENTITY, Vector3(x, y, 0.0)), 0.065, randf() < 0.2)
			label(k, t * Transform3D(Basis.IDENTITY, Vector3(x, y - 0.1, 0.0)), 0.12, 0.025)
			gi += 1
	var sy := -h * 0.5 + 0.15
	for i in switches:
		var x := -w * 0.5 + w * (i + 0.5) / maxf(1.0, switches)
		_at(k, t)
		k.box("black", Vector3(x, sy, 0.01), Vector3(0.05, 0.07, 0.02))
		k.cyl("chrome", Vector3(x, sy, 0.02), Vector3(x, sy + 0.04, 0.06), 0.006, 0.006, 4)
		if i % 3 == 0:
			k.sphere(["led_red", "led_green", "led_amber"][i % 3], Vector3(x, sy + 0.09, 0.01), 0.012, 6, 3)
		k.xf = old


static func extinguisher(k, pos: Vector3) -> void:
	k.cyl("red", pos, pos + Vector3(0, 0.5, 0), 0.08, 0.08, 10)
	k.sphere("red", pos + Vector3(0, 0.5, 0), 0.08, 8, 4, Vector3(1, 0.5, 1))
	k.cyl("black", pos + Vector3(0, 0.54, 0), pos + Vector3(0, 0.6, 0), 0.025, 0.025, 6)
	k.cyl("black", pos + Vector3(0, 0.58, 0), pos + Vector3(0.12, 0.45, 0), 0.012, 0.012, 4, false)


## Sound-powered phone box with handset. Faces +Z.
static func phone(k, t: Transform3D) -> void:
	var old = _at(k, t)
	k.box("dark", Vector3(0, 0, -0.06), Vector3(0.2, 0.26, 0.12))
	k.box("black", Vector3(0.0, 0.05, 0.02), Vector3(0.06, 0.18, 0.05))
	k.cyl("black", Vector3(0, -0.13, 0), Vector3(0.05, -0.4, 0.04), 0.008, 0.008, 4, false)
	k.xf = old


static func crate(k, t: Transform3D, s := Vector3(0.6, 0.4, 0.4)) -> void:
	var old = _at(k, t)
	k.box("wood", Vector3(0, s.y * 0.5, 0), s)
	for y in [0.08, s.y - 0.08]:
		k.box("wood_lt", Vector3(0, y, 0), Vector3(s.x + 0.01, 0.06, s.z + 0.01))
	label(k, t * Transform3D(Basis.IDENTITY, Vector3(0, s.y * 0.5, s.z * 0.5)), s.x * 0.5, 0.08)
	k.xf = old


static func cans(k, base: Vector3, n := 6) -> void:
	for i in n:
		var p := base + Vector3((i % 3) * 0.11, (i / 6) * 0.14, ((i / 3) % 2) * 0.11)
		k.cyl("tin", p, p + Vector3(0, 0.13, 0), 0.05, 0.05, 8)
		k.cyl("red" if i % 2 == 0 else "blue", p + Vector3(0, 0.03, 0), p + Vector3(0, 0.1, 0), 0.051, 0.051, 8, false)


## Hanging food: sausages, hams, bread nets (a U-boat staple).
static func hanging_food(k, top: Vector3, n := 5) -> void:
	for i in n:
		var p := top + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.4, 0.4))
		var L := randf_range(0.2, 0.55)
		k.cyl("black", p, p + Vector3(0, -0.15, 0), 0.004, 0.004, 3, false)
		if i % 3 == 0:
			k.sphere("food", p + Vector3(0, -0.15 - L * 0.5, 0), 0.1, 8, 5, Vector3(1, L * 4.0, 1))
		else:
			k.cyl("food", p + Vector3(0, -0.15, 0), p + Vector3(0.03, -0.15 - L, 0), 0.03, 0.03, 6)


## Big handwheel used for the planes and helm. Built around the origin facing +Z.
static func handwheel(k, r: float, handles := 8) -> void:
	var segs := 20
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		k.cyl("brass", Vector3(cos(a0) * r, sin(a0) * r, 0), Vector3(cos(a1) * r, sin(a1) * r, 0), 0.022, 0.022, 6, false)
	for i in 6:
		var a := TAU * i / 6
		k.cyl("brass", Vector3.ZERO, Vector3(cos(a) * r, sin(a) * r, 0), 0.014, 0.012, 5, false)
	for i in handles:
		var a := TAU * i / handles
		k.cyl("wood", Vector3(cos(a) * r, sin(a) * r, 0), Vector3(cos(a) * (r + 0.1), sin(a) * (r + 0.1), 0), 0.018, 0.022, 6)
	k.cyl("brass", Vector3(0, 0, -0.03), Vector3(0, 0, 0.05), 0.05, 0.05, 10)
