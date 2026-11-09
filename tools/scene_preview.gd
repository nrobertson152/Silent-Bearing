extends SceneTree
## Renders the outside world for a mission from a few camera positions.
## xvfb-run godot --path . -s tools/scene_preview.gd -- <out_dir> <nation> <target>

const GameData := preload("res://scripts/data.gd")
const U := preload("res://scripts/util.gd")
const World := preload("res://scripts/sim/world.gd")
const WorldView := preload("res://scripts/view/world_view.gd")

var frame := 0
var view: WorldView
var w: World
var cam: Camera3D
var out_dir := "."
var shots := ["scope", "external", "bridge", "action"]
var tag := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "."
	var nid: String = args[1] if args.size() > 1 else "us"
	var tid: String = args[2] if args.size() > 2 else "shokaku"
	tag = nid + "_" + tid
	var nat: Dictionary = GameData.nations()[nid]
	var spec: Dictionary = {}
	for t in nat["targets"]:
		if t["id"] == tid:
			spec = t
	w = World.new(nat, spec)
	var tg: World.Ship = w.target
	tg.pos = Vector2(-500, 1300)
	tg.hdg = 75.0
	for e in w.ships:
		if e.kind == "escort":
			e.pos = World._station(tg, e.off)
			e.hdg = tg.hdg
	view = WorldView.new()
	root.add_child(view)
	view.setup(w)
	cam = Camera3D.new()
	cam.far = 60000.0
	root.add_child(cam)
	cam.current = true


func _process(dt: float) -> bool:
	frame += 1
	w.update(dt)
	for ev in w.events:
		view.handle_event(ev)
	w.events.clear()
	var s := w.sub
	var tg: World.Ship = w.target
	var shot: String = shots[0]
	match shot:
		"scope":
			s.depth = 12.0
			var sp0 := U.to3(s.pos)
			cam.global_position = Vector3(sp0.x, 13.5 - s.depth + view.ocean.height(sp0.x, sp0.z) * 0.5, sp0.z)
			cam.fov = 32.0
			cam.look_at(Vector3(tg.pos.x, 8.0, -tg.pos.y))
		"external":
			s.depth = 0.0
			s.flood = 0.0
			var sp := U.to3(s.pos)
			cam.global_position = sp + Vector3(60, 18, 50)
			cam.fov = 55.0
			cam.look_at(sp + Vector3(0, 2, 0))
		"bridge":
			var eye: Vector3 = view.sub_node.get_meta("bridge_eye")
			cam.global_position = view.sub_node.global_transform * eye
			cam.fov = 60.0
			cam.look_at(Vector3(tg.pos.x, 10.0, -tg.pos.y))
		"action":
			if frame % 40 == 28:
				w.emit({"type": "boom", "pos": Vector3(tg.pos.x, 0, tg.pos.y), "size": 12.0, "kind": "torpedo"})
				w.emit({"type": "splash", "pos": Vector3(s.pos.x + 60, 0, s.pos.y + 300), "size": 8.0})
				w.emit({"type": "dc", "pos": Vector3(s.pos.x - 200, 0, s.pos.y + 500), "depth": 30.0})
				w.emit({"type": "muzzle", "pos": Vector3(tg.pos.x, 10, tg.pos.y), "cal": 127.0, "ship": tg.id})
				tg.fire = 0.8
			cam.global_position = U.to3(s.pos) + Vector3(-30, 9, 0)
			cam.fov = 50.0
			cam.look_at(Vector3(tg.pos.x, 10.0, -tg.pos.y))
	view.sync(dt, cam.global_position)
	if frame % 40 == 0:
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, tag, shot])
		shots.pop_front()
		if shots.is_empty():
			return true
	return false
