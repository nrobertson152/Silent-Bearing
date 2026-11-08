extends SceneTree
## Drives the deck through the real input path and checks it works:
## surfacing, walking on deck, climbing down a ladder, manning the gun and
## firing it with a real left click, the third-person view, and the two ways
## to die on deck (a bomb, and staying up there when she dives).
## Saves screenshots along the way when an output directory is given.
## xvfb-run godot --path . --rendering-driver opengl3 -s tools/deck_test.gd -- <out_dir|-> <nation> <target>

const Game := preload("res://scripts/game.gd")
const World := preload("res://scripts/sim/world.gd")

var game: Game
var out_dir := ""
var nid := "us"
var tid := "shokaku"
var step := 0
var wait := 0.0
var fails := 0
var note := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 and args[0] != "-" else ""
	nid = args[1] if args.size() > 1 else "us"
	tid = args[2] if args.size() > 2 else "shokaku"
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_mission.call_deferred(nid, tid)


func _check(ok: bool, what: String) -> void:
	print("DECK %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _snap(name: String) -> void:
	if out_dir != "":
		root.get_viewport().get_texture().get_image().save_png("%s/%s_deck_%s.png" % [out_dir, nid, name])


func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _click(down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	Input.parse_input_event(ev)


func _surface_now() -> void:
	var s = game.world.sub
	s.depth = 0.0
	s.flood = 0.0
	s.dep_ord = 0.0
	s.crew_ready = 0.0
	s.scope_up = false
	game.world.tc = 1


func _process(dt: float) -> bool:
	if wait > 0.0:
		wait -= dt
		return false
	var w = game.world
	var s = w.sub if w else null
	step += 1
	match step:
		1:
			wait = 0.5
		2:
			_surface_now()
			_tap(KEY_3)
			wait = 0.6
		3:
			_check(game.mode == "deck", "3 puts you on the bridge (mode=%s)" % game.mode)
			_check(w.exposed(), "sim knows you're exposed on deck")
			_snap("01_bridge")
			# Walk aft across the bridge to the ladder.
			game.deck_player.global_position += Vector3(0.75, 0, 0)
			game.deck_player.face(PI)
			_key(KEY_W, true)
			wait = 4.0
		4:
			_key(KEY_W, false)
			_check(not game.near_station.is_empty() and game.near_station["name"] == "down_aft",
				"walking aft reaches the after ladder (near=%s)" % game.near_station.get("name", "none"))
			_tap(KEY_E)
			wait = 0.4
		5:
			var z: float = game.deck_player.global_position.z - Game.DECK_ORIGIN.z
			_check(z > float(game.deck.g["tz"]) + float(game.deck.g["tl"]) * 0.5, "E climbs down to the after casing (z=%.1f)" % z)
			_snap("02_casing")
			# Walk to the gun and man it with E.
			var gs: Vector3 = game.deck.spots["gun"]
			game.deck_player.global_position = Game.DECK_ORIGIN + gs + Vector3(0, 0, 0)
			var gz: float = game.deck.g["gun_z"]
			game.deck_player.face(0.0 if gz < gs.z else PI, -0.2)
			wait = 0.4
		6:
			_check(game.near_station.get("name", "") == "gun", "standing at the gun offers 'Man the deck gun' (near=%s)" % game.near_station.get("name", "none"))
			_snap("03_at_gun")
			_tap(KEY_E)
			wait = 0.5
		7:
			_check(game.mode == "gun", "E mans the gun (mode=%s)" % game.mode)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			# Train abeam so the conning tower can't be in the way.
			game.gun_t = 90.0
			game.gun_e = 2.0
			wait = 3.0
		8:
			note["ammo"] = s.gun_ammo
			note["shells"] = w.shells.size()
			_click(true)
			_click(false)
			wait = 0.15
		9:
			_check(s.gun_ammo == note["ammo"] - 1, "left click fires the deck gun (ammo %d -> %d, mouse captured=%s)" % [note["ammo"], s.gun_ammo, Input.mouse_mode == Input.MOUSE_MODE_CAPTURED])
			_snap("04_gun_fired")
			wait = 0.5
		10:
			_tap(KEY_V)
			wait = 0.8
		11:
			_check(game.mode == "external", "V switches to the outside view")
			_check(game.deck.me_holder.visible, "your own figure is drawn on deck in the outside view")
			_snap("05_third_person")
			_tap(KEY_V)
			wait = 0.3
		12:
			_check(game.mode == "gun", "V again returns to the gun (mode=%s)" % game.mode)
			_tap(KEY_E)
			wait = 0.3
		13:
			_check(game.mode == "deck", "E steps away from the gun onto the deck")
			# Death by bomb: drop one right beside the player.
			var cp: Vector2 = w.crew_pos()
			var b := World.Shell.new()
			b.kind = "bomb"
			b.p = Vector3(cp.x + 6.0, 0.0, cp.y)
			w._shell_impact(b)
			_check(w.result == "killed", "a bomb bursting 6 m away kills you on deck (result=%s)" % w.result)
			wait = 3.5
		14:
			_snap("06_killed")
			_check(game.result_shown and game.hud.result.visible, "the patrol ends with the result screen")
			# Fresh patrol for the drowning check.
			game.start_mission(nid, tid)
			wait = 0.5
		15:
			_surface_now()
			_tap(KEY_3)
			wait = 0.3
		16:
			w.set_depth(30.0)
			wait = 0.3
		17:
			_check(w.awash_in > 0.0, "diving with you on deck starts the awash countdown (%.1f s)" % w.awash_in)
			_snap("07_diving_warning")
			w.tc = 16
			wait = 3.0
		18:
			if w.result == "" and s.flood < 0.6:
				step -= 1
				wait = 1.0
				return false
			_check(w.result == "drowned", "staying on deck as she dives drowns you (result=%s)" % w.result)
			# Third patrol: get below in time and live.
			game.start_mission(nid, tid)
			wait = 0.5
		19:
			_surface_now()
			_tap(KEY_3)
			wait = 0.3
		20:
			w.set_depth(30.0)
			var h: Dictionary = {}
			for st in game.deck.stations:
				if st["name"] == "hatch":
					h = st
			game.deck_player.global_position = Game.DECK_ORIGIN + Vector3(0, h["pos"].y - 0.25, h["pos"].z + 0.8)
			game.deck_player.face(0.0, -0.7)
			wait = 0.3
		21:
			_check(game.near_station.get("name", "") == "hatch", "the bridge hatch is offered (near=%s)" % game.near_station.get("name", "none"))
			_tap(KEY_E)
			w.tc = 16
			wait = 3.0
		22:
			_check(game.mode == "interior" and not w.exposed(), "E at the hatch takes you below")
			_check(w.result == "", "going below in time keeps you alive (result=%s)" % w.result)
			print("DECK %s %s" % [nid, "OK" if fails == 0 else "FAIL (%d)" % fails])
			quit(0 if fails == 0 else 1)
	return false

