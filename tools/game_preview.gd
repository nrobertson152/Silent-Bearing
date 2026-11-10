extends SceneTree
## Drives the real game through its screens and saves screenshots.
## xvfb-run godot --path . --fixed-fps 10 -s tools/game_preview.gd -- <out_dir> <nation> <target>

const Game := preload("res://scripts/game.gd")
const GameData := preload("res://scripts/data.gd")
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
	if GameData.is_modern(GameData.nations()[nid]):
		# The near-future boats: one control room, no deck watch.
		steps = ["menu_modern", "targets", "brief", "start", "interior", "interior_fwd", "sonar", "tdc", "chart",
			"periscope", "periscope_zoom", "external", "under", "result"]
		var ms: Dictionary = GameData.nations()[nid].get("missiles", {})
		if ms.has("tomahawk") or ms.has("harpoon"):
			# A salvo: the launch, their defences at work, and the plot.
			steps.insert(steps.find("external"), "salvo")
			steps.insert(steps.find("external"), "defence")
			steps.insert(steps.find("external"), "missile_chart")
		if ms.has("trident"):
			# The test launch from the box, seen from outside, and the plot.
			steps.insert(steps.find("external"), "box_plot")
			steps.insert(steps.find("external"), "trident")
		if tid in ["jin", "patrol"]:
			steps.insert(steps.find("external"), "sub_view")


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
		"menu_modern":
			game.menu._set_era("modern")
			wait = 2
			steps.pop_front()
			steps.push_front("menu")
			return false
		"sonar", "tdc":
			game.open_overlay(step)
			wait = 4
			steps.pop_front()
			steps.push_front(step + "_snap")
			return false
		"sonar_snap", "tdc_snap":
			_snap("08_" + step.trim_suffix("_snap"))
			game.close_overlay()
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
			if game.modern:
				game.world.sub.depth = 12.0
				game.world.sub.dep_ord = 12.0
				game.world.sub.scope_up = true
				for e in game.world.ships:
					e.heard = true
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
		"salvo":
			var tg := w.target
			tg.pos = w.sub.pos + U.dirv(w.sub.hdg + 20.0) * 9000.0
			tg.hdg = U.wrap360(w.sub.hdg + 110.0)
			for e in w.ships:
				if e.kind == "escort":
					e.pos = World._station(tg, e.off)
					e.hdg = tg.hdg
			w.lock_ship(tg)
			w.lock_obs = 15.0
			w.sub.spd = 5.0
			w.sub.zoom = false
			w.set("weapon", "tomahawk")
			w.set("salvo", 8)
			w.fire(3)
			w.tc = 1
			game.set_mode("external")
			game.ext_dist = 150.0
			game.ext_yaw = 2.6
			game.ext_pitch = 0.1
			wait = 48
			steps.pop_front()
			steps.push_front("salvo_snap")
			return false
		"salvo_snap":
			_snap("17_launch")
			game.open_overlay("tdc")
			wait = 3
			steps.pop_front()
			steps.push_front("salvo_fc_snap")
			return false
		"salvo_fc_snap":
			_snap("17_fire_control")
			game.close_overlay()
		"defence":
			w.tc = 4
			game.set_mode("periscope")
			w.sub.zoom = false
			w.sub.scope_rel = U.adiff(U.brg(w.sub.pos, w.target.pos), w.sub.hdg)
			wait = 70
			steps.pop_front()
			steps.push_front("defence_snap")
			return false
		"defence_snap":
			w.tc = 1
			w.sub.scope_rel = U.adiff(U.brg(w.sub.pos, w.target.pos), w.sub.hdg)
			_snap("18_defence")
		"missile_chart":
			game.chart_r = 12000.0
			game.open_overlay("chart")
			wait = 4
			steps.pop_front()
			steps.push_front("missile_chart_snap")
			return false
		"missile_chart_snap":
			_snap("19_plot_missiles")
			game.close_overlay()
			w.tc = 1
		"box_plot":
			game.chart_r = 24000.0
			game.open_overlay("chart")
			wait = 4
			steps.pop_front()
			steps.push_front("box_plot_snap")
			return false
		"box_plot_snap":
			_snap("20_plot_patrol")
			game.close_overlay()
		"trident":
			w.sub.pos = w.get("box")
			w.sub.depth = 35.0
			w.sub.dep_ord = 35.0
			w.sub.spd = 0.0
			w.sub.tel = 2
			w.sub.scope_up = false
			w.set("weapon", "trident")
			w.etorps.clear()
			w.t += 100.0
			w.fire(3)
			# Skip most of the minute's countdown.
			w.set("launch_seq", w.t - 57.0)
			w.tc = 1
			game.set_mode("external")
			game.ext_dist = 260.0
			game.ext_yaw = 2.4
			game.ext_pitch = 0.32
			wait = 70
			steps.pop_front()
			steps.push_front("trident_snap")
			return false
		"trident_snap":
			w.tc = 1
			_snap("21_trident_launch")
			wait = 40
			steps.pop_front()
			steps.push_front("trident_snap2")
			return false
		"trident_snap2":
			_snap("22_trident_climb")
		"sub_view":
			# Alongside their submarine, under water.
			var tg := w.target
			for e in w.ships:
				if e.type == "ssn" and e.kind == "escort":
					tg = e if tid == "patrol" else tg
			w.sub.pos = tg.pos + U.dirv(tg.hdg + 90.0) * 90.0 + U.dirv(tg.hdg) * 30.0
			w.sub.depth = tg.depth + 25.0
			w.sub.dep_ord = w.sub.depth
			w.sub.hdg = tg.hdg
			game.set_mode("external")
			game.ext_dist = 160.0
			game.ext_yaw = 2.0
			game.ext_pitch = -0.05
			wait = 8
			steps.pop_front()
			steps.push_front("sub_view_snap")
			return false
		"sub_view_snap":
			_snap("23_their_sub")
		"surface":
			w.sub.depth = 0.0
			w.sub.flood = 0.0
			w.sub.dep_ord = 0.0
			w.sub.crew_ready = 0.0
			game.set_mode("interior")
			wait = 3
		"bridge":
			game.go_deck("bridge")
			game.deck_player.face(-deg_to_rad(U.adiff(U.brg(w.sub.pos, w.target.pos), w.sub.hdg)), -0.02)
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
