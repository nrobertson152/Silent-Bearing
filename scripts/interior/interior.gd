extends Node3D
## The inside of the boat, bow to stern: forward torpedo room, officers'
## country with wardroom and radio room, control room, galley, mess and crew
## berthing, two engine rooms, maneuvering room and after torpedo room. Every
## bulkhead has a watertight door you can walk through. Instruments are live,
## controls move, the crew work their stations, the lights go red at night or
## in an emergency, and leaks spray and flood the deck.
##
## Local space: bow toward -Z, deck plates at y = 0. Everything renders on
## visual layer 2 so the outside sun and sky never reach it.

const MeshKit := preload("res://scripts/build/mesh_kit.gd")
const CrewBuilder := preload("res://scripts/build/crew_builder.gd")
const Fx := preload("res://scripts/view/fx.gd")
const Instruments := preload("res://scripts/ui/instruments.gd")
const World := preload("res://scripts/sim/world.gd")
const Tex := preload("res://scripts/interior/textures.gd")
const P := preload("res://scripts/interior/props.gd")

const R := 2.55
const CY := 1.45
const LAYER := 2
const DOOR_W := 0.42
const DOOR_H := 0.86
const DOOR_Y := 1.08
const COMPARTMENTS := [
	["Forward torpedo room", -36.0, -26.0, "ftr"],
	["Officers' country", -26.0, -17.0, "off"],
	["Control room", -17.0, -6.0, "ctl"],
	["Crew's mess and berthing", -6.0, 5.0, "crew"],
	["Forward engine room", 5.0, 14.0, "fer"],
	["After engine room", 14.0, 23.0, "aer"],
	["Maneuvering room", 23.0, 29.0, "man"],
	["After torpedo room", 29.0, 37.0, "atr"],
]
const SPAWN := Vector3(0.6, 0.05, -9.6)
const LADDER := Vector3(0.0, 0.05, -8.0)

var nat: Dictionary
var world
var mats: Dictionary
var stations: Array = []
var panels: Array = []
var lights: Array = []
var lamp_mats: Array = []
var solids: Array = []
var telegraphs: Array = []
var helm_wheel: Node3D
var plane_wheels: Array = []
var scope_head: Node3D
var torps_anim: Array = []
var rockers: Array = []
var engines: Array = []
var crew: Array = []
var leak_fx: Array = []
var water: MeshInstance3D
var red := false
var flicker := 0.0
var t := 0.0
var crew_i := 0


static func rad(z: float) -> float:
	if z < -30.0:
		return lerpf(2.0, R, clampf((z + 36.0) / 6.0, 0.0, 1.0))
	if z > 31.0:
		return lerpf(R, 1.95, clampf((z - 31.0) / 6.0, 0.0, 1.0))
	return R


static func hw(z: float) -> float:
	var r := rad(z)
	return sqrt(r * r - CY * CY)


static func compartment_at(z: float) -> String:
	for c in COMPARTMENTS:
		if z >= c[1] and z < c[2]:
			return c[0]
	return ""


func _shade(p: Vector3) -> Color:
	var f := lerpf(0.55, 1.0, smoothstep(0.0, 0.9, p.y))
	var r := rad(p.z)
	var d := Vector2(p.x, p.y - CY).length()
	f *= lerpf(0.82, 1.0, smoothstep(0.0, 0.45, r - d))
	if p.y > 3.2:
		f *= 0.85
	return Color(f, f, f)


func _kit() -> MeshKit:
	var k := MeshKit.new(mats)
	k.shade = _shade
	return k


func _solid(c: Vector3, s: Vector3) -> void:
	solids.append([c, s])


func _commit(k: MeshKit, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	parent.add_child(mi)
	return mi


func build(nation: Dictionary) -> void:
	nat = nation
	mats = Tex.materials(nat["id"])
	lamp_mats.append(mats["lamp"])
	for c in COMPARTMENTS:
		var k := _kit()
		var z0: float = c[1]
		var z1: float = c[2]
		_shell(k, z0, z1, c[3])
		match c[3]:
			"ftr":
				_ftr(k, z0, z1)
			"off":
				_officers(k, z0, z1)
			"ctl":
				_control(k, z0, z1)
			"crew":
				_crew_quarters(k, z0, z1)
			"fer", "aer":
				_engine_room(k, z0, z1, c[3] == "fer")
			"man":
				_maneuvering(k, z0, z1)
			"atr":
				_atr(k, z0, z1)
		_commit(k)
		_compartment_lights(z0, z1, c[3])
	var kb := _kit()
	for i in COMPARTMENTS.size() + 1:
		var z: float = COMPARTMENTS[i][1] if i < COMPARTMENTS.size() else COMPARTMENTS[-1][2]
		var end := i == 0 or i == COMPARTMENTS.size()
		_bulkhead(kb, z, end)
		if i > 0 and i < COMPARTMENTS.size():
			_door(kb, z, i)
	_commit(kb)
	_collisions()
	_water()
	_set_layers(self)


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 1 << (LAYER - 1)
	if n is Light3D:
		(n as Light3D).light_cull_mask = 1 << (LAYER - 1)
	for c in n.get_children():
		_set_layers(c)


# ------------------------------------------------------------------ shell
func _hull_pt(a: float, z: float, inset := 0.0) -> Vector3:
	var r := rad(z) - inset
	return Vector3(r * sin(a), CY - r * cos(a), z)


func _shell(k: MeshKit, z0: float, z1: float, kind: String) -> void:
	var segs := 36
	var step := 0.5
	var z := z0
	while z < z1 - 0.001:
		var za := z
		var zb := minf(z + step, z1)
		var ta := acos(CY / rad(za))
		var tb := acos(CY / rad(zb))
		for i in segs:
			var f0 := float(i) / segs
			var f1 := float(i + 1) / segs
			var a0 := _hull_pt(lerpf(ta, TAU - ta, f0), za)
			var a1 := _hull_pt(lerpf(ta, TAU - ta, f1), za)
			var b0 := _hull_pt(lerpf(tb, TAU - tb, f0), zb)
			var b1 := _hull_pt(lerpf(tb, TAU - tb, f1), zb)
			var mid := lerpf(ta, TAU - ta, (f0 + f1) * 0.5)
			var out := Vector3(sin(mid), -cos(mid), 0)
			k.quad_n("cork", a0, a1, b1, b0, -out, -out, -out, -out)
		z = zb
	# Frames: T-section ribs every 0.6 m.
	z = z0 + 0.3
	while z < z1 - 0.1:
		var th := acos(CY / rad(z))
		var n := 28
		for i in n:
			var a0 := lerpf(th, TAU - th, float(i) / n)
			var a1 := lerpf(th, TAU - th, float(i + 1) / n)
			var p0 := _hull_pt(a0, z, 0.0)
			var p1 := _hull_pt(a1, z, 0.0)
			var q0 := _hull_pt(a0, z, 0.12)
			var q1 := _hull_pt(a1, z, 0.12)
			k.quad("rib", p0, p1, q1, q0, Vector3(0, CY, z + 1.0))
			var f0 := _hull_pt(a0, z, 0.12)
			var f1 := _hull_pt(a1, z, 0.12)
			k.quad("rib", f0 + Vector3(0, 0, -0.04), f1 + Vector3(0, 0, -0.04), f1 + Vector3(0, 0, 0.04),
				f0 + Vector3(0, 0, 0.04), Vector3(0, CY, z))
		z += 0.6
	# Deck plates (tread plate, or grating down the engine room catwalk).
	var steps := int(ceil((z1 - z0) / 0.5))
	for i in steps:
		var za := z0 + (z1 - z0) * i / steps
		var zb := z0 + (z1 - z0) * (i + 1) / steps
		var wa := hw(za)
		var wb := hw(zb)
		var engine := kind == "fer" or kind == "aer"
		if engine:
			k.quad("grate", Vector3(-0.55, 0.0, za), Vector3(0.55, 0.0, za), Vector3(0.55, 0.0, zb), Vector3(-0.55, 0.0, zb), Vector3(0, -1, 0))
			for s in [-1.0, 1.0]:
				k.quad("floor", Vector3(s * 0.55, 0.0, za), Vector3(s * wa, 0.0, za), Vector3(s * wb, 0.0, zb), Vector3(s * 0.55, 0.0, zb), Vector3(0, -1, 0))
		else:
			k.quad("floor", Vector3(-wa, 0.0, za), Vector3(wa, 0.0, za), Vector3(wb, 0.0, zb), Vector3(-wb, 0.0, zb), Vector3(0, -1, 0))
	var zz := z0 + 1.2
	while zz < z1 - 0.2:
		k.box("black", Vector3(0, 0.003, zz), Vector3(hw(zz) * 2.0 - 0.1, 0.006, 0.02))
		zz += 1.2
	for s in [-1.0, 1.0]:
		k.box("black", Vector3(s * 0.55, 0.003, (z0 + z1) * 0.5), Vector3(0.02, 0.006, z1 - z0 - 0.1))
	# Overhead runs: pipes, conduit and a vent duct, the full length of the compartment.
	var zc := (z0 + z1) * 0.5
	var r := minf(rad(z0 + 0.3), rad(z1 - 0.3))
	var runs := [[-0.55, 0.06, "red"], [-0.42, 0.08, "paint"], [-0.32, 0.05, "green"], [-0.2, 0.035, "copper"],
		[0.2, 0.09, "paint"], [0.3, 0.05, "yellow"], [0.42, 0.04, "copper"], [0.55, 0.07, "blue"], [0.7, 0.05, "paint"],
		[-0.75, 0.045, "copper"], [0.85, 0.03, "black"], [-0.9, 0.03, "black"]]
	for run in runs:
		var a: float = PI + float(run[0])
		var pr: float = run[1]
		var p := _hull_pt(a, zc, 0.15 + pr)
		P.pipe(k, Vector3(p.x, p.y, z0 + 0.06), Vector3(p.x, p.y, z1 - 0.06), pr, run[2], 1.5)
		if absf(float(run[0])) < 0.6:
			var vz := z0 + 1.0 + fposmod(float(run[0]) * 13.0, 3.0)
			while vz < z1 - 0.8:
				var vp := _hull_pt(a, vz, 0.15 + pr * 2.0 + 0.12)
				P.valve(k, P.face(vp, (Vector3(0, CY, vz) - vp).normalized()), 0.07, "red" if run[2] == "red" else "brass", 4, 0.08)
				vz += 2.7
	var dp := _hull_pt(PI, zc, 0.55)
	P.duct(k, Vector3(0.0, dp.y, z0 + 0.1), Vector3(0.0, dp.y, z1 - 0.1), 0.38, 0.24)
	var gz := z0 + 1.6
	while gz < z1 - 1.0:
		k.box("black", Vector3(0, dp.y - 0.125, gz), Vector3(0.28, 0.01, 0.4))
		for i in 6:
			k.box("dark", Vector3(0, dp.y - 0.128, gz - 0.17 + i * 0.07), Vector3(0.26, 0.012, 0.015))
		gz += 3.2
	# Cable trays along both sides at shoulder height.
	for s in [-1.0, 1.0]:
		var cp := _hull_pt(PI * 0.5 if s > 0 else PI * 1.5, zc, 0.2)
		var cpy := CY + 0.9
		var cx: float = s * sqrt(maxf(r * r - 0.81, 0.0)) - s * 0.2
		k.box("steel", Vector3(cx, cpy, zc), Vector3(0.22, 0.02, z1 - z0 - 0.2))
		for j in 5:
			k.cyl("black", Vector3(cx - 0.08 + j * 0.04, cpy + 0.03, z0 + 0.1), Vector3(cx - 0.08 + j * 0.04, cpy + 0.03, z1 - 0.1), 0.016, 0.016, 5, false)
		var jz := z0 + 1.4
		while jz < z1 - 0.8:
			k.box("dark", Vector3(cx, cpy - 0.18, jz), Vector3(0.18, 0.24, 0.14))
			k.cyl("dark", Vector3(cx, cpy - 0.06, jz), Vector3(cx, cpy + 0.02, jz), 0.025, 0.025, 6)
			jz += 3.1


func _compartment_lights(z0: float, z1: float, kind: String) -> void:
	var n := 3 if z1 - z0 >= 9.0 else 2
	var k := _kit()
	for i in n:
		var z := lerpf(z0, z1, (i + 0.5) / n)
		var y := CY + rad(z) - 0.5
		P.lamp(k, Vector3(0.65 if i % 2 == 0 else -0.65, y + 0.12, z))
		var l := OmniLight3D.new()
		l.position = Vector3(0.65 if i % 2 == 0 else -0.65, y - 0.2, z)
		l.omni_range = 6.0
		l.omni_attenuation = 1.4
		l.light_energy = 1.4
		l.light_color = Color(1.0, 0.9, 0.74)
		l.light_specular = 0.4
		add_child(l)
		lights.append(l)
	_commit(k)


# --------------------------------------------------------------- bulkheads
func _door_pt(a: float) -> Vector2:
	return Vector2(sin(a) * DOOR_W, DOOR_Y - cos(a) * DOOR_H)


## Ray from the door centre through the door outline to the hull or deck.
func _edge_pt(z: float, dir: Vector2) -> Vector2:
	var c := Vector2(0, DOOR_Y)
	var o := c - Vector2(0, CY)
	var r := rad(z)
	var b := 2.0 * o.dot(dir)
	var cc := o.dot(o) - r * r
	var tt := (-b + sqrt(maxf(b * b - 4.0 * cc, 0.0))) * 0.5
	if dir.y < 0.0:
		tt = minf(tt, -c.y / dir.y)
	return c + dir * tt


func _bulkhead(k: MeshKit, z: float, end: bool) -> void:
	var n := 40
	for side in [-0.06, 0.06]:
		var zz: float = z + side
		if end:
			var c := Vector3(0, CY, zz)
			var th := acos(CY / rad(z))
			for i in n:
				var a0 := lerpf(th, TAU - th, float(i) / n)
				var a1 := lerpf(th, TAU - th, float(i + 1) / n)
				k.tri("paint", c, _hull_pt(a0, zz) * Vector3(1, 1, 0) + Vector3(0, 0, zz),
					_hull_pt(a1, zz) * Vector3(1, 1, 0) + Vector3(0, 0, zz), Vector3(0, 0, signf(side)))
			k.tri("paint", c, Vector3(-hw(z), 0, zz), Vector3(hw(z), 0, zz), Vector3(0, 0, signf(side)))
			continue
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var d0 := _door_pt(a0)
			var d1 := _door_pt(a1)
			var e0 := _edge_pt(z, (d0 - Vector2(0, DOOR_Y)).normalized())
			var e1 := _edge_pt(z, (d1 - Vector2(0, DOOR_Y)).normalized())
			k.quad("paint", Vector3(d0.x, d0.y, zz), Vector3(d1.x, d1.y, zz), Vector3(e1.x, e1.y, zz), Vector3(e0.x, e0.y, zz),
				Vector3(0, CY, z - side * 10.0))
	if end:
		return
	# Door frame (coaming) and the raised sill.
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := _door_pt(a0)
		var d1 := _door_pt(a1)
		var o0 := _door_pt(a0) + (_door_pt(a0) - Vector2(0, DOOR_Y)).normalized() * 0.09
		var o1 := _door_pt(a1) + (_door_pt(a1) - Vector2(0, DOOR_Y)).normalized() * 0.09
		k.quad("steel", Vector3(d0.x, d0.y, z - 0.1), Vector3(d1.x, d1.y, z - 0.1), Vector3(d1.x, d1.y, z + 0.1),
			Vector3(d0.x, d0.y, z + 0.1), Vector3(0, DOOR_Y, z))
		for s in [-0.1, 0.1]:
			k.quad("steel", Vector3(d0.x, d0.y, z + s), Vector3(d1.x, d1.y, z + s), Vector3(o1.x, o1.y, z + s),
				Vector3(o0.x, o0.y, z + s), Vector3(0, DOOR_Y, z))
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := _door_pt(a) + (_door_pt(a) - Vector2(0, DOOR_Y)).normalized() * 0.13
		for s in [-1.0, 1.0]:
			k.box("brass", Vector3(p.x, p.y, z + s * 0.12), Vector3(0.05, 0.05, 0.06))


func _door(k: MeshKit, z: float, i: int) -> void:
	# Door leaf swung open against the forward face, hinged on the port side.
	var hinge_x := -DOOR_W - 0.08
	var dz := z - 0.16
	var leaf := []
	for j in 24:
		var a := TAU * j / 24.0
		leaf.append(_door_pt(a) * 1.08)
	var c := Vector3(hinge_x - DOOR_W * 1.08, DOOR_Y, dz)
	for j in 24:
		var p0: Vector2 = leaf[j]
		var p1: Vector2 = leaf[(j + 1) % 24]
		var q0 := Vector3(hinge_x - DOOR_W * 1.08 + p0.x, p0.y, dz)
		var q1 := Vector3(hinge_x - DOOR_W * 1.08 + p1.x, p1.y, dz)
		for s in [-0.04, 0.04]:
			k.tri("paint", c + Vector3(0, 0, s), q0 + Vector3(0, 0, s), q1 + Vector3(0, 0, s), Vector3(0, 0, signf(s)))
		k.quad("steel", q0 + Vector3(0, 0, -0.04), q1 + Vector3(0, 0, -0.04), q1 + Vector3(0, 0, 0.04), q0 + Vector3(0, 0, 0.04), c)
	P.valve(k, P.face(c + Vector3(0, 0, -0.06), Vector3(0, 0, -1)), 0.14, "steel", 4, 0.04)
	for y in [DOOR_Y - 0.5, DOOR_Y + 0.5]:
		k.box("steel", Vector3(hinge_x - 0.02, y, z - 0.12), Vector3(0.12, 0.1, 0.1))
	# Fittings beside the door: compartment placard, gauge, phone, lamp.
	for s in [-1.0, 1.0]:
		var face_z: float = z + s * 0.065
		var nrm := Vector3(0, 0, s)
		P.label(k, P.face(Vector3(0.0, DOOR_Y + DOOR_H + 0.18, face_z), nrm), 0.36, 0.08)
		P.gauge(k, P.face(Vector3(0.82, 1.75, face_z), nrm), 0.07)
		P.phone(k, P.face(Vector3(-0.85, 1.45, face_z), nrm))
		P.valve(k, P.face(Vector3(0.75, 2.5, face_z), nrm), 0.11, "red", 5, 0.1)
		P.extinguisher(k, Vector3(1.2 * s, 0.0, face_z + s * 0.12))


# ----------------------------------------------------------------- stations
func _station(name: String, pos: Vector3, prompt: String) -> void:
	stations.append({"name": name, "pos": pos, "prompt": prompt})


func _panel(kind: String, pos: Vector3, size: Vector2, normal: Vector3, px: int, py: int) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, py)
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
	m.emission_energy_multiplier = 0.4
	m.roughness = 0.3
	q.material_override = m
	q.transform = P.face(pos, normal)
	add_child(q)
	var k := _kit()
	k.xf = q.transform
	k.box("dark", Vector3(0, 0, -0.04), Vector3(size.x + 0.1, size.y + 0.1, 0.06))
	k.box("steel", Vector3(0, size.y * 0.5 + 0.05, -0.01), Vector3(size.x + 0.12, 0.03, 0.03))
	_commit(k)
	panels.append({"vp": vp, "ins": ins})


func _man(pose: String, pos: Vector3, yaw: float, hands := {}) -> Node3D:
	var n := CrewBuilder.build(nat["id"], crew_i, pose, hands)
	crew_i += 1
	n.position = pos
	n.rotation.y = yaw
	add_child(n)
	var head: Node3D = n.get_node("Body/Head")
	crew.append({"node": n, "head": head, "base": pos, "phase": randf() * TAU, "look": 0.0, "next": randf_range(2, 8)})
	return n


func _wheel_node(pos: Vector3, normal: Vector3, r: float, axle := 0.4) -> Node3D:
	var n := Node3D.new()
	n.transform = P.face(pos, normal)
	add_child(n)
	var spin := Node3D.new()
	n.add_child(spin)
	var k := _kit()
	P.handwheel(k, r)
	_commit(k, spin)
	var ka := _kit()
	ka.cyl("steel", Vector3(0, 0, 0), Vector3(0, 0, -axle), 0.035, 0.035, 8)
	_commit(ka, n)
	return spin


# ------------------------------------------------------- forward torpedo room
func _ftr(k: MeshKit, z0: float, z1: float) -> void:
	var n: int = nat["tubes"]
	var rows := int(ceil(n / 2.0))
	var tube_pos := []
	for i in n:
		var col := i % 2
		var row := i / 2
		var y := (0.78 + row * 0.8) if rows == 3 else (0.95 + row * 0.9)
		tube_pos.append(Vector3((col - 0.5) * 1.0, y, z0))
	for i in n:
		var p: Vector3 = tube_pos[i]
		var front := p + Vector3(0, 0, 3.0)
		k.cyl("steel", p, front, 0.31, 0.31, 18, false)
		for bz in [0.8, 1.7, 2.6]:
			k.cyl("steel", p + Vector3(0, 0, bz), p + Vector3(0, 0, bz + 0.06), 0.34, 0.34, 18, false)
		k.cyl("brass", front, front + Vector3(0, 0, 0.1), 0.36, 0.36, 20)
		for j in 6:
			var a := TAU * j / 6.0
			k.box("brass", front + Vector3(cos(a) * 0.36, sin(a) * 0.36, 0.05), Vector3(0.07, 0.07, 0.1), Basis(Vector3(0, 0, 1), a))
		k.cyl("steel", front + Vector3(0, 0, 0.1), front + Vector3(0, 0, 0.2), 0.3, 0.27, 18)
		k.box("steel", front + Vector3(0.36, 0, 0.12), Vector3(0.12, 0.2, 0.14))
		k.cyl("chrome", front + Vector3(-0.12, 0.0, 0.21), front + Vector3(0.18, 0.0, 0.21), 0.018, 0.018, 6)
		P.label(k, P.face(front + Vector3(0, 0.12, 0.205), Vector3(0, 0, 1)), 0.12, 0.04)
		P.gauge(k, P.face(front + Vector3(0.0, -0.36, 0.0) + Vector3(0, 0, -0.4), Vector3(0, 0, 1)), 0.05)
		k.sphere("led_red" if i % 2 else "led_green", front + Vector3(-0.2, 0.2, 0.2), 0.02, 6, 3)
		_solid(Vector3(p.x, p.y, z0 + 1.6), Vector3(0.66, 0.66, 3.2))
	# Firing panel on the port side of the tubes.
	P.panel(k, P.face(Vector3(-1.35, 1.6, z0 + 0.12), Vector3(0, 0, 1)), 0.6, 0.7, 0.18, 4, 6)
	P.gauge(k, P.face(Vector3(1.25, 2.05, z0 + 0.1), Vector3(0, 0, 1)), 0.11)
	P.label(k, P.face(Vector3(1.25, 1.85, z0 + 0.1), Vector3(0, 0, 1)), 0.2, 0.05)
	# Reload racks with spare torpedoes, and hoist rail overhead.
	var rack := [Vector3(-1.45, 0.48, z1 - 3.8), Vector3(1.45, 0.48, z1 - 3.8), Vector3(-1.38, 1.25, z1 - 3.8), Vector3(1.38, 1.25, z1 - 3.8)]
	for rp in rack:
		for dz in [-2.6, 0.0, 2.6]:
			k.box("steel", rp + Vector3(0, -0.3, dz), Vector3(0.62, 0.05, 0.12))
			k.box("steel", rp + Vector3(0, -0.15, dz), Vector3(0.06, 0.3, 0.1))
	for s in [-1.0, 1.0]:
		_solid(Vector3(s * 1.5, 0.8, z1 - 3.8), Vector3(0.75, 1.6, 7.4))
	for i in n:
		var node := Node3D.new()
		var rp: Vector3 = rack[i % 4]
		node.position = rp
		var tk := _kit()
		P.torpedo(tk, Transform3D.IDENTITY, 6.9, 0.265)
		_commit(tk, node)
		add_child(node)
		var tp: Vector3 = tube_pos[i]
		torps_anim.append({"node": node, "home": rp, "tube": i, "target": Vector3(tp.x, tp.y, z0 + 3.6)})
	k.box("steel", Vector3(0, 3.45, (z0 + z1) * 0.5), Vector3(0.14, 0.2, z1 - z0 - 1.0))
	for tz in [z0 + 3.5, z1 - 3.0]:
		k.box("dark", Vector3(0, 3.28, tz), Vector3(0.3, 0.18, 0.4))
		for s in [-1.0, 1.0]:
			k.cyl("black", Vector3(s * 0.07, 3.2, tz), Vector3(s * 0.07, 1.7 + randf() * 0.4, tz + 0.1), 0.012, 0.012, 4, false)
		k.box("dark", Vector3(0.0, 1.9, tz + 0.05), Vector3(0.16, 0.22, 0.12))
	# Folding pipe bunks above the racks, two occupied.
	for s in [-1.0, 1.0]:
		for j in 2:
			var bz := z1 - 5.6 + j * 2.4
			P.bunk(k, Transform3D(Basis(Vector3(0, 0, 1), s * 0.15), Vector3(s * 1.45, 2.05, bz)), 1.9, 0.6, "blanket%d" % ((j + int(s > 0)) % 3), j == 0)
			k.cyl("black", Vector3(s * 1.15, 2.05, bz - 0.8), Vector3(s * 1.05, 3.3, bz - 0.8), 0.008, 0.008, 3, false)
			k.cyl("black", Vector3(s * 1.15, 2.05, bz + 0.8), Vector3(s * 1.05, 3.3, bz + 0.8), 0.008, 0.008, 3, false)
	_man("lie", Vector3(-1.45, 2.12, z1 - 3.2), 0.0)
	# Torpedo loading hatch trunk, slanting up through the hull.
	var hz := z1 - 1.6
	k.cyl("steel", Vector3(0, 3.3, hz), Vector3(0, 4.3, hz - 0.8), 0.42, 0.42, 16, false)
	k.cyl("steel", Vector3(0, 3.3, hz), Vector3(0, 3.36, hz), 0.5, 0.5, 16)
	P.valve(k, P.face(Vector3(0, 3.25, hz), Vector3(0, -1, 0)), 0.18, "steel", 5, 0.05)
	# Lockers and stores aft.
	P.locker(k, P.face(Vector3(-1.75, 0.0, z1 - 0.5), Vector3(1, 0, 0)), 0.6, 1.4, 0.4, 2)
	_solid(Vector3(-1.85, 0.7, z1 - 0.5), Vector3(0.45, 1.4, 0.65))
	for i in 3:
		P.crate(k, Transform3D(Basis.IDENTITY, Vector3(1.6, i * 0.4, z1 - 0.6)), Vector3(0.6, 0.38, 0.45))
	_solid(Vector3(1.6, 0.6, z1 - 0.6), Vector3(0.6, 1.2, 0.45))
	_man("work", Vector3(0.45, 0.0, z0 + 3.9), PI, {"r": Vector3(0.15, 1.2, -0.5), "l": Vector3(-0.2, 1.05, -0.45)})
	_man("stand", Vector3(-0.85, 0.0, z0 + 5.6), PI * 0.8)
	_station("torpedo", Vector3(0, 1.4, z0 + 4.0), "Check the torpedo tubes")


# ------------------------------------------------------------ officers' country
func _officers(k: MeshKit, z0: float, z1: float) -> void:
	# Port: three staterooms behind wood partitions with curtained doorways.
	var px := -0.55
	var cabins := [[z0 + 0.2, z0 + 3.1], [z0 + 3.1, z0 + 6.0], [z0 + 6.0, z1 - 0.2]]
	for ci in cabins.size():
		var ca: float = cabins[ci][0]
		var cb: float = cabins[ci][1]
		var door0 := cb - 0.9
		var door1 := cb - 0.2
		k.box("wood_lt", Vector3(px, 1.05, (ca + door0) * 0.5), Vector3(0.05, 2.1, door0 - ca))
		k.box("wood_lt", Vector3(px, 1.05, (door1 + cb) * 0.5), Vector3(0.05, 2.1, cb - door1))
		k.box("wood_lt", Vector3(px, 1.95, (door0 + door1) * 0.5), Vector3(0.05, 0.3, door1 - door0))
		k.box("wood", Vector3(px, 2.12, (ca + cb) * 0.5), Vector3(0.08, 0.06, cb - ca))
		k.box("wood", Vector3((px - hw(ca)) * 0.5, 1.05, ca + 0.02), Vector3(hw(ca) + px, 2.1, 0.05))
		_solid(Vector3(px, 1.05, (ca + door0) * 0.5), Vector3(0.12, 2.1, door0 - ca))
		_solid(Vector3(px, 1.05, (door1 + cb) * 0.5), Vector3(0.12, 2.1, cb - door1))
		_solid(Vector3((px - 2.1) * 0.5, 1.05, ca + 0.02), Vector3(2.1 + px, 2.1, 0.1))
		# Curtain half drawn across the doorway.
		k.box("canvas", Vector3(px + 0.02, 1.1, door0 + 0.18), Vector3(0.02, 1.6, 0.36))
		k.cyl("chrome", Vector3(px + 0.03, 1.92, door0), Vector3(px + 0.03, 1.92, door1), 0.01, 0.01, 4, false)
		# Bunks (two-tier except the captain's), desk, locker, wash basin.
		var bz := (ca + cb) * 0.5
		P.bunk(k, Transform3D(Basis.IDENTITY, Vector3(-1.55, 0.55, bz - 0.1)), 1.9, 0.68, "blanket%d" % ci, ci != 1)
		k.box("wood", Vector3(-1.55, 0.27, bz - 0.1), Vector3(0.7, 0.54, 1.9))
		_solid(Vector3(-1.55, 0.4, bz - 0.1), Vector3(0.75, 0.8, 1.95))
		if ci > 0:
			P.bunk(k, Transform3D(Basis.IDENTITY, Vector3(-1.5, 1.4, bz - 0.1)), 1.9, 0.62, "blanket%d" % ((ci + 1) % 3))
		k.box("wood", Vector3(-0.9, 0.78, cb - 0.45), Vector3(0.5, 0.04, 0.55))
		k.box("wood", Vector3(-0.9, 0.4, cb - 0.62), Vector3(0.5, 0.78, 0.2))
		k.box("white", Vector3(-0.95, 0.81, cb - 0.4), Vector3(0.21, 0.01, 0.29))
		k.cyl("brass", Vector3(-0.75, 0.8, cb - 0.62), Vector3(-0.75, 1.15, cb - 0.62), 0.012, 0.012, 4)
		k.cyl("green", Vector3(-0.75, 1.12, cb - 0.62), Vector3(-0.75, 1.2, cb - 0.55), 0.07, 0.1, 10)
		P.locker(k, P.face(Vector3(-0.85, 0.0, ca + 0.3), Vector3(0, 0, 1)), 0.45, 1.8, 0.35, 1, "wood_lt")
		k.box("chrome", Vector3(-1.95, 1.2, cb - 0.6), Vector3(0.1, 0.22, 0.4))
		P.label(k, P.face(Vector3(px + 0.03, 1.75, door1 + 0.18), Vector3(1, 0, 0)), 0.16, 0.05)
	_man("lie", Vector3(-1.55, 0.62, z0 + 4.45), 0.0)
	# Starboard: wardroom with green baize table, pantry, then the radio room.
	var tz := z0 + 2.3
	P.table(k, Transform3D(Basis.IDENTITY, Vector3(1.25, 0.0, tz)), 0.85, 2.0, 0.76, "felt")
	k.box("wood", Vector3(1.95, 0.25, tz), Vector3(0.35, 0.5, 2.1))
	k.box("blanket1", Vector3(1.9, 0.52, tz), Vector3(0.38, 0.1, 2.0))
	k.box("blanket1", Vector3(2.03, 0.9, tz), Vector3(0.08, 0.6, 2.0))
	_solid(Vector3(1.55, 0.45, tz), Vector3(1.3, 0.9, 2.1))
	for zz in [tz - 0.6, tz + 0.6]:
		P.stool(k, Vector3(0.62, 0.0, zz), 0.48)
	for j in 4:
		var cz := tz - 0.75 + j * 0.5
		k.cyl("white", Vector3(1.2 + (j % 2) * 0.15, 0.78, cz), Vector3(1.2 + (j % 2) * 0.15, 0.86, cz), 0.035, 0.03, 8)
		k.cyl("white", Vector3(1.4, 0.78, cz + 0.1), Vector3(1.4, 0.785, cz + 0.1), 0.11, 0.11, 12)
	k.box("white", Vector3(1.15, 0.79, tz + 0.2), Vector3(0.2, 0.01, 0.3), Basis(Vector3.UP, 0.4))
	P.locker(k, P.face(Vector3(1.75, 0.0, z0 + 4.2), Vector3(-1, 0, 0)), 0.9, 1.0, 0.5, 2, "wood")
	k.box("wood", Vector3(1.75, 1.6, z0 + 4.2), Vector3(0.45, 0.04, 0.9))
	for j in 6:
		k.cyl("white", Vector3(1.65, 1.62, z0 + 3.85 + j * 0.13), Vector3(1.65, 1.7, z0 + 3.85 + j * 0.13), 0.03, 0.03, 6)
	_solid(Vector3(1.85, 0.5, z0 + 4.2), Vector3(0.6, 1.0, 0.95))
	_man("sit_table", Vector3(0.62, 0.0, tz - 0.6), PI / 2)
	_man("sit_table", Vector3(1.88, 0.05, tz + 0.5), -PI / 2)
	# Radio room behind a partition.
	var r0 := z1 - 3.4
	k.box("wood_lt", Vector3(0.62, 1.05, r0 + 0.6), Vector3(0.05, 2.1, 1.2))
	k.box("wood_lt", Vector3(0.62, 1.05, z1 - 0.5), Vector3(0.05, 2.1, 0.8))
	k.box("wood_lt", Vector3(1.4, 1.05, r0), Vector3(1.6, 2.1, 0.05))
	_solid(Vector3(0.62, 1.05, r0 + 0.6), Vector3(0.12, 2.1, 1.2))
	_solid(Vector3(0.62, 1.05, z1 - 0.5), Vector3(0.12, 2.1, 0.8))
	_solid(Vector3(1.4, 1.05, r0), Vector3(1.6, 2.1, 0.1))
	P.panel(k, P.face(Vector3(1.92, 1.25, r0 + 1.6), Vector3(-1, 0, 0)), 1.6, 0.55, 0.4, 6, 8, "dark")
	P.panel(k, P.face(Vector3(1.85, 1.85, r0 + 1.6), Vector3(-1, 0, 0)), 1.4, 0.5, 0.35, 4, 4, "dark")
	k.box("wood", Vector3(1.6, 0.76, r0 + 1.6), Vector3(0.6, 0.04, 1.6))
	k.box("black", Vector3(1.45, 0.79, r0 + 1.5), Vector3(0.12, 0.04, 0.2))
	_solid(Vector3(1.7, 0.6, r0 + 1.6), Vector3(0.5, 1.2, 1.6))
	_man("sit_panel", Vector3(0.95, 0.0, r0 + 1.6), -PI / 2)
	_station("radio", Vector3(1.2, 1.3, r0 + 1.6), "Ask the radioman for the news")
	# Battery well access hatch in the deck.
	k.box("steel", Vector3(0.0, 0.006, (z0 + z1) * 0.5), Vector3(0.8, 0.012, 0.8))
	k.box("chrome", Vector3(0.25, 0.02, (z0 + z1) * 0.5), Vector3(0.15, 0.02, 0.04))


# ------------------------------------------------------------------ control room
func _control(k: MeshKit, z0: float, z1: float) -> void:
	# Attack and search periscope wells on the centreline.
	var az := z0 + 4.2
	var sz := z0 + 6.0
	for pz in [az, sz]:
		k.cyl("steel", Vector3(0, 0.0, pz), Vector3(0, 0.12, pz), 0.42, 0.42, 18)
		k.cyl("steel", Vector3(0, 2.4, pz), Vector3(0, 4.1, pz), 0.19, 0.19, 16, false)
		k.cyl("dark", Vector3(0, 3.2, pz), Vector3(0, 3.3, pz), 0.3, 0.3, 16)
		k.cyl("steel", Vector3(0, 0.12, pz), Vector3(0, 0.5, pz), 0.22, 0.22, 16, false)
		_solid(Vector3(0, 1.0, pz), Vector3(0.45, 2.0, 0.45))
	scope_head = Node3D.new()
	scope_head.position = Vector3(0, 0, az)
	add_child(scope_head)
	var ks := _kit()
	ks.cyl("steel", Vector3(0, 0.4, 0), Vector3(0, 2.6, 0), 0.16, 0.16, 16, false)
	ks.box("dark", Vector3(0, 1.62, -0.16), Vector3(0.36, 0.34, 0.32))
	ks.cyl("black", Vector3(0, 1.66, -0.32), Vector3(0, 1.66, -0.4), 0.06, 0.08, 10)
	ks.box("rubber", Vector3(0, 1.66, -0.41), Vector3(0.2, 0.08, 0.04))
	for s in [-1.0, 1.0]:
		ks.cyl("dark", Vector3(s * 0.18, 1.55, -0.1), Vector3(s * 0.5, 1.55, -0.1), 0.035, 0.035, 6)
		ks.cyl("rubber", Vector3(s * 0.5, 1.55, -0.1), Vector3(s * 0.5, 1.3, -0.1), 0.045, 0.045, 8)
	ks.cyl("brass", Vector3(0, 1.85, -0.12), Vector3(0, 1.85, 0.12), 0.08, 0.08, 12)
	_commit(ks, scope_head)
	_station("scope", Vector3(0, 1.6, az - 0.55), "Use the attack periscope")
	# Ladder and trunk up to the conning tower and bridge.
	var lz := LADDER.z
	P.ladder(k, P.face(Vector3(0, 0.0, lz - 0.05), Vector3(0, 0, 1)), 3.6, 0.45)
	k.cyl("steel", Vector3(0, 3.55, lz + 0.25), Vector3(0, 4.1, lz + 0.25), 0.55, 0.55, 18, false)
	k.cyl("dark", Vector3(0, 3.5, lz + 0.25), Vector3(0, 3.56, lz + 0.25), 0.62, 0.62, 18)
	P.valve(k, P.face(Vector3(0.0, 3.45, lz + 0.25), Vector3(0, -1, 0)), 0.2, "steel", 6, 0.04)
	_solid(Vector3(0, 1.2, lz), Vector3(0.6, 2.4, 0.12))
	_station("ladder", Vector3(0, 1.5, lz + 0.35), "Climb to the bridge")
	# Helm, forward port: console, wheel, gyro repeater and two engine telegraphs.
	var hz := z0 + 0.55
	k.box("dark", Vector3(-1.4, 0.65, hz), Vector3(0.95, 1.3, 0.55))
	k.box("steel", Vector3(-1.4, 1.32, hz + 0.05), Vector3(1.0, 0.06, 0.65))
	_solid(Vector3(-1.4, 0.65, hz), Vector3(0.95, 1.3, 0.6))
	helm_wheel = _wheel_node(Vector3(-1.4, 1.12, hz + 0.68), Vector3(0, 0, 1), 0.34, 0.42)
	_panel("compass", Vector3(-1.4, 1.75, hz - 0.02), Vector2(0.44, 0.44), Vector3(0, 0, 1), 256, 256)
	P.gauge(k, P.face(Vector3(-1.82, 1.75, hz + 0.0), Vector3(0, 0, 1)), 0.08)
	P.gauge(k, P.face(Vector3(-0.98, 1.75, hz + 0.0), Vector3(0, 0, 1)), 0.08)
	P.stool(k, Vector3(-1.4, 0.0, hz + 1.25), 0.5)
	_man("sit_wheel", Vector3(-1.4, 0.0, hz + 1.3), 0.0, {"r": Vector3(0.27, 1.12, -0.6), "l": Vector3(-0.27, 1.12, -0.6)})
	for i in 2:
		var tx := -0.72 + i * 0.0
		var tzz := hz + 0.1 + i * 0.55
		k.cyl("dark", Vector3(tx, 0.0, tzz), Vector3(tx, 1.0, tzz), 0.09, 0.07, 10)
		k.cyl("brass", Vector3(tx, 1.15, tzz - 0.08), Vector3(tx, 1.15, tzz + 0.08), 0.21, 0.21, 22)
		k.disc_uv("dial", Vector3(tx, 1.15, tzz + 0.081), Vector3(0, 0, 1), 0.18, 18)
		_solid(Vector3(tx, 0.6, tzz), Vector3(0.3, 1.2, 0.3))
		var tn := Node3D.new()
		tn.position = Vector3(tx, 1.15, tzz + 0.1)
		add_child(tn)
		var tk := _kit()
		tk.box("brass", Vector3(0, 0.12, 0.02), Vector3(0.035, 0.26, 0.03))
		tk.sphere("black", Vector3(0, 0.26, 0.04), 0.035, 6, 4)
		_commit(tk, tn)
		telegraphs.append(tn)
	_station("helm", Vector3(-1.4, 1.3, hz + 0.9), "Check the helm and compass")
	# Diving station, forward starboard: bow and stern plane wheels under the depth gauges.
	k.box("dark", Vector3(1.72, 0.7, hz + 0.7), Vector3(0.35, 1.4, 1.5))
	_solid(Vector3(1.72, 0.7, hz + 0.7), Vector3(0.4, 1.4, 1.5))
	plane_wheels.append(_wheel_node(Vector3(1.48, 1.15, hz + 0.25), Vector3(-1, 0, 0), 0.32, 0.25))
	plane_wheels.append(_wheel_node(Vector3(1.48, 1.15, hz + 1.15), Vector3(-1, 0, 0), 0.32, 0.25))
	_panel("depth", Vector3(1.9, 2.05, hz + 0.7), Vector2(0.62, 0.62), Vector3(-1, 0, 0), 300, 300)
	P.gauge(k, P.face(Vector3(1.88, 2.05, hz + 0.1), Vector3(-1, 0, 0)), 0.12)
	P.gauge(k, P.face(Vector3(1.88, 2.05, hz + 1.3), Vector3(-1, 0, 0)), 0.12)
	k.box("glass", Vector3(1.86, 1.62, hz + 0.7), Vector3(0.04, 0.06, 0.6))
	k.sphere("black", Vector3(1.84, 1.62, hz + 0.72), 0.02, 6, 4)
	for zz in [hz + 0.25, hz + 1.15]:
		P.stool(k, Vector3(0.78, 0.0, zz), 0.5)
		_man("sit_wheel", Vector3(0.74, 0.0, zz), -PI / 2, {"r": Vector3(0.26, 1.15, -0.62), "l": Vector3(-0.26, 1.15, -0.62)})
	_station("dive", Vector3(1.1, 1.4, hz + 0.7), "Check the diving station")
	_panel("tree", Vector3(1.2, 2.0, z0 + 0.08), Vector2(0.48, 0.7), Vector3(0, 0, 1), 200, 300)
	_man("stand", Vector3(0.35, 0.0, hz + 2.1), PI * 0.85)
	# Main gauge board above the helm on the forward bulkhead.
	_panel("gauges", Vector3(-1.15, 2.55, z0 + 0.08), Vector2(1.3, 0.82), Vector3(0, 0, 1), 600, 380)
	# Port: high-pressure air and ballast manifolds, a wall of valves and copper.
	var mz0 := z0 + 2.3
	k.box("dark", Vector3(-2.02, 1.5, mz0 + 1.6), Vector3(0.1, 1.6, 3.2))
	for row in 3:
		for c in 8:
			var vp := Vector3(-1.94, 1.0 + row * 0.42, mz0 + 0.25 + c * 0.38)
			P.valve(k, P.face(vp, Vector3(1, 0, 0)), 0.09 if row < 2 else 0.07, ["red", "green", "brass"][(row + c) % 3], 4, 0.12)
			if row == 2:
				P.gauge(k, P.face(vp + Vector3(0, 0.3, 0), Vector3(1, 0, 0)), 0.055)
	for row in 3:
		P.pipe(k, Vector3(-1.98, 0.85 + row * 0.42, mz0 + 0.1), Vector3(-1.98, 0.85 + row * 0.42, mz0 + 3.1), 0.025, "copper", 0.0)
	P.label(k, P.face(Vector3(-1.94, 2.35, mz0 + 1.6), Vector3(1, 0, 0)), 0.5, 0.08)
	_solid(Vector3(-1.95, 1.0, mz0 + 1.6), Vector3(0.35, 2.0, 3.2))
	_man("work", Vector3(-1.35, 0.0, mz0 + 1.4), PI / 2, {"r": Vector3(0.18, 1.42, -0.5), "l": Vector3(-0.25, 1.0, -0.48)})
	# Starboard mid: damage control board and trim manifold.
	_panel("damage", Vector3(1.97, 1.7, z0 + 4.6), Vector2(0.8, 1.15), Vector3(-1, 0, 0), 360, 520)
	_station("damage", Vector3(1.55, 1.5, z0 + 4.6), "Read the damage control board")
	for c in 5:
		P.valve(k, P.face(Vector3(1.92, 1.0, z0 + 5.5 + c * 0.3), Vector3(-1, 0, 0)), 0.08, "green", 4, 0.1)
	# Aft starboard: chart table with its lamp.
	var cz := z1 - 2.1
	k.box("wood", Vector3(1.4, 0.92, cz), Vector3(1.05, 0.05, 1.45))
	k.box("wood", Vector3(1.4, 0.45, cz), Vector3(0.95, 0.9, 1.35))
	for d in 3:
		k.box("chrome", Vector3(0.9, 0.3 + d * 0.22, cz), Vector3(0.02, 0.03, 0.2))
	_solid(Vector3(1.45, 0.5, cz), Vector3(1.05, 1.0, 1.45))
	_panel("chart", Vector3(1.4, 0.955, cz), Vector2(0.95, 1.3), Vector3(0, 1, 0), 420, 560)
	k.cyl("dark", Vector3(1.4, 3.3, cz), Vector3(1.4, 2.25, cz), 0.012, 0.012, 4, false)
	k.cyl("green", Vector3(1.4, 2.25, cz), Vector3(1.4, 2.15, cz), 0.06, 0.18, 12, false)
	k.sphere("lamp", Vector3(1.4, 2.18, cz), 0.04, 6, 4)
	k.cyl("brass", Vector3(1.0, 0.98, cz + 0.4), Vector3(1.15, 0.98, cz + 0.55), 0.004, 0.004, 3, false)
	_man("lean", Vector3(0.62, 0.0, cz), -PI / 2, {"r": Vector3(0.2, 0.96, -0.62), "l": Vector3(-0.3, 0.96, -0.55)})
	_station("chart", Vector3(1.35, 1.1, cz), "Study the plot table")
	# Aft port: hydrophone station.
	var hz2 := z1 - 2.0
	k.box("dark", Vector3(-1.75, 0.45, hz2), Vector3(0.6, 0.9, 1.0))
	k.box("steel", Vector3(-1.95, 1.45, hz2), Vector3(0.3, 1.1, 1.05))
	_solid(Vector3(-1.8, 0.7, hz2), Vector3(0.65, 1.4, 1.05))
	_panel("sonar", Vector3(-1.79, 1.5, hz2), Vector2(0.75, 0.75), Vector3(1, 0, 0), 400, 400)
	for c in 3:
		k.cyl("black", Vector3(-1.5, 0.92, hz2 - 0.3 + c * 0.3), Vector3(-1.45, 0.92, hz2 - 0.3 + c * 0.3), 0.04, 0.04, 8)
	P.stool(k, Vector3(-0.95, 0.0, hz2), 0.5)
	_man("sit_panel", Vector3(-0.92, 0.0, hz2), PI / 2, {"r": Vector3(0.12, 0.98, -0.55), "l": Vector3(-0.2, 0.98, -0.5)})
	_station("sonar", Vector3(-1.4, 1.4, hz2), "Listen on the hydrophones")
	# Torpedo data computer on the aft bulkhead.
	k.box("steel", Vector3(-1.2, 1.35, z1 - 0.32), Vector3(1.1, 1.5, 0.45))
	_panel("tdc", Vector3(-1.2, 1.5, z1 - 0.56), Vector2(0.95, 0.9), Vector3(0, 0, -1), 480, 450)
	for c in 6:
		k.cyl("black", Vector3(-1.6 + c * 0.16, 0.85, z1 - 0.55), Vector3(-1.6 + c * 0.16, 0.85, z1 - 0.62), 0.035, 0.035, 8)
	_solid(Vector3(-1.2, 1.0, z1 - 0.32), Vector3(1.1, 2.0, 0.5))
	_station("tdc", Vector3(-1.2, 1.5, z1 - 1.1), "Work the torpedo data computer")
	if nat["id"] == "de":
		for zz in [z0 + 3.0, z0 + 7.5]:
			P.hanging_food(k, Vector3(0.8, 3.45, zz), 6)
		P.hanging_food(k, Vector3(-0.9, 3.4, z0 + 5.5), 5)


# --------------------------------------------------------- crew's mess and berthing
func _crew_quarters(k: MeshKit, z0: float, z1: float) -> void:
	# Galley, forward port.
	var gz := z0 + 1.6
	k.box("dark", Vector3(-1.55, 0.45, gz), Vector3(0.85, 0.9, 1.6))
	k.box("black", Vector3(-1.55, 0.92, gz), Vector3(0.85, 0.04, 1.6))
	for j in 4:
		k.cyl("dark", Vector3(-1.55 + (j % 2 - 0.5) * 0.4, 0.94, gz - 0.4 + (j / 2) * 0.8), Vector3(-1.55 + (j % 2 - 0.5) * 0.4, 0.96, gz - 0.4 + (j / 2) * 0.8), 0.15, 0.15, 14)
	k.cyl("chrome", Vector3(-1.1, 0.96, gz - 0.8), Vector3(-1.1, 0.96, gz + 0.8), 0.015, 0.015, 6, false)
	for j in 2:
		k.box("black", Vector3(-1.12, 0.45, gz - 0.4 + j * 0.8), Vector3(0.02, 0.5, 0.65))
		k.box("chrome", Vector3(-1.1, 0.68, gz - 0.4 + j * 0.8), Vector3(0.03, 0.03, 0.4))
	k.cyl("steel", Vector3(-1.45, 0.94, gz + 0.4), Vector3(-1.45, 1.15, gz + 0.4), 0.16, 0.16, 14)
	k.cyl("steel", Vector3(-1.75, 0.94, gz - 0.4), Vector3(-1.75, 1.08, gz - 0.4), 0.13, 0.13, 14)
	k.cyl("black", Vector3(-1.75, 1.08, gz - 0.4), Vector3(-1.48, 1.12, gz - 0.4), 0.012, 0.012, 4)
	_solid(Vector3(-1.6, 0.5, gz), Vector3(0.9, 1.0, 1.65))
	# Coffee urn, sink and the shelves of tins.
	var uz := gz + 1.3
	k.box("steel", Vector3(-1.65, 0.45, uz), Vector3(0.7, 0.9, 0.8))
	k.cyl("chrome", Vector3(-1.75, 0.9, uz - 0.15), Vector3(-1.75, 1.4, uz - 0.15), 0.17, 0.17, 16)
	k.sphere("chrome", Vector3(-1.75, 1.4, uz - 0.15), 0.17, 10, 4, Vector3(1, 0.4, 1))
	k.cyl("chrome", Vector3(-1.58, 1.0, uz - 0.15), Vector3(-1.5, 1.0, uz - 0.15), 0.015, 0.015, 4)
	k.box("chrome", Vector3(-1.55, 0.88, uz + 0.22), Vector3(0.45, 0.05, 0.35))
	k.box("black", Vector3(-1.55, 0.9, uz + 0.22), Vector3(0.38, 0.02, 0.28))
	k.cyl("chrome", Vector3(-1.8, 0.9, uz + 0.22), Vector3(-1.8, 1.15, uz + 0.22), 0.012, 0.012, 4, false)
	_solid(Vector3(-1.65, 0.5, uz), Vector3(0.75, 1.0, 0.85))
	for sh in 2:
		var sy := 1.65 + sh * 0.42
		k.box("wood", Vector3(-1.8, sy, gz + 0.6), Vector3(0.35, 0.03, 2.4))
		k.box("chrome", Vector3(-1.63, sy + 0.08, gz + 0.6), Vector3(0.01, 0.01, 2.4))
		for j in 4:
			P.cans(k, Vector3(-1.92, sy + 0.015, gz - 0.5 + j * 0.55), 6)
	for j in 4:
		var pz := gz - 0.6 + j * 0.4
		k.cyl("dark", Vector3(-1.2, 2.35, pz), Vector3(-1.2, 2.1, pz), 0.008, 0.008, 3, false)
		k.cyl("steel", Vector3(-1.2, 2.1, pz), Vector3(-1.2, 1.88, pz), 0.12, 0.11, 12)
	_man("work", Vector3(-0.85, 0.0, gz + 0.2), PI / 2, {"r": Vector3(0.2, 1.0, -0.5), "l": Vector3(-0.15, 1.0, -0.4)})
	_station("galley", Vector3(-1.1, 1.3, uz), "Get a cup of coffee")
	# Mess tables, starboard.
	for ti in 2:
		var tz := z0 + 1.2 + ti * 2.1
		P.table(k, Transform3D(Basis.IDENTITY, Vector3(1.28, 0.0, tz)), 0.7, 1.7, 0.74, "linoleum")
		P.bench(k, Transform3D(Basis.IDENTITY, Vector3(0.72, 0.0, tz)), 1.7, 0.45, 0.3)
		P.bench(k, Transform3D(Basis.IDENTITY, Vector3(1.86, 0.0, tz)), 1.7, 0.45, 0.3)
		_solid(Vector3(1.3, 0.45, tz), Vector3(1.5, 0.9, 1.75))
		for j in 4:
			var pz := tz - 0.6 + j * 0.4
			k.cyl("white", Vector3(1.15 + (j % 2) * 0.27, 0.745, pz), Vector3(1.15 + (j % 2) * 0.27, 0.75, pz), 0.11, 0.11, 12)
			k.cyl("white", Vector3(1.05 + (j % 2) * 0.47, 0.75, pz + 0.12), Vector3(1.05 + (j % 2) * 0.47, 0.84, pz + 0.12), 0.04, 0.035, 8)
		k.cyl("red", Vector3(1.28, 0.74, tz), Vector3(1.28, 0.9, tz), 0.03, 0.03, 8)
		k.cyl("food", Vector3(1.28, 0.74, tz + 0.3), Vector3(1.28, 0.82, tz + 0.3), 0.12, 0.12, 12)
	_man("sit_table", Vector3(0.72, 0.0, z0 + 0.8), -PI / 2)
	_man("sit_table", Vector3(0.72, 0.0, z0 + 3.6), -PI / 2)
	_man("sit_table", Vector3(1.86, 0.0, z0 + 1.6), PI / 2)
	# Berthing aft: triple-tier bunks down both sides with lockers beneath.
	var b0 := z0 + 5.4
	for s in [-1.0, 1.0]:
		for bi in 2:
			var bz := b0 + 1.0 + bi * 2.15
			k.box("paint", Vector3(s * 1.5, 0.15, bz), Vector3(0.66, 0.3, 2.0))
			for j in 3:
				k.box("black", Vector3(s * 1.5 - s * 0.33, 0.15, bz - 0.66 + j * 0.66), Vector3(0.01, 0.2, 0.02))
			for tier in 3:
				var occupied := (bi + tier + int(s > 0)) % 4 == 0
				P.bunk(k, Transform3D(Basis.IDENTITY, Vector3(s * 1.5, 0.42 + tier * 0.72, bz)), 1.95, 0.62, "blanket%d" % ((bi + tier) % 3), not occupied)
				if occupied:
					_man("lie", Vector3(s * 1.5, 0.48 + tier * 0.72, bz), 0.0)
			for zz in [bz - 1.0, bz + 1.0]:
				k.cyl("steel", Vector3(s * 1.18, 0.0, zz), Vector3(s * 1.18, 2.35, zz), 0.022, 0.022, 6)
			if (bi + int(s > 0)) % 2 == 0:
				k.box("canvas", Vector3(s * 1.17, 1.4, bz - 0.5), Vector3(0.02, 1.4, 0.8))
			_solid(Vector3(s * 1.55, 1.0, bz), Vector3(0.75, 2.0, 2.05))
	# Hammock of bread over the passage, lockers at the after end.
	k.sphere("canvas", Vector3(0.0, 3.2, b0 - 1.0), 0.35, 10, 4, Vector3(1.2, 0.45, 2.2))
	for j in 5:
		k.sphere("bread", Vector3(randf_range(-0.2, 0.2), 3.18, b0 - 1.5 + j * 0.25), 0.09, 6, 4, Vector3(1, 0.7, 1.6))


# ------------------------------------------------------------------ engine rooms
func _engine_room(k: MeshKit, z0: float, z1: float, forward: bool) -> void:
	var ez0 := z0 + 0.9
	var ez1 := z1 - 1.4
	var el := ez1 - ez0
	var ezc := (ez0 + ez1) * 0.5
	for s in [-1.0, 1.0]:
		var ex: float = s * 1.12
		# Crankcase, inspection doors and the generator housing aft.
		k.block("engine", ex, ezc, 0.0, 1.1, 1.0, el, 0.86, el - 0.1)
		var dz := ez0 + 0.45
		while dz < ez1 - 0.3:
			k.cyl("engine", Vector3(ex - s * 0.47, 0.6, dz), Vector3(ex - s * 0.5, 0.6, dz), 0.17, 0.17, 12)
			k.cyl("steel", Vector3(ex - s * 0.5, 0.6, dz), Vector3(ex - s * 0.51, 0.6, dz), 0.04, 0.04, 6)
			dz += 0.78
		k.cyl("engine", Vector3(ex, 0.65, ez1), Vector3(ex, 0.65, z1 - 0.2), 0.58, 0.58, 18)
		k.cyl("steel", Vector3(ex, 0.65, ez1 - 0.05), Vector3(ex, 0.65, ez1 + 0.05), 0.62, 0.62, 18)
		for j in 6:
			k.box("dark", Vector3(ex, 0.65 + 0.58, ez1 + 0.15 + j * 0.15), Vector3(0.3, 0.04, 0.06))
		# Cylinder heads and rocker covers along the top; rockers bob when running.
		var n := 8
		var rk := Node3D.new()
		add_child(rk)
		var kr := _kit()
		for j in n:
			var cz := ez0 + 0.4 + (el - 0.8) * j / (n - 1)
			k.box("engine", Vector3(ex, 1.22, cz), Vector3(0.62, 0.24, 0.58))
			kr.box("steel", Vector3(ex, 1.42, cz), Vector3(0.5, 0.16, 0.48))
			kr.cyl("steel", Vector3(ex - 0.1, 1.5, cz), Vector3(ex + 0.1, 1.5, cz), 0.03, 0.03, 6)
			k.cyl("copper", Vector3(ex - s * 0.3, 1.1, cz), Vector3(ex - s * 0.38, 0.9, cz), 0.012, 0.012, 4, false)
		_commit(kr, rk)
		rockers.append(rk)
		k.box("engine", Vector3(ex - s * 0.4, 0.95, ezc), Vector3(0.12, 0.14, el - 0.4))
		# Lagged exhaust manifold up the outboard side and into the uptake.
		var mx: float = ex + s * 0.48
		k.cyl("canvas", Vector3(mx, 1.35, ez0 + 0.2), Vector3(mx, 1.35, ez1 - 0.2), 0.16, 0.16, 12)
		for j in 6:
			var bz2 := ez0 + 0.5 + j * (el - 1.0) / 5.0
			k.cyl("steel", Vector3(mx, 1.35, bz2 - 0.02), Vector3(mx, 1.35, bz2 + 0.02), 0.17, 0.17, 12, false)
		P.pipe_path(k, [Vector3(mx, 1.35, ez0 + 0.2), Vector3(mx, 1.35, ez0 - 0.25), Vector3(mx * 0.85, 3.2, ez0 - 0.25)], 0.17, "canvas")
		# Gauge board and controls at the forward end of each engine.
		P.panel(k, P.face(Vector3(ex, 1.85, ez0 - 0.25), Vector3(0, 0, 1)), 0.8, 0.5, 0.12, 6, 2, "dark")
		P.valve(k, P.face(Vector3(ex - s * 0.3, 1.3, ez0 - 0.06), Vector3(0, 0, 1)), 0.16, "red", 5, 0.1)
		k.cyl("dark", Vector3(ex + s * 0.25, 0.0, ez0 - 0.15), Vector3(ex + s * 0.25, 1.1, ez0 - 0.15), 0.1, 0.1, 10)
		_solid(Vector3(ex, 0.8, (ez0 + z1) * 0.5), Vector3(1.05, 1.6, z1 - ez0))
		var en := Node3D.new()
		add_child(en)
		engines.append(en)
	# Air induction duct and maintenance rail overhead, oil tank and tool board.
	P.duct(k, Vector3(0, 3.3, z0 + 0.2), Vector3(0, 3.3, z1 - 0.2), 0.6, 0.4)
	for zz in [ez0 + 1.5, ez1 - 1.5]:
		k.box("dark", Vector3(0, 3.0, zz), Vector3(0.3, 0.18, 0.3))
		k.cyl("black", Vector3(0.05, 2.9, zz), Vector3(0.05, 1.9, zz), 0.01, 0.01, 3, false)
	P.panel(k, P.face(Vector3(-1.3, 2.4, z0 + 0.1), Vector3(0, 0, 1)), 0.9, 0.5, 0.08, 0, 0, "wood")
	for j in 7:
		k.box("steel", Vector3(-1.65 + j * 0.11, 2.4, z0 + 0.13), Vector3(0.025, 0.32 - (j % 3) * 0.06, 0.02))
	k.cyl("yellow", Vector3(1.3, 2.2, z0 + 0.25), Vector3(1.3, 2.75, z0 + 0.25), 0.2, 0.2, 14)
	k.cyl("dark", Vector3(0.95, 2.2, z0 + 0.15), Vector3(0.95, 2.75, z0 + 0.15), 0.12, 0.12, 12)
	k.cyl("chrome", Vector3(0.95, 2.4, z0 + 0.3), Vector3(0.95, 2.5, z0 + 0.3), 0.05, 0.05, 8)
	P.extinguisher(k, Vector3(0.62, 0.0, z1 - 0.4))
	# Engine-order telegraph repeater beside the door.
	k.cyl("brass", Vector3(0.75, 1.9, z0 + 0.06), Vector3(0.75, 1.9, z0 + 0.14), 0.18, 0.18, 20)
	k.disc_uv("dial", Vector3(0.75, 1.9, z0 + 0.141), Vector3(0, 0, 1), 0.15, 18)
	_man("work", Vector3(0.0, 0.0, ez0 + 0.6), PI, {"r": Vector3(0.6, 1.5, -0.5), "l": Vector3(0.45, 1.4, -0.55)} if forward else {})
	_station("engine", Vector3(0, 1.4, ez0 + 0.3), "Check the engine and motor gauges")


# ------------------------------------------------------------------ maneuvering
func _maneuvering(k: MeshKit, z0: float, z1: float) -> void:
	# Main control cubicle to starboard: switchboard, ammeters, big controller levers.
	var cz := (z0 + z1) * 0.5
	k.box("dark", Vector3(1.7, 1.2, cz), Vector3(0.5, 2.4, 4.2))
	P.panel(k, P.face(Vector3(1.44, 1.95, cz), Vector3(-1, 0, 0)), 4.0, 0.9, 0.05, 16, 0, "dark")
	k.box("steel", Vector3(1.3, 0.95, cz), Vector3(0.3, 0.08, 3.8))
	for j in 6:
		var lz := cz - 1.6 + j * 0.64
		k.box("steel", Vector3(1.3, 1.0, lz), Vector3(0.22, 0.12, 0.08))
		var a := randf_range(-0.4, 0.4)
		k.cyl("chrome", Vector3(1.3, 1.02, lz), Vector3(1.3 - 0.4 * cos(a), 1.02 + 0.32, lz + 0.1 * sin(a)), 0.02, 0.016, 6)
		k.sphere("black", Vector3(1.3 - 0.4 * cos(a), 1.36, lz + 0.1 * sin(a)), 0.04, 6, 4)
	for j in 10:
		k.box(["led_red", "led_green", "led_amber"][j % 3], Vector3(1.45, 1.4, cz - 1.8 + j * 0.4), Vector3(0.02, 0.03, 0.03))
		P.label(k, P.face(Vector3(1.445, 1.32, cz - 1.8 + j * 0.4), Vector3(-1, 0, 0)), 0.18, 0.035)
	_solid(Vector3(1.6, 1.0, cz), Vector3(0.8, 2.0, 4.2))
	for zz in [cz - 0.9, cz + 0.9]:
		P.stool(k, Vector3(0.7, 0.0, zz), 0.55)
		_man("sit_panel", Vector3(0.68, 0.0, zz), -PI / 2, {"r": Vector3(0.1, 1.2, -0.6), "l": Vector3(-0.2, 1.0, -0.5)})
	_station("maneuvering", Vector3(1.1, 1.3, cz), "Check the motor controls")
	# Port: workbench with vise and a small lathe.
	k.box("wood", Vector3(-1.6, 0.85, cz - 0.6), Vector3(0.7, 0.06, 2.0))
	k.box("dark", Vector3(-1.6, 0.42, cz - 0.6), Vector3(0.65, 0.84, 1.9))
	k.box("steel", Vector3(-1.5, 0.98, cz - 1.3), Vector3(0.2, 0.18, 0.15))
	k.cyl("chrome", Vector3(-1.38, 0.95, cz - 1.3), Vector3(-1.2, 0.95, cz - 1.3), 0.012, 0.012, 4)
	k.box("engine", Vector3(-1.65, 1.02, cz - 0.3), Vector3(0.3, 0.12, 1.2))
	k.box("engine", Vector3(-1.65, 1.2, cz - 0.8), Vector3(0.35, 0.35, 0.3))
	k.cyl("chrome", Vector3(-1.65, 1.2, cz - 0.62), Vector3(-1.65, 1.2, cz - 0.52), 0.1, 0.1, 10)
	k.box("engine", Vector3(-1.65, 1.15, cz + 0.2), Vector3(0.22, 0.22, 0.2))
	_solid(Vector3(-1.65, 0.5, cz - 0.6), Vector3(0.75, 1.0, 2.0))
	P.locker(k, P.face(Vector3(-1.75, 0.0, cz + 1.4), Vector3(1, 0, 0)), 0.9, 1.6, 0.45, 2, "dark")
	_solid(Vector3(-1.85, 0.8, cz + 1.4), Vector3(0.5, 1.6, 0.95))
	for j in 8:
		k.cyl("black", Vector3(-0.6 + j * 0.16, 3.55, z0 + 0.1), Vector3(-0.6 + j * 0.16, 3.55, z1 - 0.1), 0.04, 0.04, 6, false)


# ------------------------------------------------------------------ after torpedo room
func _atr(k: MeshKit, z0: float, z1: float) -> void:
	var n: int = {"us": 4, "de": 1}.get(nat["id"], 0)
	if n > 0:
		for i in n:
			var x := 0.0 if n == 1 else ((i % 2) - 0.5) * 0.95
			var y := 1.05 if n == 1 else 0.9 + (i / 2) * 0.85
			var p := Vector3(x, y, z1)
			var front := p - Vector3(0, 0, 2.6)
			k.cyl("steel", p, front, 0.3, 0.3, 18, false)
			k.cyl("brass", front, front - Vector3(0, 0, 0.1), 0.35, 0.35, 20)
			k.cyl("steel", front - Vector3(0, 0, 0.1), front - Vector3(0, 0, 0.2), 0.3, 0.27, 18)
			k.box("steel", front + Vector3(0.35, 0, -0.12), Vector3(0.12, 0.2, 0.14))
			_solid(Vector3(p.x, p.y, z1 - 1.4), Vector3(0.66, 0.66, 2.8))
		for s in [-1.0, 1.0]:
			P.torpedo(k, Transform3D(Basis.IDENTITY, Vector3(s * 1.3, 0.48, z0 + 3.6)), 6.4, 0.25)
			k.box("steel", Vector3(s * 1.3, 0.18, z0 + 3.6), Vector3(0.6, 0.05, 6.0))
			_solid(Vector3(s * 1.35, 0.4, z0 + 3.6), Vector3(0.7, 0.8, 6.4))
		_station("torpedo", Vector3(0, 1.4, z1 - 3.0), "Check the stern tubes")
	else:
		# Steering gear: hydraulic rams, emergency steering wheel and stores.
		for s in [-1.0, 1.0]:
			k.cyl("steel", Vector3(s * 0.55, 0.9, z1 - 0.1), Vector3(s * 0.55, 0.9, z1 - 2.0), 0.14, 0.14, 12)
			k.cyl("chrome", Vector3(s * 0.55, 0.9, z1 - 2.0), Vector3(s * 0.55, 0.9, z1 - 2.6), 0.06, 0.06, 8)
		k.box("dark", Vector3(0, 0.45, z1 - 1.2), Vector3(1.6, 0.9, 1.6))
		_solid(Vector3(0, 0.7, z1 - 1.3), Vector3(1.6, 1.4, 2.6))
		var wn := _wheel_node(Vector3(0, 1.3, z1 - 2.8), Vector3(0, 0, -1), 0.3, 0.3)
		wn.rotation.z = 0.4
		for i in 6:
			P.crate(k, Transform3D(Basis(Vector3.UP, randf_range(-0.2, 0.2)), Vector3(1.4 * (1 if i % 2 else -1), (i / 2) % 2 * 0.4, z0 + 1.5 + (i / 4) * 0.8)), Vector3(0.6, 0.4, 0.5))
		for i in 5:
			k.sphere("canvas", Vector3(-1.4, 0.2, z0 + 3.5 + i * 0.5), 0.28, 8, 4, Vector3(1, 0.7, 1.2))
		for s in [-1.0, 1.0]:
			_solid(Vector3(s * 1.45, 0.4, z0 + 2.5), Vector3(0.7, 0.8, 4.0))
		_station("steering", Vector3(0, 1.3, z1 - 3.2), "Check the steering gear")
	for s in [-1.0, 1.0]:
		P.bunk(k, Transform3D(Basis.IDENTITY, Vector3(s * 1.35, 1.65, z0 + 2.2)), 1.9, 0.6, "blanket%d" % (int(s > 0) + 1))
		P.bunk(k, Transform3D(Basis.IDENTITY, Vector3(s * 1.35, 1.65, z0 + 4.6)), 1.9, 0.6, "blanket0", s > 0)
	_man("lie", Vector3(-1.35, 1.72, z0 + 4.6), 0.0)
	_man("work", Vector3(0.4, 0.0, z0 + 5.0), 0.3, {"r": Vector3(0.2, 1.1, -0.5), "l": Vector3(-0.15, 1.3, -0.45)})


# ------------------------------------------------------------------ collisions
func _collisions() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var zf: float = COMPARTMENTS[0][1]
	var za: float = COMPARTMENTS[-1][2]
	var zc := (zf + za) * 0.5
	_box(body, Vector3(0, -0.15, zc), Vector3(8, 0.3, za - zf + 2))
	_box(body, Vector3(0, 3.95, zc), Vector3(8, 0.3, za - zf + 2))
	for c in COMPARTMENTS:
		var z0: float = c[1]
		var z1: float = c[2]
		var w := minf(hw(z0 + 0.05), hw(z1 - 0.05))
		for s in [-1.0, 1.0]:
			_box(body, Vector3(s * (w + 0.1), 2.0, (z0 + z1) * 0.5), Vector3(0.3, 4.0, z1 - z0))
	for ze in [zf - 0.15, za + 0.15]:
		_box(body, Vector3(0, 2.0, ze), Vector3(8, 4, 0.3))
	for i in range(1, COMPARTMENTS.size()):
		var zb: float = COMPARTMENTS[i][1]
		_box(body, Vector3(-2.0, 2.0, zb), Vector3(3.1, 4.0, 0.24))
		_box(body, Vector3(2.0, 2.0, zb), Vector3(3.1, 4.0, 0.24))
		_box(body, Vector3(0, 3.1, zb), Vector3(1.0, 1.8, 0.24))
	for sdef in solids:
		_box(body, sdef[0], sdef[1])


func _box(body: StaticBody3D, c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = s
	cs.shape = b
	cs.position = c
	body.add_child(cs)


func _water() -> void:
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var zf: float = COMPARTMENTS[0][1]
	var za: float = COMPARTMENTS[-1][2]
	pm.size = Vector2(4.4, za - zf)
	water.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.2, 0.22, 0.78)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic = 0.3
	water.material_override = m
	water.position = Vector3(0, -0.2, (zf + za) * 0.5)
	water.visible = false
	add_child(water)


# ------------------------------------------------------------------ update
func set_world(w) -> void:
	world = w
	for p in panels:
		p["ins"].world = w
	red = w.tod == "night"


func set_active(on: bool) -> void:
	for p in panels:
		p["vp"].render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	visible = on


static func door_zs() -> Array:
	var out := []
	for i in range(1, COMPARTMENTS.size()):
		out.append(COMPARTMENTS[i][1])
	return out


func spawn_leak() -> void:
	var p := CPUParticles3D.new()
	p.mesh = QuadMesh.new()
	p.material_override = Fx._pmat(Color(0.75, 0.85, 0.9), false)
	p.amount = 50
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
	var z := randf_range(-30.0, 30.0)
	p.position = Vector3(side * 1.9, randf_range(2.2, 3.2), z)
	add_child(p)
	_set_layers(p)
	leak_fx.append(p)
	flicker = 1.5


func update(dt: float) -> void:
	if world == null:
		return
	t += dt
	var s = world.sub
	var tel_a := lerpf(-2.2, 2.2, float(s.tel) / 7.0)
	for tn in telegraphs:
		tn.rotation.z = lerp_angle(tn.rotation.z, -tel_a, clampf(dt * 6.0, 0.0, 1.0))
	helm_wheel.rotation.z = lerp_angle(helm_wheel.rotation.z, -deg_to_rad(s.rud) * 4.0, clampf(dt * 3.0, 0.0, 1.0))
	var dd: float = s.dep_ord - s.depth
	for i in plane_wheels.size():
		plane_wheels[i].rotation.z += clampf(dd, -1.0, 1.0) * dt * (2.4 if i == 0 else -1.8)
	var up: bool = s.scope_up and not s.surfaced()
	scope_head.position.y = move_toward(scope_head.position.y, 0.0 if up else -0.95, dt * 0.8)
	for ta in torps_anim:
		var i: int = ta["tube"]
		var node: Node3D = ta["node"]
		var v: float = s.tubes[i] if i < s.tubes.size() else 0.0
		if v > 0.0:
			var f := 1.0 - v / World.RELOAD
			node.position = (ta["home"] as Vector3).lerp(ta["target"], smoothstep(0.1, 0.95, f))
			node.visible = true
		else:
			node.position = ta["home"]
			node.visible = s.spares > i
	var diesel: bool = s.flood < 0.5
	for i in rockers.size():
		rockers[i].position.y = (absf(sin(t * 22.0 + i)) * 0.012) if diesel else 0.0
	var shake: float = world.shake
	for c in crew:
		var n: Node3D = c["node"]
		var head: Node3D = c["head"]
		n.position = c["base"] + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * shake * 0.06
		c["next"] -= dt
		if c["next"] <= 0.0:
			c["look"] = randf_range(-0.7, 0.7) if randf() < 0.6 else 0.0
			c["next"] = randf_range(2.0, 7.0)
		head.rotation.y = lerp_angle(head.rotation.y, c["look"], clampf(dt * 2.0, 0.0, 1.0))
		head.rotation.x = sin(t * 0.4 + c["phase"]) * 0.05
	# Lighting: red at night or in an emergency, flicker after close explosions.
	flicker = maxf(0.0, flicker - dt)
	if shake > 0.6:
		flicker = maxf(flicker, 0.8)
	var emergency: bool = s.hull < 40.0 or s.water > 30.0
	var col := Color(1.0, 0.9, 0.74)
	if red or emergency:
		col = Color(1.0, 0.22, 0.14)
	var energy := 1.4 if not (red or emergency) else 1.1
	if flicker > 0.0 and randf() < 0.5:
		energy *= randf_range(0.0, 0.4)
	for l in lights:
		l.light_color = col
		l.light_energy = energy
	for m in lamp_mats:
		m.emission = col
		m.emission_energy_multiplier = 3.0 * energy
	while leak_fx.size() < int(ceil(s.leak * 6.0)) and leak_fx.size() < 6:
		spawn_leak()
	if s.leak <= 0.01:
		for p in leak_fx:
			p.queue_free()
		leak_fx.clear()
	water.visible = s.water > 1.0
	water.position.y = -0.1 + s.water * 0.012
