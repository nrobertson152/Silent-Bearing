extends SceneTree
## Renders a ship going down, from a fixed camera, at eight points through
## her sinking. Run with a fixed frame rate so the result does not depend on
## how fast the machine renders:
## xvfb-run godot --path . --fixed-fps 10 --resolution 960x540 -s tools/sink_preview.gd -- <out_dir> <nation> <target> <how> [tod]
## how: list (one torpedo hit, still afloat), founder, capsize, magazine,
##      broken (an escort's back broken by a torpedo)

const GameData := preload("res://scripts/data.gd")
const U := preload("res://scripts/util.gd")
const World := preload("res://scripts/sim/world.gd")
const WorldView := preload("res://scripts/view/world_view.gd")

## Seconds the whole sinking takes here (compressed; in the game it is longer).
const SINK_TIME := 16.0
const WARM := 30
const SNAPS := [0.0, 0.12, 0.25, 0.4, 0.55, 0.7, 0.85, 0.95]

var frame := 0
var view: WorldView
var w: World
var cam: Camera3D
var ship: World.Ship
var out_dir := "."
var how := "founder"
var tag := ""
var snap_i := 0
var t_sink := 0.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "."
	var nid: String = args[1] if args.size() > 1 else "us"
	var tid: String = args[2] if args.size() > 2 else "shokaku"
	how = args[3] if args.size() > 3 else "founder"
	var nat: Dictionary = GameData.nations()[nid]
	var spec: Dictionary = {}
	for t in nat["targets"]:
		if t["id"] == tid:
			spec = t.duplicate()
	if args.size() > 4:
		spec["tod"] = args[4]
	tag = "%s_%s_%s" % [nid, tid, how]
	w = World.new(nat, spec)
	if args.size() > 4:
		w.tod = args[4]
	w.sub.pos = Vector2(0, -4000)
	w.sub.depth = 30.0
	w.sub.flood = 1.0
	ship = w.target
	if how == "broken":
		for e in w.ships:
			if e.kind != "target":
				ship = e
				break
	for e in w.ships:
		e.spd = 0.0
		e.want_spd = 0.0
		if e != ship:
			e.pos = Vector2(8000 + e.id * 400, 8000)
	ship.pos = Vector2.ZERO
	ship.hdg = 90.0
	var h: World.Damage = ship.hull
	match how:
		"list":
			h.torpedo(0.45, 1, 1.0)
			for i in 600:
				h.step(0.25)
		"founder":
			h.torpedo(0.2, 1, 1.0)
			h.torpedo(0.3, -1, 1.0)
			for i in 400:
				h.step(0.25)
			h.mode = "founder"
		"capsize":
			h.torpedo(0.4, 1, 1.0)
			h.torpedo(0.55, 1, 1.0)
			for i in 200:
				h.step(0.25)
			h.list = maxf(h.list, 24.0)
			h.mode = "capsize"
		"magazine":
			h.mode = "explode"
			h.break_u = 0.72
			var i := clampi(int(h.break_u * h.n), 0, h.n - 1)
			for j in range(maxi(i - 1, 0), mini(i + 2, h.n)):
				h.fire[j] = 1.0
		"broken":
			h.mode = "explode"
			h.break_u = 0.45
			var i := clampi(int(h.break_u * h.n), 0, h.n - 1)
			h.fire[i] = 0.7
	if how != "list":
		ship.struct = 0.0
	view = WorldView.new()
	root.add_child(view)
	view.setup(w)
	cam = Camera3D.new()
	cam.far = 60000.0
	cam.near = 0.5
	root.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var L := ship.length
	var d := L * 1.7 + 80.0
	cam.look_at_from_position(Vector3(L * 0.3, L * 0.16 + 8.0, d), Vector3(0, L * 0.1, 0))


func _process(dt: float) -> bool:
	frame += 1
	w.t += dt
	if frame == WARM and how == "magazine":
		w.emit({"type": "boom", "pos": Vector3(ship.pos.x, 4.0, ship.pos.y), "size": ship.length / 7.0,
			"kind": "magazine", "ship": ship.id, "u": ship.hull.break_u})
	if frame >= WARM and how != "list":
		t_sink += dt
		ship.sinking = clampf(t_sink / SINK_TIME, 0.0, 1.0)
	for ev in w.events:
		view.handle_event(ev)
	w.events.clear()
	view.sync(dt, cam.global_position)
	if frame < WARM:
		return false
	var at: float = SNAPS[snap_i]
	var now := ship.sinking if how != "list" else float(frame - WARM) / 160.0
	if now >= at:
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [out_dir, tag, snap_i])
		snap_i += 1
		if snap_i >= SNAPS.size():
			print("SINK PREVIEW DONE ", tag, " list=%.1f trim=%.1f settle=%.1f mode=%s" % [ship.hull.list, ship.hull.trim, ship.hull.settle, ship.hull.mode])
			return true
	return false
