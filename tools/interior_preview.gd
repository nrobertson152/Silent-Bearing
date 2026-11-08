extends SceneTree
## Walks through every compartment and saves a screenshot from each.
## xvfb-run godot --path . --rendering-driver opengl3 -s tools/interior_preview.gd -- <out_dir> <nation> <target>

const Game := preload("res://scripts/game.gd")

var game: Game
var out_dir := "."
var nid := "us"
var tid := "shokaku"
var wait := 30
var i := 0
## [name, position, yaw (0 = facing bow), pitch]
var shots := [
	["ftr", Vector3(0.3, 0.05, -28.0), 0.0, -0.05],
	["ftr_aft", Vector3(0.0, 0.05, -31.0), PI, -0.05],
	["officers", Vector3(0.0, 0.05, -18.5), 0.0, -0.08],
	["wardroom", Vector3(0.0, 0.05, -22.5), deg_to_rad(-60), -0.15],
	["control_fwd", Vector3(-0.2, 0.05, -10.0), deg_to_rad(10), -0.12],
	["helm", Vector3(-0.8, 0.05, -14.4), deg_to_rad(20), -0.2],
	["dive", Vector3(-0.2, 0.05, -13.2), deg_to_rad(-50), -0.2],
	["control_aft", Vector3(0.2, 0.05, -13.0), PI, -0.1],
	["galley", Vector3(0.1, 0.05, -5.0), deg_to_rad(10), -0.1],
	["berthing", Vector3(0.0, 0.05, 4.2), 0.0, -0.05],
	["engine", Vector3(0.0, 0.05, 6.0), PI, -0.12],
	["maneuvering", Vector3(-0.3, 0.05, 24.0), PI, -0.1],
	["atr", Vector3(0.0, 0.05, 30.0), PI, -0.05],
	["door", Vector3(0.0, 0.05, -3.0), PI, -0.05],
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "."
	nid = args[1] if args.size() > 1 else "us"
	tid = args[2] if args.size() > 2 else "shokaku"
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_mission.call_deferred(nid, tid)


func _process(_dt: float) -> bool:
	if wait > 0:
		wait -= 1
		return false
	if i > 0:
		var prev: Array = shots[i - 1]
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%02d_%s.png" % [out_dir, nid, i, prev[0]])
	if i >= shots.size():
		return true
	var s: Array = shots[i]
	game.player.global_position = Game.INTERIOR_ORIGIN + s[1]
	game.player.face(s[2], s[3])
	i += 1
	wait = 6
	return false
