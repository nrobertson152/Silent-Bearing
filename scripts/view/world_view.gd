extends Node3D
## The outside world: sky, light, ocean, islands, every ship, aircraft and
## projectile, plus their smoke, wakes and fires. Reads World each frame.

const Fx := preload("res://scripts/view/fx.gd")
const GameData := preload("res://scripts/data.gd")
const Gfx := preload("res://scripts/view/gfx.gd")
const IslandBuilder := preload("res://scripts/build/island_builder.gd")
const MeshKit := preload("res://scripts/build/mesh_kit.gd")
const Ocean := preload("res://scripts/view/ocean.gd")
const PlaneBuilder := preload("res://scripts/build/plane_builder.gd")
const ShipBuilder := preload("res://scripts/build/ship_builder.gd")
const SubBuilder := preload("res://scripts/build/sub_builder.gd")
const U := preload("res://scripts/util.gd")
const Wakes := preload("res://scripts/view/wakes.gd")
const World := preload("res://scripts/sim/world.gd")

const PAL := {
	"day": {"top": Color(0.24, 0.42, 0.64), "hor": Color(0.68, 0.75, 0.79), "ground": Color(0.12, 0.17, 0.19),
		"sun": Color(1.0, 0.95, 0.86), "sun_e": 1.6, "amb": 0.45, "deep": Color(0.014, 0.06, 0.095),
		"shallow": Color(0.04, 0.17, 0.19), "under": Color(0.03, 0.12, 0.14), "fog": 0.00009,
		"cloud": Color(0.95, 0.95, 0.96), "cover": 0.45, "sun_dir": Vector3(0.45, 0.62, -0.64), "stars": 0.0,
		"moon": 0.0, "amp": 1.0, "smoke": Color(0.42, 0.41, 0.4), "exposure": 1.0},
	"dusk": {"top": Color(0.14, 0.18, 0.33), "hor": Color(0.9, 0.56, 0.36), "ground": Color(0.08, 0.08, 0.10),
		"sun": Color(1.0, 0.6, 0.32), "sun_e": 1.2, "amb": 0.3, "deep": Color(0.02, 0.035, 0.06),
		"shallow": Color(0.10, 0.11, 0.13), "under": Color(0.02, 0.06, 0.08), "fog": 0.00016,
		"cloud": Color(0.8, 0.5, 0.4), "cover": 0.5, "sun_dir": Vector3(-0.85, 0.06, -0.3), "stars": 0.15,
		"moon": 0.0, "amp": 1.2, "smoke": Color(0.22, 0.2, 0.2), "exposure": 1.1},
	"night": {"top": Color(0.012, 0.02, 0.04), "hor": Color(0.11, 0.14, 0.20), "ground": Color(0.01, 0.015, 0.02),
		"sun": Color(0.62, 0.70, 0.88), "sun_e": 0.5, "amb": 0.34, "deep": Color(0.006, 0.014, 0.026),
		"shallow": Color(0.03, 0.06, 0.09), "under": Color(0.005, 0.02, 0.03), "fog": 0.00028,
		"cloud": Color(0.10, 0.11, 0.14), "cover": 0.4, "sun_dir": Vector3(-0.4, 0.22, 0.8), "stars": 1.0,
		"moon": 1.0, "amp": 0.8, "smoke": Color(0.1, 0.1, 0.11), "exposure": 1.45},
}
## Sea state by where the target is met: open ocean, near a coast, a strait, a harbour.
const SEA := {"open": 1.0, "coast": 0.75, "strait": 0.55, "harbor": 0.3}

var world: World
var pal: Dictionary
var ocean: Ocean
var wakes: Wakes
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
var wind := Vector3(1, 0, 0)
var m_smoke: Material
var m_tracer: StandardMaterial3D
var m_shell: StandardMaterial3D
var sub_wk: Dictionary
var scope_wk: Dictionary
var sub_bow: CPUParticles3D
var feather: CPUParticles3D
var sub_motion := {"heave": 0.0, "pitch": 0.0, "roll": 0.0}
var aim_scope := false


func setup(w: World) -> void:
	Gfx.load_settings()
	world = w
	pal = PAL[w.tod]
	# A steady wind for the whole patrol: it sets the waves, the foam and the smoke.
	var wind_deg := float(hash(String(w.spec.get("id", "demo"))) % 360)
	wind = Vector3(cos(deg_to_rad(wind_deg)), 0, sin(deg_to_rad(wind_deg)))
	_environment()
	ocean = Ocean.new()
	add_child(ocean)
	ocean.set_colors(pal["deep"], pal["shallow"], pal["under"], pal["amp"])
	ocean.set_sea(float(pal["amp"]) * float(SEA.get(w.spec.get("terrain", "open"), 1.0)), wind_deg)
	ocean.set_sun(pal["sun_dir"], pal["sun"], pal["sun_e"])
	wakes = Wakes.new()
	add_child(wakes)
	fx = Fx.new()
	fx.night = w.tod == "night"
	fx.wind = wind
	fx.wakes = wakes
	add_child(fx)
	m_smoke = fx.smoke_mat(pal["smoke"])
	m_tracer = StandardMaterial3D.new()
	m_tracer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_tracer.albedo_color = Color(1.0, 0.75, 0.35)
	m_tracer.emission_enabled = true
	m_tracer.emission = Color(1.0, 0.7, 0.3)
	m_tracer.emission_energy_multiplier = 2.0
	m_shell = MeshKit.mat(Color(0.15, 0.15, 0.15), 0.6)
	for isl in w.islands:
		var style := "north" if w.spec["nation"] in ["de", "uk"] else "south"
		var mi := IslandBuilder.build(isl["r"], isl["h"], isl["seed"], style)
		add_child(mi)
		mi.position = U.to3(isl["pos"])
	sub_node = SubBuilder.build(w.nat)
	add_child(sub_node)
	var L: float = w.nat["sub"]["len"]
	var B: float = w.nat["sub"]["beam"]
	sub_wk = wakes.ship(sub_node, B, L, 40.0)
	scope_wk = {"trail": wakes.trail(1.4, 14.0, 40, 0.8), "arms": [wakes.arm(1.0, 1.6, 9.0, 30), wakes.arm(-1.0, 1.6, 9.0, 30)]}
	sub_bow = fx.bow_spray(B)
	feather = fx.bow_spray(0.6)
	feather.amount = 24
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
	sky_mat.set_shader_parameter("wind", Vector2(wind.x, wind.z))
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL if Gfx.advanced() else Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = pal["amb"]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	Gfx.setup_env(env, pal, world.tod == "night")
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	var d: Vector3 = pal["sun_dir"]
	sun.look_at_from_position(Vector3.ZERO, -d, Vector3.UP)
	sun.light_color = pal["sun"]
	sun.light_energy = pal["sun_e"]
	sun.light_cull_mask = 1
	Gfx.setup_sun(sun)
	add_child(sun)


## Re-applies the quality preset (F9) to the running scene.
func refresh_quality() -> void:
	Gfx.setup_env(env, pal, world.tod == "night")
	Gfx.setup_sun(sun)


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
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if Gfx.forward_plus() and Gfx.quality >= 2:
		# Light shafts hanging in the water.
		e.volumetric_fog_enabled = true
		e.volumetric_fog_density = 0.02
		e.volumetric_fog_albedo = Color(0.5, 0.75, 0.75)
		e.volumetric_fog_anisotropy = 0.7
		e.volumetric_fog_length = 120.0
		e.volumetric_fog_sky_affect = 0.0
	return e


func _add_ship(sh: World.Ship) -> void:
	var node := ShipBuilder.build(sh.layout, sh.length, sh.beam, sh.draft)
	add_child(node)
	var rec := {"node": node, "turrets": node.get_meta("turrets"), "smoke": [], "fires": [], "fire_at": [],
		"heave": 0.0, "pitch": 0.0, "roll": 0.0, "aft": null, "cut": 0.0, "foam": 0.0}
	for top in node.get_meta("funnels"):
		rec["smoke"].append(fx.funnel_smoke(node, top + Vector3(0, 1.0, 0), m_smoke, 3.2 if sh.type != "pc" else 1.6))
	rec["wk"] = wakes.ship(node, sh.beam, sh.length, clampf(sh.length * 0.25, 30.0, 60.0))
	rec["bow"] = fx.bow_spray(sh.beam)
	# Where each compartment's fire breaks out: on deck above it (the flight
	# deck for a carrier), a little to one side.
	var lay := GameData.layout(sh.layout)
	for i in sh.hull.n:
		var u := sh.hull.comp_u(i)
		var y := float(lay["deck"]["h"]) if lay["hull"] == "cv" else ShipBuilder.deck_h(lay, u)
		rec["fire_at"].append(Vector3(randf_range(-0.22, 0.22) * sh.beam, y + 0.4, ShipBuilder.z_of(u, sh.length)))
		rec["fires"].append(null)
	ships[sh.id] = rec


## Ship transform: riding the swell (big ships answer slowly and barely
## pitch), heeling, trimming and settling with the water in her, then going
## down the way she was lost. A ship broken in two is placed by _half_xform.
func _ship_xform(sh: World.Ship, rec: Dictionary, dt: float) -> Transform3D:
	var base := _base_xform(sh, rec, dt)
	if rec["aft"] != null:
		return _half_xform(sh, rec, base, true)
	var pose := _pose(sh, rec)
	var b := base.basis * Basis.from_euler(Vector3(pose.y, 0.0, pose.x), EULER_ORDER_YXZ)
	return Transform3D(b, base.origin - Vector3(0, pose.z, 0))


## Heading, position and the swell under her, fading as she goes down.
func _base_xform(sh: World.Ship, rec: Dictionary, dt: float) -> Transform3D:
	var p := Vector3(sh.pos.x, 0.0, -sh.pos.y)
	var h := deg_to_rad(sh.hdg)
	var fwd := Vector3(sin(h), 0, -cos(h))
	var stbd := Vector3(cos(h), 0, sin(h))
	var hl := sh.length * 0.36
	var hw := sh.beam * 0.45
	var y_bow := ocean.height(p.x + fwd.x * hl, p.z + fwd.z * hl)
	var y_st := ocean.height(p.x - fwd.x * hl, p.z - fwd.z * hl)
	var y_p := ocean.height(p.x - stbd.x * hw, p.z - stbd.z * hw)
	var y_s := ocean.height(p.x + stbd.x * hw, p.z + stbd.z * hw)
	var tau := 0.6 + sh.length / 110.0
	var k := 1.0 - exp(-dt / tau)
	rec["heave"] = lerpf(rec["heave"], (y_bow + y_st + y_p + y_s) * 0.25 * 0.85, k)
	rec["pitch"] = lerpf(rec["pitch"], atan2(y_bow - y_st, hl * 2.0) * 0.8, k)
	rec["roll"] = lerpf(rec["roll"], atan2(y_s - y_p, hw * 2.0) * 0.5, k * 0.7)
	var calm := 1.0 - smoothstep(0.4, 1.0, sh.sinking)
	var roll: float = (rec["roll"] + sin(time * 0.5 + sh.id * 2.0) * 0.012) * calm
	var pitch: float = (rec["pitch"] + sin(time * 0.43 + sh.id) * 0.004) * calm
	var b := Basis.from_euler(Vector3(pitch, U.yaw(sh.hdg), roll), EULER_ORDER_YXZ)
	return Transform3D(b, Vector3(p.x, rec["heave"] * calm, p.z))


## How she lies: heel and trim from the water in her, and once she is lost,
## how she goes down: foundering by the head or the stern, or rolling over.
## Returns (roll, pitch, drop): roll + = port side down and pitch + = bow up,
## in radians; drop in metres.
func _pose(sh: World.Ship, rec: Dictionary) -> Vector3:
	var h := sh.hull
	var roll := -deg_to_rad(h.list)
	var pitch := -deg_to_rad(h.trim)
	var drop := h.settle
	var s := sh.sinking
	if s <= 0.0:
		return Vector3(roll, pitch, drop)
	var L := sh.length
	var top: float = rec["node"].get_meta("height", 30.0)
	var side := signf(roll) if absf(roll) > 0.005 else (1.0 if sh.id % 2 == 0 else -1.0)
	var by_head := h.trim > 0.15 or (absf(h.trim) <= 0.15 and ((sh.id >> 1) & 1) == 0)
	var end := -1.0 if by_head else 1.0
	if h.mode == "capsize":
		# Over she goes, slowly at first; she floats bottom up for a while,
		# then one end dips and she slides under.
		var over := smoothstep(0.0, 0.5, s)
		roll = lerpf(roll, side * deg_to_rad(168.0), over)
		var k := smoothstep(0.5, 1.0, s)
		pitch += end * deg_to_rad(26.0) * k
		drop += 1.5 * over + pow(k, 1.5) * (sh.draft + sh.beam * 0.5 + L * 0.5 * sin(deg_to_rad(26.0)) + 10.0)
		return Vector3(roll, pitch, drop)
	# Foundering: she settles until the sea is over her deck, then one end goes
	# under, the other rears up out of the water and she slides down.
	var k0 := smoothstep(0.0, 0.35, s)
	drop = lerpf(drop, maxf(drop, h.freeboard * 0.85), k0)
	pitch += end * deg_to_rad(5.0) * k0
	roll *= 1.0 + 0.6 * smoothstep(0.0, 0.8, s)
	var steep := deg_to_rad(38.0 + 14.0 * clampf(1.0 - L / 250.0, 0.0, 1.0))
	var k1 := smoothstep(0.35, 0.8, s)
	var p1 := pitch
	pitch += end * steep * k1
	drop += L * 0.5 * (absf(sin(pitch)) - absf(sin(p1))) - 0.12 * L * k1
	var k2 := smoothstep(0.78, 1.0, s)
	drop += pow(k2, 1.5) * (0.12 * L + h.freeboard + top + 12.0)
	return Vector3(roll, pitch, drop)


## One half of a ship broken in two: it swings about its free end as the
## broken end fills, the free end rearing out of the sea, then slides under.
## The half that took the blast (the shorter one) goes first.
func _half_xform(sh: World.Ship, rec: Dictionary, base: Transform3D, bow: bool) -> Transform3D:
	var h := sh.hull
	var L := sh.length
	var cut: float = rec["cut"]
	var tip := -L * 0.5 if bow else L * 0.5
	var len_half := absf(tip - cut)
	var shorter := len_half < L * 0.5
	var s := clampf(sh.sinking * (1.7 if shorter else 1.0), 0.0, 1.0)
	var a := deg_to_rad(60.0 + 20.0 * float((sh.id + (0 if bow else 1)) % 2)) * pow(smoothstep(0.0, 0.65, s), 0.9)
	var rise := (0.1 * L + 5.0 if bow else 0.06 * L + 3.0) * smoothstep(0.05, 0.5, s)
	var fb_tip := h.freeboard * (1.3 if bow else 1.0)
	var under := pow(smoothstep(0.5, 1.0, s), 1.4) * (rise + fb_tip + 14.0)
	var twist := deg_to_rad(6.0 + 12.0 * fmod(sh.id * 0.37 + (0.0 if bow else 0.5), 1.0)) * (1.0 if bow else -1.0) \
		* smoothstep(0.0, 0.6, s)
	var pivot := Vector3(0, 0, tip)
	var turn := Basis(Vector3(1, 0, 0), a if bow else -a) * Basis(Vector3(0, 0, 1), twist - deg_to_rad(h.list))
	var lean := Basis(Vector3(1, 0, 0), -deg_to_rad(h.trim))
	var local := Transform3D(lean, Vector3.ZERO) * Transform3D(Basis(), pivot) * Transform3D(turn, Vector3.ZERO) \
		* Transform3D(Basis(), -pivot)
	var xf := base * local
	xf.origin.y += rise - under - h.settle
	return xf


## She has blown up or broken her back: the stern half becomes a node of its
## own drawing the same mesh, and each copy clips away the other's half. The
## turrets and fires aft of the break go with the stern.
func _split(sh: World.Ship, rec: Dictionary) -> void:
	var node: Node3D = rec["node"]
	var mi: MeshInstance3D = node.get_meta("hull_mesh")
	var cut := ShipBuilder.z_of(sh.hull.break_u, sh.length)
	var aft := Node3D.new()
	aft.name = "SternHalf"
	add_child(aft)
	aft.transform = node.transform
	var mi2 := MeshInstance3D.new()
	mi2.mesh = mi.mesh
	aft.add_child(mi2)
	mi.set_instance_shader_parameter("cut", Vector2(cut, 1.0))
	mi2.set_instance_shader_parameter("cut", Vector2(cut, -1.0))
	for tn in rec["turrets"]:
		if (tn as Node3D).position.z > cut:
			tn.reparent(aft, false)
	for i in rec["fires"].size():
		var f = rec["fires"][i]
		if f != null and rec["fire_at"][i].z > cut:
			for k in ["flames", "smoke", "embers", "light"]:
				(f[k] as Node).reparent(aft, false)
	for sm in rec["smoke"]:
		sm.emitting = false
	rec["aft"] = aft
	rec["cut"] = cut


## Fires burning in her compartments, each above its own part of the hull.
## They go out in a burst of steam as the sea closes over them.
func _sync_fires(sh: World.Ship, rec: Dictionary) -> void:
	var h := sh.hull
	var fires: Array = rec["fires"]
	var lit := 0
	for f in fires:
		if f != null:
			lit += 1
	var size := clampf(sh.beam * 0.3, 3.0, 9.0)
	for i in fires.size():
		var lvl: float = h.fire[i]
		var f = fires[i]
		if f == null:
			if lvl < 0.06 or lit >= 6:
				continue
			var holder: Node3D = rec["node"]
			if rec["aft"] != null and rec["fire_at"][i].z > rec["cut"]:
				holder = rec["aft"]
			f = fx.ship_fire(holder, rec["fire_at"][i], size)
			f["under"] = false
			fires[i] = f
			lit += 1
		var fl: Node3D = f["flames"]
		var wp := fl.global_position
		var under := wp.y < ocean.height(wp.x, wp.z) + 0.2
		if under and not f["under"] and float(f["level"]) > 0.2:
			fx.quench(wp, size)
		f["under"] = under
		fx.set_fire(f, 0.0 if under else lvl, lvl > 0.03 and not under)


## Air and oil boiling up where she is going down: white water wherever her
## hull meets the sea.
func _sinking_foam(sh: World.Ship, rec: Dictionary, dt: float) -> void:
	rec["foam"] -= dt
	if rec["foam"] > 0.0:
		return
	rec["foam"] = randf_range(0.3, 0.6)
	var node: Node3D = rec["node"]
	var spots := []
	var prev := Vector3.ZERO
	for i in 25:
		var z := ShipBuilder.z_of(i / 24.0, sh.length)
		var xf := node.transform
		if rec["aft"] != null and z > rec["cut"]:
			xf = (rec["aft"] as Node3D).transform
		var p := xf * Vector3(0, 0, z)
		if absf(p.y) < 3.0 or (i > 0 and signf(p.y) != signf(prev.y)):
			spots.append(p)
		prev = p
	if spots.is_empty():
		return
	var at: Vector3 = spots[randi() % spots.size()]
	at += Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)) * sh.beam
	wakes.patch(at, sh.beam * randf_range(0.8, 1.4), 25.0, 0.9)


func sync(dt: float, cam_pos: Vector3) -> void:
	time += dt
	var cam := get_viewport().get_camera_3d()
	var cam_xf := Transform3D(Basis(), cam_pos)
	if cam != null:
		cam_xf = cam.global_transform
		cam.cull_mask &= ~Wakes.MASK

	ocean.follow(cam_pos, world.t if not world.demo else time)
	wakes.follow(cam_xf)
	ocean.set_wake(wakes.texture(), wakes.center, wakes.size)
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
				if rec["aft"] != null:
					rec["aft"].visible = false
				wakes.free_ship(rec["wk"])
				wakes.patch(node.global_position, sh.length * 0.3, 45.0, 0.9)
				rec["bow"].emitting = false
				for s in rec["smoke"]:
					s.emitting = false
				for f in rec["fires"]:
					if f != null:
						fx.stop_fire(f)
			continue
		if sh.hull.mode == "explode" and rec["aft"] == null:
			_split(sh, rec)
		node.transform = _ship_xform(sh, rec, dt)
		if rec["aft"] != null:
			rec["aft"].transform = _half_xform(sh, rec, _base_xform(sh, rec, 0.0), false)
		var whole := rec["aft"] == null
		wakes.steer(rec["wk"], node.transform, sh.length * 0.5, sh.spd, sh.sinking < 0.6 and whole)
		rec["bow"].global_position = node.transform * Vector3(0, 0.6, -sh.length * 0.47)
		rec["bow"].emitting = sh.spd > 8.0 and sh.sinking < 0.2
		fx.aim_spray(rec["bow"], node.transform, sh.spd)
		for s in rec["smoke"]:
			s.emitting = sh.sinking < 0.6 and whole and (s as Node3D).global_position.y > 1.0
		_sync_fires(sh, rec)
		if sh.sinking > 0.0:
			_sinking_foam(sh, rec, dt)
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
				var e := U.elev_for_range(r, 800.0, 150.0)
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
	var L: float = world.nat["sub"]["len"]
	var B: float = world.nat["sub"]["beam"]
	var surf_mix := clampf(1.0 - s.depth / 6.0, 0.0, 1.0)
	var heave := 0.0
	var pitch := 0.0
	var roll := 0.0
	if surf_mix > 0.0:
		var h := deg_to_rad(s.hdg)
		var fwd := Vector3(sin(h), 0, -cos(h))
		var stbd := Vector3(cos(h), 0, sin(h))
		var bow := ocean.height(p.x + fwd.x * L * 0.4, p.z + fwd.z * L * 0.4)
		var st := ocean.height(p.x - fwd.x * L * 0.4, p.z - fwd.z * L * 0.4)
		var yp := ocean.height(p.x - stbd.x * B * 0.5, p.z - stbd.z * B * 0.5)
		var ys := ocean.height(p.x + stbd.x * B * 0.5, p.z + stbd.z * B * 0.5)
		heave = (bow + st + yp + ys) * 0.25 * 0.75 * surf_mix
		pitch = atan2(bow - st, L * 0.8) * 0.6 * surf_mix
		roll = (atan2(ys - yp, B) * 0.35 + sin(time * 0.7) * 0.02) * surf_mix
	var k := 1.0 - exp(-dt / 1.1)
	sub_motion["heave"] = lerpf(sub_motion["heave"], heave, k)
	sub_motion["pitch"] = lerpf(sub_motion["pitch"], pitch, k)
	sub_motion["roll"] = lerpf(sub_motion["roll"], roll, k * 0.8)
	var y: float = -s.depth + sub_motion["heave"]
	# The diving angle, + = bow up.
	var trim := deg_to_rad(s.pitch)
	sub_node.transform = Transform3D(Basis.from_euler(Vector3(sub_motion["pitch"] + trim, U.yaw(s.hdg), sub_motion["roll"]),
		EULER_ORDER_YXZ), Vector3(p.x, y, p.z))
	var kn := absf(s.spd)
	wakes.steer(sub_wk, sub_node.transform, L * 0.5, kn, s.depth < 3.0)
	sub_bow.global_position = sub_node.transform * Vector3(0, 1.0, -L * 0.47)
	sub_bow.emitting = s.depth < 2.0 and kn > 6.0
	fx.aim_spray(sub_bow, sub_node.transform, kn)
	var head: Vector3 = sub_node.get_meta("scope_head")
	var hp := sub_node.transform * head
	var scope_on := s.scope_up and s.depth > 2.0 and s.depth <= World.PERI_MAX and kn > 2.0
	var sxf := Transform3D(Basis(Vector3.UP, U.yaw(s.hdg)), Vector3(hp.x, 0.0, hp.z))
	scope_wk["trail"].global_transform = sxf
	scope_wk["trail"].emitting = scope_on
	for a in scope_wk["arms"]:
		a.global_transform = sxf
		a.emitting = scope_on
		a.initial_velocity_min = kn * U.KN * Wakes.KELVIN
		a.initial_velocity_max = a.initial_velocity_min
	feather.global_position = Vector3(hp.x, 0.2, hp.z)
	feather.emitting = scope_on
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
			rec["smoke"] = fx.trail_smoke(node)


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
			# Steam torpedoes leave a bubbling white track; electric and oxygen ones barely a trace.
			var life := 16.0 if tp.wake else 5.0
			e = wakes.trail(2.2, life, int(clampf(life * tp.kn * U.KN / 1.4, 20.0, 300.0)), 0.45 if tp.wake else 0.1)
			e.emitting = true
			torps[tp.id] = e
		e.global_transform = Transform3D(Basis(Vector3.UP, U.yaw(tp.hdg)), Vector3(tp.pos.x, 0.0, -tp.pos.y))
	for id in torps.keys():
		if not seen.has(id):
			var e: CPUParticles3D = torps[id]
			e.emitting = false
			get_tree().create_timer(17.0).timeout.connect(e.queue_free)
			torps.erase(id)


static func s3(v: Vector3) -> Vector3:
	return Vector3(v.x, v.y, -v.z)


func handle_event(ev: Dictionary) -> void:
	match ev["type"]:
		"splash":
			fx.splash(s3(ev["pos"]), ev["size"])
		"boom":
			var pos := s3(ev["pos"])
			if ev.get("kind", "") == "torpedo" and ships.has(ev.get("ship", -1)):
				# The hit is reported at the ship's centre; show it on the side facing the boat.
				var node: Node3D = ships[ev["ship"]]["node"]
				var side := node.global_transform.basis.x.normalized()
				var to_sub := U.to3(world.sub.pos) - node.global_position
				var beam: float = node.get_meta("beam", 20.0)
				pos = node.global_position + side * signf(side.dot(to_sub)) * beam * 0.55
				pos.y = 0.0
			match ev.get("kind", ""):
				"magazine":
					# Where along her length the magazine was.
					if ships.has(ev.get("ship", -1)):
						var sh_rec: Dictionary = ships[ev["ship"]]
						var sh_node: Node3D = sh_rec["node"]
						var L: float = float(ev["size"]) * 7.0
						pos = sh_node.global_transform * Vector3(0, 3.0, ShipBuilder.z_of(float(ev.get("u", 0.5)), L))
					fx.magazine(pos, ev["size"])
				"bounce":
					fx.ricochet(pos)
				_:
					fx.explosion(pos, ev["size"], ev.get("kind", ""))
		"dc":
			fx.depth_charge(s3(ev["pos"]), ev["depth"])
		"muzzle":
			var pos := s3(ev["pos"])
			var dir := Vector3.ZERO
			if ev.has("ship") and ships.has(ev["ship"]):
				var tl: Array = ships[ev["ship"]]["turrets"]
				if not tl.is_empty():
					var tn: Node3D = tl[randi() % tl.size()]
					var cr: Node3D = tn.get_node_or_null("Cradle")
					var bx: Transform3D = cr.global_transform if cr else tn.global_transform
					pos = tn.global_transform * Vector3(0, 1.5, -6.0)
					dir = -bx.basis.z
			if ev.get("own", false):
				var gp: Node3D = sub_node.get_meta("gun_pitch")
				pos = gp.global_transform * Vector3(0, 0, -float(world.nat["gun"]["cal"]) * 0.045 - 0.5)
				dir = -gp.global_transform.basis.z
			fx.muzzle(pos, ev["cal"], dir)
		"strafe":
			fx.strafe(s3(ev["from"]), s3(ev["to"]))
		"spark":
			fx.spark(s3(ev["pos"]))
