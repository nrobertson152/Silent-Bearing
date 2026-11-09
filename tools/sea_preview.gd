extends SceneTree
## Renders the sea, wakes, ships and effects after letting a convoy steam for
## a while, from a handful of fixed cameras. Run with a fixed frame rate so the
## result does not depend on how fast the machine renders:
## xvfb-run godot --path . --fixed-fps 10 -s tools/sea_preview.gd -- <out_dir> <nation> <target> [tod] [shot,shot,...]

const GameData := preload("res://scripts/data.gd")
const U := preload("res://scripts/util.gd")
const World := preload("res://scripts/sim/world.gd")
const WorldView := preload("res://scripts/view/world_view.gd")

const WARM := 140

var frame := 0
var view: WorldView
var w: World
var cam: Camera3D
var out_dir := "."
var tag := ""
var shots := ["close", "bow", "target", "aerial", "scope", "action", "action2", "fire"]
var shot_frame := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "."
	var nid: String = args[1] if args.size() > 1 else "us"
	var tid: String = args[2] if args.size() > 2 else "shokaku"
	var nat: Dictionary = GameData.nations()[nid]
	var spec: Dictionary = {}
	for t in nat["targets"]:
		if t["id"] == tid:
			spec = t.duplicate()
	if args.size() > 3 and args[3] != "-":
		spec["tod"] = args[3]
	if args.size() > 4:
		shots = Array(args[4].split(","))
	tag = nid + "_" + tid + ("_" + args[3] if args.size() > 3 and args[3] != "-" else "")
	w = World.new(nat, spec)
	if args.size() > 3 and args[3] != "-":
		w.tod = args[3]
	var s := w.sub
	s.pos = Vector2(0, 0)
	s.hdg = 30.0
	s.spd = 16.0
	s.depth = 0.0
	s.flood = 0.0
	var tg: World.Ship = w.target
	tg.pos = Vector2(-150, 900)
	tg.hdg = 75.0
	tg.spd = 20.0
	for e in w.ships:
		if e.kind == "escort":
			e.pos = World._station(tg, e.off)
			e.hdg = tg.hdg
			e.spd = tg.spd
		elif e.kind == "chaser":
			e.pos = tg.pos + Vector2(sin(e.orb_a), cos(e.orb_a)) * 900.0
			e.spd = 12.0
	view = WorldView.new()
	root.add_child(view)
	view.setup(w)
	cam = Camera3D.new()
	cam.far = 60000.0
	cam.near = 0.2
	root.add_child(cam)
	cam.current = true


func _move(dt: float) -> void:
	w.t += dt
	var s := w.sub
	s.pos += U.dirv(s.hdg) * s.spd * U.KN * dt
	for e in w.ships:
		e.pos += U.dirv(e.hdg) * e.spd * U.KN * dt


func _process(dt: float) -> bool:
	frame += 1
	_move(dt)
	for ev in w.events:
		view.handle_event(ev)
	w.events.clear()
	var s := w.sub
	var sp := U.to3(s.pos)
	var tg: World.Ship = w.target
	var tp := U.to3(tg.pos)
	var fw := U.to3(U.dirv(s.hdg))
	var tf := U.to3(U.dirv(tg.hdg))
	if frame < WARM:
		cam.global_position = sp + Vector3(40, 20, 40)
		cam.look_at(sp)
		view.sync(dt, cam.global_position)
		return false
	var shot: String = shots[0]
	shot_frame += 1
	match shot:
		"close":
			cam.fov = 55.0
			cam.global_position = sp - fw * 35.0 + Vector3(fw.z, 0, -fw.x) * 45.0 + Vector3(0, 14, 0)
			cam.look_at(sp + fw * 10.0 + Vector3(0, 1, 0))
		"bow":
			cam.fov = 50.0
			cam.global_position = sp + fw * 70.0 + Vector3(-fw.z, 0, fw.x) * 22.0 + Vector3(0, 6, 0)
			cam.look_at(sp + fw * 25.0 + Vector3(0, 1.5, 0))
		"target":
			cam.fov = 45.0
			cam.global_position = tp + tf * 120.0 + Vector3(-tf.z, 0, tf.x) * 260.0 + Vector3(0, 45, 0)
			cam.look_at(tp - tf * 30.0 + Vector3(0, 8, 0))
		"aerial":
			cam.fov = 50.0
			cam.global_position = tp - tf * 160.0 + Vector3(0, 380, 0) + Vector3(-tf.z, 0, tf.x) * 120.0
			cam.look_at(tp - tf * 200.0)
		"scope":
			cam.fov = 32.0
			var eye := sp + Vector3(-fw.z, 0, fw.x) * 30.0
			cam.global_position = Vector3(eye.x, 1.6 + view.ocean.height(eye.x, eye.z) * 0.6, eye.z)
			cam.look_at(tp + Vector3(0, 10, 0))
		"action", "action2", "fire":
			if shot == "action" and shot_frame == 1:
				w.emit({"type": "boom", "pos": Vector3(tg.pos.x, 0, tg.pos.y), "size": 12.0, "kind": "torpedo"})
				w.emit({"type": "splash", "pos": Vector3(tg.pos.x - 120, 0, tg.pos.y - 80), "size": 9.0})
				w.emit({"type": "dc", "pos": Vector3(s.pos.x + 160, 0, s.pos.y + 260), "depth": 30.0})
				w.emit({"type": "muzzle", "pos": Vector3(tg.pos.x, 10, tg.pos.y), "cal": 127.0, "ship": tg.id})
				tg.fire = 0.9
			cam.fov = 48.0
			cam.global_position = sp + fw * 20.0 + Vector3(0, 9, 0)
			cam.look_at(tp + Vector3(0, 14, 0))
	view.sync(dt, cam.global_position)
	var wait: int = {"action": 4, "action2": 12, "fire": 40}.get(shot, 3)
	if shot_frame >= wait:
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, tag, shot])
		shots.pop_front()
		shot_frame = 0
		if shots.is_empty():
			return true
	return false
