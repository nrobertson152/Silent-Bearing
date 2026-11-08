class_name WorldView
extends Node3D
## The outside world: sky, light, ocean, islands, every ship, aircraft and
## projectile, plus their smoke, wakes and fires. Reads World each frame.

const PAL := {
	"day": {"top": Color(0.28, 0.46, 0.66), "hor": Color(0.68, 0.75, 0.79), "ground": Color(0.12, 0.17, 0.19),
		"sun": Color(1.0, 0.95, 0.86), "sun_e": 1.25, "amb": 0.55, "deep": Color(0.02, 0.08, 0.11),
		"shallow": Color(0.04, 0.15, 0.18), "under": Color(0.03, 0.12, 0.14), "fog": 0.00011,
		"cloud": Color(0.92, 0.92, 0.94), "cover": 0.45, "sun_dir": Vector3(0.45, 0.62, -0.64), "stars": 0.0,
		"moon": 0.0, "amp": 1.0, "smoke": Color(0.5, 0.5, 0.5)},
	"dusk": {"top": Color(0.16, 0.20, 0.34), "hor": Color(0.86, 0.56, 0.38), "ground": Color(0.08, 0.08, 0.10),
		"sun": Color(1.0, 0.62, 0.35), "sun_e": 0.85, "amb": 0.35, "deep": Color(0.03, 0.05, 0.08),
		"shallow": Color(0.10, 0.12, 0.15), "under": Color(0.02, 0.06, 0.08), "fog": 0.00018,
		"cloud": Color(0.75, 0.48, 0.38), "cover": 0.5, "sun_dir": Vector3(-0.85, 0.06, -0.3), "stars": 0.15,
		"moon": 0.0, "amp": 1.2, "smoke": Color(0.25, 0.22, 0.22)},
	"night": {"top": Color(0.012, 0.02, 0.04), "hor": Color(0.11, 0.14, 0.20), "ground": Color(0.01, 0.015, 0.02),
		"sun": Color(0.62, 0.70, 0.88), "sun_e": 0.45, "amb": 0.35, "deep": Color(0.01, 0.02, 0.035),
		"shallow": Color(0.03, 0.06, 0.09), "under": Color(0.005, 0.02, 0.03), "fog": 0.00030,
		"cloud": Color(0.10, 0.11, 0.14), "cover": 0.4, "sun_dir": Vector3(-0.4, 0.22, 0.8), "stars": 1.0,
		"moon": 1.0, "amp": 0.8, "smoke": Color(0.12, 0.12, 0.13)},
}

var world: World
var pal: Dictionary
var ocean: Ocean
var fx: Fx
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var sub_node: Node3D
var ships := {}
var planes := {}
var shells := {}
var torps := {}
var time := 0.0
var m_wake: StandardMaterial3D
var m_smoke: StandardMaterial3D
var m_fire: StandardMaterial3D
var m_tracer: StandardMaterial3D
var m_shell: StandardMaterial3D
var flat_quad: QuadMesh
var sub_wake: CPUParticles3D
var sub_bow: CPUParticles3D
var feather: CPUParticles3D
var aim_scope := false


func setup(w: World) -> void:
	world = w
	pal = PAL[w.tod]
	_environment()
	ocean = Ocean.new()
	add_child(ocean)
	ocean.set_colors(pal["deep"], pal["shallow"], pal["under"], pal["amp"])
	fx = Fx.new()
	fx.night = w.tod == "night"
	add_child(fx)
	m_wake = Fx._pmat(Color(0.92, 0.95, 0.95), false)
	m_wake.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m_smoke = Fx._pmat(pal["smoke"], false)
	m_fire = Fx._pmat(Color(1.0, 0.55, 0.2), true)
	m_tracer = StandardMaterial3D.new()
	m_tracer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_tracer.albedo_color = Color(1.0, 0.75, 0.35)
	m_shell = MeshKit.mat(Color(0.15, 0.15, 0.15), 0.6)
	flat_quad = QuadMesh.new()
	flat_quad.orientation = PlaneMesh.FACE_Y
	for isl in w.islands:
		var style := "north" if w.spec["nation"] in ["de", "uk"] else "south"
		var mi := IslandBuilder.build(isl["r"], isl["h"], isl["seed"], style)
		add_child(mi)
		mi.position = U.to3(isl["pos"])
	sub_node = SubBuilder.build(w.nat)
	add_child(sub_node)
	sub_wake = _wake_emitter(float(w.nat["sub"]["beam"]), 50)
	sub_bow = _spray_emitter()
	feather = _spray_emitter()
	for sh in w.ships:
		_add_ship(sh)


func _environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("top_col", pal["top"])
	sky_mat.set_shader_parameter("hor_col", pal["hor"])
	sky_mat.set_shader_parameter("ground_col", pal["ground"])
	sky_mat.set_shader_parameter("sun_dir", pal["sun_dir"])
	sky_mat.set_shader_parameter("sun_col", pal["sun"])
	sky_mat.set_shader_parameter("stars", pal["stars"])
	sky_mat.set_shader_parameter("moon", pal["moon"])
	sky_mat.set_shader_parameter("moon_dir", pal["sun_dir"])
	sky_mat.set_shader_parameter("cloud_col", pal["cloud"])
	sky_mat.set_shader_parameter("cloud_cover", pal["cover"])
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = pal["amb"]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = pal["hor"]
	env.fog_density = pal["fog"]
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	var d: Vector3 = pal["sun_dir"]
	sun.look_at_from_position(Vector3.ZERO, -d, Vector3.UP)
	sun.light_color = pal["sun"]
	sun.light_energy = pal["sun_e"]
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 500.0
	sun.light_cull_mask = 1
	add_child(sun)


func underwater_env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = pal["under"]
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.5, 0.55)
	e.ambient_light_energy = 0.5 if world.tod == "day" else 0.15
	e.fog_enabled = true
	e.fog_light_color = pal["under"]
	e.fog_density = 0.035
	return e


func _wake_emitter(width: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = flat_quad
	p.material_override = m_wake
	p.amount = amount
	p.lifetime = 22.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 0.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.2
	p.gravity = Vector3.ZERO
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(width * 0.5, 0.0, 2.0)
	p.scale_amount_min = width * 0.5
	p.scale_amount_max = width * 0.9
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 3.0))
	p.scale_amount_curve = curve
	p.color_ramp = Fx.ramp(Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	add_child(p)
	return p


func _spray_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = QuadMesh.new()
	p.material_override = fx.m_spray
	p.amount = 30
	p.lifetime = 1.4
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.color_ramp = Fx.ramp(Color(1, 1, 1, 0.7), Color(1, 1, 1, 0))
	p.emitting = false
	add_child(p)
	return p


func _smoke_emitter(parent: Node3D, pos: Vector3, amount: int, mat: Material, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = QuadMesh.new()
	p.material_override = mat
	p.amount = amount
	p.lifetime = 12.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(1.4, 0.5, 0.6)
	p.damping_min = 0.2
	p.damping_max = 0.5
	p.scale_amount_min = size
	p.scale_amount_max = size * 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 4.0))
	p.scale_amount_curve = curve
	p.color_ramp = Fx.ramp(Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	parent.add_child(p)
	return p


func _add_ship(sh: World.Ship) -> void:
	var node := ShipBuilder.build(sh.layout, sh.length, sh.beam, sh.draft)
	add_child(node)
	var rec := {"node": node, "turrets": node.get_meta("turrets"), "smoke": [], "fire": null, "fire_smoke": null}
	for top in node.get_meta("funnels"):
		rec["smoke"].append(_smoke_emitter(node, top + Vector3(0, 1.0, 0), 20, m_smoke, 3.0 if sh.type != "pc" else 1.5))
	rec["wake"] = _wake_emitter(sh.beam, 70)
	rec["bow"] = _spray_emitter()
	ships[sh.id] = rec


func _ship_xform(sh: World.Ship) -> Transform3D:
	var bob := sin(time * 0.6 + sh.id) * 0.15
	var drop := pow(sh.sinking, 1.4) * (sh.draft + 28.0)
	var roll := sh.sinking * 0.9 * sh.sink_side + sin(time * 0.5 + sh.id * 2.0) * 0.012
	var pitch := sh.sinking * 0.14 + sin(time * 0.43 + sh.id) * 0.006
	var b := Basis.from_euler(Vector3(pitch, U.yaw(sh.hdg), roll), EULER_ORDER_YXZ)
	return Transform3D(b, Vector3(sh.pos.x, bob - drop, -sh.pos.y))


func sync(dt: float, cam_pos: Vector3) -> void:
	time += dt
	ocean.follow(cam_pos, world.t if not world.demo else time)
	sky_mat.set_shader_parameter("t", time)
	fx.update(dt)
	_sync_sub(dt)
	for sh in world.ships:
		var rec: Dictionary = ships.get(sh.id)
		if rec == null:
			continue
		var node: Node3D = rec["node"]
		if sh.dead:
			if node.visible:
				node.visible = false
				rec["wake"].emitting = false
				rec["bow"].emitting = false
				for s in rec["smoke"]:
					s.emitting = false
				if rec["fire"]:
					rec["fire"].emitting = false
					rec["fire_smoke"].emitting = false
			continue
		node.transform = _ship_xform(sh)
		var stern := node.transform * Vector3(0, 0.3, sh.length * 0.48)
		rec["wake"].global_position = stern
		rec["wake"].emitting = sh.spd > 1.5 and sh.sinking < 0.3
		rec["bow"].global_position = node.transform * Vector3(0, 0.5, -sh.length * 0.47)
		rec["bow"].emitting = sh.spd > 8.0 and sh.sinking < 0.2
		for s in rec["smoke"]:
			s.emitting = sh.sinking < 0.6
		if sh.fire > 0.05 and rec["fire"] == null:
			var fp := Vector3(randf_range(-sh.beam * 0.2, sh.beam * 0.2), 9.0, randf_range(-sh.length * 0.2, sh.length * 0.2))
			rec["fire"] = _smoke_emitter(node, fp, 30, m_fire, 3.0)
			rec["fire"].lifetime = 1.5
			rec["fire"].gravity = Vector3(0, 4, 0)
			rec["fire_smoke"] = _smoke_emitter(node, fp + Vector3(0, 4, 0), 40, fx.m_smoke, 6.0)
			rec["fire_smoke"].lifetime = 16.0
		if rec["fire"]:
			rec["fire"].emitting = sh.fire > 0.05 and sh.sinking < 0.85
			rec["fire_smoke"].emitting = sh.fire > 0.03
		_aim_turrets(sh, rec, dt)
	_sync_planes(dt)
	_sync_shells()
	_sync_torps()


func _aim_turrets(sh: World.Ship, rec: Dictionary, dt: float) -> void:
	var s := world.sub
	var engage := sh.aware and s.surfaced() and sh.alive()
	var r := sh.pos.distance_to(s.pos)
	var rel := U.adiff(U.brg(sh.pos, s.pos), sh.hdg)
	for tn in rec["turrets"]:
		var dir: int = tn.get_meta("dir")
		var want := 0.0 if dir > 0 else PI
		var elev := deg_to_rad(2.0)
		if engage:
			var ok := (dir > 0 and absf(rel) < 150.0) or (dir < 0 and absf(rel) > 30.0)
			if ok:
				want = -deg_to_rad(rel)
				var e := U.elev_for_range(r, 800.0)
				elev = deg_to_rad(maxf(e, 0.5))
		var cur: float = tn.rotation.y
		var diff := wrapf(want - cur, -PI, PI)
		tn.rotation.y = cur + clampf(diff, -0.12 * dt, 0.12 * dt)
		var cradle: Node3D = tn.get_node_or_null("Cradle")
		if cradle:
			cradle.rotation.x = move_toward(cradle.rotation.x, elev, 0.1 * dt)


func _sync_sub(dt: float) -> void:
	var s := world.sub
	var p := U.to3(s.pos)
	var wave := ocean.height(p.x, p.z) if s.depth < 6.0 else 0.0
	var surf_mix := clampf(1.0 - s.depth / 6.0, 0.0, 1.0)
	var y := -s.depth + wave * surf_mix * 0.7
	var L: float = world.nat["sub"]["len"]
	var pitch := 0.0
	var roll := 0.0
	if surf_mix > 0.0:
		var f := U.dirv(s.hdg)
		var bow := ocean.height(p.x + f.x * L * 0.4, p.z - f.y * L * 0.4)
		var st := ocean.height(p.x - f.x * L * 0.4, p.z + f.y * L * 0.4)
		pitch = atan2(bow - st, L * 0.8) * 0.6 * surf_mix
		roll = sin(time * 0.7) * 0.025 * surf_mix
	sub_node.transform = Transform3D(Basis.from_euler(Vector3(pitch, U.yaw(s.hdg), roll), EULER_ORDER_YXZ), Vector3(p.x, y, p.z))
	sub_wake.global_position = sub_node.transform * Vector3(0, 0.3, L * 0.48)
	sub_wake.emitting = s.depth < 3.0 and absf(s.spd) > 1.0
	sub_bow.global_position = sub_node.transform * Vector3(0, 1.0, -L * 0.47)
	sub_bow.emitting = s.depth < 2.0 and absf(s.spd) > 6.0
	var head: Vector3 = sub_node.get_meta("scope_head")
	var hp := sub_node.transform * head
	feather.global_position = Vector3(hp.x, 0.2, hp.z)
	feather.emitting = s.scope_up and s.depth > 2.0 and s.depth <= World.PERI_MAX and absf(s.spd) > 2.0
	# Gun mounts follow the crew's aim.
	var gy: Node3D = sub_node.get_meta("gun_yaw")
	var gp: Node3D = sub_node.get_meta("gun_pitch")
	gy.rotation.y = -deg_to_rad(s.gun_trav)
	gp.rotation.x = deg_to_rad(s.gun_elev)


func set_aa_aim(yaw: float, pitch: float) -> void:
	var ay: Node3D = sub_node.get_meta("aa_yaw")
	var ap: Node3D = sub_node.get_meta("aa_pitch")
	ay.rotation.y = yaw
	ap.rotation.x = pitch


func _sync_planes(dt: float) -> void:
	for p in world.planes:
		var rec = planes.get(p.id)
		if rec == null:
			var node := PlaneBuilder.build(p.info, world.spec["nation"])
			add_child(node)
			rec = {"node": node, "alt": p.alt, "smoke": null}
			planes[p.id] = rec
		var node: Node3D = rec["node"]
		if p.dead:
			node.visible = false
			if rec["smoke"]:
				rec["smoke"].emitting = false
			continue
		var climb: float = (p.alt - rec["alt"]) / maxf(dt, 1e-3)
		rec["alt"] = p.alt
		var pitch := clampf(atan2(climb, p.kn * U.KN), -0.6, 0.5)
		node.transform = Transform3D(Basis.from_euler(Vector3(pitch, U.yaw(p.hdg), -p.roll), EULER_ORDER_YXZ),
			Vector3(p.pos.x, p.alt, -p.pos.y))
		for pr in node.get_meta("props"):
			pr.rotation.z += dt * 40.0
		if p.falling and rec["smoke"] == null:
			rec["smoke"] = _smoke_emitter(node, Vector3.ZERO, 40, fx.m_smoke, 3.0)
			rec["smoke"].lifetime = 6.0


func _sync_shells() -> void:
	var seen := {}
	for sh in world.shells:
		seen[sh.id] = true
		var node: MeshInstance3D = shells.get(sh.id)
		if node == null:
			node = MeshInstance3D.new()
			if sh.kind == "aa":
				var bm := BoxMesh.new()
				bm.size = Vector3(0.12, 0.12, 7.0)
				node.mesh = bm
				node.material_override = m_tracer
			else:
				var sm := SphereMesh.new()
				var r := clampf(sh.cal / 400.0, 0.15, 0.6) * (2.0 if sh.kind == "bomb" else 1.0)
				sm.radius = r
				sm.height = r * (2.0 if sh.kind != "bomb" else 4.0)
				node.mesh = sm
				node.material_override = m_tracer if world.tod == "night" and sh.kind != "bomb" else m_shell
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			shells[sh.id] = node
		var p := Vector3(sh.p.x, sh.p.y, -sh.p.z)
		var v := Vector3(sh.v.x, sh.v.y, -sh.v.z)
		if v.length_squared() > 1.0:
			node.look_at_from_position(p, p + v, Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.FORWARD)
		else:
			node.position = p
	for id in shells.keys():
		if not seen.has(id):
			shells[id].queue_free()
			shells.erase(id)


func _sync_torps() -> void:
	var seen := {}
	for tp in world.torps:
		seen[tp.id] = true
		var e: CPUParticles3D = torps.get(tp.id)
		if e == null:
			e = _wake_emitter(1.5, 60 if tp.wake else 12)
			e.lifetime = 14.0 if tp.wake else 4.0
			e.color_ramp = Fx.ramp(Color(1, 1, 1, 0.75 if tp.wake else 0.12), Color(1, 1, 1, 0))
			e.emitting = true
			torps[tp.id] = e
		e.global_position = Vector3(tp.pos.x, 0.15, -tp.pos.y)
	for id in torps.keys():
		if not seen.has(id):
			var e: CPUParticles3D = torps[id]
			e.emitting = false
			get_tree().create_timer(15.0).timeout.connect(e.queue_free)
			torps.erase(id)


static func s3(v: Vector3) -> Vector3:
	return Vector3(v.x, v.y, -v.z)


func handle_event(ev: Dictionary) -> void:
	match ev["type"]:
		"splash":
			fx.splash(s3(ev["pos"]), ev["size"])
		"boom":
			fx.explosion(s3(ev["pos"]), ev["size"], ev.get("kind", ""))
		"dc":
			fx.depth_charge(s3(ev["pos"]), ev["depth"])
		"muzzle":
			var pos := s3(ev["pos"])
			if ev.has("ship") and ships.has(ev["ship"]):
				var tl: Array = ships[ev["ship"]]["turrets"]
				if not tl.is_empty():
					var tn: Node3D = tl[randi() % tl.size()]
					pos = tn.global_transform * Vector3(0, 1.5, -6.0)
			if ev.get("own", false):
				var gp: Node3D = sub_node.get_meta("gun_pitch")
				pos = gp.global_transform * Vector3(0, 0, -float(world.nat["gun"]["cal"]) * 0.045 - 0.5)
			fx.muzzle(pos, ev["cal"])
		"strafe":
			fx.strafe(s3(ev["from"]), s3(ev["to"]))
		"spark":
			fx.spark(s3(ev["pos"]))
