extends SceneTree
## Headless check that ships go down cleanly with the 3D view attached:
## foundering, capsizing, a magazine explosion and an escort broken in two,
## for one target per navy. Prints SINK OK or SINK FAIL lines.
## godot --headless --path . -s tools/sink_test.gd

const GameData := preload("res://scripts/data.gd")
const U := preload("res://scripts/util.gd")
const World := preload("res://scripts/sim/world.gd")
const WorldView := preload("res://scripts/view/world_view.gd")

const CASES := [["us", "shinano"], ["uk", "tirpitz"], ["de", "hood"], ["jp", "yorktown"]]

var fails := 0


func _process(_dt: float) -> bool:
	# Runs once the scene tree is up, so the view has a viewport.
	seed(4)
	for c in CASES:
		for how in ["founder", "capsize", "magazine", "broken"]:
			_run(c[0], c[1], how)
	print("SINK %s" % ("OK" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
	return true


func _run(nid: String, tid: String, how: String) -> void:
	var nat: Dictionary = GameData.nations()[nid]
	var spec: Dictionary = {}
	for t in nat["targets"]:
		if t["id"] == tid:
			spec = t
	var w := World.new(nat, spec)
	w.sub.pos = Vector2(0, -6000)
	w.sub.depth = 60.0
	w.sub.dep_ord = 60.0
	w.sub.flood = 1.0
	var ship: World.Ship = w.target
	if how == "broken":
		for e in w.ships:
			if e.kind == "escort":
				ship = e
				break
	var view := WorldView.new()
	root.add_child(view)
	view.setup(w)
	var h: World.Damage = ship.hull
	match how:
		"founder":
			var side := 1
			while h.afloat():
				h.torpedo(randf_range(0.2, 0.8), side, 1.0)
				side = -side
				for i in 120:
					h.step(0.5)
		"capsize":
			while h.afloat():
				h.torpedo(randf_range(0.3, 0.7), 1, 1.0)
				for i in 120:
					h.step(0.5)
		"magazine":
			var mag_i := -1
			for i in h.mags:
				mag_i = i
			h._explode(mag_i)
		"broken":
			h.torpedo(0.5, 1, 1.0)
	var frames := 0
	var saw_split := false
	var lowest := 0.0
	while not ship.dead and frames < 900:
		w.update(0.2)
		for ev in w.events:
			view.handle_event(ev)
		w.events.clear()
		view.sync(0.2, Vector3(0, 30, 600))
		var rec: Dictionary = view.ships[ship.id]
		saw_split = saw_split or rec["aft"] != null
		lowest = minf(lowest, (rec["node"] as Node3D).global_position.y)
		frames += 1
	var rec: Dictionary = view.ships[ship.id]
	var ok := ship.dead and not (rec["node"] as Node3D).visible
	if h.mode == "explode":
		ok = ok and saw_split and rec["aft"] != null and not (rec["aft"] as Node3D).visible
	var line := "%s %s %s: mode=%s dead=%s split=%s sank to %.0f m in %.0f s" % [nid, tid, how, h.mode, ship.dead, saw_split, lowest, frames * 0.2]
	if ok:
		print("SINK ok   ", line)
	else:
		fails += 1
		print("SINK FAIL ", line)
	view.queue_free()
