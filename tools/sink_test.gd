extends SceneTree
## Headless check that ships go down cleanly with the 3D view attached:
## foundering, capsizing, a magazine explosion and an escort broken in two,
## for one target per navy. Prints SINK OK or SINK FAIL lines.
## godot --headless --path . -s tools/sink_test.gd

const GameData := preload("res://scripts/data.gd")
const Sim := preload("res://scripts/sim/sim.gd")
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
	_modern_battle()
	_missile_battle()
	print("SINK %s" % ("OK" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
	return true


## A near-future attack with the view attached: fire Mk 48s, get hunted by
## helicopters, rockets and torpedoes, and sink the target.
func _modern_battle() -> void:
	var nat: Dictionary = GameData.nations()["us_ssn"]
	var w: World = Sim.create(nat, nat["targets"][0])
	var tg: World.Ship = w.target
	w.sub.pos = tg.pos + U.dirv(tg.hdg) * 9000.0 + U.dirv(tg.hdg + 90.0) * 6000.0
	var view := WorldView.new()
	root.add_child(view)
	view.setup(w)
	w.lock_ship(tg)
	w.lock_obs = 20.0
	w.fire(2)
	w.launch_decoy()
	var frames := 0
	while frames < 2500 and w.result == "":
		w.update(0.2)
		if frames % 50 == 0 and w.sub.spares > 0:
			w.lock_ship(tg)
			w.fire(2)
		for ev in w.events:
			view.handle_event(ev)
		w.events.clear()
		view.sync(0.2, Vector3(0, 30, 600))
		frames += 1
	var ok := w.fired > 0
	print("SINK %s modern battle: result '%s' after %d s, fired %d, hits %d, hull %d" % ["ok  " if ok else "FAIL", w.result, int(w.t),
		w.fired, w.hits, int(w.sub.hull)])
	if not ok:
		fails += 1
	view.queue_free()


## A Tomahawk salvo against the Shandong group with the view attached:
## launches, their missiles, guns and chaff, and the hits.
func _missile_battle() -> void:
	var nat: Dictionary = GameData.nations()["us_ssgn"]
	var w = Sim.create(nat, nat["targets"][0])
	var tg: World.Ship = w.target
	w.sub.pos = tg.pos + U.dirv(tg.hdg) * 30000.0
	w.sub.depth = 20.0
	w.sub.dep_ord = 20.0
	w.sub.spd = 5.0
	w.sub.scope_up = true
	var view := WorldView.new()
	root.add_child(view)
	view.setup(w)
	w.lock_ship(tg)
	w.lock_obs = 20.0
	w.weapon = "tomahawk"
	w.salvo = 64
	w.fire(3)
	var frames := 0
	while frames < 3000 and (w.missiles_out() > 0 or frames < 10):
		w.update(0.2)
		for ev in w.events:
			view.handle_event(ev)
		w.events.clear()
		view.sync(0.2, Vector3(tg.pos.x, 40, -tg.pos.y + 3000))
		frames += 1
	var ok: bool = w.m_fired == 64 and w.m_down > 0 and w.missiles_out() == 0
	print("SINK %s missile battle: result '%s' after %d s, %d fired, %d shot down, %d hits" % ["ok  " if ok else "FAIL", w.result,
		int(w.t), w.m_fired, w.m_down, w.m_hits])
	if not ok:
		fails += 1
	view.queue_free()


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
