extends Node
## Runs the whole game: menus, the patrol, camera modes (walking inside the
## boat, periscope, bridge, deck gun, AA gun, outside view), input, stations
## and sound.

const GameData := preload("res://scripts/data.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Interior := preload("res://scripts/interior/interior.gd")
const Menu := preload("res://scripts/ui/menu.gd")
const Player := preload("res://scripts/interior/player.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const U := preload("res://scripts/util.gd")
const World := preload("res://scripts/sim/world.gd")
const WorldView := preload("res://scripts/view/world_view.gd")

const INTERIOR_ORIGIN := Vector3(0, -6000, 0)
const STATION_TITLES := {"chart": "Plot table", "sonar": "Hydrophones", "tdc": "Torpedo data computer",
	"damage": "Damage control", "gauges": "Control room gauges"}

var world: World
var view: WorldView
var interior: Interior
var player: Player
var world_cam: Camera3D
var hud: Hud
var menu: Menu
var sfx: Sfx
var state := "menu"
var mode := "interior"
var overlay := ""
var in_patrol := false
var paused := false
var result_shown := false
var end_timer := 0.0
var nat_id := ""
var tgt_id := ""
var chart_r := 6000.0
var zoomed := false
var free_yaw := 0.0
var free_pitch := -0.05
var ext_yaw := 0.6
var ext_pitch := 0.22
var ext_dist := 140.0
var scope_wash := 0.0
var range_err := 0.0
var aa_yaw := 0.0
var aa_pitch := 0.35
var gun_t := 0.0
var gun_e := 2.0
var firing_aa := false
var real_t := 0.0
var demo_angle := 0.0
var interior_env: Environment
var under_env: Environment
var near_station := {}


func _ready() -> void:
	sfx = Sfx.new()
	add_child(sfx)
	world_cam = Camera3D.new()
	world_cam.far = 90000.0
	world_cam.near = 0.2
	world_cam.cull_mask = 1
	add_child(world_cam)
	interior_env = Environment.new()
	interior_env.background_mode = Environment.BG_COLOR
	interior_env.background_color = Color(0.02, 0.02, 0.02)
	interior_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	interior_env.ambient_light_color = Color(0.55, 0.52, 0.48)
	interior_env.ambient_light_energy = 0.25
	interior_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	interior_env.glow_enabled = true
	interior_env.glow_intensity = 0.4
	hud = Hud.new()
	add_child(hud)
	hud.build(self)
	hud.root.visible = false
	menu = Menu.new()
	add_child(menu)
	menu.build(self)
	_demo()
	# Debug helper: SilentBearing -- --autostart us shokaku
	var args := OS.get_cmdline_user_args()
	var i := args.find("--autostart")
	if i >= 0:
		var nid: String = args[i + 1] if args.size() > i + 1 else "us"
		var tid: String = args[i + 2] if args.size() > i + 2 else "shokaku"
		start_mission.call_deferred(nid, tid)
	# CI smoke test: -- --smoke 8  runs for N seconds, then quits with code 0.
	var k := args.find("--smoke")
	if k >= 0 and args.size() > k + 1:
		get_tree().create_timer(float(args[k + 1])).timeout.connect(func():
			print("SMOKE OK mode=", mode, " t=", world.t if world else -1.0)
			get_tree().quit(0))
	# Debug helper: -- --shot /path/out.png 20  saves a screenshot after N seconds and quits.
	var j := args.find("--shot")
	if j >= 0 and args.size() > j + 2:
		var path: String = args[j + 1]
		get_tree().create_timer(float(args[j + 2])).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path, " mode=", mode, " t=", world.t if world else -1.0)
			get_tree().quit())


# ------------------------------------------------------------------ setup
func _clear_world() -> void:
	for n in [view, interior, player]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	view = null
	interior = null
	player = null


func _demo() -> void:
	_clear_world()
	var nat: Dictionary = GameData.nations()["us"]
	var spec: Dictionary = nat["targets"][4]
	world = World.new(nat, spec, true)
	var tg := world.target
	tg.pos = Vector2(0, 0)
	tg.hdg = 80.0
	for e in world.ships:
		if e.kind == "escort":
			e.pos = World._station(tg, e.off)
			e.hdg = tg.hdg
		elif e.kind == "chaser":
			e.pos = tg.pos + Vector2(sin(e.orb_a), cos(e.orb_a)) * 900.0
	world.sub.pos = Vector2(-600, -900)
	world.sub.depth = 0.0
	world.sub.flood = 0.0
	view = WorldView.new()
	add_child(view)
	view.setup(world)
	world_cam.current = true
	world_cam.environment = null
	state = "menu"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func start_mission(nid: String, tid: String) -> void:
	nat_id = nid
	tgt_id = tid
	var nat: Dictionary = GameData.nations()[nid]
	var spec: Dictionary = {}
	for t in nat["targets"]:
		if t["id"] == tid:
			spec = t
	_clear_world()
	world = World.new(nat, spec)
	view = WorldView.new()
	add_child(view)
	view.setup(world)
	under_env = view.underwater_env()
	interior = Interior.new()
	interior.position = INTERIOR_ORIGIN
	add_child(interior)
	interior.build(nat)
	interior.set_world(world)
	player = Player.new()
	add_child(player)
	player.global_position = INTERIOR_ORIGIN + Vector3(0.5, 0.05, 3.2)
	player.face(0.0)
	player.cam.environment = interior_env
	state = "play"
	in_patrol = true
	paused = false
	result_shown = false
	end_timer = 0.0
	overlay = ""
	chart_r = 6000.0
	menu.root.visible = false
	hud.root.visible = true
	hud.pause.visible = false
	hud.result.visible = false
	hud.help.visible = false
	hud.close_station()
	set_mode("interior")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world.report("Press F1 for controls. Walk to a station and press E, or use the number keys.", "info")


func restart() -> void:
	start_mission(nat_id, tgt_id)


func to_menu(step := "nation") -> void:
	in_patrol = false
	paused = false
	result_shown = false
	hud.root.visible = false
	menu.root.visible = true
	if step == "target" and nat_id != "":
		menu.nat_id = nat_id
	menu.show_step(step)
	_demo()


func resume() -> void:
	if not in_patrol:
		return
	paused = false
	hud.pause.visible = false
	menu.root.visible = false
	hud.root.visible = true
	state = "play"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ modes
func set_mode(m: String) -> void:
	var s := world.sub
	match m:
		"periscope":
			if s.surfaced():
				world.report("We're on the surface. Going up to the bridge.")
				m = "bridge"
			elif s.depth > World.PERI_MAX:
				world.report("Too deep for the periscope. Come up to 12 metres (R).", "warn")
				return
			elif not s.scope_up:
				world.toggle_scope()
				if not s.scope_up:
					return
		"bridge", "gun", "aa":
			if not s.surfaced():
				world.report("The hatch is shut. We have to surface first (R until surfaced).", "warn")
				return
	if m in ["bridge", "gun", "aa"] and not s.surfaced():
		return
	mode = m
	overlay = ""
	hud.close_station()
	zoomed = false
	world.station = m if m in ["bridge", "gun", "aa"] else "control"
	var inside := m == "interior"
	interior.set_active(inside)
	view.visible = not inside
	if inside:
		player.cam.current = true
		player.enabled = true
	else:
		world_cam.current = true
		player.enabled = false
	if m == "gun":
		gun_t = s.gun_trav
		gun_e = s.gun_elev
		range_err = randf_range(-0.08, 0.08)
	if m == "bridge":
		free_yaw = 0.0
		free_pitch = -0.04


func open_overlay(kind: String) -> void:
	if mode != "interior":
		set_mode("interior")
	overlay = kind
	player.enabled = false
	hud.open_station(kind, STATION_TITLES.get(kind, kind))


func close_overlay() -> void:
	overlay = ""
	hud.close_station()
	if mode == "interior":
		player.enabled = true


func view_brg() -> float:
	var s := world.sub
	match mode:
		"periscope":
			return U.wrap360(s.hdg + s.scope_rel)
		"bridge":
			return U.wrap360(s.hdg - rad_to_deg(free_yaw))
		"gun":
			return U.wrap360(s.hdg + s.gun_trav)
	return s.hdg


func scope_fov() -> float:
	return 8.0 if world.sub.zoom else 32.0


# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and state == "play" and not paused and not result_shown \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_move(event.relative)


func _mouse_move(rel: Vector2) -> void:
	var s := world.sub
	match mode:
		"interior":
			if overlay == "":
				player.look(rel)
		"periscope":
			var k := scope_fov() / 32.0
			s.scope_rel = U.wrap360(s.scope_rel + rel.x * 0.09 * k)
			s.scope_elev = clampf(s.scope_elev - rel.y * 0.07 * k, -8.0, 60.0)
		"bridge":
			var k := 0.15 if zoomed else 1.0
			free_yaw -= rel.x * 0.0025 * k
			free_pitch = clampf(free_pitch - rel.y * 0.0025 * k, -1.2, 1.3)
		"gun":
			var k := 0.25 if zoomed else 1.0
			gun_t = U.wrap360(gun_t + rel.x * 0.08 * k + 180.0) - 180.0
			gun_e = clampf(gun_e - rel.y * 0.04 * k, -5.0, float(world.nat["gun"]["max_elev"]))
		"aa":
			aa_yaw -= rel.x * 0.0025
			aa_pitch = clampf(aa_pitch - rel.y * 0.0025, -0.1, 1.45)
		"external":
			ext_yaw -= rel.x * 0.005
			ext_pitch = clampf(ext_pitch + rel.y * 0.004, -0.6, 1.4)


func _unhandled_input(event: InputEvent) -> void:
	if state == "menu":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_F11:
				_fullscreen()
			else:
				menu.key(event.keycode)
		return
	if result_shown:
		return
	if paused:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			resume()
		return
	if event is InputEventMouseButton:
		_mouse_button(event)
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var w := world
	var s := w.sub
	var k: int = event.keycode
	match k:
		KEY_ESCAPE:
			if overlay != "":
				close_overlay()
			elif hud.help.visible:
				hud.help.visible = false
			elif mode != "interior":
				set_mode("interior")
			else:
				paused = true
				hud.pause.visible = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_E:
			if overlay != "":
				close_overlay()
			elif mode == "interior" and not near_station.is_empty():
				_use_station(near_station["name"])
		KEY_F1:
			hud.help.visible = not hud.help.visible
		KEY_F11:
			_fullscreen()
		KEY_UP:
			w.set_telegraph(s.tel + 1)
		KEY_DOWN:
			w.set_telegraph(s.tel - 1)
		KEY_LEFT:
			w.set_rudder(s.rud_i - 1)
		KEY_RIGHT:
			w.set_rudder(s.rud_i + 1)
		KEY_R:
			w.depth_step(-1)
		KEY_F:
			w.depth_step(1)
		KEY_C:
			w.crash_dive()
		KEY_P:
			w.toggle_scope()
			if mode == "periscope" and not s.scope_up:
				set_mode("interior")
		KEY_Z:
			if mode == "periscope":
				s.zoom = not s.zoom
			else:
				zoomed = not zoomed
		KEY_L:
			_lock()
		KEY_SPACE:
			w.fire(1, view_brg() if mode in ["periscope", "bridge"] else -1.0)
		KEY_X:
			w.fire(3, view_brg() if mode in ["periscope", "bridge"] else -1.0)
		KEY_BRACKETLEFT:
			w.set_torp_depth(s.torp_depth - 1.0)
		KEY_BRACKETRIGHT:
			w.set_torp_depth(s.torp_depth + 1.0)
		KEY_T:
			_cycle_tc()
		KEY_TAB:
			if overlay == "chart":
				close_overlay()
			else:
				open_overlay("chart")
		KEY_V:
			sfx.toggle()
			w.report("Sound %s." % ("on" if sfx.on else "off"))
		KEY_1:
			if overlay != "":
				close_overlay()
			set_mode("interior")
		KEY_2:
			set_mode("periscope")
		KEY_3:
			set_mode("bridge")
		KEY_4:
			set_mode("gun")
		KEY_5:
			set_mode("aa")
		KEY_6:
			open_overlay("chart")
		KEY_7:
			open_overlay("sonar")
		KEY_8:
			open_overlay("tdc")
		KEY_9:
			open_overlay("damage")
		KEY_0:
			set_mode("external" if mode != "external" else "interior")


func _mouse_button(ev: InputEventMouseButton) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and ev.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	var s := world.sub
	match ev.button_index:
		MOUSE_BUTTON_LEFT:
			match mode:
				"periscope", "bridge":
					if ev.pressed:
						_lock()
				"gun":
					if ev.pressed:
						world.fire_gun()
				"aa":
					firing_aa = ev.pressed
				"interior":
					if ev.pressed and overlay == "" and not near_station.is_empty():
						_use_station(near_station["name"])
		MOUSE_BUTTON_RIGHT:
			if mode in ["bridge", "gun"]:
				zoomed = ev.pressed
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not ev.pressed:
				return
			var up := ev.button_index == MOUSE_BUTTON_WHEEL_UP
			if overlay == "chart":
				chart_r = clampf(chart_r * (0.5 if up else 2.0), 3000.0, 12000.0)
			elif mode == "periscope":
				s.zoom = up
			elif mode == "external":
				ext_dist = clampf(ext_dist * (0.85 if up else 1.18), 25.0, 900.0)


func _lock() -> void:
	if mode == "periscope":
		world.lock_nearest(view_brg(), scope_fov())
	elif mode == "bridge":
		world.lock_nearest(view_brg(), 12.0 if zoomed else 40.0)
	else:
		world.report("Locking needs the periscope or the bridge.", "warn")


func _cycle_tc() -> void:
	var order := [1, 4, 16]
	var i := order.find(world.tc)
	var nxt: int = order[(i + 1) % 3] if i >= 0 else 1
	if nxt > 4:
		for e in world.ships:
			if e.kind != "target" and e.alive() and e.state != "screen":
				world.report("Can't speed up time with escorts hunting us.", "warn")
				nxt = 1
				break
	world.tc = nxt


func _fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if m == DisplayServer.WINDOW_MODE_FULLSCREEN
		else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _use_station(name: String) -> void:
	match name:
		"scope":
			set_mode("periscope")
		"ladder":
			set_mode("bridge")
		"chart", "sonar", "tdc", "damage":
			open_overlay(name)
		"torpedo":
			open_overlay("tdc")
		"helm", "dive", "engine":
			open_overlay("gauges")


# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	real_t += dt
	if state == "menu":
		_menu_frame(dt)
		return
	var w := world
	var playing := not paused and not result_shown
	if playing:
		var sim := dt * w.tc
		while sim > 1e-6:
			var st := minf(0.1, sim)
			w.update(st)
			sim -= st
		_events()
		if firing_aa and mode == "aa":
			var d := -world_cam.global_transform.basis.z
			w.fire_aa(Vector3(d.x, d.y, -d.z))
		_gun_slew(dt)
		if w.result != "":
			end_timer += dt
			if end_timer >= w.end_delay:
				result_shown = true
				hud.show_result()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cameras(dt)
	var cam_pos := world_cam.global_position if mode != "interior" else U.to3(w.sub.pos)
	if view.visible:
		view.sync(dt, cam_pos)
	if mode == "interior":
		interior.update(dt)
		_station_prompt()
	else:
		hud.prompt.text = ""
	hud.update(dt)
	_sounds()


func _menu_frame(dt: float) -> void:
	demo_angle += dt * 0.05
	var tg := world.target
	var c := U.to3(tg.pos, 12.0)
	world_cam.global_position = c + Vector3(sin(demo_angle) * 420.0, 30.0, cos(demo_angle) * 420.0)
	world_cam.look_at(c)
	view.sync(dt, world_cam.global_position)


func _gun_slew(dt: float) -> void:
	var s := world.sub
	if mode != "gun":
		return
	var dtrav := U.adiff(gun_t, s.gun_trav)
	s.gun_trav = U.wrap360(s.gun_trav + clampf(dtrav, -14.0 * dt, 14.0 * dt) + 180.0) - 180.0
	s.gun_elev = move_toward(s.gun_elev, gun_e, 8.0 * dt)


func _events() -> void:
	var w := world
	var sp := U.to3(w.sub.pos)
	for ev in w.events:
		match ev["type"]:
			"sound":
				var vol: float = ev["vol"]
				var delay := 0.0
				if ev.has("pos"):
					var p: Vector3 = ev["pos"]
					var d := Vector2(p.x, p.z).distance_to(w.sub.pos)
					delay = d / 343.0
					vol *= clampf(1.2 - d / 12000.0, 0.15, 1.0)
				sfx.play(ev["name"], vol, delay)
			"muzzle":
				if not ev.get("own", false):
					var p: Vector3 = ev["pos"]
					var d := Vector2(p.x, p.z).distance_to(w.sub.pos)
					sfx.play("gun_far", clampf(1.2 - d / 15000.0, 0.15, 1.0) * (0.5 if mode == "interior" else 1.0), d / 343.0)
			"clear_bridge":
				if mode in ["bridge", "gun", "aa"]:
					w.report("Clear the bridge! Everyone down the hatch!", "warn")
					set_mode("interior")
					player.global_position = INTERIOR_ORIGIN + Vector3(0.6, 0.05, 2.6)
			"dc":
				if mode != "interior":
					hud.overlay.flash = 0.0
			"boom":
				if ev.get("kind", "") in ["shell_hit", "bomb", "ram"]:
					var p: Vector3 = ev["pos"]
					if Vector2(p.x, p.z).distance_to(w.sub.pos) < 60.0:
						hud.overlay.flash = 0.8
						hud.overlay.flash_col = Color(1.0, 0.6, 0.3)
		view.handle_event(ev)
	w.events.clear()


func _cameras(dt: float) -> void:
	var w := world
	var s := w.sub
	var sn := view.sub_node
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * w.shake * 0.25
	world_cam.environment = null
	match mode:
		"interior":
			player.shake = w.shake
			var tr := sn.global_transform.basis.get_euler(EULER_ORDER_YXZ)
			player.roll = tr.z * 0.8
			player.hull_pitch = tr.x * 0.8
		"periscope":
			var head: Vector3 = sn.get_meta("scope_head")
			var hp := sn.global_transform * head
			var wave := view.ocean.height(hp.x, hp.z)
			var eye := (World.PERI_MAX + 1.5) - s.depth
			var y := eye + wave * 0.15
			scope_wash = clampf((wave - eye + 0.6) / 0.8, 0.0, 1.0)
			world_cam.global_position = Vector3(hp.x, maxf(y, wave + 0.05) if scope_wash < 1.0 else y, hp.z) + shake * 0.2
			world_cam.rotation = Vector3(deg_to_rad(s.scope_elev), U.yaw(view_brg()), 0)
			world_cam.fov = scope_fov()
			if y < wave - 0.3:
				world_cam.environment = under_env
		"bridge":
			var eye: Vector3 = sn.get_meta("bridge_eye")
			var b := sn.global_transform.basis * Basis.from_euler(Vector3(free_pitch, free_yaw, 0), EULER_ORDER_YXZ)
			world_cam.global_transform = Transform3D(b, sn.global_transform * eye + shake)
			world_cam.fov = 11.0 if zoomed else 70.0
		"gun":
			var gp: Node3D = sn.get_meta("gun_pitch")
			var off := Vector3(-0.45, 0.25, 0.4) if zoomed else Vector3(-1.1, 0.55, 2.4)
			world_cam.global_transform = Transform3D(gp.global_transform.basis, gp.global_transform * off + shake)
			world_cam.fov = 14.0 if zoomed else 62.0
		"aa":
			var ay: Node3D = sn.get_meta("aa_yaw")
			view.set_aa_aim(aa_yaw, aa_pitch)
			var ap: Node3D = sn.get_meta("aa_pitch")
			world_cam.global_transform = Transform3D(ap.global_transform.basis, ap.global_transform * Vector3(0, 0.85, 1.6) + shake)
			world_cam.fov = 68.0
		"external":
			var c := sn.global_position + Vector3(0, 3, 0)
			var p := c + Vector3(sin(ext_yaw) * cos(ext_pitch), sin(ext_pitch), cos(ext_yaw) * cos(ext_pitch)) * ext_dist
			world_cam.global_position = p
			world_cam.look_at(c)
			world_cam.fov = 60.0
			if p.y < view.ocean.height(p.x, p.z):
				world_cam.environment = under_env


func _station_prompt() -> void:
	near_station = {}
	if overlay != "":
		hud.prompt.text = ""
		return
	var pp := player.global_position + Vector3(0, 1.5, 0)
	var fwd := -player.cam.global_transform.basis.z
	var best := 1e9
	for st in interior.stations:
		var sp: Vector3 = interior.to_global(st["pos"])
		var d := pp.distance_to(sp)
		if d > 2.0:
			continue
		var facing := fwd.dot((sp - pp).normalized())
		if facing < 0.35:
			continue
		var score := d - facing
		if score < best:
			best = score
			near_station = st
	hud.prompt.text = ("E   " + near_station["prompt"]) if not near_station.is_empty() else ""


func _sounds() -> void:
	var s := world.sub
	var inside := mode == "interior"
	var surf := s.flood < 0.5
	var spd := absf(s.spd)
	sfx.set_loop("motor", (0.18 + spd / 9.0 * 0.25) if (inside and not surf) else 0.0, 0.8 + spd / 20.0)
	sfx.set_loop("diesel", (0.5 if inside else 0.22) if surf else 0.0, 0.85 + spd / 40.0)
	sfx.set_loop("sea", 0.0 if inside else (0.45 if mode != "periscope" else 0.25))
	sfx.set_loop("flow", (spd / 9.0 * 0.25) if (inside and not surf) else 0.0)
