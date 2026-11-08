class_name Interior
extends Node3D
## The inside of the boat: torpedo room, control room and engine room, with
## working stations, live instrument panels, moving controls, crew, lighting
## that goes red at night or after damage, leaks and rising bilge water.
##
## Local space: bow toward -Z, deck plates at y = 0. Everything here renders
## on visual layer 2 so the outside sun and sky never touch it.

const R := 2.55
const CY := 1.45
const Z_FWD := -21.0
const Z_AFT := 22.0
const BULK := [-8.0, 8.0]
const LAYER := 2

var nat: Dictionary
var world: World
var stations: Array = []
var panels: Array = []
var lights: Array = []
var lamp_mats: Array = []
var telegraph: Node3D
var helm_wheel: Node3D
var plane_wheels: Array = []
var torps_anim: Array = []
var engines: Array = []
var crew: Array = []
var leak_fx: Array = []
var water: MeshInstance3D
var red := false
var flicker := 0.0
var t := 0.0
var mats := {}


func build(nation: Dictionary) -> void:
	nat = nation
	var paint := Color(0.80, 0.80, 0.74)
	match nat["id"]:
		"us":
			paint = Color(0.82, 0.83, 0.78)
		"uk":
			paint = Color(0.70, 0.76, 0.70)
		"de":
			paint = Color(0.78, 0.76, 0.66)
		"jp":
			paint = Color(0.72, 0.74, 0.70)
	mats = {
		"paint": MeshKit.mat(paint, 0.85),
		"rib": MeshKit.mat(paint.darkened(0.12), 0.8),
		"floor": MeshKit.mat(Color(0.30, 0.31, 0.31), 0.55, 0.5),
		"steel": MeshKit.mat(Color(0.42, 0.44, 0.45), 0.5, 0.6),
		"dark": MeshKit.mat(Color(0.16, 0.17, 0.18), 0.6, 0.4),
		"brass": MeshKit.mat(Color(0.70, 0.56, 0.30), 0.3, 0.85),
		"red": MeshKit.mat(Color(0.62, 0.12, 0.10), 0.6),
		"green": MeshKit.mat(Color(0.20, 0.36, 0.26), 0.7),
		"white": MeshKit.mat(Color(0.86, 0.86, 0.83), 0.7),
		"wood": MeshKit.mat(Color(0.43, 0.30, 0.19), 0.8),
		"torp": MeshKit.mat(Color(0.50, 0.52, 0.48), 0.4, 0.7),
		"cloth": MeshKit.mat(Color(0.30, 0.33, 0.27), 0.95),
		"black": MeshKit.mat(Color(0.03, 0.03, 0.03), 0.9),
		"lamp": MeshKit.mat(Color(1.0, 0.95, 0.85), 0.5, 0.0, Color(1.0, 0.92, 0.78), 2.0),
	}
	lamp_mats.append(mats["lamp"])
	var k := MeshKit.new(mats)
	_hull(k)
	_pipes(k)
	_bulkheads(k)
	_control_room(k)
	_torpedo_room(k)
	_engine_room(k)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	add_child(mi)
	_collisions()
	_lights()
	_water()
	_crew()
	_set_layers(self)


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 1 << (LAYER - 1)
	if n is Light3D:
		(n as Light3D).light_cull_mask = 1 << (LAYER - 1)
	for c in n.get_children():
		_set_layers(c)


# ------------------------------------------------------------------ shell
func _hull(k: MeshKit) -> void:
	var theta0 := acos(CY / R)
	var segs := 30
	var z := Z_FWD
	var dz := 0.7
	while z < Z_AFT - 0.01:
		var z1 := minf(z + dz, Z_AFT)
		for i in segs:
			var a0 := lerpf(theta0, TAU - theta0, float(i) / segs)
			var a1 := lerpf(theta0, TAU - theta0, float(i + 1) / segs)
			var p0 := Vector3(R * sin(a0), CY - R * cos(a0), z)
			var p1 := Vector3(R * sin(a1), CY - R * cos(a1), z)
			var outside := Vector3(sin((a0 + a1) * 0.5), -cos((a0 + a1) * 0.5), 0) * R * 3.0 + Vector3(0, CY, (z + z1) * 0.5)
			k.quad("paint", p0, p1, Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1), outside)
		# Frame (rib).
		for i in segs:
			var a0 := lerpf(theta0, TAU - theta0, float(i) / segs)
			var a1 := lerpf(theta0, TAU - theta0, float(i + 1) / segs)
			var rr := R - 0.08
			var q0 := Vector3(rr * sin(a0), CY - rr * cos(a0), z)
			var q1 := Vector3(rr * sin(a1), CY - rr * cos(a1), z)
			var mid := (q0 + q1) * 0.5
			var b := Basis.looking_at((q1 - q0).normalized(), (Vector3(0, CY, z) - mid).normalized())
			k.box("rib", mid, Vector3(0.06, 0.16, (q1 - q0).length() + 0.02), b)
		z = z1
	var half := sqrt(R * R - CY * CY)
	k.box("floor", Vector3(0, -0.05, (Z_FWD + Z_AFT) * 0.5), Vector3(half * 2.0, 0.1, Z_AFT - Z_FWD))
	var zz := Z_FWD + 0.6
	while zz < Z_AFT:
		k.box("dark", Vector3(0, 0.005, zz), Vector3(half * 1.9, 0.01, 0.03))
		zz += 1.2
	# End caps.
	for ze in [Z_FWD, Z_AFT]:
		var poly := []
		for i in 24:
			var a := lerpf(theta0, TAU - theta0, float(i) / 23.0)
			poly.append(Vector2(R * sin(a), CY - R * cos(a)))
		var c := Vector3(0, CY, ze)
		for i in poly.size() - 1:
			var p0: Vector2 = poly[i]
			var p1: Vector2 = poly[i + 1]
			var dir := 1.0 if ze < 0 else -1.0
			k.tri("paint", c, Vector3(p0.x, p0.y, ze), Vector3(p1.x, p1.y, ze), Vector3(0, 0, dir))
		k.tri("paint", c, Vector3(poly[-1].x, poly[-1].y, ze), Vector3(poly[0].x, poly[0].y, ze), Vector3(0, 0, 1.0 if ze < 0 else -1.0))


func _pipes(k: MeshKit) -> void:
	var runs := [[-1.9, 2.95, 0.07, "red"], [-1.75, 3.2, 0.09, "white"], [-1.4, 3.55, 0.06, "green"], [1.5, 3.45, 0.08, "steel"],
		[1.8, 3.1, 0.06, "red"], [1.98, 2.6, 0.1, "white"], [0.4, 3.8, 0.05, "brass"], [-0.5, 3.82, 0.11, "steel"]]
	for r in runs:
		k.cyl(r[3], Vector3(r[0], r[1], Z_FWD + 0.2), Vector3(r[0], r[1], Z_AFT - 0.2), r[2], r[2], 8, false)
		var z := Z_FWD + 1.0
		while z < Z_AFT:
			k.cyl("steel", Vector3(r[0], r[1], z - 0.04), Vector3(r[0], r[1], z + 0.04), r[2] + 0.03, r[2] + 0.03, 8)
			z += 2.1
	# Cable trays.
	for s in [-1.0, 1.0]:
		k.box("dark", Vector3(s * 2.12, 2.2, (Z_FWD + Z_AFT) * 0.5), Vector3(0.05, 0.25, Z_AFT - Z_FWD - 0.4))


func _bulkheads(k: MeshKit) -> void:
	var theta0 := acos(CY / R)
	for zb in BULK:
		var poly := []
		for i in 32:
			var a := lerpf(theta0, TAU - theta0, float(i) / 31.0)
			poly.append(Vector2(R * sin(a), CY - R * cos(a)))
		# A plate with an oval door: fill the ring between the hull and the door outline.
		var door := []
		for i in 32:
			var a := TAU * float(i) / 32.0
			door.append(Vector2(sin(a) * 0.48, 1.12 - cos(a) * 0.85))
		for side in [-0.06, 0.06]:
			var z: float = zb + side
			for i in 32:
				var j := (i + 1) % 32
				var a0: Vector2 = _ring_pt(poly, door[i])
				var a1: Vector2 = _ring_pt(poly, door[j])
				k.quad("paint", Vector3(door[i].x, door[i].y, z), Vector3(door[j].x, door[j].y, z), Vector3(a1.x, a1.y, z),
					Vector3(a0.x, a0.y, z), Vector3(0, CY, z - side * 10.0))
		for i in 32:
			var j := (i + 1) % 32
			var d0: Vector2 = door[i]
			var d1: Vector2 = door[j]
			k.quad("steel", Vector3(d0.x, d0.y, zb - 0.07), Vector3(d1.x, d1.y, zb - 0.07), Vector3(d1.x, d1.y, zb + 0.07),
				Vector3(d0.x, d0.y, zb + 0.07), Vector3(0, 1.12, zb))
		# Open hatch door swung against the bulkhead, with its dogs.
		var hc := Vector3(0.95, 1.12, zb - 0.12)
		k.cyl("steel", hc, hc + Vector3(0, 0, -0.08), 0.5, 0.5, 18)
		k.cyl("brass", hc + Vector3(0, 0, -0.08), hc + Vector3(0, 0, -0.18), 0.12, 0.08, 10)
		for zz in [zb - 0.15, zb + 0.15]:
			k.box("brass", Vector3(-1.5, 2.0, zz), Vector3(0.25, 0.35, 0.03))


static func _ring_pt(poly: Array, d: Vector2) -> Vector2:
	# Project from the door centre outward until we hit the hull outline.
	var c := Vector2(0, 1.12)
	var dir := (d - c).normalized()
	var best := c + dir * 3.0
	for i in poly.size() - 1:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		var hit = Geometry2D.segment_intersects_segment(c, c + dir * 6.0, a, b)
		if hit != null:
			best = hit
			break
	if dir.y < -0.5:
		best = Vector2(best.x, maxf(best.y, 0.0))
	return best


# ----------------------------------------------------------- control room
func _control_room(k: MeshKit) -> void:
	# Periscope wells: attack scope forward, search scope aft.
	for pz in [-1.0, 0.6]:
		k.cyl("steel", Vector3(0, 0, pz), Vector3(0, 3.9, pz), 0.17, 0.17, 14)
		k.cyl("dark", Vector3(0, 0, pz), Vector3(0, 0.15, pz), 0.4, 0.4, 14)
	k.box("dark", Vector3(0, 1.62, -1.25), Vector3(0.35, 0.3, 0.3))
	k.cyl("black", Vector3(0, 1.62, -1.41), Vector3(0, 1.62, -1.47), 0.07, 0.09, 10)
	for s in [-1.0, 1.0]:
		k.cyl("dark", Vector3(s * 0.18, 1.55, -1.25), Vector3(s * 0.48, 1.55, -1.25), 0.035, 0.035, 6)
		k.cyl("black", Vector3(s * 0.48, 1.55, -1.25), Vector3(s * 0.48, 1.32, -1.25), 0.045, 0.045, 6)
	_station("scope", Vector3(0, 1.6, -1.6), "Use the attack periscope")
	# Ladder to the conning tower.
	for s in [-1.0, 1.0]:
		k.cyl("steel", Vector3(s * 0.25, 0, 2.2), Vector3(s * 0.25, 3.9, 2.2), 0.03, 0.03, 6)
	for i in 10:
		k.cyl("steel", Vector3(-0.25, 0.35 + i * 0.35, 2.2), Vector3(0.25, 0.35 + i * 0.35, 2.2), 0.02, 0.02, 4)
	k.cyl("dark", Vector3(0, 3.7, 2.2), Vector3(0, 3.9, 2.2), 0.45, 0.45, 16)
	_station("ladder", Vector3(0, 1.6, 2.2), "Climb to the bridge")
	# Helm, forward port: wheel, rudder indicator and telegraph.
	k.box("dark", Vector3(-1.35, 0.55, -6.6), Vector3(0.9, 1.1, 0.6))
	k.box("steel", Vector3(-1.35, 1.3, -6.85), Vector3(0.9, 0.5, 0.15))
	helm_wheel = _wheel(Vector3(-1.35, 1.25, -6.25), 0.32, Basis.IDENTITY)
	_station("helm", Vector3(-1.35, 1.3, -5.9), "Check the helm and compass")
	telegraph = Node3D.new()
	telegraph.position = Vector3(-0.55, 1.15, -6.5)
	add_child(telegraph)
	k.cyl("dark", Vector3(-0.55, 0, -6.5), Vector3(-0.55, 1.05, -6.5), 0.12, 0.09, 10)
	k.cyl("brass", Vector3(-0.55, 1.15, -6.62), Vector3(-0.55, 1.15, -6.38), 0.2, 0.2, 20)
	k.cyl("white", Vector3(-0.55, 1.15, -6.64), Vector3(-0.55, 1.15, -6.63), 0.17, 0.17, 20)
	var tk := MeshKit.new(mats)
	tk.box("brass", Vector3(0, 0.15, -0.16), Vector3(0.04, 0.32, 0.04))
	tk.sphere("black", Vector3(0, 0.32, -0.16), 0.04, 6, 4)
	var tm := MeshInstance3D.new()
	tm.mesh = tk.commit()
	telegraph.add_child(tm)
	# Diving station, forward starboard: bow and stern plane wheels under the depth gauges.
	k.box("dark", Vector3(1.45, 0.5, -6.3), Vector3(0.8, 1.0, 1.4))
	plane_wheels.append(_wheel(Vector3(1.05, 1.15, -6.7), 0.36, Basis(Vector3.UP, PI / 2)))
	plane_wheels.append(_wheel(Vector3(1.05, 1.15, -5.9), 0.36, Basis(Vector3.UP, PI / 2)))
	for z in [-6.7, -5.9]:
		k.box("dark", Vector3(0.6, 0.25, z), Vector3(0.4, 0.5, 0.4))
	_panel("depth", Vector3(1.98, 1.85, -6.3), Vector2(0.7, 0.7), Basis(Vector3.UP, -PI / 2), 320, 320)
	_station("dive", Vector3(1.1, 1.4, -6.3), "Check the diving station")
	_panel("tree", Vector3(2.02, 1.8, -4.5), Vector2(0.5, 0.75), Basis(Vector3.UP, -PI / 2), 200, 300)
	# Main gauge board on the forward bulkhead.
	_panel("gauges", Vector3(-1.2, 2.55, -7.88), Vector2(1.5, 0.95), Basis.IDENTITY, 600, 380)
	_panel("compass", Vector3(-1.35, 1.75, -6.92), Vector2(0.45, 0.45), Basis.IDENTITY, 256, 256)
	# Plot table, aft starboard.
	k.box("wood", Vector3(1.35, 0.92, 4.3), Vector3(1.1, 0.06, 1.5))
	k.box("dark", Vector3(1.35, 0.45, 4.3), Vector3(1.0, 0.9, 1.4))
	k.box("lamp", Vector3(1.35, 2.3, 4.3), Vector3(0.4, 0.06, 0.3))
	_panel("chart", Vector3(1.35, 0.96, 4.3), Vector2(1.0, 1.35), Basis(Vector3.RIGHT, -PI / 2), 420, 560)
	_station("chart", Vector3(1.35, 1.1, 4.3), "Study the plot table")
	# Hydrophone station, aft port.
	k.box("dark", Vector3(-1.75, 0.45, 4.6), Vector3(0.6, 0.9, 0.9))
	k.box("steel", Vector3(-1.95, 1.5, 4.6), Vector3(0.3, 1.1, 1.0))
	_panel("sonar", Vector3(-1.79, 1.55, 4.6), Vector2(0.8, 0.8), Basis(Vector3.UP, PI / 2), 400, 400)
	k.cyl("black", Vector3(-1.6, 0.98, 4.35), Vector3(-1.6, 1.0, 4.35), 0.09, 0.09, 10)
	_station("sonar", Vector3(-1.5, 1.4, 4.6), "Listen on the hydrophones")
	# Torpedo data computer on the aft bulkhead.
	k.box("steel", Vector3(-1.1, 1.5, 7.75), Vector3(1.1, 1.4, 0.4))
	_panel("tdc", Vector3(-1.1, 1.55, 7.53), Vector2(1.0, 0.95), Basis(Vector3.UP, PI), 480, 450)
	_station("tdc", Vector3(-1.1, 1.5, 7.0), "Work the torpedo data computer")
	# Damage control board.
	_panel("damage", Vector3(2.02, 1.7, 0.2), Vector2(0.9, 1.3), Basis(Vector3.UP, -PI / 2), 360, 520)
	_station("damage", Vector3(1.6, 1.5, 0.2), "Read the damage control board")
	# Ballast manifold valves along the port side.
	for i in 6:
		var z := -4.0 + i * 0.55
		k.cyl("steel", Vector3(-2.0, 1.4, z), Vector3(-1.85, 1.4, z), 0.05, 0.05, 6)
		k.cyl(["red", "green", "brass"][i % 3], Vector3(-1.85, 1.4, z), Vector3(-1.8, 1.4, z), 0.14, 0.14, 12)


func _wheel(c: Vector3, r: float, basis: Basis) -> Node3D:
	var n := Node3D.new()
	n.position = c
	n.basis = basis
	var k := MeshKit.new(mats)
	var segs := 16
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		k.cyl("brass", Vector3(cos(a0) * r, sin(a0) * r, 0), Vector3(cos(a1) * r, sin(a1) * r, 0), 0.025, 0.025, 6, false)
	for i in 6:
		var a := TAU * i / 6
		k.cyl("brass", Vector3.ZERO, Vector3(cos(a) * r, sin(a) * r, 0), 0.015, 0.015, 4, false)
		k.cyl("wood", Vector3(cos(a) * r, sin(a) * r, 0), Vector3(cos(a) * r * 1.25, sin(a) * r * 1.25, 0), 0.02, 0.02, 4)
	k.cyl("brass", Vector3(0, 0, -0.05), Vector3(0, 0, 0.05), 0.05, 0.05, 8)
	k.cyl("dark", Vector3(0, 0, 0.05), Vector3(0, 0, 0.35), 0.03, 0.03, 6)
	var m := MeshInstance3D.new()
	m.mesh = k.commit()
	n.add_child(m)
	add_child(n)
	return n


func _panel(kind: String, pos: Vector3, size: Vector2, basis: Basis, px: int, py: int) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, py)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var ins := Instruments.new()
	ins.kind = kind
	ins.size = Vector2(px, py)
	vp.add_child(ins)
	add_child(vp)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = vp.get_texture()
	m.emission_enabled = true
	m.emission_texture = vp.get_texture()
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.4
	q.material_override = m
	q.position = pos
	q.basis = basis
	add_child(q)
	var frame := MeshKit.new(mats)
	frame.box("dark", Vector3(0, 0, -0.03), Vector3(size.x + 0.08, size.y + 0.08, 0.04))
	var fm := MeshInstance3D.new()
	fm.mesh = frame.commit()
	q.add_child(fm)
	panels.append({"vp": vp, "ins": ins})


func _station(name: String, pos: Vector3, prompt: String) -> void:
	stations.append({"name": name, "pos": pos, "prompt": prompt})


# ---------------------------------------------------------- torpedo room
func _torpedo_room(k: MeshKit) -> void:
	var n: int = nat["tubes"]
	var zb := Z_FWD + 0.05
	for i in n:
		var col := i % 2
		var row := i / 2
		var x := (col - 0.5) * 0.95
		var y := 0.75 + row * 0.85
		k.cyl("brass", Vector3(x, y, zb), Vector3(x, y, zb + 0.18), 0.34, 0.34, 18)
		k.cyl("steel", Vector3(x, y, zb + 0.18), Vector3(x, y, zb + 0.25), 0.2, 0.2, 12)
		k.box("brass", Vector3(x + 0.33, y, zb + 0.2), Vector3(0.08, 0.18, 0.12))
		k.cyl("steel", Vector3(x, y, zb), Vector3(x, y, zb + 1.2), 0.3, 0.3, 14, false)
	_station("torpedo", Vector3(0, 1.4, Z_FWD + 1.8), "Check the torpedo tubes")
	# Reload racks with spare torpedoes; a few slide forward when tubes reload.
	for s in [-1.0, 1.0]:
		for lvl in 2:
			var y := 0.55 + lvl * 0.75
			var x: float = s * 1.45
			k.box("steel", Vector3(x, y - 0.3, -14.5), Vector3(0.7, 0.05, 11.0))
	for i in n:
		var s := -1.0 if i % 2 == 0 else 1.0
		var lvl := (i / 2) % 2
		var node := Node3D.new()
		node.position = Vector3(s * 1.45, 0.55 + lvl * 0.75, -12.0)
		var tk := MeshKit.new(mats)
		tk.cyl("torp", Vector3(0, 0, -3.3), Vector3(0, 0, 3.3), 0.27, 0.27, 12)
		tk.sphere("torp", Vector3(0, 0, -3.3), 0.27, 10, 4, Vector3(1, 1, 1.6))
		tk.cyl("torp", Vector3(0, 0, 3.3), Vector3(0, 0, 3.8), 0.27, 0.12, 12)
		tk.cyl("brass", Vector3(0, 0, 3.8), Vector3(0, 0, 3.9), 0.25, 0.25, 8)
		var tm := MeshInstance3D.new()
		tm.mesh = tk.commit()
		node.add_child(tm)
		add_child(node)
		torps_anim.append({"node": node, "home": node.position, "tube": i})
	# Bunks above the racks.
	for s in [-1.0, 1.0]:
		for z in [-17.5, -11.5]:
			k.box("cloth", Vector3(s * 1.55, 2.35, z), Vector3(0.7, 0.12, 2.0))
			k.box("steel", Vector3(s * 1.55, 2.28, z), Vector3(0.75, 0.04, 2.05))
	# Chain hoist rail.
	k.box("steel", Vector3(0, 3.45, -14.5), Vector3(0.12, 0.12, 12.0))


# ----------------------------------------------------------- engine room
func _engine_room(k: MeshKit) -> void:
	for s in [-1.0, 1.0]:
		var node := Node3D.new()
		node.position = Vector3(s * 1.25, 0, 15.0)
		var ek := MeshKit.new(mats)
		ek.box("green", Vector3(0, 0.55, 0), Vector3(1.1, 1.1, 9.0))
		ek.box("green", Vector3(0, 1.25, 0), Vector3(0.8, 0.3, 8.6))
		for i in 8:
			var z := -3.6 + i * 1.03
			ek.box("steel", Vector3(0, 1.5, z), Vector3(0.55, 0.22, 0.7))
			ek.cyl("brass", Vector3(-s * 0.45, 0.9, z), Vector3(-s * 0.58, 0.9, z), 0.06, 0.06, 6)
		ek.cyl("steel", Vector3(s * 0.4, 1.9, -4.5), Vector3(s * 0.4, 1.9, 4.5), 0.18, 0.18, 10, false)
		var m := MeshInstance3D.new()
		m.mesh = ek.commit()
		node.add_child(m)
		add_child(node)
		engines.append(node)
	k.box("dark", Vector3(0, 1.1, Z_AFT - 0.35), Vector3(1.6, 2.2, 0.5))
	for i in 5:
		k.cyl("white", Vector3(-0.6 + i * 0.3, 1.8, Z_AFT - 0.61), Vector3(-0.6 + i * 0.3, 1.8, Z_AFT - 0.62), 0.11, 0.11, 12)
	_station("engine", Vector3(0, 1.4, Z_AFT - 1.2), "Check the engine and motor gauges")


# ------------------------------------------------------------ collisions
func _collisions() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var half := sqrt(R * R - CY * CY)
	var L := Z_AFT - Z_FWD
	var zc := (Z_FWD + Z_AFT) * 0.5
	_box(body, Vector3(0, -0.15, zc), Vector3(6, 0.3, L + 2))
	_box(body, Vector3(0, 3.95, zc), Vector3(6, 0.3, L + 2))
	for s in [-1.0, 1.0]:
		_box(body, Vector3(s * (half + 0.15), 2.0, zc), Vector3(0.3, 4.0, L + 2))
		_box(body, Vector3(s * (half - 0.25), 0.4, zc), Vector3(0.3, 0.8, L))
	for ze in [Z_FWD - 0.15, Z_AFT + 0.15]:
		_box(body, Vector3(0, 2.0, ze), Vector3(6, 4, 0.3))
	for zb in BULK:
		_box(body, Vector3(-1.5, 2.0, zb), Vector3(2.0, 4.0, 0.2))
		_box(body, Vector3(1.5, 2.0, zb), Vector3(2.0, 4.0, 0.2))
		_box(body, Vector3(0, 3.0, zb), Vector3(1.2, 2.0, 0.2))
		_box(body, Vector3(0, 0.12, zb), Vector3(1.2, 0.24, 0.2))
	_box(body, Vector3(1.35, 0.5, 4.3), Vector3(1.1, 1.0, 1.5))
	_box(body, Vector3(-1.35, 0.55, -6.6), Vector3(0.9, 1.1, 0.6))
	_box(body, Vector3(1.45, 0.5, -6.3), Vector3(0.8, 1.0, 1.4))
	_box(body, Vector3(-1.75, 0.45, 4.6), Vector3(0.6, 0.9, 0.9))
	for pz in [-1.0, 0.6]:
		_box(body, Vector3(0, 2.0, pz), Vector3(0.36, 4.0, 0.36))
	for s in [-1.0, 1.0]:
		_box(body, Vector3(s * 1.25, 0.8, 15.0), Vector3(1.1, 1.6, 9.0))
		_box(body, Vector3(s * 1.45, 0.8, -14.5), Vector3(0.75, 1.6, 11.0))


func _box(body: StaticBody3D, c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = s
	cs.shape = b
	cs.position = c
	body.add_child(cs)


# ----------------------------------------------------------------- lights
func _lights() -> void:
	# Eight lights at most: the Compatibility renderer lights each mesh with up to eight.
	var z := Z_FWD + 2.7
	while z < Z_AFT:
		var l := OmniLight3D.new()
		l.position = Vector3(0, 3.3, z)
		l.omni_range = 7.5
		l.light_energy = 1.2
		l.light_color = Color(1.0, 0.94, 0.82)
		l.omni_attenuation = 1.2
		add_child(l)
		lights.append(l)
		var lk := MeshKit.new(mats)
		lk.cyl("lamp", Vector3(0, 3.6, z), Vector3(0, 3.45, z), 0.14, 0.18, 10)
		var lm := MeshInstance3D.new()
		lm.mesh = lk.commit()
		add_child(lm)
		z += 5.4


func _water() -> void:
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.4, Z_AFT - Z_FWD)
	water.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.15, 0.25, 0.28, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.3
	water.material_override = m
	water.position = Vector3(0, -0.2, (Z_FWD + Z_AFT) * 0.5)
	water.visible = false
	add_child(water)


# ------------------------------------------------------------------- crew
func _crew() -> void:
	var uniform := Color(0.55, 0.50, 0.38)
	match nat["id"]:
		"uk":
			uniform = Color(0.16, 0.18, 0.26)
		"de":
			uniform = Color(0.30, 0.28, 0.26)
		"jp":
			uniform = Color(0.48, 0.45, 0.33)
	var spots := [[Vector3(-1.35, 0, -5.85), 0.0, true], [Vector3(0.62, 0, -6.7), -PI / 2, true],
		[Vector3(0.62, 0, -5.9), -PI / 2, true], [Vector3(-1.45, 0, 4.4), PI / 2, true],
		[Vector3(0.8, 0, 4.0), PI / 2, false], [Vector3(0.6, 0, -16.0), PI, false], [Vector3(-0.5, 0, -18.5), 0.0, false],
		[Vector3(0.0, 0, 18.5), PI, false], [Vector3(0.2, 0, 11.0), 0.2, false]]
	for s in spots:
		var node := CrewBuilder.build(uniform, nat["id"], s[2])
		node.position = s[0]
		node.rotation.y = s[1]
		add_child(node)
		crew.append({"node": node, "base": s[0], "phase": randf() * TAU})


# ------------------------------------------------------------------ update
func set_world(w: World) -> void:
	world = w
	for p in panels:
		p["ins"].world = w
	red = w.tod == "night"


func set_active(on: bool) -> void:
	for p in panels:
		p["vp"].render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	visible = on


func spawn_leak() -> void:
	var p := CPUParticles3D.new()
	p.mesh = QuadMesh.new()
	var m := Fx._pmat(Color(0.75, 0.85, 0.9), false)
	p.material_override = m
	p.amount = 40
	p.lifetime = 1.0
	p.direction = Vector3(randf_range(-1, 1), -0.3, randf_range(-1, 1)).normalized()
	p.spread = 15.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.15
	p.color_ramp = Fx.ramp(Color(1, 1, 1, 0.8), Color(1, 1, 1, 0))
	var side := -1.0 if randf() < 0.5 else 1.0
	p.position = Vector3(side * 1.9, randf_range(2.0, 3.2), randf_range(-18.0, 20.0))
	add_child(p)
	_set_layers(p)
	leak_fx.append(p)
	flicker = 1.5


func update(dt: float) -> void:
	if world == null:
		return
	t += dt
	var s := world.sub
	telegraph.rotation.z = lerpf(1.1, -1.1, float(s.tel) / 7.0)
	helm_wheel.rotation.z = -deg_to_rad(s.rud) * 6.0
	var dd := s.dep_ord - s.depth
	for wv in plane_wheels:
		wv.rotation.x += clampf(dd, -1.0, 1.0) * dt * 2.0
	for ta in torps_anim:
		var i: int = ta["tube"]
		var node: Node3D = ta["node"]
		var v: float = s.tubes[i] if i < s.tubes.size() else 0.0
		if v > 0.0 and s.spares >= 0:
			var f := 1.0 - v / World.RELOAD
			var target := Vector3((i % 2 - 0.5) * 0.95, 0.75 + (i / 2) * 0.85, Z_FWD + 4.2)
			node.position = ta["home"].lerp(target, smoothstep(0.1, 0.95, f))
			node.visible = true
		else:
			node.position = ta["home"]
			node.visible = s.spares > i / 2
	var diesel := s.flood < 0.5
	for e in engines:
		e.position.y = (sin(t * 70.0) * 0.004) if diesel else 0.0
	var shake := world.shake
	for c in crew:
		var n: Node3D = c["node"]
		n.position = c["base"] + Vector3(sin(t * 0.7 + c["phase"]) * 0.01 + randf_range(-1, 1) * shake * 0.08, 0, randf_range(-1, 1) * shake * 0.08)
	# Lighting: red at night or in an emergency, flicker after hits.
	flicker = maxf(0.0, flicker - dt)
	if shake > 0.6:
		flicker = maxf(flicker, 0.8)
	var emergency := s.hull < 40.0 or s.water > 30.0
	var col := Color(1.0, 0.94, 0.82)
	if red or emergency:
		col = Color(1.0, 0.22, 0.15)
	var energy := 1.2 if not (red or emergency) else 1.0
	if flicker > 0.0 and randf() < 0.5:
		energy *= randf_range(0.0, 0.5)
	for l in lights:
		l.light_color = col
		l.light_energy = energy
	for m in lamp_mats:
		m.emission = col
		m.emission_energy_multiplier = 2.0 * energy
	# Leaks and bilge water.
	while leak_fx.size() < int(ceil(s.leak * 6.0)) and leak_fx.size() < 6:
		spawn_leak()
	if s.leak <= 0.01:
		for p in leak_fx:
			p.queue_free()
		leak_fx.clear()
	water.visible = s.water > 1.0
	water.position.y = -0.1 + s.water * 0.012
