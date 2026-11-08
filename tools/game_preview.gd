extends SceneTree
## Drives the real game through its screens and saves screenshots.
## xvfb-run godot --path . --rendering-driver opengl3 -s tools/game_preview.gd -- <out_dir> <nation> <target>

const Game := preload("res://scripts/game.gd")
const U := preload("res://scripts/util.gd")
const World := preload("res://scripts/sim/world.gd")

var game: Game
var frame := 0
var out_dir := "."
var nid := "us"
var tid := "shokaku"
var steps := []
var wait := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "."
	nid = args[1] if args.size() > 1 else "us"
	tid = args[2] if args.size() > 2 else "shokaku"
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	steps = ["menu", "targets", "brief", "start", "interior", "interior_fwd", "torpedo_room", "engine_room", "chart",
		"periscope", "periscope_zoom", "surface", "bridge", "gun", "aa", "external", "under", "result"]


func _snap(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s.png" % [out_dir, nid, tid, name])


func _process(_dt: float) -> bool:
	frame += 1
	if wait > 0:
		wait -= 1
		return false
	if steps.is_empty():
		return true
	var step: String = steps[0]
	var w := game.world
	match step:
		"menu":
			_snap("01_menu")
		"targets":
			game.menu.nat_id = nid
			game.menu.show_step("target")
			wait = 2
			steps.pop_front()
			steps.push_front("targets_snap")
			return false
		"targets_snap":
			_snap("02_targets")
		"brief":
			game.menu.tgt_id = tid
			game.menu.show_step("brief")
			wait = 2
			steps.pop_front()
			steps.push_front("brief_snap")
			return false
		"brief_snap":
			_snap("03_brief")
		"start":
			game.start_mission(nid, tid)
			var tg := game.world.target
			tg.pos = Vector2(-700, 1500)
			tg.hdg = 80.0
			for e in game.world.ships:
				if e.kind == "escort":
					e.pos = World._station(tg, e.off)
					e.hdg = tg.hdg
			game.world.lock_ship(tg)
			game.world.lock_obs = 15.0
			wait = 20
		"interior":
			game.player.global_position = Game.INTERIOR_ORIGIN + Vector3(0.4, 0.05, 6.0)
			game.player.face(0.0, -0.08)
			wait = 8
			steps.pop_front()
			steps.push_front("interior_snap")
			return false
		"interior_snap":
			_snap("04_control_room")
		"interior_fwd":
			game.player.global_position = Game.INTERIOR_ORIGIN + Vector3(-0.2, 0.05, -3.0)
			game.player.face(deg_to_rad(40), -0.15)
			wait = 6
			steps.pop_front()
			steps.push_front("fwd_snap")
			return false
		"fwd_snap":
			_snap("05_control_fwd")
		"torpedo_room":
			game.player.global_position = Game.INTERIOR_ORIGIN + Vector3(0, 0.05, -10.0)
			game.player.face(0.0, -0.1)
			game.world.sub.tubes[0] = 20.0
			wait = 6
			steps.pop_front()
			steps.push_front("torp_snap")
			return false
		"torp_snap":
			_snap("06_torpedo_room")
		"engine_room":
			game.player.global_position = Game.INTERIOR_ORIGIN + Vector3(0, 0.05, 10.0)
			game.player.face(PI, -0.1)
			wait = 6
			steps.pop_front()
			steps.push_front("eng_snap")
			return false
		"eng_snap":
			_snap("07_engine_room")
		"chart":
			game.open_overlay("chart")
			wait = 4
			steps.pop_front()
			steps.push_front("chart_snap")
			return false
		"chart_snap":
			_snap("08_plot_table")
			game.close_overlay()
		"periscope":
			game.set_mode("periscope")
			var tg := w.target
			w.sub.scope_rel = U.adiff(U.brg(w.sub.pos, tg.pos), w.sub.hdg) + 3.0
			wait = 10
			steps.pop_front()
			steps.push_front("scope_snap")
			return false
		"scope_snap":
			_snap("09_periscope")
		"periscope_zoom":
			w.sub.zoom = true
			w.sub.scope_rel = U.adiff(U.brg(w.sub.pos, w.target.pos), w.sub.hdg)
			wait = 6
			steps.pop_front()
			steps.push_front("zoom_snap")
			return false
		"zoom_snap":
			_snap("10_periscope_high")
			w.sub.zoom = false
		"surface":
			w.sub.depth = 0.0
			w.sub.flood = 0.0
			w.sub.dep_ord = 0.0
			w.sub.crew_ready = 0.0
			game.set_mode("interior")
			wait = 3
		"bridge":
			game.go_deck("bridge")
			game.free_yaw = -deg_to_rad(U.adiff(U.brg(w.sub.pos, w.target.pos), w.sub.hdg))
			wait = 8
			steps.pop_front()
			steps.push_front("bridge_snap")
			return false
		"bridge_snap":
			_snap("11_bridge")
		"gun":
			game.set_mode("gun")
			game.gun_t = U.adiff(U.brg(w.sub.pos, w.target.pos), w.sub.hdg)
			if w.gun_blocked(game.gun_t):
				game.gun_t = 90.0
			w.sub.gun_trav = game.gun_t
			game.gun_e = 3.0
			w.sub.gun_elev = 3.0
			w.fire_gun()
			wait = 10
			steps.pop_front()
			steps.push_front("gun_snap")
			return false
		"gun_snap":
			_snap("12_deck_gun")
		"aa":
			game.set_mode("aa")
			if not w.planes.is_empty():
				var p = w.planes[0]
				p.pos = w.sub.pos + Vector2(300, 900)
				p.alt = 250.0
			game.aa_yaw = 0.3
			game.aa_pitch = 0.35
			game.firing_aa = true
			wait = 12
			steps.pop_front()
			steps.push_front("aa_snap")
			return false
		"aa_snap":
			game.firing_aa = false
			_snap("13_aa_gun")
		"external":
			game.set_mode("external")
			game.ext_dist = 110.0
			game.ext_yaw = 0.9
			game.ext_pitch = 0.18
			wait = 8
			steps.pop_front()
			steps.push_front("ext_snap")
			return false
		"ext_snap":
			_snap("14_outside")
		"under":
			w.sub.dep_ord = 40.0
			w.sub.flood = 1.0
			w.sub.depth = 30.0
			game.ext_pitch = -0.25
			game.ext_dist = 70.0
			wait = 8
			steps.pop_front()
			steps.push_front("under_snap")
			return false
		"under_snap":
			_snap("15_underwater")
		"result":
			w.result = "win"
			game.result_shown = true
			game.hud.show_result()
			wait = 3
			steps.pop_front()
			steps.push_front("result_snap")
			return false
		"result_snap":
			_snap("16_result")
	steps.pop_front()
	return false
