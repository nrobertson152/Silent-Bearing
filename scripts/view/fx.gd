extends Node3D
## Short-lived effects: shell splashes, depth-charge eruptions, explosions,
## muzzle flashes, strafing lines and hit sparks. Positions are Godot space.

var items: Array = []
var pending: Array = []
var t := 0.0
var night := false

var m_spray: StandardMaterial3D
var m_smoke: StandardMaterial3D
var m_fire: StandardMaterial3D
var quad: QuadMesh
var col_mesh: CylinderMesh
var ball: SphereMesh


func _init() -> void:
	m_spray = _pmat(Color(0.92, 0.95, 0.96), false)
	m_smoke = _pmat(Color(0.2, 0.2, 0.2), false)
	m_fire = _pmat(Color(1.0, 0.6, 0.25), true)
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	col_mesh = CylinderMesh.new()
	col_mesh.top_radius = 0.35
	col_mesh.bottom_radius = 1.0
	col_mesh.height = 1.0
	col_mesh.radial_segments = 14
	col_mesh.rings = 1
	ball = SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 14
	ball.rings = 8


static var _soft: GradientTexture2D


## Soft round sprite so particles read as puffs rather than squares.
static func soft_tex() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 0.55))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(0.5, 0.0)
		_soft.width = 64
		_soft.height = 64
	return _soft


static func _pmat(c: Color, emissive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = soft_tex()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if emissive else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _solid(c: Color, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emit > 0.0:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func particles(pos: Vector3, mat: Material, amount: int, life: float, vel: Vector2, spread: float,
		size: Vector2, grav: float, fade: Gradient, one_shot := true, dir := Vector3.UP, box := Vector3.ZERO) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.material_override = mat
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.85 if one_shot else 0.0
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = Vector3(0, grav, 0)
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	p.color_ramp = fade
	p.damping_min = 0.4
	p.damping_max = 1.2
	if box != Vector3.ZERO:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = box
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	return p


static func ramp(c0: Color, c1: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	return g


func _track(node: Node, life: float, kind: String, data := {}) -> void:
	items.append({"node": node, "t0": t, "life": life, "kind": kind, "data": data})


# --------------------------------------------------------------- effects
func splash(pos: Vector3, size: float) -> void:
	var h := size * 4.5
	var col := MeshInstance3D.new()
	col.mesh = col_mesh
	var m := _solid(Color(0.9, 0.93, 0.94, 0.85))
	col.material_override = m
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(col)
	col.global_position = Vector3(pos.x, 0, pos.z)
	col.scale = Vector3(size * 0.5, 0.01, size * 0.5)
	_track(col, 3.5, "column", {"h": h, "r": size * 0.5, "mat": m})
	particles(Vector3(pos.x, h * 0.4, pos.z), m_spray, 16, 2.5, Vector2(size * 1.2, size * 2.6), 30.0,
		Vector2(size * 0.6, size * 1.4), -9.8, ramp(Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)))


func explosion(pos: Vector3, size: float, kind: String) -> void:
	var fb := MeshInstance3D.new()
	fb.mesh = ball
	var m := _solid(Color(1.0, 0.65, 0.25, 1.0), 1.0)
	fb.material_override = m
	add_child(fb)
	fb.global_position = pos + Vector3(0, size * 0.8, 0)
	_track(fb, 1.0, "fireball", {"r": size * 5.0, "mat": m})
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.35)
	light.omni_range = size * 60.0
	light.light_energy = 8.0
	add_child(light)
	light.global_position = pos + Vector3(0, size * 2.0, 0)
	_track(light, 0.8, "flash", {"e": 8.0})
	if kind == "torpedo" or kind == "bomb" or kind == "plane_crash" or kind == "ram":
		splash(pos, size * (1.6 if kind == "torpedo" else 1.0))
	particles(pos + Vector3(0, size, 0), m_fire, 18, 1.2, Vector2(size * 1.5, size * 4.0), 70.0,
		Vector2(size * 1.0, size * 2.2), 2.0, ramp(Color(1, 0.8, 0.4, 1), Color(0.6, 0.15, 0.05, 0)))
	particles(pos + Vector3(0, size * 1.5, 0), m_smoke, 22, 10.0, Vector2(size * 0.6, size * 1.6), 25.0,
		Vector2(size * 2.0, size * 4.5), 1.2, ramp(Color(0.12, 0.11, 0.1, 0.85), Color(0.25, 0.25, 0.25, 0)))


func depth_charge(pos: Vector3, depth: float) -> void:
	var dome := MeshInstance3D.new()
	dome.mesh = ball
	var m := _solid(Color(0.86, 0.92, 0.92, 0.9))
	dome.material_override = m
	add_child(dome)
	dome.global_position = Vector3(pos.x, 0, pos.z)
	var r := clampf(30.0 - depth * 0.12, 8.0, 26.0)
	_track(dome, 3.0, "dome", {"r": r, "mat": m})
	if depth < 90.0:
		pending.append({"at": t + 0.35, "fn": "splash", "pos": pos, "size": clampf(9.0 - depth * 0.08, 2.5, 8.0)})


func muzzle(pos: Vector3, cal: float) -> void:
	var s := clampf(cal / 60.0, 1.0, 6.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.4)
	light.omni_range = s * 40.0
	light.light_energy = 6.0
	add_child(light)
	light.global_position = pos
	_track(light, 0.18, "flash", {"e": 6.0})
	var fb := MeshInstance3D.new()
	fb.mesh = ball
	var m := _solid(Color(1.0, 0.8, 0.45, 1.0), 1.0)
	fb.material_override = m
	add_child(fb)
	fb.global_position = pos
	_track(fb, 0.15, "fireball", {"r": s * 3.0, "mat": m})
	particles(pos, m_smoke, 8, 4.0, Vector2(1.0, 3.0), 50.0, Vector2(s * 2.0, s * 4.0), 0.5,
		ramp(Color(0.6, 0.6, 0.58, 0.6), Color(0.7, 0.7, 0.7, 0)))


func strafe(from: Vector3, to: Vector3) -> void:
	for i in 10:
		var f := float(i) / 9.0
		pending.append({"at": t + f * 0.6, "fn": "bullet", "pos": from.lerp(to, f) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))})


func spark(pos: Vector3) -> void:
	particles(pos, m_fire, 8, 0.5, Vector2(8, 20), 180.0, Vector2(0.6, 1.2), -5.0,
		ramp(Color(1, 0.9, 0.5, 1), Color(1, 0.4, 0.1, 0)))


func _bullet(pos: Vector3) -> void:
	particles(Vector3(pos.x, 0.2, pos.z), m_spray, 5, 0.8, Vector2(3, 6), 12.0, Vector2(0.3, 0.6), -9.8,
		ramp(Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)))


func update(dt: float) -> void:
	t += dt
	var keep_p := []
	for p in pending:
		if t >= p["at"]:
			match p["fn"]:
				"splash":
					splash(p["pos"], p["size"])
				"bullet":
					_bullet(p["pos"])
		else:
			keep_p.append(p)
	pending = keep_p
	var keep := []
	for it in items:
		var node: Node3D = it["node"]
		var a: float = (t - it["t0"]) / it["life"]
		var d: Dictionary = it["data"]
		if a >= 1.0:
			node.queue_free()
			continue
		match it["kind"]:
			"column":
				var rise := minf(1.0, a * 5.0)
				var h: float = d["h"] * rise * (1.0 - maxf(0.0, a - 0.35) * 0.6)
				node.scale = Vector3(d["r"] * (1.0 + a), maxf(h, 0.01), d["r"] * (1.0 + a))
				node.position.y = h * 0.5
				d["mat"].albedo_color.a = 0.85 * (1.0 - smoothstep(0.3, 1.0, a))
			"dome":
				var s: float = d["r"] * minf(1.0, a * 4.0)
				node.scale = Vector3(s, s * 0.45, s)
				d["mat"].albedo_color.a = 0.9 * (1.0 - a)
			"fireball":
				var s: float = d["r"] * (0.3 + a)
				node.scale = Vector3(s, s, s)
				d["mat"].albedo_color.a = 1.0 - a
			"flash":
				node.light_energy = d["e"] * (1.0 - a)
		keep.append(it)
	items = keep
	for c in get_children():
		if c is CPUParticles3D and c.one_shot and not c.emitting:
			c.queue_free()
