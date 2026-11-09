extends SceneTree
## Headless simulation tests: godot --headless --path . -s tests/run_tests.gd

const Ballistics := preload("res://scripts/sim/ballistics.gd")
const Damage := preload("res://scripts/sim/damage.gd")
const GameData := preload("res://scripts/data.gd")
const U := preload("res://scripts/util.gd")
const World := preload("res://scripts/sim/world.gd")

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

	_damage_tests()
	_ballistics_tests()
	_diving_tests()

	print("\n%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _hull(key: String, type: String, nat: String, L: float, B: float, D: float, hp: float) -> Damage:
	var h := Damage.new()
	h.setup(key, type, nat, L, B, D, hp)
	h.mag_risk = 0.0
	return h


func _soak(h: Damage, secs: float) -> void:
	var t := 0.0
	while t < secs and h.afloat():
		h.step(0.25)
		h.events.clear()
		t += 0.25


func _damage_tests() -> void:
	seed(20261108)
	# One torpedo lists a big ship toward the hit side, settles her, and she floats.
	var h1 := _hull("shinano", "cv", "jp", 266.0, 36.0, 10.5, 4.0)
	h1.torpedo(0.5, 1, 1.0)
	_soak(h1, 300.0)
	check(h1.afloat() and h1.list > 2.0 and h1.settle > 0.5,
		"one hit lists her to starboard and settles her (list %.1f, settle %.1f m)" % [h1.list, h1.settle])
	var h2 := _hull("shinano", "cv", "jp", 266.0, 36.0, 10.5, 4.0)
	h2.torpedo(0.5, -1, 1.0)
	_soak(h2, 300.0)
	check(h2.list < -2.0, "a hit to port lists her to port (list %.1f)" % h2.list)
	# A hit forward puts her down by the head.
	var h3 := _hull("kongo", "bb", "jp", 222.0, 31.0, 9.7, 3.0)
	h3.torpedo(0.12, 1, 1.0)
	_soak(h3, 300.0)
	check(h3.trim > 0.3, "a hit forward trims her by the head (trim %.1f)" % h3.trim)
	# Enough hits sink anything, and about as many as the hits-to-sink figure.
	var total := 0
	for k in 10:
		var h := _hull("kongo", "bb", "jp", 222.0, 31.0, 9.7, 3.0)
		var hits := 0
		while h.afloat() and hits < 20:
			h.torpedo(randf_range(0.1, 0.9), 1 if randf() < 0.5 else -1, 1.0)
			hits += 1
			_soak(h, 120.0)
		total += hits
	check(total >= 20 and total <= 45, "a battleship rated three hits takes about three (%.1f on average)" % (total / 10.0))
	# Hits all down one side roll a battleship over.
	var caps := 0
	for k in 10:
		var h := _hull("royaloak", "bb", "uk", 190.0, 27.0, 8.7, 3.0)
		while h.afloat():
			h.torpedo(randf_range(0.3, 0.7), -1, 1.0)
			_soak(h, 120.0)
		if h.mode == "capsize":
			caps += 1
	check(caps >= 6, "hits down one side capsize a battleship (%d of 10)" % caps)
	# A hit right aft can jam the rudder.
	var jams := 0
	for k in 10:
		var h := _hull("kongo", "bb", "jp", 222.0, 31.0, 9.7, 3.0)
		h.torpedo(0.95, 1, 1.0)
		if h.rudder_jam != 0.0:
			jams += 1
	check(jams >= 3, "a hit under the stern jams the rudder (%d of 10)" % jams)
	# A hit in the engine rooms slows her.
	var h4 := _hull("kongo", "bb", "jp", 222.0, 31.0, 9.7, 3.0)
	h4.torpedo(0.56, 1, 1.0)
	check(h4.speed_factor() < 0.85, "a hit in the machinery spaces slows her (%.2f of full speed)" % h4.speed_factor())
	# A torpedo breaks a destroyer's back.
	var dd := _hull("", "dd", "us", 110.0, 11.0, 3.5, 1.0)
	dd.torpedo(0.5, 1, 1.0)
	check(dd.mode == "explode", "a torpedo breaks a destroyer in two")
	# A magazine hit blows her apart where the magazine is.
	var hm := _hull("hood", "bb", "uk", 262.0, 32.0, 9.8, 3.0)
	var mag_i := -1
	for i in hm.mags:
		mag_i = i
		break
	hm._explode(mag_i)
	check(hm.mode == "explode" and absf(hm.break_u - hm.comp_u(mag_i)) < 0.01 and hm.fire[mag_i] > 0.9,
		"a magazine explosion breaks her in two there and leaves her burning")
	# Armour: a 4-inch shell bounces off a battleship's belt but goes through a destroyer.
	var y := _hull("yamato", "bb", "jp", 263.0, 38.9, 10.4, 8.0)
	var r1 := y.shell(0.5, 1, 0.5, 102.0, 700.0, 1.0, 10.0, 100.0)
	var d2 := _hull("", "dd", "jp", 115.0, 10.8, 3.8, 1.0)
	var r2 := d2.shell(0.5, 1, 0.5, 102.0, 700.0, 1.0, 10.0, 100.0)
	check(not r1["pen"] and r2["pen"], "4-inch shells bounce off a battleship belt and hole a destroyer")
	var r3 := y.shell(0.5, 1, 0.5, 460.0, 720.0, 1.0, 10.0, 100.0)
	check(r3["pen"], "an 18-inch shell at close range gets through the belt")
	# Shell hits start fires that burn on without damage control.
	var fires := 0
	for k in 20:
		var hf := _hull("indianapolis", "ca", "us", 186.0, 20.0, 6.4, 2.0)
		var rf := hf.shell(0.4, 1, 6.0, 152.0, 700.0, 1.0, 10.0, 100.0)
		if rf["fire"] or hf.burning() > 0.0:
			fires += 1
	check(fires >= 2, "shell hits start fires (%d of 20)" % fires)


func _ballistics_tests() -> void:
	# The elevation tables agree with flying a shell through the same air.
	for g in [[850.0, 102.0, 6000.0], [650.0, 140.0, 9000.0], [780.0, 380.0, 20000.0]]:
		var v0: float = g[0]
		var cal: float = g[1]
		var r: float = g[2]
		var e := Ballistics.elev_for_range(r, v0, cal)
		var p := Vector3.ZERO
		var v := Vector3(0, sin(deg_to_rad(e)), cos(deg_to_rad(e))) * v0
		var k := Ballistics.drag(cal)
		var t := 0.0
		while t < 200.0:
			var st := Ballistics.fly(p, v, k, 0.1)
			var p2: Vector3 = st[0]
			if p2.y < 0.0 and v.y < 0.0:
				p = p.lerp(p2, p.y / (p.y - p2.y))
				break
			p = p2
			v = st[1]
			t += 0.1
		check(e > 0.0 and absf(p.z - r) < r * 0.02,
			"a %d mm shell at %.1f deg lands at %d m (aimed for %d m)" % [int(cal), e, int(p.z), int(r)])
	check(Ballistics.time_for_range(6000.0, 850.0, 102.0) > 6000.0 / 850.0, "air drag makes the shell slower than its muzzle speed")
	check(Ballistics.penetration(380.0, 600.0) > Ballistics.penetration(102.0, 800.0), "heavy shells penetrate more armour")


func _diving_tests() -> void:
	var nations := GameData.nations()
	var us: Dictionary = nations["us"]
	# Changing depth with way on takes a real down angle, then levels off.
	var w := World.new(us, us["targets"][0])
	w.ships.clear()
	var s := w.sub
	s.flood = 1.0
	s.depth = 12.0
	s.dep_ord = 12.0
	s.tel = 3
	s.spd = 0.3 * float(us["sub_kn"])
	w.set_depth(40.0)
	var min_pitch := 0.0
	for i in 200:
		w.update(0.1)
		min_pitch = minf(min_pitch, s.pitch)
	check(min_pitch < -5.0, "she takes a down angle going deeper (%.0f deg)" % min_pitch)
	for i in 1200:
		w.update(0.1)
	check(absf(s.depth - 40.0) < 2.0 and absf(s.pitch) < 2.0, "she levels off at the ordered depth (%.1f m, %.1f deg)" % [s.depth, s.pitch])
	# With no way on the planes do nothing: depth changes slowly, on the trim tanks.
	var w2 := World.new(us, us["targets"][0])
	w2.ships.clear()
	w2.sub.flood = 1.0
	w2.sub.depth = 30.0
	w2.sub.dep_ord = 30.0
	w2.sub.tel = 2
	w2.sub.spd = 0.0
	w2.set_depth(60.0)
	for i in 300:
		w2.update(0.1)
	check(w2.sub.depth > 31.0 and w2.sub.depth < 45.0 and absf(w2.sub.pitch) < 1.0,
		"stopped, she sinks slowly and level on the trim tanks (%.1f m after 30 s)" % w2.sub.depth)
	# A boat heavy with water sinks when stopped, but holds her depth with speed.
	var w3 := World.new(us, us["targets"][0])
	w3.ships.clear()
	w3.sub.flood = 1.0
	w3.sub.depth = 30.0
	w3.sub.dep_ord = 30.0
	w3.sub.tel = 2
	w3.sub.spd = 0.0
	w3.sub.water = 75.0
	for i in 600:
		w3.update(0.1)
	check(w3.sub.depth > 36.0, "flooded and stopped, she goes down (%.1f m after 60 s)" % w3.sub.depth)
	var w4 := World.new(us, us["targets"][0])
	w4.ships.clear()
	w4.sub.flood = 1.0
	w4.sub.depth = 30.0
	w4.sub.dep_ord = 30.0
	w4.sub.tel = 5
	w4.sub.spd = 0.75 * float(us["sub_kn"])
	w4.sub.water = 75.0
	for i in 600:
		w4.update(0.1)
	check(absf(w4.sub.depth - 30.0) < 3.0 and w4.sub.pitch > 3.0,
		"flooded but making way, she holds depth with an up angle (%.1f m, %.0f deg)" % [w4.sub.depth, w4.sub.pitch])
