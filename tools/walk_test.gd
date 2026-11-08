extends SceneTree
## Headless check that every watertight door can be walked through, both ways,
## using the real keyboard input path.
## godot --headless --path . -s tools/walk_test.gd -- <nation> <target>

const Game := preload("res://scripts/game.gd")
const Interior := preload("res://scripts/interior/interior.gd")

var game: Game
var frame := 0
var nid := "us"
var tests := []
var cur := {}
var timer := 0.0
var fails := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	nid = args[0] if args.size() > 0 else "us"
	var tid: String = args[1] if args.size() > 1 else "shokaku"
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_mission.call_deferred(nid, tid)
	for dz in Interior.door_zs():
		tests.append({"door": dz, "dir": 1.0})
		tests.append({"door": dz, "dir": -1.0})


func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _process(dt: float) -> bool:
	frame += 1
	if frame < 10:
		return false
	var z: float = game.player.global_position.z - Game.INTERIOR_ORIGIN.z
	if cur.is_empty():
		if tests.is_empty():
			_key(KEY_W, false)
			print("WALK %s %s" % [nid, "OK" if fails == 0 else "FAIL"])
			quit(0 if fails == 0 else 1)
			return true
		cur = tests.pop_front()
		var d: float = cur["dir"]
		game.player.global_position = Game.INTERIOR_ORIGIN + Vector3(0, 0.05, cur["door"] - d * 1.0)
		game.player.velocity = Vector3.ZERO
		game.player.face(0.0 if d < 0.0 else PI)
		_key(KEY_W, true)
		timer = 1.6
		return false
	timer -= dt
	if timer <= 0.0:
		var d: float = cur["dir"]
		var passed: bool = (z - float(cur["door"])) * d > 0.6
		if not passed:
			fails += 1
			print("WALK blocked at door z=%.1f heading %s, stopped at z=%.2f" % [cur["door"], "aft" if d > 0 else "fwd", z])
		cur = {}
	return false
