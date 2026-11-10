extends Node3D
## Effects: shell splashes, depth-charge eruptions, explosions, muzzle blasts,
## strafing, hit sparks, funnel smoke, ship fires, bow spray, magazine
## explosions and rocket-thrown torpedoes. Built from
## billboard particles drawn by shaders/puff.gdshader (lit smoke and spray) and
## shaders/flame.gdshader (fire), plus brief lights, and foam patches on the
## wake map. Positions are Godot space.

const MeshKit := preload("res://scripts/build/mesh_kit.gd")
const Wakes := preload("res://scripts/view/wakes.gd")

var items: Array = []
var pending: Array = []
var flights: Array = []    # rockets in the air: {"node", "from", "to", "dur", "t", "smoke"}
var t := 0.0
var night := false
var wind := Vector3(1, 0, 0)
var wakes: Wakes

var m_spray: ShaderMaterial
var m_column: ShaderMaterial
var m_mist: ShaderMaterial
var m_smoke: ShaderMaterial
var m_soot: ShaderMaterial
var m_steam: ShaderMaterial
var m_cloud: ShaderMaterial
var m_fire: ShaderMaterial
var m_flash: ShaderMaterial
var m_debris: StandardMaterial3D
var m_ember: StandardMaterial3D
var quad: QuadMesh
var chunk: BoxMesh
var fires: Array = []


func _init() -> void:
	m_spray = puff_mat(Color(0.93, 0.95, 0.96), 2.5, 0.8, 0.35, 1.5)
	m_column = puff_mat(Color(0.95, 0.97, 0.98), 2.0, 0.7, 0.12, 1.5)
	m_mist = puff_mat(Color(0.9, 0.93, 0.95, 0.7), 1.2, 0.7, 1.0, 4.0)
	m_smoke = puff_mat(Color(0.2, 0.19, 0.18), 1.2, 0.95, 0.0, 6.0)
	m_soot = puff_mat(Color(0.07, 0.065, 0.06), 1.0, 1.0, 0.0, 8.0)
	m_steam = puff_mat(Color(0.82, 0.82, 0.8, 0.8), 1.4, 0.9, 0.6, 6.0)
	# Huge smoke clouds fade out over tens of metres where they meet the sea.
	m_cloud = puff_mat(Color(0.08, 0.075, 0.07), 0.8, 1.0, 0.0, 70.0)
	m_fire = flame_mat(1.0, 0.5)
	m_flash = flame_mat(2.5, 0.0)
	m_debris = StandardMaterial3D.new()
	m_debris.albedo_color = Color(0.08, 0.08, 0.08)
	m_debris.roughness = 0.9
	m_ember = StandardMaterial3D.new()
	m_ember.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_ember.albedo_color = Color(3.0, 1.8, 0.7)
	m_ember.albedo_texture = soft_tex()
	m_ember.vertex_color_use_as_albedo = true
	m_ember.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_ember.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	chunk = BoxMesh.new()
	chunk.size = Vector3(0.6, 0.35, 0.9)


static func puff_mat(c: Color, churn: float, lumpy: float, thin: float, soft: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/puff.gdshader")
	m.set_shader_parameter("tint", c)
	m.set_shader_parameter("scatter", 0.15 + thin * 1.1)
	m.set_shader_parameter("churn", churn)
	m.set_shader_parameter("lumpy", lumpy)
	m.set_shader_parameter("thin", thin)
	m.set_shader_parameter("soft", soft)
	return m


static func flame_mat(heat: float, soot: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/flame.gdshader")
	m.set_shader_parameter("heat", heat)
	m.set_shader_parameter("soot", soot)
	return m


## Funnel smoke in a given colour.
func smoke_mat(c: Color) -> ShaderMaterial:
	return puff_mat(c, 1.0, 0.95, 0.15, 6.0)


static var _soft: GradientTexture2D


## Soft round sprite (used by the boat's interior spray).
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


static func ramp(c0: Color, c1: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	return g


## Colour ramp through several (offset, colour) stops.
static func stops(pts: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(pts.map(func(p): return p[0]))
	g.colors = PackedColorArray(pts.map(func(p): return p[1]))
	return g


static func grow(a: float, b: float, c := -1.0) -> Curve:
	var cv := Curve.new()
	cv.max_value = maxf(maxf(a, b), c) + 0.01
	cv.add_point(Vector2(0, a))
	if c >= 0.0:
		cv.add_point(Vector2(0.25, b))
		cv.add_point(Vector2(1, c))
	else:
		cv.add_point(Vector2(1, b))
	return cv


func particles(pos: Vector3, mat: Material, amount: int, life: float, vel: Vector2, spread: float,
		size: Vector2, grav: Vector3, fade: Gradient, one_shot := true, dir := Vector3.UP, box := Vector3.ZERO,
		scale := Vector3(0.5, 1.0, 1.6), damp := Vector2(0.4, 1.2), mesh: Mesh = null) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh if mesh != null else quad
	p.material_override = mat
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	p.randomness = 0.3
	p.lifetime_randomness = 0.3
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = grav
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.scale_amount_curve = grow(scale.x, scale.y, scale.z)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -20.0
	p.angular_velocity_max = 20.0
	p.color_ramp = fade
	p.damping_min = damp.x
	p.damping_max = damp.y
	if box != Vector3.ZERO:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = box
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	return p


func _light(pos: Vector3, col: Color, rng: float, energy: float, life: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = col
	light.omni_range = rng
	light.omni_attenuation = 1.6
	light.light_energy = energy
	light.light_volumetric_fog_energy = 4.0
	light.shadow_enabled = false
	add_child(light)
	light.global_position = pos
	_track(light, life, "flash", {"e": energy})


func _track(node: Node, life: float, kind: String, data := {}) -> void:
	items.append({"node": node, "t0": t, "life": life, "kind": kind, "data": data})


func _patch(pos: Vector3, radius: float, life: float, peak := 1.0, ring := false) -> void:
	if wakes != null:
		wakes.patch(pos, radius, life, peak, ring)


# --------------------------------------------------------------- effects
## A shell or bomb hitting the water: a tall column of spray thrown straight
## up (droplets at a spread of speeds fill it from foot to top), a crown of
## spray flung out round its base, mist rolling away and a foam patch.
func splash(pos: Vector3, size: float) -> void:
	var h := size * 4.5
	var v := sqrt(2.0 * 9.8 * h)
	var base := Vector3(pos.x, 0.3, pos.z)
	var n := int(clampf(size * 9.0, 24.0, 110.0))
	particles(base, m_column, n, v / 9.8 * 2.0, Vector2(v * 0.25, v), 3.0,
		Vector2(size * 0.36, size * 0.62), Vector3(0, -9.8, 0),
		stops([[0.0, Color(1, 1, 1, 1.0)], [0.55, Color(1, 1, 1, 0.85)], [1.0, Color(1, 1, 1, 0)]]),
		true, Vector3.UP, Vector3(size * 0.12, 0.1, size * 0.12), Vector3(0.7, 1.2, 2.6), Vector2(0.0, 0.3))
	particles(base, m_spray, n / 2, v / 9.8 * 0.8, Vector2(v * 0.12, v * 0.32), 38.0,
		Vector2(size * 0.3, size * 0.55), Vector3(0, -9.8, 0),
		stops([[0.0, Color(1, 1, 1, 0.85)], [0.6, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0)]]),
		true, Vector3.UP, Vector3(size * 0.2, 0.1, size * 0.2), Vector3(0.6, 1.2, 2.0), Vector2(0.0, 0.4))
	particles(base, m_mist, int(clampf(size * 2.5, 8.0, 30.0)), 5.0, Vector2(size * 0.4, size * 1.2), 85.0,
		Vector2(size * 0.9, size * 1.6), Vector3(wind.x, 0.5, wind.z), ramp(Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)),
		true, Vector3.UP, Vector3(size * 0.3, 0.2, size * 0.3), Vector3(0.5, 1.5, 2.8), Vector2(0.8, 1.6))
	_patch(pos, size * 1.6, 14.0, 0.9)


## An explosion: flash, fireball, a column of smoke, debris and embers, and
## for hits at the waterline a white column and a shock ring on the sea.
func explosion(pos: Vector3, size: float, kind: String) -> void:
	var big := kind in ["torpedo", "magazine", "ram"]
	_light(pos + Vector3(0, size * 2.0, 0), Color(1.0, 0.62, 0.32), size * 70.0, 14.0 if big else 8.0, 0.9)
	particles(pos + Vector3(0, size * 0.8, 0), m_flash, 3, 0.18, Vector2(0, 0), 0.0, Vector2(size * 7.0, size * 9.0),
		Vector3.ZERO, ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 0)), true, Vector3.UP, Vector3.ZERO, Vector3(0.6, 1.0, 1.2))
	if kind in ["torpedo", "bomb", "plane_crash", "ram"]:
		splash(pos, size * (1.7 if kind == "torpedo" else 1.0))
		_patch(pos, size * 2.0, 3.0, 1.0, true)
	# Fireball: hot puffs flung out fast, slowed by the air, cooling to soot.
	particles(pos + Vector3(0, size, 0), m_fire, int(clampf(size * 2.5, 10.0, 30.0)), 1.4, Vector2(size * 1.5, size * 4.5), 180.0,
		Vector2(size * 1.2, size * 2.6), Vector3(0, 3.0, 0),
		stops([[0.0, Color(1, 1, 1, 1)], [0.5, Color(0.6, 1, 1, 0.9)], [1.0, Color(0.1, 1, 1, 0)]]),
		true, Vector3.UP, Vector3.ZERO, Vector3(0.4, 1.2, 1.8), Vector2(3.0, 5.0))
	# Smoke column drifting downwind.
	var drift := wind * 1.6 + Vector3(0, 1.4, 0)
	particles(pos + Vector3(0, size * 1.5, 0), m_soot, int(clampf(size * 2.5, 12.0, 36.0)), 14.0, Vector2(size * 0.6, size * 1.8), 30.0,
		Vector2(size * 2.2, size * 4.0), drift,
		stops([[0.0, Color(1, 1, 1, 0.0)], [0.06, Color(1, 1, 1, 0.9)], [0.5, Color(1.3, 1.3, 1.3, 0.6)], [1.0, Color(1.8, 1.8, 1.8, 0)]]),
		true, Vector3.UP, Vector3(size * 0.5, size * 0.3, size * 0.5), Vector3(0.5, 1.6, 3.4), Vector2(0.6, 1.4))
	# Debris and embers on ballistic arcs.
	particles(pos + Vector3(0, size, 0), m_debris, int(clampf(size * 1.5, 6.0, 20.0)), 3.0, Vector2(size * 3.0, size * 7.0), 55.0,
		Vector2(0.4, 1.4) * clampf(size / 6.0, 0.6, 2.5), Vector3(0, -9.8, 0), ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 1)),
		true, Vector3.UP, Vector3.ZERO, Vector3(1, 1, 1), Vector2(0.0, 0.2), chunk)
	particles(pos + Vector3(0, size, 0), m_ember, int(clampf(size * 3.0, 10.0, 40.0)), 2.2, Vector2(size * 2.0, size * 6.0), 70.0,
		Vector2(0.5, 1.0), Vector3(0, -6.0, 0), ramp(Color(1.0, 0.85, 0.5, 1), Color(1.0, 0.3, 0.05, 0)),
		true, Vector3.UP, Vector3.ZERO, Vector3(1, 1, 0.6), Vector2(0.2, 0.6))


## A magazine going up: a blinding flash, a jet of flame driven hundreds of
## feet into the sky, a towering cloud of smoke spreading at its top, and
## wreckage raining down into the sea for seconds afterwards. `size` is about
## a seventh of the ship's length.
func magazine(pos: Vector3, size: float) -> void:
	var s := size
	var k := sqrt(s / 30.0)
	_light(pos + Vector3(0, s * 3.0, 0), Color(1.0, 0.66, 0.36), s * 150.0, 28.0, 2.4)
	particles(pos + Vector3(0, s * 1.5, 0), m_flash, 4, 0.45, Vector2(0, 0), 0.0, Vector2(s * 9.0, s * 13.0),
		Vector3.ZERO, ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 0)), true, Vector3.UP, Vector3.ZERO, Vector3(0.6, 1.0, 1.3))
	# The jet: flame and burning cordite driven straight up out of the hull.
	particles(pos, m_fire, 48, 2.8, Vector2(45.0, 100.0) * k, 9.0, Vector2(s * 0.9, s * 2.0), Vector3(0, -3.0, 0),
		stops([[0.0, Color(1, 1, 1, 1)], [0.45, Color(0.75, 1, 1, 0.95)], [1.0, Color(0.15, 1, 1, 0)]]),
		true, Vector3.UP, Vector3(s * 0.25, s * 0.2, s * 0.7), Vector3(0.5, 1.3, 2.2), Vector2(16.0, 26.0) * k)
	# A low fireball rolling out over the water.
	particles(pos + Vector3(0, s * 0.6, 0), m_fire, 26, 1.8, Vector2(s * 0.8, s * 2.2), 85.0, Vector2(s * 1.6, s * 3.0),
		Vector3(0, 2.0, 0), stops([[0.0, Color(1, 1, 1, 1)], [0.5, Color(0.6, 1, 1, 0.9)], [1.0, Color(0.1, 1, 1, 0)]]),
		true, Vector3.UP, Vector3(s * 0.6, s * 0.3, s * 1.2), Vector3(0.4, 1.2, 1.8), Vector2(2.0, 4.0))
	# The smoke: a column that climbs and spreads at the top, drifting downwind.
	particles(pos + Vector3(0, s * 2.0, 0), m_cloud, 50, 45.0, Vector2(28.0, 60.0) * k, 8.0, Vector2(s * 1.4, s * 2.6),
		wind * 0.6 + Vector3(0, 0.3, 0),
		stops([[0.0, Color(1, 1, 1, 0.0)], [0.03, Color(1, 1, 1, 0.95)], [0.4, Color(1.2, 1.2, 1.2, 0.85)], [1.0, Color(1.7, 1.7, 1.7, 0)]]),
		true, Vector3.UP, Vector3(s * 0.4, s * 1.0, s * 0.8), Vector3(0.4, 1.8, 3.2), Vector2(1.4, 2.0) * k)
	particles(pos + Vector3(0, s * 8.0, 0), m_cloud, 30, 45.0, Vector2(4.0, 14.0) * k, 70.0, Vector2(s * 3.0, s * 5.0),
		wind * 0.7 + Vector3(0, 0.1, 0),
		stops([[0.0, Color(1, 1, 1, 0.0)], [0.12, Color(1, 1, 1, 0.9)], [0.5, Color(1.3, 1.3, 1.3, 0.7)], [1.0, Color(1.8, 1.8, 1.8, 0)]]),
		true, Vector3.UP, Vector3(s * 1.2, s * 1.0, s * 1.2), Vector3(0.5, 1.8, 3.6), Vector2(0.5, 1.0))
	# Wreckage and embers flung high, falling back into the sea.
	particles(pos + Vector3(0, s, 0), m_debris, 44, 9.0, Vector2(s * 1.2, s * 2.8), 60.0,
		Vector2(0.6, 2.2) * clampf(s / 12.0, 0.8, 3.0), Vector3(0, -9.8, 0), ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 1)),
		true, Vector3.UP, Vector3(s * 0.3, s * 0.3, s * 0.8), Vector3(1, 1, 1), Vector2(0.0, 0.3), chunk)
	particles(pos + Vector3(0, s, 0), m_ember, 70, 4.5, Vector2(s * 1.0, s * 3.2), 75.0, Vector2(0.8, 1.6),
		Vector3(0, -7.0, 0), ramp(Color(1.0, 0.85, 0.5, 1), Color(1.0, 0.3, 0.05, 0)),
		true, Vector3.UP, Vector3(s * 0.3, s * 0.3, s * 0.8), Vector3(1, 1, 0.6), Vector2(0.2, 0.6))
	for i in 14:
		var r := s * randf_range(1.5, 7.0)
		var a := randf() * TAU
		pending.append({"at": t + randf_range(2.5, 8.0), "fn": "splash",
			"pos": Vector3(pos.x + cos(a) * r, 0.0, pos.z + sin(a) * r), "size": randf_range(1.4, 3.6)})
	_patch(pos, s * 3.5, 6.0, 1.0, true)
	_patch(pos, s * 2.6, 45.0, 1.0)


## A rocket-thrown torpedo: it leaps out of a launch cell in a gout of smoke,
## arcs out to where the sub was last heard and drops into the sea.
func rocket(from: Vector3, to: Vector3, dur: float) -> void:
	particles(from, m_soot, 18, 6.0, Vector2(3.0, 9.0), 25.0, Vector2(4.0, 8.0), wind * 1.2 + Vector3(0, 1.0, 0),
		stops([[0.0, Color(1, 1, 1, 0.0)], [0.06, Color(1.3, 1.3, 1.3, 0.85)], [1.0, Color(1.6, 1.6, 1.6, 0)]]),
		true, Vector3.UP, Vector3(1.5, 0.5, 1.5), Vector3(0.4, 1.6, 2.6), Vector2(0.6, 1.2))
	_light(from + Vector3(0, 6, 0), Color(1.0, 0.7, 0.4), 120.0, 6.0, 0.6)
	var n := Node3D.new()
	add_child(n)
	n.global_position = from
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.28
	cm.height = 6.0
	body.mesh = cm
	body.rotation.x = PI * 0.5
	body.material_override = MeshKit.mat(Color(0.75, 0.76, 0.74), 0.6)
	n.add_child(body)
	var flame := CPUParticles3D.new()
	flame.mesh = quad
	flame.material_override = m_fire
	flame.amount = 24
	flame.lifetime = 0.35
	flame.local_coords = false
	flame.direction = Vector3(0, 0, 1)
	flame.spread = 8.0
	flame.initial_velocity_min = 10.0
	flame.initial_velocity_max = 18.0
	flame.gravity = Vector3.ZERO
	flame.scale_amount_min = 1.2
	flame.scale_amount_max = 2.0
	flame.color_ramp = ramp(Color(1, 1, 1, 1), Color(0.4, 1, 1, 0))
	flame.position = Vector3(0, 0, 3.2)
	n.add_child(flame)
	var smoke := funnel_smoke(n, Vector3(0, 0, 3.5), m_soot, 1.4)
	smoke.amount = 90
	smoke.lifetime = 9.0
	smoke.gravity = wind * 0.8 + Vector3(0, 0.3, 0)
	flights.append({"node": n, "from": from, "to": to, "dur": maxf(dur, 1.0), "t": 0.0, "smoke": smoke, "flame": flame})


func _fly(dt: float) -> void:
	var keep := []
	for f in flights:
		f["t"] = float(f["t"]) + dt
		var k := clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		var a: Vector3 = f["from"]
		var b: Vector3 = f["to"]
		var apex := clampf(a.distance_to(b) * 0.12, 300.0, 1600.0)
		var p := a.lerp(b, k) + Vector3(0, 4.0 * apex * k * (1.0 - k), 0)
		var p2 := a.lerp(b, minf(k + 0.01, 1.0)) + Vector3(0, 4.0 * apex * minf(k + 0.01, 1.0) * (1.0 - minf(k + 0.01, 1.0)), 0)
		var n: Node3D = f["node"]
		if p2.distance_to(p) > 0.01:
			n.look_at_from_position(p, p2 + (p2 - p) * 10.0, Vector3.UP)
		else:
			n.global_position = p
		# The motor burns out after the first part of the flight.
		(f["flame"] as CPUParticles3D).emitting = k < 0.35
		(f["smoke"] as CPUParticles3D).emitting = k < 0.45
		if k >= 1.0:
			splash(Vector3(b.x, 0.0, b.z), 1.6)
			n.queue_free()
		else:
			keep.append(f)
	flights = keep


## A missile or surface-to-air missile airframe with its motor flame and a
## smoke trail. Returns {"node", "meshes", "flame", "smoke"}; the node faces -Z.
func missile_body(kind: String) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	var sam := kind == "sam"
	var big := kind == "trident"
	var length := 6.6 if sam else (6.2 if kind == "tomahawk" else (13.4 if big else 4.6))
	var r := 0.23 if sam else (0.27 if kind == "tomahawk" else (1.05 if big else 0.17))
	var mat := MeshKit.mat(Color(0.86, 0.86, 0.83) if sam or big else Color(0.42, 0.44, 0.45), 0.55, 0.2)
	var meshes := []
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * (0.55 if big else 0.3)
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 10
	body.mesh = cm
	body.rotation.x = -PI * 0.5
	body.material_override = mat
	n.add_child(body)
	meshes.append(body)
	# Wings (cruise missiles) or fins (all), as thin plates.
	var plates := [[Vector3(length * 0.5 if not sam else 1.0, 0.05, 0.5), Vector3(0, 0, 0.3 if not sam else 1.6)],
		[Vector3(0.05, 1.0, 0.45), Vector3(0, 0, length * 0.44)], [Vector3(1.0, 0.05, 0.45), Vector3(0, 0, length * 0.44)]]
	if big:
		plates = []
	for pl in plates:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pl[0]
		mi.mesh = bm
		mi.position = pl[1]
		mi.material_override = mat
		n.add_child(mi)
		meshes.append(mi)
	var flame := CPUParticles3D.new()
	flame.mesh = quad
	flame.material_override = m_fire
	flame.amount = 18
	flame.lifetime = 0.25
	flame.local_coords = false
	flame.direction = Vector3(0, 0, 1)
	flame.spread = 6.0
	flame.initial_velocity_min = 14.0
	flame.initial_velocity_max = 22.0
	flame.gravity = Vector3.ZERO
	flame.scale_amount_min = 0.9 if sam else (4.5 if big else 1.3)
	flame.scale_amount_max = 1.5 if sam else (8.0 if big else 2.2)
	if big:
		flame.amount = 40
		flame.lifetime = 0.5
		flame.initial_velocity_min = 30.0
		flame.initial_velocity_max = 45.0
	flame.color_ramp = ramp(Color(1, 1, 1, 1), Color(0.4, 1, 1, 0))
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.position = Vector3(0, 0, length * 0.5 + 0.3)
	n.add_child(flame)
	# Enough puffs, close enough together, to read as a trail at their speed.
	var smoke := funnel_smoke(n, Vector3(0, 0, length * 0.5 + 0.8), m_steam, 1.8 if sam else (7.0 if big else 1.5))
	smoke.amount = 200 if sam else (900 if big else 70)
	smoke.lifetime = 2.6 if sam else (18.0 if big else 8.0)
	smoke.direction = Vector3(0, 0, 1)
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 2.0
	smoke.gravity = wind * 0.7 + Vector3(0, 0.15, 0)
	smoke.color_ramp = stops([[0.0, Color(1, 1, 1, 0.0)], [0.04, Color(1.2, 1.2, 1.2, 0.85)], [0.5, Color(1.2, 1.2, 1.2, 0.45)], [1.0, Color(1.3, 1.3, 1.3, 0)]])
	var rec := {"node": n, "meshes": meshes, "flame": flame, "smoke": smoke}
	if big:
		# The first stage's glare lights up its own smoke at night.
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.75, 0.45)
		glow.omni_range = 450.0
		glow.light_energy = 10.0
		glow.shadow_enabled = false
		glow.position = Vector3(0, 0, length * 0.5 + 4.0)
		glow.visible = false
		n.add_child(glow)
		rec["light"] = glow
	return rec


## A missile gone (hit, shot down or into the sea): the airframe vanishes and
## its trail is left to drift away.
func drop_missile(rec: Dictionary) -> void:
	for mi in rec["meshes"]:
		(mi as Node3D).visible = false
	(rec["flame"] as CPUParticles3D).emitting = false
	(rec["smoke"] as CPUParticles3D).emitting = false
	if rec.has("light"):
		(rec["light"] as Node3D).visible = false
	var n: Node3D = rec["node"]
	get_tree().create_timer(9.0).timeout.connect(n.queue_free)


## A missile bursting out of the sea from a submerged boat.
func broach(pos: Vector3) -> void:
	splash(Vector3(pos.x, 0.0, pos.z), 2.4)
	particles(Vector3(pos.x, 1.0, pos.z), m_steam, 22, 7.0, Vector2(2.0, 8.0), 35.0, Vector2(3.0, 6.0), wind * 1.0 + Vector3(0, 0.8, 0),
		stops([[0.0, Color(1, 1, 1, 0.0)], [0.05, Color(1.2, 1.2, 1.2, 0.85)], [1.0, Color(1.3, 1.3, 1.3, 0)]]),
		true, Vector3.UP, Vector3(2.0, 0.5, 2.0), Vector3(0.5, 1.4, 2.6), Vector2(0.6, 1.4))
	_light(pos + Vector3(0, 6, 0), Color(1.0, 0.75, 0.45), 90.0, 5.0, 0.5)


## A ballistic missile test launch: the sea heaves as the gas charge throws
## her clear, a great burst of spray and steam, and the first stage's glare.
func trident_launch(pos: Vector3) -> void:
	splash(Vector3(pos.x, 0.0, pos.z), 6.0)
	particles(Vector3(pos.x, 2.0, pos.z), m_steam, 40, 14.0, Vector2(4.0, 14.0), 40.0, Vector2(8.0, 16.0), wind * 1.0 + Vector3(0, 1.2, 0),
		stops([[0.0, Color(1, 1, 1, 0.0)], [0.05, Color(1.25, 1.25, 1.25, 0.9)], [1.0, Color(1.35, 1.35, 1.35, 0)]]),
		true, Vector3.UP, Vector3(6.0, 1.0, 6.0), Vector3(0.5, 1.5, 3.0), Vector2(0.4, 1.0))
	_patch(pos, 30.0, 40.0, 1.0)
	_patch(pos, 22.0, 4.0, 1.0, true)
	pending.append({"at": t + 1.4, "fn": "flash", "pos": pos + Vector3(0, 30, 0)})


## A surface-to-air missile leaving its cell: a flash and a gout of smoke.
func cell_launch(pos: Vector3) -> void:
	particles(pos, m_steam, 16, 5.0, Vector2(2.0, 7.0), 30.0, Vector2(3.0, 6.0), wind * 1.2 + Vector3(0, 0.6, 0),
		stops([[0.0, Color(1, 1, 1, 0.0)], [0.05, Color(1.2, 1.2, 1.2, 0.9)], [1.0, Color(1.3, 1.3, 1.3, 0)]]),
		true, Vector3.UP, Vector3(1.5, 0.5, 1.5), Vector3(0.5, 1.4, 2.6), Vector2(0.6, 1.4))
	_light(pos + Vector3(0, 4, 0), Color(1.0, 0.75, 0.45), 70.0, 6.0, 0.35)


## A burst from a close-in gun: a stream of glowing rounds toward a missile.
func tracers(from: Vector3, to: Vector3) -> void:
	var d := to - from
	var dist := d.length()
	if dist < 5.0:
		return
	particles(from, m_ember, 14, clampf(dist / 1050.0, 0.1, 3.0), Vector2(1000.0, 1100.0), 0.6, Vector2(0.7, 1.0), Vector3.ZERO,
		ramp(Color(1.0, 0.85, 0.5, 1), Color(1.0, 0.6, 0.2, 0.6)), true, d / dist, Vector3.ZERO, Vector3(1, 1, 1), Vector2(0.0, 0.0))
	_light(from, Color(1.0, 0.8, 0.5), 25.0, 3.0, 0.1)


## A homing torpedo dropped into the sea, or a decoy fired from the hull.
func drop_splash(pos: Vector3) -> void:
	splash(Vector3(pos.x, 0.0, pos.z), 1.4)


func bubbles(pos: Vector3) -> void:
	particles(pos, m_steam, 20, 6.0, Vector2(0.5, 2.0), 40.0, Vector2(0.4, 1.0), Vector3(0, 3.0, 0),
		stops([[0.0, Color(1, 1, 1, 0.0)], [0.1, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0)]]),
		true, Vector3.UP, Vector3(2.0, 1.0, 2.0), Vector3(0.6, 1.0, 1.4), Vector2(0.0, 0.2))


## A shell that bounced off armour: a shower of sparks and a puff of smoke.
func ricochet(pos: Vector3) -> void:
	_light(pos, Color(1.0, 0.8, 0.5), 18.0, 3.0, 0.12)
	spark(pos)


## Burning wreckage going under: a gush of steam.
func quench(pos: Vector3, size: float) -> void:
	particles(Vector3(pos.x, 0.5, pos.z), m_steam, 16, 9.0, Vector2(size * 0.8, size * 2.0), 25.0,
		Vector2(size * 1.0, size * 1.8), wind * 1.2 + Vector3(0, 0.6, 0),
		stops([[0.0, Color(1, 1, 1, 0.0)], [0.08, Color(1, 1, 1, 0.8)], [1.0, Color(1.1, 1.1, 1.1, 0)]]),
		true, Vector3.UP, Vector3(size * 0.6, 0.3, size * 0.6), Vector3(0.5, 1.6, 3.0), Vector2(0.5, 1.2))
	_patch(pos, size * 1.4, 18.0, 0.8)


## A depth charge: the sea bulges into a white dome of spray, then for shallow
## settings bursts into a plume, leaving a wide foam slick and a shock ring.
func depth_charge(pos: Vector3, depth: float) -> void:
	var r := clampf(30.0 - depth * 0.12, 8.0, 26.0)
	var base := Vector3(pos.x, 0.3, pos.z)
	var v := sqrt(2.0 * 9.8 * r * 0.7)
	particles(base, m_spray, 70, v / 9.8 * 1.9, Vector2(v * 0.35, v), 50.0, Vector2(r * 0.18, r * 0.32), Vector3(0, -9.8, 0),
		stops([[0.0, Color(1, 1, 1, 0.9)], [0.5, Color(1, 1, 1, 0.75)], [1.0, Color(1, 1, 1, 0)]]),
		true, Vector3.UP, Vector3(r * 0.35, 0.1, r * 0.35), Vector3(0.6, 1.2, 2.2), Vector2(0.0, 0.4))
	particles(base, m_mist, 22, 6.0, Vector2(r * 0.05, r * 0.2), 80.0, Vector2(r * 0.35, r * 0.7), Vector3(wind.x, 0.4, wind.z),
		ramp(Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)), true, Vector3.UP, Vector3(r * 0.45, 0.2, r * 0.45), Vector3(0.6, 1.4, 2.6), Vector2(0.8, 1.6))
	_patch(pos, r * 1.3, 30.0, 1.0)
	_patch(pos, r * 1.2, 4.0, 0.9, true)
	if depth < 90.0:
		pending.append({"at": t + 0.45, "fn": "splash", "pos": pos, "size": clampf(9.0 - depth * 0.08, 2.5, 8.0)})


## A gun firing: a blinding flash, a jet of flame along the barrel and a
## cloud of propellant smoke. `dir` is the barrel direction if known.
func muzzle(pos: Vector3, cal: float, dir := Vector3.ZERO) -> void:
	var s := clampf(cal / 60.0, 1.0, 6.0)
	_light(pos, Color(1.0, 0.72, 0.4), s * 45.0, 9.0, 0.16)
	var d := dir.normalized() if dir.length() > 0.1 else Vector3.UP
	particles(pos, m_flash, 4, 0.14, Vector2(s * 4.0, s * 9.0), 8.0, Vector2(s * 1.4, s * 2.4), Vector3.ZERO,
		ramp(Color(1, 1, 1, 1), Color(0.6, 1, 1, 0)), true, d, Vector3.ZERO, Vector3(0.7, 1.1, 1.3), Vector2(4.0, 6.0))
	particles(pos, m_steam, int(clampf(s * 4.0, 5.0, 18.0)), 5.0, Vector2(s * 2.0, s * 7.0), 25.0, Vector2(s * 1.5, s * 3.0),
		wind * 1.2 + Vector3(0, 0.3, 0), ramp(Color(0.85, 0.84, 0.8, 0.7), Color(0.9, 0.9, 0.9, 0)), true, d,
		Vector3.ZERO, Vector3(0.5, 1.6, 3.0), Vector2(1.5, 3.0))
	if pos.y < 12.0 and s >= 2.0:
		_patch(pos, s * 6.0, 2.5, 0.5, true)


func strafe(from: Vector3, to: Vector3) -> void:
	for i in 10:
		var f := float(i) / 9.0
		pending.append({"at": t + f * 0.6, "fn": "bullet", "pos": from.lerp(to, f) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))})


func spark(pos: Vector3) -> void:
	particles(pos, m_ember, 14, 0.6, Vector2(8, 20), 180.0, Vector2(0.6, 1.0), Vector3(0, -6.0, 0),
		ramp(Color(1, 0.9, 0.5, 1), Color(1, 0.4, 0.1, 0)), true, Vector3.UP, Vector3.ZERO, Vector3(1, 1, 0.5), Vector2(0.2, 0.5))
	particles(pos, m_smoke, 4, 2.5, Vector2(0.5, 1.5), 60.0, Vector2(1.0, 2.0), wind * 0.8 + Vector3(0, 0.5, 0),
		ramp(Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)))


func _bullet(pos: Vector3) -> void:
	particles(Vector3(pos.x, 0.2, pos.z), m_spray, 6, 0.9, Vector2(3, 7), 10.0, Vector2(0.3, 0.6), Vector3(0, -9.8, 0),
		ramp(Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)))
	_patch(pos, 1.2, 4.0, 0.6)


# --------------------------------------------------------- continuous
## Smoke pouring from a funnel and streaming downwind.
func funnel_smoke(parent: Node3D, pos: Vector3, mat: Material, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.material_override = mat
	p.amount = 34
	p.lifetime = 16.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 5.0
	p.gravity = wind * 1.5 + Vector3(0, 0.25, 0)
	p.damping_min = 0.3
	p.damping_max = 0.6
	p.scale_amount_min = size
	p.scale_amount_max = size * 1.5
	p.scale_amount_curve = grow(0.6, 2.0, 5.5)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.color_ramp = stops([[0.0, Color(1, 1, 1, 0.0)], [0.05, Color(1, 1, 1, 0.75)], [0.5, Color(1.15, 1.15, 1.15, 0.4)], [1.0, Color(1.3, 1.3, 1.3, 0)]])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	parent.add_child(p)
	return p


## Smoke trailing from a falling aircraft.
func trail_smoke(parent: Node3D) -> CPUParticles3D:
	var p := funnel_smoke(parent, Vector3.ZERO, m_soot, 2.5)
	p.amount = 60
	p.lifetime = 7.0
	p.initial_velocity_max = 1.0
	p.gravity = wind * 1.0 + Vector3(0, 0.5, 0)
	return p


## A fire burning on deck: flames, a thick column of black smoke, embers and a
## flickering light on the superstructure.
func ship_fire(parent: Node3D, pos: Vector3, size: float) -> Dictionary:
	var fl := CPUParticles3D.new()
	fl.mesh = quad
	fl.material_override = m_fire
	fl.amount = 26
	fl.lifetime = 1.3
	fl.local_coords = false
	fl.direction = Vector3.UP
	fl.spread = 18.0
	fl.initial_velocity_min = 2.0
	fl.initial_velocity_max = 5.0
	fl.gravity = Vector3(0, 5.0, 0) + wind * 1.5
	fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fl.emission_box_extents = Vector3(size * 0.5, 0.3, size * 0.8)
	fl.scale_amount_min = size * 0.6
	fl.scale_amount_max = size * 1.1
	fl.scale_amount_curve = grow(0.5, 1.2, 0.6)
	fl.angle_min = -30.0
	fl.angle_max = 30.0
	fl.color_ramp = stops([[0.0, Color(1, 1, 1, 0)], [0.1, Color(1, 1, 1, 1)], [1.0, Color(0.2, 1, 1, 0)]])
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fl.position = pos
	parent.add_child(fl)
	var sm := funnel_smoke(parent, pos + Vector3(0, size * 0.8, 0), m_soot, size * 1.4)
	sm.amount = 46
	sm.lifetime = 20.0
	sm.initial_velocity_min = 4.0
	sm.initial_velocity_max = 7.0
	sm.gravity = wind * 1.8 + Vector3(0, 0.8, 0)
	sm.scale_amount_curve = grow(0.5, 2.2, 7.0)
	var em := CPUParticles3D.new()
	em.mesh = quad
	em.material_override = m_ember
	em.amount = 20
	em.lifetime = 2.5
	em.local_coords = false
	em.direction = Vector3.UP
	em.spread = 25.0
	em.initial_velocity_min = 4.0
	em.initial_velocity_max = 9.0
	em.gravity = Vector3(0, -2.0, 0) + wind * 1.5
	em.scale_amount_min = 0.6
	em.scale_amount_max = 1.2
	em.color_ramp = ramp(Color(1.0, 0.8, 0.4, 1), Color(1.0, 0.25, 0.05, 0))
	em.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	em.emission_box_extents = Vector3(size * 0.5, 0.3, size * 0.8)
	em.position = pos
	parent.add_child(em)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.22)
	light.omni_range = size * 9.0
	light.omni_attenuation = 1.4
	light.light_energy = 0.0
	light.light_volumetric_fog_energy = 3.0
	light.position = pos + Vector3(0, size * 0.8, 0)
	parent.add_child(light)
	var rec := {"flames": fl, "smoke": sm, "embers": em, "light": light, "level": 0.0, "seed": randf() * 10.0}
	fires.append(rec)
	return rec


func set_fire(rec: Dictionary, level: float, smoke_on: bool) -> void:
	rec["level"] = level
	rec["flames"].emitting = level > 0.05
	rec["embers"].emitting = level > 0.3
	rec["smoke"].emitting = smoke_on


func stop_fire(rec: Dictionary) -> void:
	set_fire(rec, 0.0, false)


## Spray thrown off both sides of the bow; strength follows speed.
func bow_spray(beam: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.material_override = m_spray
	p.amount = 40
	p.lifetime = 1.6
	p.local_coords = false
	p.direction = Vector3(1, 1.2, -0.3)
	p.spread = 25.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -9.8, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(beam * 0.1, 0.3, 1.0)
	p.scale_amount_min = maxf(beam * 0.12, 0.4)
	p.scale_amount_max = maxf(beam * 0.3, 0.9)
	p.scale_amount_curve = grow(0.5, 1.4, 2.2)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.color_ramp = stops([[0.0, Color(1, 1, 1, 0.0)], [0.1, Color(1, 1, 1, 0.8)], [1.0, Color(1, 1, 1, 0)]])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	add_child(p)
	p.set_meta("flip", 1.0)
	return p


## Swings a bow-spray emitter with the ship and alternates the side it throws to.
func aim_spray(p: CPUParticles3D, xf: Transform3D, kn: float) -> void:
	var yaw := xf.basis.get_euler(EULER_ORDER_YXZ).y
	p.global_transform = Transform3D(Basis(Vector3.UP, yaw), p.global_position)
	var flip: float = -float(p.get_meta("flip", 1.0))
	p.set_meta("flip", flip)
	p.direction = Vector3(flip, 1.1, -0.4)
	var v := clampf(kn * 0.25, 2.0, 9.0)
	p.initial_velocity_min = v * 0.6
	p.initial_velocity_max = v


func update(dt: float) -> void:
	t += dt
	_fly(dt)
	var keep_p := []
	for p in pending:
		if t >= p["at"]:
			match p["fn"]:
				"splash":
					splash(p["pos"], p["size"])
				"bullet":
					_bullet(p["pos"])
				"flash":
					_light(p["pos"], Color(1.0, 0.85, 0.6), 600.0, 18.0, 2.5)
		else:
			keep_p.append(p)
	pending = keep_p
	var keep := []
	for it in items:
		var node: Node3D = it["node"]
		var a: float = (t - it["t0"]) / it["life"]
		if a >= 1.0:
			node.queue_free()
			continue
		if it["kind"] == "flash":
			node.light_energy = it["data"]["e"] * (1.0 - a) * (1.0 - a)
		keep.append(it)
	items = keep
	# Fires flicker.
	for f in fires:
		var l: OmniLight3D = f["light"]
		if not is_instance_valid(l):
			continue
		var s: float = f["seed"]
		var flick := 0.75 + 0.25 * sin(t * 13.0 + s) * sin(t * 7.3 + s * 2.0) + 0.1 * sin(t * 29.0 + s)
		l.light_energy = 3.5 * float(f["level"]) * flick * (1.6 if night else 1.0)
	for c in get_children():
		if c is CPUParticles3D and c.one_shot and not c.emitting:
			c.queue_free()
