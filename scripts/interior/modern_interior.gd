extends Node3D
## The near-future boats' command and control centre: one long, low room on
## a deck inside the pressure hull, lit by overhead panels and screens. Ship
## control (two seats with sticks) and the photonics displays forward, the
## sonar stack along the starboard side, fire control to port, the digital
## plot in the middle and the ship's status board aft.
##
## Same public face as the wartime Interior, so the game can use either:
## build(), set_world(), set_active(), update(), level_water(), spawn_leak(),
## `stations`, SPAWN and LADDER. Local space: bow toward -Z, floor at y = 0.

const MeshKit := preload("res://scripts/build/mesh_kit.gd")
const CrewBuilder := preload("res://scripts/build/crew_builder.gd")
const Fx := preload("res://scripts/view/fx.gd")
const Instruments := preload("res://scripts/ui/instruments.gd")
const Tex := preload("res://scripts/interior/textures.gd")
const P := preload("res://scripts/interior/props.gd")

const LAYER := 2
const Z0 := -9.0
const Z1 := 7.0
const W := 3.4            # half width at the floor
const H := 2.45           # deck to overhead
const SPAWN := Vector3(0.9, 0.05, -1.5)
const LADDER := Vector3(0.0, 0.05, 5.5)

var nat: Dictionary
var world
var mats: Dictionary
var stations: Array = []
var panels: Array = []
var lights: Array = []
var lamp_mats: Array = []
var screen_mats: Array = []
var crew: Array = []
var leak_fx: Array = []
var sticks: Array = []
var water: MeshInstance3D
var red := false
var flicker := 0.0
var t := 0.0
var crew_i := 0
var _body: StaticBody3D


func build(nation: Dictionary) -> void:
	nat = nation
	mats = Tex.materials("us").duplicate()
	mats["console"] = MeshKit.mat(Color(0.16, 0.17, 0.18), 0.55, 0.2)
	mats["bezel"] = MeshKit.mat(Color(0.06, 0.065, 0.07), 0.4, 0.3)
	mats["panelwall"] = MeshKit.mat(Color(0.74, 0.76, 0.77), 0.7)
	mats["deck"] = MeshKit.mat(Color(0.20, 0.22, 0.23), 0.85)
	mats["seat"] = MeshKit.mat(Color(0.10, 0.11, 0.13), 0.9)
	var lamp := MeshKit.mat(Color(0.95, 0.97, 1.0), 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(0.85, 0.9, 1.0)
	lamp.emission_energy_multiplier = 2.5
	mats["lamp"] = lamp
	lamp_mats.append(lamp)
	_body = StaticBody3D.new()
	add_child(_body)
	var k := MeshKit.new(mats)
	_room(k)
	_ship_control(k)
	_photonics(k)
	_sonar(k)
	_fire_control(k)
	_plot(k)
	_aft(k)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	add_child(mi)
	_lights()
	_water()
	_set_layers(self)


# ------------------------------------------------------------------ room
func _room(k: MeshKit) -> void:
	var zc := (Z0 + Z1) * 0.5
	var L := Z1 - Z0
	# Deck in non-skid grey with a lighter walkway down the middle.
	k.box("deck", Vector3(0, -0.05, zc), Vector3(W * 2.0, 0.1, L))
	k.box("steel", Vector3(0, 0.002, zc), Vector3(1.4, 0.004, L - 0.4))
	# Walls lean in toward the overhead, following the hull.
	for sd in [-1.0, 1.0]:
		var s: float = sd
		k.quad("panelwall", Vector3(s * W, 0, Z0), Vector3(s * W, 0, Z1), Vector3(s * (W - 0.35), H, Z1),
			Vector3(s * (W - 0.35), H, Z0), Vector3(0, 1, zc))
		# Panel seams.
		var z := Z0 + 1.2
		while z < Z1:
			k.box("dark", Vector3(s * (W - 0.18), H * 0.5, z), Vector3(0.02, H, 0.02), Basis(Vector3(0, 0, 1), -s * 0.14))
			z += 1.2
		# Cable tray along the top of the wall.
		k.box("steel", Vector3(s * (W - 0.55), H - 0.12, zc), Vector3(0.4, 0.06, L))
		_solid(Vector3(s * (W + 0.1), 1.2, zc), Vector3(0.3, 2.6, L))
	# Overhead: panels, light strips and pipes.
	k.box("panelwall", Vector3(0, H + 0.02, zc), Vector3(W * 2.0, 0.04, L))
	for x in [-1.6, 1.6]:
		k.box("lamp", Vector3(x, H - 0.03, zc), Vector3(0.22, 0.03, L - 1.0))
	for x in [-0.6, 0.0, 0.6]:
		P.pipe(k, Vector3(x, H - 0.15, Z0), Vector3(x, H - 0.15, Z1), 0.05, "steel", 2.4)
	# End bulkheads with doors.
	for zz in [Z0, Z1]:
		var ze: float = zz
		var face := 1.0 if ze < 0.0 else -1.0
		k.quad("panelwall", Vector3(-W, 0, ze), Vector3(W, 0, ze), Vector3(W - 0.35, H, ze), Vector3(-W + 0.35, H, ze),
			Vector3(0, 1, ze + face))
		k.box("dark", Vector3(0, 0.95, ze + face * 0.02), Vector3(0.9, 1.9, 0.04))
		k.box("steel", Vector3(0.32, 1.0, ze + face * 0.05), Vector3(0.06, 0.12, 0.05))
		_solid(Vector3(0, 1.2, ze - face * 0.15), Vector3(W * 2.0, 2.6, 0.3))
	_solid(Vector3(0, -0.15, (Z0 + Z1) * 0.5), Vector3(W * 2.2, 0.3, L + 1.0))
	_solid(Vector3(0, H + 0.2, (Z0 + Z1) * 0.5), Vector3(W * 2.2, 0.3, L + 1.0))
	# The trunk up to the sail: a ladder, its hatch shut.
	P.ladder(k, P.face(Vector3(0, 0, LADDER.z + 0.4), Vector3(0, 0, -1)), H)
	k.cyl("steel", Vector3(0, H, LADDER.z + 0.4), Vector3(0, H + 0.05, LADDER.z + 0.4), 0.45, 0.45, 16)


func _screen(k: MeshKit, kind: String, pos: Vector3, size: Vector2, normal: Vector3, px: int, py: int) -> void:
	k.box("bezel", pos - normal * 0.03, Vector3(size.x + 0.06, size.y + 0.06, 0.05) if absf(normal.z) > 0.5
		else Vector3(0.05, size.y + 0.06, size.x + 0.06))
	if kind == "":
		# A dark screen with a faint glow.
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = size
		q.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.02, 0.05, 0.06)
		m.emission_enabled = true
		m.emission = Color(0.05, 0.18, 0.2)
		m.emission_energy_multiplier = 0.8
		q.material_override = m
		q.transform = P.face(pos, normal)
		add_child(q)
		screen_mats.append(m)
		return
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
	m.emission_energy_multiplier = 0.7
	m.roughness = 0.2
	q.material_override = m
	q.transform = P.face(pos, normal)
	add_child(q)
	panels.append({"vp": vp, "ins": ins})


## A console: sloped desk, keyboard shelf and a pair of screens above.
func _console(k: MeshKit, x: float, z: float, facing: Vector3, kinds: Array, width := 1.1) -> void:
	var side := Vector3(-facing.z, 0, facing.x)
	var base := Vector3(x, 0, z)
	var back := base - facing * 0.35
	k.box("console", base - facing * 0.15 + Vector3(0, 0.38, 0), Vector3(width, 0.76, 0.6) if absf(facing.z) > 0.5
		else Vector3(0.6, 0.76, width))
	k.box("bezel", base + facing * 0.12 + Vector3(0, 0.78, 0), Vector3(width * 0.8, 0.03, 0.25) if absf(facing.z) > 0.5
		else Vector3(0.25, 0.03, width * 0.8))
	k.box("console", back + Vector3(0, 1.25, 0), Vector3(width, 0.95, 0.15) if absf(facing.z) > 0.5 else Vector3(0.15, 0.95, width))
	var sw := width / kinds.size() - 0.06
	for i in kinds.size():
		var off := (float(i) - (kinds.size() - 1) * 0.5) * (width / kinds.size())
		_screen(k, kinds[i], back + side * off + Vector3(0, 1.27, 0) + facing * 0.09, Vector2(sw, 0.62),
			facing, int(400.0 * sw / 0.62), 400)
	_solid(base - facing * 0.15 + Vector3(0, 0.6, 0), Vector3(width, 1.2, 0.6) if absf(facing.z) > 0.5 else Vector3(0.6, 1.2, width))


## A watchstander's chair facing his console.
func _chair(k: MeshKit, pos: Vector3, facing: Vector3) -> void:
	k.cyl("steel", pos + Vector3(0, 0.05, 0), pos + Vector3(0, 0.45, 0), 0.05, 0.05, 6)
	k.box("seat", pos + Vector3(0, 0.5, 0), Vector3(0.5, 0.1, 0.5))
	k.box("seat", pos - facing * 0.25 + Vector3(0, 0.85, 0), Vector3(0.5, 0.65, 0.08) if absf(facing.z) > 0.5
		else Vector3(0.08, 0.65, 0.5))


func _man(pose: String, pos: Vector3, yaw: float, hands := {}) -> void:
	var n := CrewBuilder.build(nat["id"], crew_i, pose, hands)
	crew_i += 1
	n.position = pos
	n.rotation.y = yaw
	add_child(n)
	var head: Node3D = n.get_node("Body/Head")
	crew.append({"node": n, "head": head, "base": pos, "phase": randf() * TAU, "look": 0.0, "next": randf_range(2, 8)})


# --------------------------------------------------------------- stations
## Ship control forward to port: pilot and copilot in front of their
## displays, each with a stick for the rudder and planes.
func _ship_control(k: MeshKit) -> void:
	var z := Z0 + 1.3
	for xx in [-2.3, -1.2]:
		var x: float = xx
		_console(k, x, z, Vector3(0, 0, 1), ["gauges" if x < -2.0 else "compass"], 1.0)
		_chair(k, Vector3(x, 0, z + 0.9), Vector3(0, 0, -1))
		var st := Node3D.new()
		st.position = Vector3(x + 0.25, 0.62, z + 0.45)
		var sk := MeshKit.new(mats)
		sk.cyl("black", Vector3.ZERO, Vector3(0, 0.22, 0), 0.025, 0.02, 6)
		sk.box("black", Vector3(0, 0.25, 0), Vector3(0.06, 0.08, 0.05))
		var sm := MeshInstance3D.new()
		sm.mesh = sk.commit()
		st.add_child(sm)
		add_child(st)
		sticks.append(st)
		_man("sit_panel", Vector3(x, 0, z + 0.85), PI, {"r": Vector3(0.25, 0.85, -0.42), "l": Vector3(-0.2, 0.8, -0.35)})
	_screen(k, "depth", Vector3(-1.75, 1.95, Z0 + 0.95), Vector2(0.5, 0.5), Vector3(0, 0, 1), 300, 300)
	_station("helm", Vector3(-1.75, 1.2, z + 1.4), "Check ship control: course, speed and depth")


## The photonics mast displays forward on the centreline: the view from the
## mast, the officer of the deck's station.
func _photonics(k: MeshKit) -> void:
	var z := Z0 + 1.1
	_console(k, 0.6, z, Vector3(0, 0, 1), ["", ""], 1.3)
	_screen(k, "", Vector3(0.6, 2.0, Z0 + 0.12), Vector2(1.5, 0.75), Vector3(0, 0, 1), 0, 0)
	_station("scope", Vector3(0.6, 1.3, z + 1.1), "Use the photonics mast")
	_man("stand", Vector3(1.5, 0, z + 1.4), PI * 0.9)


## The sonar stack: three consoles side by side along the starboard side.
func _sonar(k: MeshKit) -> void:
	var x := W - 0.75
	for i in 3:
		var z := -4.2 + i * 1.25
		_console(k, x, z, Vector3(-1, 0, 0), ["sonar" if i == 1 else ""], 1.15)
		_chair(k, Vector3(x - 0.95, 0, z), Vector3(1, 0, 0))
		_man("sit_panel", Vector3(x - 0.9, 0, z), -PI * 0.5, {"r": Vector3(0.18, 0.8, -0.4), "l": Vector3(-0.18, 0.8, -0.4)})
	_station("sonar", Vector3(x - 1.2, 1.2, -2.95), "Listen on the sonar stack")


## Fire control along the port side: the solution and the weapons.
func _fire_control(k: MeshKit) -> void:
	var x := -W + 0.75
	for i in 3:
		var z := -3.6 + i * 1.25
		_console(k, x, z, Vector3(1, 0, 0), ["tdc" if i == 1 else ""], 1.15)
		_chair(k, Vector3(x + 0.95, 0, z), Vector3(-1, 0, 0))
		if i != 2:
			_man("sit_panel", Vector3(x + 0.9, 0, z), PI * 0.5, {"r": Vector3(0.18, 0.8, -0.4), "l": Vector3(-0.18, 0.8, -0.4)})
	_station("tdc", Vector3(x + 1.2, 1.2, -2.35), "Work fire control")


## The digital plot: a big table screen amidships.
func _plot(k: MeshKit) -> void:
	var z := 1.6
	k.box("console", Vector3(0, 0.45, z), Vector3(1.3, 0.9, 1.8))
	_screen(k, "chart", Vector3(0, 0.915, z), Vector2(1.15, 1.6), Vector3(0, 1, 0), 440, 600)
	_solid(Vector3(0, 0.5, z), Vector3(1.3, 1.0, 1.8))
	_station("chart", Vector3(0.9, 1.0, z), "Study the plot")
	_man("stand", Vector3(-0.95, 0, z + 0.4), PI * 0.5)


## Aft: the ship's status board and the radio room door.
func _aft(k: MeshKit) -> void:
	_screen(k, "damage", Vector3(1.8, 1.45, Z1 - 0.12), Vector2(0.8, 1.15), Vector3(0, 0, -1), 360, 520)
	_station("damage", Vector3(1.8, 1.3, Z1 - 0.9), "Read the ship's status board")
	_screen(k, "tree", Vector3(2.75, 1.5, Z1 - 0.12), Vector2(0.48, 0.7), Vector3(0, 0, -1), 200, 300)
	k.box("console", Vector3(-2.4, 0.5, Z1 - 0.5), Vector3(1.2, 1.0, 0.7))
	_station("radio", Vector3(-2.4, 1.2, Z1 - 1.2), "Check the radio room's traffic")


func _station(name: String, pos: Vector3, prompt: String) -> void:
	stations.append({"name": name, "pos": pos, "prompt": prompt})


func _solid(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = s
	cs.shape = b
	cs.position = c
	_body.add_child(cs)


func _lights() -> void:
	for i in 4:
		var l := OmniLight3D.new()
		l.position = Vector3(-0.8 if i % 2 == 0 else 0.8, H - 0.3, lerpf(Z0 + 2.0, Z1 - 2.0, i / 3.0))
		l.omni_range = 7.0
		l.omni_attenuation = 1.2
		l.light_energy = 1.1
		l.light_color = Color(0.85, 0.9, 1.0)
		l.light_specular = 0.3
		add_child(l)
		lights.append(l)


func _water() -> void:
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(W * 2.0, (Z1 - Z0) * 2.0)
	water.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.2, 0.22, 0.78)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic = 0.3
	water.material_override = m
	water.position = Vector3(0, -0.2, (Z0 + Z1) * 0.5)
	water.visible = false
	add_child(water)


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 1 << (LAYER - 1)
	if n is Light3D:
		(n as Light3D).light_cull_mask = 1 << (LAYER - 1)
	for c in n.get_children():
		_set_layers(c)


# ------------------------------------------------------------------ live
func level_water(pitch: float, roll: float, at_z: float) -> void:
	water.basis = Basis(Vector3(0, 0, 1), -roll) * Basis(Vector3(1, 0, 0), -pitch)
	water.position.z = at_z


func set_world(w) -> void:
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
	p.position = Vector3((-1.0 if randf() < 0.5 else 1.0) * (W - 0.5), H - 0.2, randf_range(Z0 + 1.0, Z1 - 1.0))
	add_child(p)
	_set_layers(p)
	leak_fx.append(p)
	flicker = 1.5


func update(dt: float) -> void:
	if world == null:
		return
	t += dt
	var s = world.sub
	for st in sticks:
		st.rotation.x = lerpf(st.rotation.x, clampf((s.dep_ord - s.depth) * 0.02, -0.4, 0.4), clampf(dt * 3.0, 0.0, 1.0))
		st.rotation.z = lerpf(st.rotation.z, -deg_to_rad(s.rud) * 0.6, clampf(dt * 3.0, 0.0, 1.0))
	var shake: float = world.shake
	for c in crew:
		var n: Node3D = c["node"]
		var head: Node3D = c["head"]
		n.position = c["base"] + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * shake * 0.06
		c["next"] -= dt
		if c["next"] <= 0.0:
			c["look"] = randf_range(-0.6, 0.6) if randf() < 0.6 else 0.0
			c["next"] = randf_range(2.0, 7.0)
		head.rotation.y = lerp_angle(head.rotation.y, c["look"], clampf(dt * 2.0, 0.0, 1.0))
		head.rotation.x = sin(t * 0.4 + c["phase"]) * 0.05
	# Rigged for red at night; red and flashing when she's hurt or a torpedo
	# is coming.
	flicker = maxf(0.0, flicker - dt)
	if shake > 0.6:
		flicker = maxf(flicker, 0.8)
	var alarm: bool = s.hull < 40.0 or s.water > 30.0 or world.threats().size() > 0
	var col := Color(0.85, 0.9, 1.0)
	var energy := 1.1
	if red:
		col = Color(1.0, 0.2, 0.12)
		energy = 0.8
	if alarm:
		col = Color(1.0, 0.18, 0.1)
		energy = 0.6 + 0.5 * absf(sin(t * 3.0))
	if flicker > 0.0 and randf() < 0.5:
		energy *= randf_range(0.0, 0.4)
	for l in lights:
		l.light_color = col
		l.light_energy = energy
	for m in lamp_mats:
		m.emission = col
		m.emission_energy_multiplier = 2.5 * energy
	while leak_fx.size() < int(ceil(s.leak * 6.0)) and leak_fx.size() < 6:
		spawn_leak()
	if s.leak <= 0.01:
		for p in leak_fx:
			p.queue_free()
		leak_fx.clear()
	water.visible = s.water > 1.0
	water.position.y = -0.1 + s.water * 0.012
