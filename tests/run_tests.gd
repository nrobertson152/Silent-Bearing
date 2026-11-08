extends SceneTree
## Headless simulation tests: godot --headless --path . -s tests/run_tests.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok   ", msg)


func _init() -> void:
	var nations := GameData.nations()
	# Every mission runs for ten simulated minutes without errors.
	for nid in GameData.NATION_ORDER:
		var nat: Dictionary = nations[nid]
		for spec in nat["targets"]:
			var w := World.new(nat, spec)
			for i in 6000:
				w.update(0.1)
			check(w.sub.hull >= 0.0, "%s vs %s runs (result '%s', t=%d)" % [nid, spec["id"], w.result, int(w.t)])

	# The TDC leads a crossing target.
	var uk: Dictionary = nations["uk"]
	var w2 := World.new(uk, uk["targets"][0])
	var tg: World.Ship = w2.target
	tg.pos = Vector2(-1500, 1500)
	tg.hdg = 90.0
	tg.spd = 15.0
	w2.lock = tg
	w2.lock_obs = 20.0
	var sol = w2.solution()
	check(sol != null and U.adiff(sol["hdg"], U.brg(w2.sub.pos, tg.pos)) > 0.0, "solution leads a crossing target")

	# A torpedo on the solution hits a steady target.
	var jp: Dictionary = nations["jp"]
	var spec_i: Dictionary = jp["targets"][2]
	var w3 := World.new(jp, spec_i)
	var t3: World.Ship = w3.target
	t3.pos = Vector2(-1800, 1800)
	t3.hdg = 90.0
	t3.leg = 90.0
	t3.spd = 17.0
	t3.want_spd = 17.0
	t3.cruise = 17.0
	t3.zig = false
	w3.sub.hdg = 0.0
	w3.lock = t3
	w3.lock_obs = 30.0
	var s0 := t3.struct
	w3.fire(1)
	for i in 1200:
		w3.update(0.1)
	check(t3.struct < s0 or w3.duds > 0, "torpedo on the solution hits")

	# Surfacing blows ballast, charges the battery and readies the gun.
	var us: Dictionary = nations["us"]
	var w4 := World.new(us, us["targets"][0])
	w4.sub.bat = 50.0
	w4.set_depth(0.0)
	for i in 600:
		w4.update(0.1)
	check(w4.sub.surfaced(), "boat surfaces")
	check(w4.sub.bat > 50.0, "battery charges on the surface")
	check(w4.gun_ready() == "ready", "deck gun manned after surfacing")
	# Diving again takes time.
	w4.set_depth(30.0)
	w4.update(1.0)
	check(w4.sub.depth < 5.0, "diving from the surface is not instant")
	for i in 900:
		w4.update(0.1)
	check(w4.sub.depth > 25.0, "boat dives after flooding ballast")

	# Deck gun shells can hit a nearby ship.
	var w5 := World.new(us, us["targets"][0])
	w5.set_depth(0.0)
	for i in 400:
		w5.update(0.1)
	var tgt: World.Ship = w5.target
	tgt.pos = w5.sub.pos + Vector2(1500, 0)
	tgt.hdg = 0.0
	tgt.spd = 0.0
	tgt.want_spd = 0.0
	tgt.cruise = 0.0
	tgt.max_kn = 0.0
	w5.sub.hdg = 0.0
	w5.sub.spd = 0.0
	w5.sub.tel = 2
	w5.sub.gun_trav = 90.0
	w5.sub.gun_elev = U.elev_for_range(1500.0, float(us["gun"]["v"])) + 0.1
	var before := tgt.struct
	for k in 6:
		w5.sub.gun_reload = 0.0
		w5.fire_gun()
		for i in 40:
			w5.update(0.1)
	check(tgt.struct < before, "deck gun hits a ship at 1,500 m")

	# Crush depth ends the patrol.
	var w6 := World.new(us, us["targets"][0])
	w6.sub.depth = float(us["crush"]) + 1.0
	w6.sub.dep_ord = w6.sub.depth
	w6.update(0.1)
	check(w6.result == "crushed", "crush depth ends the patrol")

	print("\n%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
