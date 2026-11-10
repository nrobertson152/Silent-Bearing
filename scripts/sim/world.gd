extends RefCounted
## The whole battle: your boat, the target, escorts, sub-chasers, aircraft,
## torpedoes, depth charges, shells and bombs. No rendering in here, so the
## simulation can be stepped headlessly by tests.
##
## Sim space: Vector2(x east, y north) in metres. 3D sim vectors are
## Vector3(x, altitude, north). U.to3() converts to Godot space.

const Ballistics := preload("res://scripts/sim/ballistics.gd")
const Damage := preload("res://scripts/sim/damage.gd")
const GameData := preload("res://scripts/data.gd")
const U := preload("res://scripts/util.gd")

const PERI_MAX := 14.5
const FIRE_MAX := 40.0
const RELOAD := 45.0
const ARM_DIST := 250.0
const ESCAPE := 18000.0
const GRAV := 9.81

const TELEGRAPH := [["BACK FULL", -0.5], ["BACK 1/3", -0.2], ["ALL STOP", 0.0], ["AHEAD 1/3", 0.3],
	["AHEAD 2/3", 0.55], ["STANDARD", 0.75], ["FULL", 0.9], ["FLANK", 1.0]]
const RUDDER := [[-35.0, "HARD LEFT"], [-15.0, "LEFT 15"], [0.0, "MIDSHIPS"], [15.0, "RIGHT 15"], [35.0, "HARD RIGHT"]]
const STATIONS := [Vector2(2000, 0), Vector2(600, 1500), Vector2(600, -1500), Vector2(-1200, 1200), Vector2(-1200, -1200)]
const VIS := {"day": 14000.0, "dusk": 8000.0, "night": 5000.0}
const SYSTEMS := ["periscope", "hydrophones", "diesels", "motors", "planes", "tubes", "gun", "pumps"]
const SYS_NAMES := {"periscope": "Periscope", "hydrophones": "Hydrophones", "diesels": "Diesels",
	"motors": "Electric motors", "planes": "Dive planes", "tubes": "Torpedo tubes", "gun": "Deck gun", "pumps": "Bilge pumps"}

# Ship gun batteries by type: calibre mm, barrels per salvo, reload s, range m, damage, muzzle velocity, min range
const BATTERIES := {
	"dd": [{"cal": 127.0, "n": 2, "reload": 6.0, "range": 14000.0, "dmg": 12.0, "v": 790.0, "min": 150.0}],
	"pc": [{"cal": 76.0, "n": 1, "reload": 4.0, "range": 9000.0, "dmg": 7.0, "v": 700.0, "min": 100.0}],
	"cl": [{"cal": 127.0, "n": 3, "reload": 5.0, "range": 14000.0, "dmg": 12.0, "v": 790.0, "min": 200.0},
		{"cal": 152.0, "n": 4, "reload": 9.0, "range": 20000.0, "dmg": 22.0, "v": 850.0, "min": 2500.0}],
	"ca": [{"cal": 127.0, "n": 3, "reload": 5.0, "range": 14000.0, "dmg": 12.0, "v": 790.0, "min": 200.0},
		{"cal": 203.0, "n": 6, "reload": 15.0, "range": 25000.0, "dmg": 45.0, "v": 830.0, "min": 3000.0}],
	"bb": [{"cal": 150.0, "n": 4, "reload": 7.0, "range": 18000.0, "dmg": 20.0, "v": 850.0, "min": 300.0},
		{"cal": 380.0, "n": 6, "reload": 35.0, "range": 30000.0, "dmg": 90.0, "v": 800.0, "min": 4000.0}],
	"cv": [{"cal": 127.0, "n": 4, "reload": 5.0, "range": 12000.0, "dmg": 12.0, "v": 790.0, "min": 200.0}],
}


class Sub:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var hdg := 0.0
	var spd := 2.0
	var tel := 3
	var rud_i := 2
	var rud := 0.0
	var depth := 12.0
	var dep_ord := 12.0
	var crash := false
	var flood := 1.0          # main ballast: 1 flooded (submerged trim), 0 blown (surfaced)
	var hull := 100.0
	var leak := 0.0           # flooding rate
	var water := 0.0          # water taken aboard, 0..100
	var bat := 100.0
	var air := 100.0
	var scope_up := true
	var scope_rel := 0.0
	var scope_elev := 0.0
	var zoom := false
	var tubes: Array = []     # 0 loaded, >0 reloading, -1 empty
	var spares := 0
	var torp_depth := 4.0
	var gun_ammo := 0
	var gun_reload := 0.0
	var gun_trav := 0.0       # relative to bow, degrees
	var gun_elev := 2.0
	var crew_ready := 0.0     # seconds until the gun crews are on deck
	var aa_reload := 0.0
	var sys := {}
	var grounded := false
	var decoys := 0           # near-future boats: decoys left to launch
	var pitch := 0.0          # hull angle, degrees, + = bow up
	var vz := 0.0             # vertical speed, m/s, + = going deeper
	var ballast := 0.0        # variable ballast, m/s it adds to vz (+ = flooded, heavy)

	func surfaced() -> bool:
		return depth < 0.8 and flood < 0.05

	func can_see() -> bool:
		if surfaced():
			return true
		return scope_up and depth <= PERI_MAX and sys["periscope"] > 25.0


class Ship:
	var id := 0
	var name := ""
	var short := ""
	var nation := ""
	var type := "dd"
	var kind := "escort"      # target, escort, chaser
	var layout := ""
	var length := 115.0
	var beam := 11.0
	var draft := 3.5
	var pos := Vector2.ZERO
	var hdg := 0.0
	var spd := 0.0
	var want_spd := 0.0
	var max_kn := 30.0
	var cruise := 15.0
	var struct := 100.0
	var max_struct := 100.0
	var sinking := 0.0
	var sink_side := 1.0
	var dead := false
	var fire := 0.0
	var plot = null
	var heard := false
	var ever_heard := false
	var ever_seen := false
	var state := "screen"
	var detect := 0.0
	var est := Vector2.ZERO
	var has_est := false
	var est_depth := 30.0
	var last_fix := -999.0
	var to_drop := 0
	var next_dc := 0.0
	var run_until := 0.0
	var search_until := 0.0
	var orbit := false
	var orb_a := 0.0
	var orb_r := 1400.0
	var orb_dir := 1
	var off := Vector2.ZERO
	var leg := 0.0
	var base_hdg := 0.0
	var next_zig := 0.0
	var zig := false
	var guns: Array = []
	var spread := 1.0
	var aim_hdg := 0.0
	var aim_spd := 0.0
	var aware := false
	var comb_done := false
	var hits_taken := 0
	var hull: Damage            # compartments, flooding, list, machinery, rudder, fires
	var said := {}              # damage reports already given
	var depth := 0.0            # submarines: metres below the surface
	var want_depth := 0.0
	var route: Array = []       # patrol line [from, to] for units that patrol rather than screen
	var home := "screen"        # the state a unit goes back to when the hunt is off
	var loud_until := 0.0       # a submarine that just fired is loud on our array till then

	func alive() -> bool:
		return not dead and struct > 0.0

	func hunting() -> bool:
		return state == "hunt" or state == "run"


class Aircraft:
	var id := 0
	var key := ""
	var info := {}
	var name := ""
	var pos := Vector2.ZERO
	var alt := 400.0
	var hdg := 0.0
	var kn := 120.0
	var state := "patrol"
	var bombs := 2
	var hp := 4
	var center := Vector2.ZERO
	var orb_r := 5000.0
	var orb_dir := 1
	var tgt := Vector2.ZERO
	var detect := 0.0
	var seen_t := -999.0
	var pass_until := 0.0
	var prev_d := 1e9
	var strafe_next := 0.0
	var dead := false
	var falling := false
	var leave_at := 0.0
	var spotted := false
	var roll := 0.0

	func pos3() -> Vector3:
		return Vector3(pos.x, alt, pos.y)


class Torpedo:
	var id := 0
	var pos := Vector2.ZERO
	var hdg := 0.0
	var kn := 45.0
	var rng := 4000.0
	var run := 0.0
	var wake := true
	var depth := 4.0
	var trail: Array = []


class Charge:
	var pos := Vector2.ZERO
	var z := 0.0
	var fuse := 30.0
	var sink := 3.2
	var aerial := false


class Shell:
	var id := 0
	var p := Vector3.ZERO
	var v := Vector3.ZERO
	var kind := "ship"        # ship, gun, aa, bomb
	var dmg := 10.0
	var cal := 100.0
	var life := 0.0
	var owner := -1


var nat: Dictionary
var spec: Dictionary
var demo := false
var t := 0.0
var tc := 1
var tod := "day"
var vis := 14000.0
var sub: Sub
var ships: Array[Ship] = []
var planes: Array[Aircraft] = []
var torps: Array[Torpedo] = []
var charges: Array[Charge] = []
var shells: Array[Shell] = []
var islands: Array = []
var msgs: Array = []
var events: Array = []
var target: Ship
var lock: Ship = null
var lock_obs := 0.0
var lock_err := Vector2.ZERO
var alert := false
var fired := 0
var hits := 0
var duds := 0
var esc_sunk := 0
var gun_hits := 0
var planes_down := 0
var result := ""
var end_delay := 0.0
var shake := 0.0
var ping_flash := 0.0
var next_ping := 0.0
var ram_cool := 0.0
var layer_depth := 60.0
var next_plane := 1e9
var depths: Array = []
var station := "control"   # where the player is: control, deck, gun, aa
var crew_z := 0.0          # player's position along the boat (local z, bow negative) when on deck
var awash_in := -1.0       # seconds until the deck goes under with the player still on it
var death := ""
var _throttle := {}
var _once := {}
var _ids := 0


func _init(nation: Dictionary, target_spec: Dictionary, is_demo := false) -> void:
	nat = nation
	spec = target_spec
	demo = is_demo
	tod = spec["tod"]
	vis = VIS[tod]
	layer_depth = randf_range(45.0, 85.0)
	sub = Sub.new()
	sub.hdg = U.wrap360(randf_range(-20.0, 20.0))
	for i in nat["tubes"]:
		sub.tubes.append(0.0)
	sub.spares = int(nat["torps"]) - int(nat["tubes"])
	sub.gun_ammo = int((nat["gun"] as Dictionary).get("ammo", 0))
	sub.decoys = int(nat.get("decoys", 0))
	for k in SYSTEMS:
		sub.sys[k] = 100.0
	var test := float(nat["test"])
	for d in [0.0, 12.0, 30.0, 60.0, 100.0, 150.0, 200.0]:
		if d < test:
			depths.append(d)
	depths.append(test)
	_spawn()
	_make_islands(spec.get("terrain", "open"))
	if not demo:
		_opening()
	_observe(0.0)


func _opening() -> void:
	report("Conn: patrol station reached. Hunting %s." % target.name, "good")
	report("Sonar: listening. Raise the scope and find her.")
	if nat.get("bt", false):
		report("Bathythermograph shows a thermal layer near %d metres." % int(layer_depth))


func _new_id() -> int:
	_ids += 1
	return _ids


# ----------------------------------------------------------------- setup
func _spawn() -> void:
	var tg := Ship.new()
	tg.id = _new_id()
	tg.kind = "target"
	tg.name = GameData.PREFIX[spec["nation"]] + spec["name"]
	tg.short = spec["name"]
	tg.nation = spec["nation"]
	tg.type = spec["type"]
	tg.layout = spec["layout"]
	tg.length = spec["length"]
	tg.beam = spec["beam"]
	tg.draft = spec["draft"]
	tg.max_struct = float(spec["hp"]) * 100.0
	tg.struct = tg.max_struct
	tg.max_kn = spec["kn"]
	tg.zig = spec["zig"]
	tg.cruise = tg.max_kn if tg.max_kn < 4.0 else tg.max_kn * 0.85
	tg.guns = _batteries(tg.type)
	tg.hull = _make_hull(tg, float(spec["hp"]))
	if tg.max_kn < 4.0:
		tg.pos = Vector2(randf_range(-1200, 1200), randf_range(5200, 6600))
		tg.hdg = randf_range(0, 360)
	else:
		var side := 1.0 if randf() < 0.5 else -1.0
		tg.pos = Vector2(-side * randf_range(7200, 8600), randf_range(2800, 4200))
		tg.hdg = 90.0 if side > 0 else 270.0
	tg.base_hdg = tg.hdg
	tg.leg = tg.hdg
	tg.spd = tg.cruise
	tg.want_spd = tg.cruise
	tg.next_zig = randf_range(90, 200)
	target = tg
	ships.append(tg)

	var n_esc := int(spec["escorts"])
	var nation_s: String = spec["nation"]
	for i in n_esc:
		var e := _make_small(nation_s, "escort", GameData.ESCORT_NAMES[nation_s][i])
		if tg.cruise < 4.0:
			_orbit_init(e, tg, i, n_esc, randf_range(1200, 1600), 10.0)
		else:
			e.off = STATIONS[i]
			e.pos = _station(tg, e.off)
			e.hdg = tg.hdg
			e.spd = tg.cruise
			e.want_spd = tg.cruise
		ships.append(e)
	var n_ch := int(spec.get("chasers", 0))
	for i in n_ch:
		var c := _make_small(nation_s, "chaser", GameData.CHASER_NAMES[nation_s][i])
		_orbit_init(c, tg, i, n_ch, randf_range(3000, 3800), 12.0)
		ships.append(c)

	if tod != "night":
		for key in spec.get("air", []):
			_spawn_plane(key, true)
		if not spec.get("air", []).is_empty():
			next_plane = 1e9


func _make_small(nation_s: String, kind: String, nm: String) -> Ship:
	var e := Ship.new()
	e.id = _new_id()
	e.kind = kind
	e.nation = nation_s
	e.short = nm
	e.name = (GameData.PREFIX[nation_s] + nm) if kind == "escort" else nm
	if kind == "escort":
		e.type = "dd"
		e.layout = GameData.escort_layout(nation_s)
		e.length = 115.0
		e.beam = 11.0
		e.draft = 3.6
		e.max_struct = 100.0
		e.max_kn = 33.0
	else:
		e.type = "pc"
		e.layout = "pc"
		e.length = 52.0
		e.beam = 7.0
		e.draft = 2.4
		e.max_struct = 45.0
		e.max_kn = 20.0
	e.struct = e.max_struct
	e.guns = _batteries(e.type)
	e.hull = _make_hull(e, e.max_struct / 100.0)
	return e


func _make_hull(sh: Ship, hits_to_sink: float) -> Damage:
	var h := Damage.new()
	h.setup(sh.layout, sh.type, sh.nation, sh.length, sh.beam, sh.draft, hits_to_sink)
	return h


func _orbit_init(e: Ship, tg: Ship, i: int, n: int, r: float, kn: float) -> void:
	e.orbit = true
	e.orb_a = float(i) / max(1, n) * TAU + randf() * 0.5
	e.orb_r = r
	e.orb_dir = 1 if i % 2 == 0 else -1
	e.pos = tg.pos + Vector2(sin(e.orb_a), cos(e.orb_a)) * r
	e.hdg = U.wrap360(rad_to_deg(e.orb_a) + 90.0 * e.orb_dir)
	e.spd = kn
	e.want_spd = kn


func _batteries(type: String) -> Array:
	var out := []
	for g in BATTERIES.get(type, []):
		var gg: Dictionary = g.duplicate()
		gg["next"] = randf_range(0.0, 4.0)
		out.append(gg)
	return out


func _spawn_plane(key: String, initial: bool) -> void:
	var info: Dictionary = GameData.AIRCRAFT[key]
	var p := Aircraft.new()
	p.id = _new_id()
	p.key = key
	p.info = info
	p.name = info["name"]
	p.kn = info["kn"]
	p.hp = info["hp"]
	p.bombs = info["bombs"]
	p.center = target.pos
	p.orb_r = randf_range(3500, 7000)
	p.orb_dir = 1 if randf() < 0.5 else -1
	var a := randf() * TAU
	if initial:
		p.pos = p.center + Vector2(sin(a), cos(a)) * p.orb_r
	else:
		p.pos = p.center + Vector2(sin(a), cos(a)) * 16000.0
	p.hdg = randf_range(0, 360)
	p.alt = randf_range(350, 550)
	planes.append(p)
	if not initial:
		report("Sonar: they've called in more air cover. Expect aircraft.", "warn")


func _make_islands(terrain: String) -> void:
	var tg := target
	match terrain:
		"harbor":
			var gap := U.brg(tg.pos, sub.pos)
			for i in 10:
				var a := 36.0 * i + randf_range(-8, 8)
				if absf(U.adiff(a, gap)) < 40.0:
					continue
				var c := tg.pos + U.dirv(a) * randf_range(3300, 4800)
				islands.append({"pos": c, "r": randf_range(900, 1700), "h": randf_range(40, 110), "seed": randi()})
		"coast", "strait":
			var side := 1.0 if tg.pos.y > sub.pos.y else -1.0
			var y0 := tg.pos.y + side * randf_range(5500, 7500)
			var x := -16000.0
			while x < 16000.0:
				islands.append({"pos": Vector2(x + randf_range(-600, 600), y0 + randf_range(-900, 900) + side * 1500.0),
					"r": randf_range(1800, 3200), "h": randf_range(80, 260), "seed": randi()})
				x += randf_range(2600, 4000)
			if terrain == "strait":
				x = -16000.0
				while x < 16000.0:
					islands.append({"pos": Vector2(x + randf_range(-600, 600), sub.pos.y - side * randf_range(7000, 8500)),
						"r": randf_range(1500, 2600), "h": randf_range(40, 120), "seed": randi()})
					x += randf_range(3000, 4500)


static func _station(tg: Ship, off: Vector2) -> Vector2:
	var f := U.dirv(tg.hdg)
	var r := U.dirv(tg.hdg + 90.0)
	return tg.pos + f * off.x + r * off.y


func escorts() -> Array:
	var out := []
	for s in ships:
		if s.kind != "target":
			out.append(s)
	return out


# -------------------------------------------------------------- messages
func report(text: String, kind := "info", key := "", every := 0.0) -> void:
	if demo:
		return
	if key != "":
		var last: float = _throttle.get(key, -1e9)
		if t - last < every:
			return
		_throttle[key] = t
	msgs.append([t, text, kind])
	if msgs.size() > 120:
		msgs = msgs.slice(40)


func once(key: String, text: String, kind := "info") -> void:
	if _once.has(key):
		return
	_once[key] = true
	report(text, kind)


func emit(ev: Dictionary) -> void:
	if not demo:
		events.append(ev)


func sound(name: String, vol := 1.0, pos = null) -> void:
	var ev := {"type": "sound", "name": name, "vol": vol}
	if pos != null:
		ev["pos"] = pos
	emit(ev)


# ---------------------------------------------------------------- orders
func set_telegraph(i: int) -> void:
	i = clampi(i, 0, TELEGRAPH.size() - 1)
	if i != sub.tel:
		sub.tel = i
		report("Engine room: %s, aye." % TELEGRAPH[i][0].to_lower(), "info", "tel", 0.0)
		sound("telegraph", 0.7)


func set_rudder(i: int) -> void:
	i = clampi(i, 0, RUDDER.size() - 1)
	if i != sub.rud_i:
		sub.rud_i = i
		report("Helm: %s, aye." % RUDDER[i][1].to_lower(), "info", "rud", 0.0)


func set_depth(d: float, crash := false) -> void:
	var s := sub
	s.dep_ord = d
	s.crash = crash
	if crash:
		report("Dive, dive! Flood negative, all hands forward!", "warn")
		sound("klaxon", 1.0)
	elif d <= 0.0:
		report("Diving officer: surface, surface! Blowing main ballast.")
		sound("blow", 0.8)
	else:
		if s.flood < 1.0:
			report("Diving officer: diving to %d metres. Opening vents." % int(d))
			sound("klaxon", 0.8)
		elif absf(s.spd) < 1.5 and absf(d - s.depth) > 4.0:
			report("Diving officer: make my depth %d metres. With no way on the planes won't bite; it'll be slow on the trim tanks." % int(d))
		else:
			report("Diving officer: make my depth %d metres." % int(d))
	if d > 0.0 and s.flood < 0.5 and exposed():
		emit({"type": "clear_bridge"})


func depth_step(step: int) -> void:
	var cur := 0
	var best := 1e9
	for i in depths.size():
		var dd: float = absf(depths[i] - sub.dep_ord)
		if dd < best:
			best = dd
			cur = i
	set_depth(depths[clampi(cur + step, 0, depths.size() - 1)])


func crash_dive() -> void:
	var tgt := 60.0
	for d in depths:
		if d <= 60.0:
			tgt = d
	set_depth(tgt, true)


func toggle_scope() -> void:
	var s := sub
	if s.surfaced():
		report("We're on the surface. Use the bridge to look around.")
		return
	if s.scope_up:
		s.scope_up = false
		report("Down scope.")
		sound("scope", 0.6)
	elif s.depth > PERI_MAX:
		report("Too deep to raise the scope. Come up to 12 metres.", "warn")
	elif s.sys["periscope"] <= 25.0:
		report("The periscope is damaged and won't raise.", "warn")
	else:
		s.scope_up = true
		report("Up scope.")
		sound("scope", 0.6)


func set_torp_depth(d: float) -> void:
	sub.torp_depth = clampf(d, 1.0, 12.0)
	report("Torpedo room: running depth set to %d metres." % int(sub.torp_depth), "info", "tdepth", 0.0)


# --------------------------------------------------------------- weapons
func lock_ship(sh: Ship) -> void:
	if sh == null or not sh.alive():
		return
	if lock != sh:
		lock_obs = 0.0
		lock_err = Vector2(U.gauss(), U.gauss())
	lock = sh
	report("TDC: locked on %s. Keep her in sight to refine the solution." % sh.name, "good")


func lock_nearest(view_brg: float, fov: float) -> void:
	if not sub.can_see():
		report("Can't take a bearing without a view.", "warn")
		return
	var best: Ship = null
	var score := 1e9
	for sh in ships:
		if not sh.alive() or sh.pos.distance_to(sub.pos) > vis:
			continue
		var rel: float = absf(U.adiff(U.brg(sub.pos, sh.pos), view_brg))
		if rel > fov / 2.0:
			continue
		var sc := rel - (0.75 if sh.kind == "target" else 0.0)
		if sc < score:
			score = sc
			best = sh
	if best:
		lock_ship(best)
	else:
		report("Nothing in the reticle to lock.", "warn")


func solution():
	var sh := lock
	if sh == null or not sh.alive():
		return null
	var s := sub
	var q := clampf(lock_obs / 12.0, 0.0, 1.0)
	var err := 1.0 - q
	var vs := sh.spd * (1.0 + lock_err.x * 0.3 * err)
	var hs := sh.hdg + lock_err.y * 15.0 * err
	var v := U.dirv(hs) * vs * U.KN
	var d := sh.pos - s.pos
	var S: float = float(nat["torp"]["kn"]) * U.KN
	var a := v.dot(v) - S * S
	var b := 2.0 * d.dot(v)
	var c := d.dot(d)
	var ts := []
	if absf(a) < 1e-9:
		if absf(b) < 1e-9:
			return null
		ts = [-c / b]
	else:
		var disc := b * b - 4.0 * a * c
		if disc < 0.0:
			return null
		var r := sqrt(disc)
		ts = [(-b - r) / (2.0 * a), (-b + r) / (2.0 * a)]
	var tt := 1e18
	for x in ts:
		if x > 0.0 and x < tt:
			tt = x
	if tt > 1e17:
		return null
	var hdg := U.brg(s.pos, sh.pos + v * tt)
	var run := S * tt
	return {"hdg": hdg, "t": tt, "run": run, "q": q, "gyro": U.adiff(hdg, s.hdg),
		"in_range": run <= float(nat["torp"]["range"])}


func fire(n := 1, view_brg := -1.0) -> void:
	if result != "" or demo:
		return
	var s := sub
	if s.depth > fire_max():
		report("Too deep to fire. Come above %d metres." % int(fire_max()), "warn")
		return
	if s.sys["tubes"] <= 25.0:
		report("Torpedo room: the tubes are damaged, we can't fire!", "warn")
		return
	var loaded := []
	for i in s.tubes.size():
		if s.tubes[i] == 0.0:
			loaded.append(i)
	if loaded.is_empty():
		report("Torpedo room: no tubes loaded!", "warn")
		return
	var sol = solution() if lock != null else null
	var base: float = sol["hdg"] if sol != null else (view_brg if view_brg >= 0.0 else U.wrap360(s.hdg + s.scope_rel))
	if absf(U.adiff(base, s.hdg)) > 90.0:
		report("Gyro angle over 90 degrees. Swing the bow toward the target.", "warn")
		return
	var offs := [-1.6, 0.0, 1.6] if n == 3 else [0.0]
	var used := []
	for o in offs:
		if loaded.is_empty():
			break
		var i: int = loaded.pop_front()
		var tp := Torpedo.new()
		tp.id = _new_id()
		tp.pos = s.pos + U.dirv(s.hdg) * (float(nat["sub"]["len"]) * 0.45)
		tp.hdg = U.wrap360(base + o)
		tp.kn = nat["torp"]["kn"]
		tp.rng = nat["torp"]["range"]
		tp.wake = nat["torp"]["wake"]
		tp.depth = s.torp_depth
		tp.trail = [tp.pos]
		torps.append(tp)
		if s.spares > 0:
			s.tubes[i] = RELOAD
			s.spares -= 1
		else:
			s.tubes[i] = -1.0
		used.append(str(i + 1))
	fired += used.size()
	sound("launch", 1.0)
	var aim := "on the TDC solution" if sol != null else "bearing %s" % U.p3(base)
	var what := "Torpedo" if used.size() == 1 else "Spread of %d" % used.size()
	report("%s away from tube %s, %s. Running %d knots, depth %d m." % [what, ", ".join(used), aim,
		int(nat["torp"]["kn"]), int(s.torp_depth)], "good")
	if sol != null and not sol["in_range"]:
		report("TDC: target is beyond torpedo range. It may run dry.", "warn")


## How strong a heard ship's strobe is on the sonar screen, 0 to 1.
func strobe(sh: Ship) -> float:
	var r := sub.pos.distance_to(sh.pos)
	return clampf((0.35 + sh.spd / 14.0) * (4000.0 / (r + 1500.0)), 0.08, 1.0) * (0.3 + 0.7 * sub.sys["hydrophones"] / 100.0)


## Torpedoes coming for us that sonar can hear (near-future only).
func threats() -> Array:
	return []


## Fire control's estimate of the locked target: [position, velocity, error
## radius in metres]; empty when there is none (near-future only).
func fire_control_estimate() -> Array:
	return []


## Near-future boats only: cut the guidance wires, launch a decoy, lock the
## strongest sonar contact. ModernWorld overrides these.
func cut_wires() -> void:
	pass


func launch_decoy() -> void:
	pass


## Near-future boats only: pick the weapon, and the missile salvo size.
func cycle_weapon() -> void:
	pass


## Weapons left, for the top bar (the near-future boats override this).
func weapon_line() -> String:
	return "TORPEDOES %d" % (sub.spares + sub.tubes.count(0.0))


func salvo_step(_d: int) -> void:
	pass


func lock_sonar() -> void:
	report("Locking needs the periscope or the binoculars on deck.", "warn")


## Deepest the tubes can fire from.
func fire_max() -> float:
	return float(nat.get("fire_max", FIRE_MAX))


## Deck gun mount position in sim 3D space.
func gun_pos() -> Vector3:
	var L: float = nat["sub"]["len"]
	var x: float = nat["sub"]["gun_x"]
	var p := sub.pos + U.dirv(sub.hdg) * (0.5 - x) * L
	return Vector3(p.x, 3.6, p.y)


func gun_ready() -> String:
	var s := sub
	if (nat["gun"] as Dictionary).is_empty():
		return "none"
	if not s.surfaced():
		return "submerged"
	if s.crew_ready > 0.0:
		return "manning"
	if s.sys["gun"] <= 25.0:
		return "damaged"
	if s.gun_ammo <= 0:
		return "no ammo"
	if s.gun_reload > 0.0:
		return "loading"
	return "ready"


func gun_blocked(trav: float) -> bool:
	var fwd: bool = float(nat["sub"]["gun_x"]) < float(nat["sub"]["tower"])
	var a := absf(U.adiff(trav, 180.0 if fwd else 0.0))
	return a < 16.0


func fire_gun() -> void:
	var s := sub
	var st := gun_ready()
	if st != "ready":
		if st == "loading" or st == "none":
			return
		report("Gun crew: %s." % {"submerged": "we're submerged", "manning": "still manning the gun",
			"damaged": "the gun is damaged", "no ammo": "out of ammunition"}[st], "warn", "gunwarn", 2.0)
		return
	if gun_blocked(s.gun_trav):
		report("Gun crew: can't fire through the conning tower!", "warn", "gunblock", 2.0)
		return
	var g: Dictionary = nat["gun"]
	var v: float = g["v"]
	var b := U.wrap360(s.hdg + s.gun_trav)
	var e := deg_to_rad(s.gun_elev + randf_range(-0.15, 0.15))
	var dh := U.dirv(b + randf_range(-0.2, 0.2))
	var sh := Shell.new()
	sh.id = _new_id()
	sh.kind = "gun"
	sh.p = gun_pos() + Vector3(dh.x, 0.0, dh.y) * 4.0
	sh.v = Vector3(dh.x * cos(e) * v, sin(e) * v, dh.y * cos(e) * v)
	sh.v += Vector3(s.vel.x, 0.0, s.vel.y)
	sh.dmg = g["dmg"]
	sh.cal = g["cal"]
	shells.append(sh)
	s.gun_ammo -= 1
	s.gun_reload = float(g["reload"])
	alert = true
	emit({"type": "muzzle", "pos": sh.p, "cal": g["cal"], "own": true})
	sound("deckgun", 1.0)


func fire_aa(dir3: Vector3) -> void:
	var s := sub
	if (nat["aa"] as Dictionary).is_empty() or not s.surfaced() or s.crew_ready > 0.0 or s.aa_reload > 0.0:
		return
	var a: Dictionary = nat["aa"]
	var L: float = nat["sub"]["len"]
	var p2 := s.pos + U.dirv(s.hdg) * (0.5 - float(nat["sub"]["aa_x"])) * L
	var sh := Shell.new()
	sh.id = _new_id()
	sh.kind = "aa"
	var d := dir3.normalized()
	d += Vector3(U.gauss(), U.gauss(), U.gauss()) * 0.004
	sh.p = Vector3(p2.x, 7.0, p2.y) + d * 2.0
	sh.v = d.normalized() * float(a["v"]) + Vector3(s.vel.x, 0.0, s.vel.y)
	sh.dmg = 1
	sh.cal = 20.0
	shells.append(sh)
	s.aa_reload = 1.0 / float(a["rate"])
	sound("aa", 0.5)


# ---------------------------------------------------------------- update
func update(dt: float) -> void:
	if demo:
		return
	t += dt
	_update_sub(dt)
	for sh in ships:
		if sh.dead:
			continue
		if sh.struct <= 0.0:
			_sink(sh, dt)
			continue
		var h0 := sh.hdg
		if sh.kind == "target":
			_target_ai(sh, dt)
		else:
			_escort_ai(sh, dt)
		_ship_guns(sh, dt)
		_damage_limits(sh, h0, dt)
		_move(sh, dt)
		sh.hull.step(dt)
		_hull_news(sh)
	_update_planes(dt)
	_update_torps(dt)
	_update_shells(dt)
	_update_charges(dt)
	_observe(dt)
	_pings()
	shake = maxf(0.0, shake - dt * 1.2)
	ping_flash = maxf(0.0, ping_flash - dt * 1.5)
	var hunted := false
	for e in ships:
		if e.kind != "target" and e.alive() and e.state not in ["screen", "patrol"]:
			hunted = true
	for p in planes:
		if not p.dead and p.state != "patrol":
			hunted = true
	if hunted:
		tc = mini(tc, 4)
	if alert and t > next_plane and not spec.get("air", []).is_empty() and tod != "night":
		var alive := 0
		for p in planes:
			if not p.dead:
				alive += 1
		if alive < 3:
			var arr: Array = spec["air"]
			_spawn_plane(arr[randi() % arr.size()], false)
		next_plane = t + randf_range(200, 320)
	_check_end()


func _update_sub(dt: float) -> void:
	var s := sub
	var N := nat
	var surf_trim := s.flood < 0.5
	var motors: float = s.sys["motors"]
	var diesels: float = s.sys["diesels"]
	var max_kn: float = float(N["surf_kn"]) * (0.4 + 0.6 * diesels / 100.0) if surf_trim else float(N["sub_kn"]) * (0.5 + 0.5 * motors / 100.0)
	if not surf_trim and s.bat <= 0.0:
		max_kn = 1.5
	if s.hull < 35.0:
		max_kn *= 0.6
	if s.grounded:
		max_kn = 0.0
	var want: float = TELEGRAPH[s.tel][1] * max_kn
	s.spd += clampf(want - s.spd, -0.25 * dt, 0.25 * dt)
	s.rud += clampf(RUDDER[s.rud_i][0] - s.rud, -10.0 * dt, 10.0 * dt)
	var turn := (s.rud / 35.0) * 3.0 * clampf(absf(s.spd) / 4.0, 0.0, 1.0) * (1.0 if s.spd >= 0.0 else -1.0)
	s.hdg = U.wrap360(s.hdg + turn * dt)
	s.vel = U.dirv(s.hdg) * s.spd * U.KN
	s.pos += s.vel * dt

	# Ballast and depth. Submerged, the planes and the hull's angle do most of
	# the work, and only bite with way on; the variable ballast helps, slowly.
	var planes_ok: float = 0.5 + 0.5 * s.sys["planes"] / 100.0
	var v_ms := absf(s.spd) * U.KN
	if s.dep_ord <= 0.0:
		if s.depth > 3.0:
			# Blow main ballast: she rises bodily, bow up.
			s.ballast = move_toward(s.ballast, -1.0, 0.25 * dt)
			s.pitch = move_toward(s.pitch, 7.0 * planes_ok, 2.5 * dt)
			s.vz = s.ballast - v_ms * sin(deg_to_rad(s.pitch)) * planes_ok + _heaviness() * 0.3
			s.depth = maxf(3.0, s.depth + minf(s.vz, -0.25) * dt)
		else:
			var was := s.flood
			s.flood = maxf(0.0, s.flood - dt / 9.0)
			s.depth = 3.0 * s.flood
			s.pitch = move_toward(s.pitch, 0.0, 2.0 * dt)
			s.ballast = 0.0
			s.vz = 0.0
			if was > 0.0 and s.flood == 0.0:
				s.crew_ready = 10.0
				s.scope_up = false
				report("Diving officer: surfaced. Diesels running, charging batteries.", "good")
				report("Gun crews to the deck.")
	else:
		if s.flood < 1.0:
			var dt_f: float = float(N["dive_time"]) * (0.65 if s.crash else 1.0)
			s.flood = minf(1.0, s.flood + dt / dt_f)
			var cap := s.flood * s.flood * 8.0
			var d0 := s.depth
			s.depth = move_toward(s.depth, minf(s.dep_ord, cap), 2.0 * dt)
			s.vz = (s.depth - d0) / maxf(dt, 1e-4)
			# The bow dips as the forward tanks flood.
			s.pitch = move_toward(s.pitch, -(7.0 if s.crash else 4.0) * s.flood, 3.0 * dt)
			if s.flood >= 1.0:
				report("Diving officer: we're under. Decks awash, %d metres." % int(s.depth))
		else:
			_depth_keeping(s, v_ms, planes_ok, dt)

	# Flooding.
	if s.leak > 0.0:
		s.water += s.leak * dt
		s.leak = maxf(0.0, s.leak - 0.012 * dt)
	if s.water > 0.0:
		s.water = maxf(0.0, s.water - 0.12 * dt * s.sys["pumps"] / 100.0)
		s.water = minf(s.water, 100.0)
	s.depth = maxf(0.0, s.depth)

	if not s.surfaced() and s.scope_up and s.depth > PERI_MAX:
		s.scope_up = false
		report("Scope lowered, we're going under.")

	# Battery and air. A nuclear boat has neither to worry about.
	if N.get("nuclear", false):
		s.bat = 100.0
		s.air = 100.0
	elif surf_trim:
		var frac := absf(s.spd) / float(N["surf_kn"])
		s.bat = minf(100.0, s.bat + 0.14 * dt * (1.0 - 0.6 * frac) * diesels / 100.0)
		s.air = minf(100.0, s.air + 1.0 * dt)
	else:
		var drain := 0.004 + 0.11 * pow(absf(s.spd) / float(N["sub_kn"]), 2.0)
		s.bat = maxf(0.0, s.bat - drain * dt)
		s.air = maxf(0.0, s.air - 0.012 * dt)
		if s.bat < 20.0:
			once("bat20", "Electrician: battery under 20 percent. Slow down or surface to charge.", "warn")
		if s.bat <= 0.0:
			once("bat0", "Electrician: battery flat! We can only creep.", "alarm")
	if s.air < 25.0:
		once("air25", "The air is getting foul. Men are slowing down. We need to surface soon.", "warn")
	if s.air <= 0.0:
		s.hull -= 0.05 * dt

	if s.depth > float(N["test"]):
		var over := (s.depth - float(N["test"])) / (float(N["crush"]) - float(N["test"]))
		s.hull -= over * 2.5 * dt
		s.leak = maxf(s.leak, over * 0.5)
		if _throttle.get("creak", -1e9) + 15.0 < t:
			report("The hull is groaning. We're below test depth (%d m)!" % int(N["test"]), "alarm", "creak", 15.0)
			sound("creak", 1.0)
	if s.depth >= float(N["crush"]):
		s.hull = 0.0
		_end("crushed", 3.0)

	# Grounding near islands.
	s.grounded = false
	for isl in islands:
		if s.pos.distance_to(isl["pos"]) < float(isl["r"]) * 0.85:
			s.grounded = true
			if absf(s.spd) > 1.0:
				s.hull -= absf(s.spd) * 0.5 * dt
			s.spd = 0.0
			report("We've run aground! Back off the shoal!", "alarm", "aground", 20.0)

	# Crew work: reloads, repairs.
	var work := 0.5 + 0.5 * clampf(s.air / 50.0, 0.0, 1.0)
	for i in s.tubes.size():
		var v: float = s.tubes[i]
		if v > 0.0:
			v -= dt * work
			if v <= 0.0:
				v = 0.0
				report("Torpedo room: tube %d reloaded." % (i + 1))
			s.tubes[i] = v
	for k in SYSTEMS:
		if s.sys[k] < 100.0:
			var before: float = s.sys[k]
			s.sys[k] = minf(100.0, s.sys[k] + 0.3 * dt * work)
			if before <= 25.0 and s.sys[k] > 25.0:
				report("Damage control: %s repaired." % SYS_NAMES[k].to_lower(), "good")
	# Anyone still on deck when she goes under is left behind.
	awash_in = -1.0
	if exposed() and result == "":
		if s.flood >= 0.55:
			kill_player("drowned", "The sea closed over the deck before you reached the hatch.")
		elif s.dep_ord > 0.0:
			var dt_f2: float = float(N["dive_time"]) * (0.65 if s.crash else 1.0)
			awash_in = (0.55 - s.flood) * dt_f2
	s.crew_ready = maxf(0.0, s.crew_ready - dt)
	s.gun_reload = maxf(0.0, s.gun_reload - dt)
	s.aa_reload = maxf(0.0, s.aa_reload - dt)


## How fast the water aboard would sink her with no way on (m/s).
func _heaviness() -> float:
	return sub.water * 0.008


## The diving officer holds or changes depth: he angles the boat with the
## planes, which only work with way on, and floods or pumps the variable
## ballast to help, which is slow. The trim pumps can only offset so much
## water; a heavy, flooded boat needs speed and an up angle just to stay
## where she is, or main ballast blown.
func _depth_keeping(s: Sub, v_ms: float, planes_ok: float, dt: float) -> void:
	var vmax := 2.4 if s.crash else 1.0
	var err := s.dep_ord - s.depth
	var want := clampf(err * (0.12 if s.crash else 0.08), -vmax, vmax)
	if s.crash and err < 4.0:
		s.crash = false
		report("Diving officer: blowing negative. Leveling off at %d metres." % int(s.dep_ord))
	var heavy := _heaviness()
	# Variable ballast: the negative tank in a crash dive, the trim tanks
	# otherwise, pumped dry to carry water she has taken aboard.
	var pump_out: float = 0.25 * s.sys["pumps"] / 100.0
	var bal_want := clampf(want * (0.9 if s.crash else 0.5) - heavy, -pump_out, 1.4 if s.crash else 0.3)
	var rate := 0.35 if s.crash else (0.3 if s.ballast > 0.35 else 0.08)
	s.ballast = move_toward(s.ballast, bal_want, rate * dt)
	# Planes: angle the hull to make up the rest, within what the speed allows.
	var need := want - s.ballast - heavy
	var max_ang := (22.0 if s.crash else 12.0) * planes_ok
	var ang := 0.0
	if v_ms > 0.15:
		ang = -rad_to_deg(asin(clampf(need / v_ms, -1.0, 1.0)))
	ang = clampf(ang, -max_ang, max_ang)
	if s.spd < 0.0:
		ang = -ang * 0.5
	s.pitch = move_toward(s.pitch, ang, (6.0 if s.crash else 3.0) * dt)
	var planes_vz := -v_ms * sin(deg_to_rad(s.pitch)) * (1.0 if s.spd >= 0.0 else -1.0)
	s.vz = planes_vz + s.ballast + heavy
	s.depth += s.vz * dt
	if s.depth < 3.5:
		s.depth = 3.5
		s.vz = maxf(s.vz, 0.0)
	if heavy > 0.05 and s.vz > 0.05 and s.depth > s.dep_ord + 3.0:
		report("Diving officer: she's heavy and going down! I need more speed, or we blow ballast.", "warn", "heavy", 45.0)


func exposed() -> bool:
	return station in ["deck", "gun", "aa"]


func crew_pos() -> Vector2:
	return sub.pos + U.dirv(sub.hdg) * (-crew_z)


## The player is the captain: if he is killed the patrol is over.
func kill_player(kind: String, how: String) -> void:
	if result != "":
		return
	death = how
	report(how, "alarm")
	report("The captain is down!", "alarm")
	shake = 1.0
	_end(kind, 2.5)


## A blast at p2 on the surface; lethal close in, a chance of a fatal wound further out.
func _blast_crew(p2: Vector2, lethal: float, danger: float, how: String) -> void:
	if not exposed() or not sub.surfaced():
		return
	var d := p2.distance_to(crew_pos())
	if d < lethal or (d < danger and randf() < (danger - d) / (danger - lethal) * 0.55):
		kill_player("killed", how)


func damage_sub(amount: float, cause: String) -> void:
	var s := sub
	s.hull = maxf(0.0, s.hull - amount)
	if amount >= 8.0:
		s.leak += amount * 0.006
		var n := 1 + int(amount / 15.0)
		for i in n:
			var k: String = SYSTEMS[randi() % SYSTEMS.size()]
			var before: float = s.sys[k]
			s.sys[k] = maxf(0.0, s.sys[k] - randf_range(25.0, 70.0))
			if before > 25.0 and s.sys[k] <= 25.0:
				report("Damage report: %s knocked out!" % SYS_NAMES[k].to_lower(), "alarm")
		emit({"type": "leak", "amount": amount})
	if cause != "":
		report(cause, "alarm" if amount >= 15.0 else "warn")


# ------------------------------------------------------------ ship motion
static func _steer(sh, want: float, dt: float, rate: float) -> void:
	var d := U.adiff(want, sh.hdg)
	sh.hdg = U.wrap360(sh.hdg + clampf(d, -rate * dt, rate * dt))


static func _move(sh: Ship, dt: float) -> void:
	sh.spd += clampf(sh.want_spd - sh.spd, -0.5 * dt, 0.5 * dt)
	sh.pos += U.dirv(sh.hdg) * sh.spd * U.KN * dt


func _sink(sh: Ship, dt: float) -> void:
	sh.want_spd = 0.0
	sh.spd = maxf(0.0, sh.spd - dt)
	sh.pos += U.dirv(sh.hdg) * sh.spd * U.KN * dt
	sh.fire = minf(1.0, maxf(sh.fire, sh.hull.burning()) + dt * 0.05)
	var big := sh.kind == "target"
	var dur: float = {"capsize": 40.0 if big else 24.0, "explode": 30.0 if big else 16.0}.get(sh.hull.mode, 75.0 if big else 40.0)
	sh.sinking = minf(1.0, sh.sinking + dt / dur)
	# Battleships that roll over can still blow up as the magazines turn turtle.
	if sh.hull.mode == "capsize" and sh.type == "bb" and sh.sinking > 0.3 and not sh.said.has("rollblast"):
		sh.said["rollblast"] = true
		if randf() < 0.35:
			_magazine_blast(sh, 0.3, "As she rolled over, her magazine exploded!")
	if sh.sinking >= 1.0:
		sh.dead = true
		if lock == sh:
			lock = null


## Damage caps her speed, and a jammed rudder turns her in circles whatever
## the helm wants.
func _damage_limits(sh: Ship, h0: float, dt: float) -> void:
	var h := sh.hull
	sh.want_spd = minf(sh.want_spd, sh.max_kn * h.speed_factor())
	if h.rudder_jam != 0.0:
		var turn := h.rudder_jam / 35.0 * 2.2 * clampf(sh.spd / 8.0, 0.15, 1.0)
		sh.hdg = U.wrap360(h0 + turn * dt)
	sh.struct = sh.max_struct * h.health()
	sh.fire = h.burning()
	sh.sink_side = 1.0 if h.list >= 0.0 else -1.0


## Where along the hull (0 bow, 1 stern) and which side (-1 port, +1 starboard) a point is.
static func hull_spot(sh: Ship, p: Vector2) -> Vector2:
	var d := p - sh.pos
	var along := d.dot(U.dirv(sh.hdg))
	var across := d.dot(U.dirv(sh.hdg + 90.0))
	return Vector2(clampf(0.5 - along / sh.length, 0.02, 0.98), 1.0 if across >= 0.0 else -1.0)


static func where(u: float) -> String:
	return "forward" if u < 0.3 else ("aft" if u > 0.7 else "amidships")


func _visible(sh: Ship) -> bool:
	return sub.can_see() and sub.pos.distance_to(sh.pos) < vis


## Turns what happened inside a ship's hull this tick into reports and effects.
func _hull_news(sh: Ship) -> void:
	var h := sh.hull
	var seen := _visible(sh)
	var nm := sh.short
	for ev in h.events:
		match ev["what"]:
			"rudder":
				if seen:
					report("Conn: %s is turning in circles! Her rudder must be jammed." % nm, "good")
				else:
					report("Sonar: %s's bearing is drifting oddly. She may be circling." % nm, "info")
			"engines":
				if not sh.said.has("eng") and h.engines < 0.6:
					sh.said["eng"] = true
					report("Sonar: %s's screws are slowing. Her machinery is hurt." % nm, "good")
			"dead_in_water":
				report("Conn: %s has lost way. She's dead in the water!" % nm, "good")
			"counterflood":
				if seen and sh.kind == "target":
					report("She's counterflooding. The list is easing a little.", "info", "cf%d" % sh.id, 60.0)
			"mag_flooded":
				if seen and sh.kind == "target":
					report("Smoke and steam from her forward deck. They're flooding a magazine.", "info", "mf%d" % sh.id, 90.0)
			"magazine":
				_magazine_blast(sh, float(ev["u"]), "Her magazine went up! %s has blown apart!" % nm)
			"broken":
				sh.struct = 0.0
				report("%s's back is broken! She's going down in two pieces." % nm, "good")
				_ship_sunk(sh, "broken")
			"capsize":
				sh.struct = 0.0
				_ship_sunk(sh, "capsize")
			"founder":
				sh.struct = 0.0
				_ship_sunk(sh, "founder")
			"wrecked":
				sh.struct = 0.0
				_ship_sunk(sh, "wrecked")
	h.events.clear()
	if not h.afloat() and sh.struct > 0.0:
		sh.struct = 0.0
	# Running commentary on how she lies in the water.
	if seen and sh.kind == "target" and h.afloat():
		var l := absf(h.list)
		for step in [5.0, 12.0, 20.0, 27.0]:
			var key := "list%d" % int(step)
			if l > step and not sh.said.has(key):
				sh.said[key] = true
				report("She's listing to %s, about %d degrees." % ["starboard" if h.list > 0.0 else "port", int(l)], "good")
		if absf(h.trim) > 2.0 and not sh.said.has("trim"):
			sh.said["trim"] = true
			report("She's down by the %s." % ("bow" if h.trim > 0.0 else "stern"), "good")
		if h.burning() > 0.6 and not sh.said.has("fire"):
			sh.said["fire"] = true
			report("Fires are spreading aboard %s." % nm, "good")


func _magazine_blast(sh: Ship, u: float, text: String) -> void:
	var p := sh.pos + U.dirv(sh.hdg) * (0.5 - u) * sh.length
	emit({"type": "boom", "pos": Vector3(p.x, 4.0, p.y), "size": sh.length / 7.0, "kind": "magazine", "ship": sh.id, "u": u})
	sound("breakup", 1.0)
	sound("torp_hit", 1.0, Vector3(p.x, 0.0, p.y))
	shake = maxf(shake, 0.5)
	report(text, "good" if sh.kind != "own" else "alarm")
	if sh.struct > 0.0:
		sh.struct = 0.0
		_ship_sunk(sh, "magazine")


func _target_ai(sh: Ship, dt: float) -> void:
	var s := sub
	if sh.max_kn < 4.0:
		sh.want_spd = sh.cruise
		_steer(sh, sh.leg, dt, 0.5)
		return
	if alert:
		sh.want_spd = sh.max_kn
		var r := sh.pos.distance_to(s.pos)
		var away := U.brg(s.pos, sh.pos)
		if r < 7000.0:
			_steer(sh, away, dt, 1.0)
		else:
			sh.leg = away
			_steer(sh, sh.leg, dt, 1.0)
		return
	if sh.zig and t > sh.next_zig:
		sh.leg = U.wrap360(sh.base_hdg + randf_range(-35, 35))
		sh.next_zig = t + randf_range(150, 260)
	sh.want_spd = sh.cruise
	_steer(sh, sh.leg, dt, 1.0)


func _escort_ai(e: Ship, dt: float) -> void:
	var s := sub
	var tg := target
	var r := e.pos.distance_to(s.pos)
	_detect(e, r, dt)
	match e.state:
		"screen":
			var p: Vector2
			var base := 11.0
			if e.orbit:
				var kn := 12.0 if e.kind == "chaser" else 11.0
				e.orb_a += e.orb_dir * (kn * U.KN / e.orb_r) * dt
				var lead := e.orb_a + e.orb_dir * 0.25
				p = tg.pos + Vector2(sin(lead), cos(lead)) * e.orb_r
				base = kn
			else:
				p = _station(tg, e.off)
				base = tg.spd
			var d := e.pos.distance_to(p)
			var want := U.brg(e.pos, p) if (d > 80.0 or e.orbit) else tg.hdg
			_steer(e, want, dt, 3.0)
			e.want_spd = clampf(base + d / 120.0, 5.0, e.max_kn * 0.9)
		"hunt":
			var d := e.pos.distance_to(e.est)
			_steer(e, U.brg(e.pos, e.est), dt, 3.5)
			e.want_spd = minf(e.max_kn * 0.75, 24.0) if d > 900.0 else 12.0
			if d < 110.0:
				e.state = "run"
				e.to_drop = 5 if e.kind == "escort" else 3
				e.next_dc = t
				e.run_until = t + 35.0
				if r < 3000.0:
					report("Sonar: splashes astern of %s. Depth charges!" % e.short, "alarm", "dcdrop", 10.0)
					tc = 1
			elif t - e.last_fix > 75.0:
				e.state = "search"
				e.search_until = t + 100.0
		"run":
			e.want_spd = minf(20.0, e.max_kn * 0.9)
			if e.to_drop > 0 and t >= e.next_dc:
				_drop(e)
				e.to_drop -= 1
				e.next_dc = t + 2.2
			if t > e.run_until and e.to_drop == 0:
				if t - e.last_fix < 45.0:
					e.state = "hunt"
				else:
					e.state = "search"
					e.search_until = t + 100.0
		"search":
			var a := t * 0.06 + e.id
			var p := e.est + Vector2(sin(a), cos(a)) * 600.0
			_steer(e, U.brg(e.pos, p), dt, 3.0)
			e.want_spd = 12.0
			if t > e.search_until:
				e.state = "screen"
				e.detect = 0.0
				report("Sonar: %s has slowed and is rejoining the screen. I think we lost them." % e.short, "good")
	if r < 35.0 and s.depth < 9.0 and t > ram_cool:
		ram_cool = t + 15.0
		shake = 1.0
		emit({"type": "boom", "pos": Vector3(s.pos.x, 2.0, s.pos.y), "size": 6.0, "kind": "ram"})
		damage_sub(55.0, "Collision! %s rammed us!" % e.short)


func _detect(e: Ship, r: float, dt: float) -> void:
	var s := sub
	var spd := absf(s.spd)
	var rate := 0.0
	var mult := 1.3 if e.kind == "chaser" else 1.0
	if s.surfaced():
		var R := vis * 0.8
		if r < R:
			rate += 0.25 * (1.0 - r / R) + 0.05
	else:
		if s.scope_up and s.depth <= PERI_MAX:
			var R := vis * 0.3
			if r < R:
				rate += 0.045 * (1.0 - r / R) * (1.0 + spd / 4.0)
		if s.flood < 1.0:
			rate += 0.08 * (1.0 - clampf(r / 6000.0, 0.0, 1.0))
		var A := 2000.0 if e.kind == "chaser" else 1600.0
		if r < A:
			var f := (1.0 - r / A) * (0.12 + pow(spd / 8.0, 2.0) * 0.8) * 0.25 * mult
			if s.depth > layer_depth:
				f *= 0.5
			if e.spd > 18.0:
				f *= 0.3
			rate += f
		if spd > 4.0 and r < 2800.0:
			rate += (spd - 4.0) / 12.0 * (1.0 - r / 2800.0) * 0.25
	e.detect = clampf(e.detect + (rate - 0.02) * dt, 0.0, 1.3)
	if e.detect >= 0.7 and rate > 0.02 and t - e.last_fix > 3.0:
		var err := 25.0 + r * 0.04
		e.est = s.pos + Vector2(U.gauss(), U.gauss()) * err
		e.has_est = true
		e.est_depth = s.depth + U.gauss() * (8.0 + s.depth * 0.12)
		e.last_fix = t
	if e.detect >= 1.0 and (e.state == "screen" or e.state == "search") and e.has_est:
		e.state = "hunt"
		report("Sonar: %s bearing %s is turning toward us. Fast screws!" % [e.short, U.p3(U.brg(s.pos, e.pos))], "alarm")
		tc = 1


func _alert_escort(e: Ship, where: Vector2, err: float) -> void:
	if not e.alive():
		return
	if e.state == "screen" or e.state == "search":
		e.state = "hunt"
	e.est = where + Vector2(U.gauss(), U.gauss()) * err
	e.has_est = true
	e.est_depth = sub.depth + U.gauss() * 20.0
	e.last_fix = t
	e.detect = maxf(e.detect, 0.8)


func _drop(e: Ship) -> void:
	var fresh := t - e.last_fix < 20.0
	var c := Charge.new()
	c.pos = e.pos - U.dirv(e.hdg) * (e.length * 0.45) + Vector2(U.gauss(), U.gauss()) * 15.0
	c.fuse = clampf(e.est_depth + U.gauss() * (6.0 if fresh else 25.0), 10.0, 260.0)
	charges.append(c)
	emit({"type": "splash", "pos": Vector3(c.pos.x, 0.0, c.pos.y), "size": 1.5})


func _pings() -> void:
	if t < next_ping:
		return
	for e in ships:
		if e.kind != "target" and e.alive() and e.hunting() and e.pos.distance_to(sub.pos) < 3000.0:
			sound("ping", 0.8)
			ping_flash = 1.0
			next_ping = t + 3.5
			return


# ------------------------------------------------------------ ship gunfire
func _ship_guns(sh: Ship, dt: float) -> void:
	if sh.guns.is_empty():
		return
	var s := sub
	var r := sh.pos.distance_to(s.pos)
	var surf := s.surfaced()
	var at_scope: bool = (not surf) and s.scope_up and s.depth <= PERI_MAX and sh.kind != "target" \
		and sh.detect >= 1.0 and r < 2500.0
	if not surf and not at_scope:
		sh.aware = false
		return
	if surf and not sh.aware:
		var see_r := vis * (0.55 if sh.kind == "target" else 0.75)
		if r < see_r or sh.detect >= 1.0:
			sh.aware = true
			report("Lookout: gun flashes from %s! They've seen us!" % sh.short, "alarm", "gunflash", 20.0)
			tc = 1
			for e in ships:
				if e.kind != "target":
					_alert_escort(e, s.pos, 300.0)
		else:
			return
	for g in sh.guns:
		if t < g["next"]:
			continue
		if r > g["range"] or r < g["min"]:
			continue
		if at_scope and g["cal"] > 130.0:
			continue
		g["next"] = t + float(g["reload"]) * randf_range(0.9, 1.25)
		_salvo(sh, g, r, at_scope)


func _salvo(sh: Ship, g: Dictionary, r: float, at_scope: bool) -> void:
	var s := sub
	var dh := absf(U.adiff(s.hdg, sh.aim_hdg))
	var ds := absf(s.spd - sh.aim_spd)
	if dh > 12.0 or ds > 3.0:
		sh.spread = 1.0
	else:
		sh.spread = maxf(0.22, sh.spread * 0.72)
	sh.aim_hdg = s.hdg
	sh.aim_spd = s.spd
	var v: float = g["v"]
	var cal: float = g["cal"]
	var tof := Ballistics.time_for_range(r, v, cal)
	if tof < 0.0:
		return
	var lead := s.pos + s.vel * tof
	var err := (30.0 + r * 0.02) * sh.spread * (1.6 if at_scope else 1.0)
	var center := Vector2(U.gauss(), U.gauss()) * err
	var from2 := sh.pos + U.dirv(sh.hdg) * randf_range(-0.2, 0.2) * sh.length
	var from := Vector3(from2.x, 10.0 if sh.type != "pc" else 4.0, from2.y)
	for i in int(g["n"]):
		var aim := lead + center + Vector2(U.gauss(), U.gauss()) * err * 0.35
		_launch(from, aim, v, "ship", g["dmg"], g["cal"], sh.id)
	emit({"type": "muzzle", "pos": from, "cal": g["cal"], "ship": sh.id})


func _launch(from: Vector3, aim: Vector2, v: float, kind: String, dmg: float, cal: float, owner: int) -> void:
	var d := aim - Vector2(from.x, from.z)
	var R := d.length()
	var e := U.elev_for_range(R, v, cal)
	if e < 0.0:
		return
	var dir := d.normalized()
	var er := deg_to_rad(e)
	var sh := Shell.new()
	sh.id = _new_id()
	sh.p = from
	sh.v = Vector3(dir.x * v * cos(er), v * sin(er), dir.y * v * cos(er))
	sh.kind = kind
	sh.dmg = dmg
	sh.cal = cal
	sh.owner = owner
	shells.append(sh)


func _hull_height(sh: Ship, along: float) -> float:
	var base := {"bb": 9.0, "cv": 18.0, "ca": 8.0, "cl": 7.0, "dd": 5.0, "pc": 3.5}.get(sh.type, 6.0) as float
	var top := {"bb": 30.0, "cv": 0.0, "ca": 20.0, "cl": 16.0, "dd": 8.0, "pc": 5.0}.get(sh.type, 8.0) as float
	if absf(along) < sh.length * 0.16:
		return base + top
	return base


func _update_shells(dt: float) -> void:
	var s := sub
	var keep: Array[Shell] = []
	for sh in shells:
		var p0: Vector3 = sh.p
		if sh.kind in ["ship", "gun"]:
			# Air drag slows shells down over their flight.
			var f := Ballistics.fly(sh.p, sh.v, Ballistics.drag(sh.cal), dt)
			sh.p = f[0]
			sh.v = f[1]
		else:
			sh.v.y -= GRAV * dt
			sh.p += sh.v * dt
		sh.life += dt
		var done := false
		match sh.kind:
			"gun":
				# Shells cover ~80 m a tick, so test the path in short steps.
				var n := int(ceil(p0.distance_to(sh.p) / 8.0))
				for k in range(1, n + 1):
					var q := p0.lerp(sh.p, float(k) / n)
					for ship in ships:
						if ship.dead:
							continue
						var d2 := Vector2(q.x, q.z) - ship.pos
						if d2.length() > ship.length:
							continue
						var along := d2.dot(U.dirv(ship.hdg))
						var across := d2.dot(U.dirv(ship.hdg + 90.0))
						var sink_drop := ship.sinking * 20.0 + ship.hull.settle
						if absf(along) < ship.length * 0.5 and absf(across) < ship.beam * 0.5 \
								and q.y < _hull_height(ship, along) - sink_drop and q.y > -1.0:
							sh.p = q
							_gun_hit(ship, sh)
							done = true
							break
					if done:
						break
			"aa":
				for p in planes:
					if p.dead:
						continue
					var pp: Vector3 = p.pos3()
					var rad: float = float(p.info["span"]) * 0.32
					if _seg_dist(p0, sh.p, pp) < rad:
						p.hp -= 1
						emit({"type": "spark", "pos": pp})
						if p.hp <= 0 and not p.falling:
							p.falling = true
							planes_down += 1
							report("Got him! %s is going down in flames!" % p.name, "good")
							sound("cheer", 0.6)
						done = true
						break
				if sh.life > 3.5:
					done = true
		if done:
			continue
		if sh.p.y <= 0.0:
			_shell_impact(sh)
			continue
		keep.append(sh)
	shells = keep


static func _seg_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return (a + ab * tt).distance_to(p)


func _gun_hit(ship: Ship, sh: Shell) -> void:
	var spot := hull_spot(ship, Vector2(sh.p.x, sh.p.z))
	var side_n := U.dirv(ship.hdg + 90.0) * spot.y
	var fl := Vector2(sh.v.x, sh.v.z)
	var cos_ob := absf(fl.normalized().dot(side_n)) if fl.length() > 1.0 else 1.0
	var height: float = sh.p.y + ship.hull.settle
	var res := ship.hull.shell(spot.x, int(spot.y), height, sh.cal, sh.v.length(), cos_ob, sh.dmg, ship.max_struct)
	ship.struct = ship.max_struct * ship.hull.health()
	ship.hits_taken += 1
	gun_hits += 1
	alert = true
	emit({"type": "boom", "pos": sh.p, "size": 2.5 if res["pen"] else 1.4, "kind": "shell_hit" if res["pen"] else "bounce", "ship": ship.id})
	sound("hit_far", 0.6, sh.p)
	_hull_news(ship)
	if ship.struct <= 0.0:
		if ship.alive() or ship.hull.afloat():
			_ship_sunk(ship, "gunfire")
	elif not res["pen"]:
		report("Gun crew: hit on %s, but it bounced off her %s." % [ship.short, "armour belt" if res["where"] == "belt" else "plating"],
			"info", "gunhit%d" % ship.id, 6.0)
	else:
		report("Gun crew: hit on %s%s!" % [ship.short, ", at the waterline" if res["flood"] else (", she's burning" if res["fire"] else "")],
			"good", "gunhit%d" % ship.id, 6.0)
	if ship.kind != "target" and not ship.aware:
		ship.aware = true
	if ship.kind == "target" or ship.kind == "escort":
		for e in ships:
			if e.kind != "target":
				_alert_escort(e, sub.pos, 300.0)


func _shell_impact(sh: Shell) -> void:
	var s := sub
	var p2 := Vector2(sh.p.x, sh.p.z)
	match sh.kind:
		"ship":
			var d := p2 - s.pos
			var along := d.dot(U.dirv(s.hdg))
			var across := d.dot(U.dirv(s.hdg + 90.0))
			var L: float = nat["sub"]["len"]
			if s.surfaced() and absf(along) < L * 0.5 and absf(across) < float(nat["sub"]["beam"]) * 0.5 + 1.0:
				shake = 1.0
				emit({"type": "boom", "pos": Vector3(p2.x, 2.0, p2.y), "size": 3.0, "kind": "shell_hit"})
				sound("hull_hit", 1.0)
				damage_sub(float(sh.dmg) * randf_range(0.7, 1.3), "Hit! A shell struck the casing!")
				_blast_crew(p2, 6.0 + float(sh.cal) / 40.0, 16.0 + float(sh.cal) / 15.0, "A shell burst on the casing beside you.")
				if exposed():
					s.crew_ready = maxf(s.crew_ready, 12.0)
					report("Men down on deck! The gun crew is hit!", "alarm")
				return
			if not s.surfaced() and s.scope_up and s.depth <= PERI_MAX and d.length() < 5.0:
				s.sys["periscope"] = minf(s.sys["periscope"], 15.0)
				s.scope_up = false
				report("A shell smashed the periscope head! Scope is out.", "alarm")
				sound("hull_hit", 0.8)
			if d.length() < 18.0 and s.surfaced():
				shake = maxf(shake, 0.6)
				damage_sub(2.0, "")
			_blast_crew(p2, 3.0, 4.0 + float(sh.cal) / 25.0, "Shell splinters from a near miss swept the deck.")
			emit({"type": "splash", "pos": Vector3(p2.x, 0.0, p2.y), "size": clampf(float(sh.cal) / 30.0, 2.0, 14.0)})
			sound("splash_near" if d.length() < 300.0 else "splash", 0.7, sh.p)
		"gun":
			emit({"type": "splash", "pos": Vector3(p2.x, 0.0, p2.y), "size": clampf(float(sh.cal) / 30.0, 2.5, 6.0)})
		"bomb":
			var d := p2.distance_to(s.pos)
			_blast_crew(p2, 16.0, 38.0, "A bomb burst right beside you on deck.")
			if s.surfaced() and d < 14.0:
				shake = 1.0
				emit({"type": "boom", "pos": Vector3(p2.x, 2.0, p2.y), "size": 6.0, "kind": "bomb"})
				damage_sub(35.0, "Bomb hit! We're holed!")
				return
			emit({"type": "splash", "pos": Vector3(p2.x, 0.0, p2.y), "size": 4.0})
			var c := Charge.new()
			c.pos = p2
			c.fuse = randf_range(8.0, 14.0)
			c.sink = 3.5
			c.aerial = true
			charges.append(c)
		"aa":
			pass


# ------------------------------------------------------------------ aircraft
func _update_planes(dt: float) -> void:
	var s := sub
	for p in planes:
		if p.dead:
			continue
		if p.falling:
			p.alt -= (25.0 + p.alt * 0.1) * dt
			p.hdg = U.wrap360(p.hdg + 25.0 * dt)
			p.roll += dt * 2.0
			p.pos += U.dirv(p.hdg) * p.kn * U.KN * dt
			if p.alt <= 0.0:
				p.dead = true
				emit({"type": "boom", "pos": Vector3(p.pos.x, 0.0, p.pos.y), "size": 8.0, "kind": "plane_crash"})
				emit({"type": "splash", "pos": Vector3(p.pos.x, 0.0, p.pos.y), "size": 10.0})
			continue
		var r := p.pos.distance_to(s.pos)
		_plane_detect(p, r, dt)
		var want_alt := 400.0
		var want_hdg := p.hdg
		var turn := 4.0
		match p.state:
			"patrol":
				p.center = target.pos if target.alive() else p.center
				var a := atan2(p.pos.x - p.center.x, p.pos.y - p.center.y)
				a += p.orb_dir * 0.35
				var tgt := p.center + Vector2(sin(a), cos(a)) * p.orb_r
				want_hdg = U.brg(p.pos, tgt)
			"attack":
				if t - p.seen_t < 2.0:
					var tof := r / (p.kn * U.KN)
					p.tgt = s.pos + s.vel * minf(tof, 30.0)
				var d := p.pos.distance_to(p.tgt)
				want_hdg = U.brg(p.pos, p.tgt)
				turn = 8.0
				want_alt = 60.0 if d < 3500.0 else 300.0
				var fall_t := sqrt(2.0 * maxf(p.alt, 1.0) / GRAV)
				var release := p.kn * U.KN * fall_t + 15.0
				if s.surfaced() and d < 1500.0 and d > 200.0 and t > p.strafe_next \
						and absf(U.adiff(U.brg(p.pos, s.pos), p.hdg)) < 12.0:
					_strafe(p, r)
				if p.bombs > 0 and d < release and absf(U.adiff(U.brg(p.pos, p.tgt), p.hdg)) < 25.0:
					_drop_bombs(p)
					p.state = "climb"
					p.pass_until = t + 25.0
				elif d > p.prev_d and d < 300.0:
					p.state = "climb"
					p.pass_until = t + 20.0
				p.prev_d = d
			"climb":
				want_alt = 320.0
				turn = 2.0
				if t > p.pass_until:
					if p.bombs > 0 and t - p.seen_t < 60.0:
						p.state = "attack"
						p.prev_d = 1e9
					elif p.bombs <= 0:
						p.state = "shadow"
						p.leave_at = t + 150.0
					else:
						p.state = "patrol"
			"shadow":
				want_alt = 500.0
				var a := atan2(p.pos.x - p.tgt.x, p.pos.y - p.tgt.y) + p.orb_dir * 0.35
				want_hdg = U.brg(p.pos, p.tgt + Vector2(sin(a), cos(a)) * 1500.0)
				if p.detect >= 1.0 and t - p.seen_t < 1.0:
					for e in ships:
						if e.kind != "target" and e.alive() and e.state == "screen":
							_alert_escort(e, s.pos, 200.0)
				if s.surfaced() and r < 1500.0 and t > p.strafe_next and absf(U.adiff(U.brg(p.pos, s.pos), p.hdg)) < 12.0:
					_strafe(p, r)
				if t > p.leave_at:
					p.state = "leave"
			"leave":
				want_alt = 600.0
				want_hdg = U.brg(target.pos, p.pos)
				if r > 18000.0:
					p.dead = true
					continue
		var dh := clampf(U.adiff(want_hdg, p.hdg), -turn * dt, turn * dt)
		p.hdg = U.wrap360(p.hdg + dh)
		p.roll = lerpf(p.roll, clampf(dh / maxf(dt, 1e-4) / turn, -1.0, 1.0) * 0.5, clampf(dt * 2.0, 0.0, 1.0))
		p.alt = move_toward(p.alt, want_alt, 18.0 * dt)
		p.pos += U.dirv(p.hdg) * p.kn * U.KN * dt
		# Lookouts on the bridge spot aircraft.
		if s.surfaced() and not p.spotted and r < vis * 0.85:
			p.spotted = true
			report("Lookout: aircraft bearing %s, %.0f km! %s!" % [U.p3(U.brg(s.pos, p.pos)), r / 1000.0, p.name], "alarm")
			sound("alarm", 0.8)
			tc = 1


func _plane_detect(p: Aircraft, r: float, dt: float) -> void:
	var s := sub
	var rate := 0.0
	if s.surfaced():
		var R := vis * 0.75
		if r < R:
			rate += 0.3 * (1.0 - r / R) + 0.08
	elif s.scope_up and s.depth <= PERI_MAX:
		var R := 2000.0 * vis / 14000.0
		if r < R:
			rate += 0.035 * (1.0 - r / R) * (0.4 + absf(s.spd) / 4.0)
	elif s.depth < 25.0 and tod == "day":
		if r < 450.0:
			rate += 0.12 * (1.0 - r / 450.0)
	if s.flood < 1.0 and not s.surfaced():
		var R2 := vis * 0.5
		if r < R2:
			rate += 0.2 * (1.0 - r / R2)
	p.detect = clampf(p.detect + (rate - 0.02) * dt, 0.0, 1.2)
	if p.detect >= 1.0 and rate > 0.02:
		p.seen_t = t
		if p.state == "patrol" or p.state == "leave":
			p.state = "attack"
			p.tgt = s.pos
			p.prev_d = 1e9
			if s.pos.distance_to(target.pos) < 6000.0:
				alert = true
			if next_plane > 1e8:
				next_plane = t + 240.0
			if s.surfaced() or s.scope_up:
				report("Lookout: aircraft diving on us, bearing %s! Clear the bridge!" % U.p3(U.brg(s.pos, p.pos)), "alarm", "airatk", 15.0)
			else:
				report("Sonar: aircraft engines overhead... they may have seen us!", "warn", "airatk", 15.0)
			sound("alarm", 0.8)
			tc = 1
			for e in ships:
				if e.kind != "target" and e.alive():
					_alert_escort(e, s.pos, 250.0)


func _drop_bombs(p: Aircraft) -> void:
	var n := mini(p.bombs, 2)
	p.bombs -= n
	var fwd := U.dirv(p.hdg) * p.kn * U.KN
	for i in n:
		var sh := Shell.new()
		sh.id = _new_id()
		sh.kind = "bomb"
		var off := U.dirv(p.hdg) * (-float(i) * 25.0)
		sh.p = Vector3(p.pos.x + off.x, p.alt - 2.0, p.pos.y + off.y)
		sh.v = Vector3(fwd.x, -2.0, fwd.y)
		sh.cal = 250.0
		sh.dmg = 35.0
		sh.owner = p.id
		shells.append(sh)
	report("%s has dropped bombs!" % p.name, "alarm", "bombs", 5.0)


func _strafe(p: Aircraft, r: float) -> void:
	p.strafe_next = t + 0.5
	var s := sub
	var dir := U.dirv(p.hdg)
	var end := s.pos + dir * randf_range(-30.0, 60.0) + U.dirv(p.hdg + 90.0) * U.gauss() * 8.0
	var start := end - dir * 120.0
	emit({"type": "strafe", "from": Vector3(start.x, 0.0, start.y), "to": Vector3(end.x, 0.0, end.y),
		"plane": Vector3(p.pos.x, p.alt, p.pos.y)})
	sound("mg", 0.7)
	if r < 800.0 and s.surfaced():
		s.hull = maxf(0.0, s.hull - 0.8)
		if exposed():
			s.crew_ready = maxf(s.crew_ready, 6.0)
			var cp := crew_pos()
			var a3 := Vector3(start.x, 0, start.y)
			var b3 := Vector3(end.x, 0, end.y)
			if _seg_dist(a3, b3, Vector3(cp.x, 0, cp.y)) < 2.5 and randf() < 0.5:
				kill_player("killed", "A burst of aircraft fire cut you down on deck.")
		report("We're being strafed! Bullets are ripping across the deck!", "alarm", "strafe", 8.0)


# --------------------------------------------------------------- torpedoes
func _update_torps(dt: float) -> void:
	var keep: Array[Torpedo] = []
	for tp in torps:
		var step: float = tp.kn * U.KN * dt
		tp.pos += U.dirv(tp.hdg) * step
		tp.run += step
		if tp.pos.distance_to(tp.trail[-1]) > 60.0:
			tp.trail.append(tp.pos)
		var hit: Ship = null
		for sh in ships:
			if sh.alive() and _inside(sh, tp.pos):
				hit = sh
				break
		if hit != null:
			if tp.depth > hit.draft + hit.hull.settle + 1.5:
				if not tp.has_meta("under%d" % hit.id):
					tp.set_meta("under%d" % hit.id, true)
					report("Sonar: torpedo ran under %s! Set it shallower." % hit.short, "warn")
				keep.append(tp)
				continue
			_torp_hit(tp, hit)
			continue
		if tp.run > tp.rng:
			if result == "":
				report("Sonar: a torpedo has run its course and sunk. Miss.", "warn")
			continue
		_wake_spotting(tp)
		keep.append(tp)
	torps = keep


func _wake_spotting(tp: Torpedo) -> void:
	if not tp.wake or tod == "night":
		return
	for sh in ships:
		if sh.kind != "target" or not sh.alive() or sh.comb_done or sh.max_kn < 4.0:
			continue
		var d := sh.pos.distance_to(tp.pos)
		if d < (1200.0 if tod == "day" else 600.0) and randf() < 0.004:
			sh.comb_done = true
			sh.leg = U.wrap360(tp.hdg + 180.0)
			sh.base_hdg = sh.leg
			alert = true
			report("Conn: she's turning hard! Her lookouts have spotted the wakes!", "warn")


static func _inside(sh: Ship, p: Vector2) -> bool:
	var d := p - sh.pos
	var along := d.dot(U.dirv(sh.hdg))
	var across := d.dot(U.dirv(sh.hdg + 90.0))
	return absf(along) < sh.length * 0.5 and absf(across) < sh.beam * 0.5 + 3.0


func _torp_hit(tp: Torpedo, sh: Ship) -> void:
	var s := sub
	var r := s.pos.distance_to(sh.pos)
	if tp.run < ARM_DIST:
		duds += 1
		sound("thud", 0.6)
		report("A clang against %s... the warhead hadn't armed yet. Too close!" % sh.short, "warn")
	elif randf() < float(nat["torp"]["dud"]):
		duds += 1
		sound("thud", 0.6)
		report("Hit on %s, but no explosion. A dud!" % sh.short, "warn")
	else:
		var spot := hull_spot(sh, tp.pos)
		sh.hits_taken += 1
		hits += 1
		emit({"type": "boom", "pos": Vector3(tp.pos.x, 0.0, tp.pos.y), "size": sh.length / 18.0, "kind": "torpedo", "ship": sh.id})
		sound("torp_hit", clampf(1.2 - r / 8000.0, 0.3, 1.0))
		tc = 1
		sh.hull.torpedo(spot.x, int(spot.y), float(nat["torp"].get("kg", 300.0)) / 300.0)
		sh.struct = sh.max_struct * sh.hull.health()
		var blew := sh.hull.mode == "explode"
		_hull_news(sh)
		if not blew and sh.struct > 0.0:
			var left := sh.hull.hits_left()
			report("Explosion! Torpedo hit %s on %s, %s side. Estimate %d more hit%s to sink her." % [where(spot.x), sh.short,
				"starboard" if spot.y > 0.0 else "port", left, "s" if left > 1 else ""], "good")
		elif sh.struct <= 0.0 and not blew and sh.kind == "target" and result == "":
			_ship_sunk(sh, "torpedo")
	alert = true
	var err := 350.0 if bool(nat["torp"]["wake"]) else 700.0
	for e in ships:
		if e.kind != "target" and e.alive() and (e.state == "screen" or e.state == "search"):
			_alert_escort(e, s.pos, err)
	if escorts().size() > 0:
		once("escorts_alert", "Sonar: all escorts increasing speed! They're coming for us.", "alarm")
	if next_plane > 1e8:
		next_plane = t + 180.0


func _ship_sunk(sh: Ship, how: String) -> void:
	if sh.said.has("sunk"):
		return
	sh.said["sunk"] = true
	if sh.hull.mode == "":
		sh.hull.mode = "founder"
	var how_txt: String = {"capsize": "She's rolling over! %s is capsizing!", "magazine": "%s is going down in two pieces!",
		"broken": "%s is going down in two pieces!",
		"wrecked": "%s is a burning wreck. She's going down!", "founder": "She's settling fast. %s is going down!"}.get(how,
		"She's breaking up! %s is going down!")
	if sh.kind == "target":
		if how not in ["magazine", "broken"]:
			report(how_txt % sh.name, "good")
		sound("breakup", 1.0)
		_end("win", 12.0)
	else:
		esc_sunk += 1
		if how not in ["magazine", "broken"]:
			report("%s is sinking! Escort destroyed." % sh.name, "good")
		sound("breakup", 0.6)


func _update_charges(dt: float) -> void:
	var s := sub
	var keep: Array[Charge] = []
	for c in charges:
		c.z += c.sink * dt
		if c.z < c.fuse:
			keep.append(c)
			continue
		var d3 := Vector3(c.pos.x - s.pos.x, c.z - s.depth, c.pos.y - s.pos.y).length()
		var dmg := 38.0 if d3 < 10.0 else (20.0 if d3 < 25.0 else (9.0 if d3 < 45.0 else (3.0 if d3 < 80.0 else 0.0)))
		if c.aerial:
			dmg *= 0.85
		shake = maxf(shake, clampf(1.0 - d3 / 160.0, 0.0, 1.0))
		emit({"type": "dc", "pos": Vector3(c.pos.x, 0.0, c.pos.y), "depth": c.z, "near": d3})
		sound("dc", clampf(1.1 - d3 / 500.0, 0.15, 1.0))
		if dmg >= 20.0:
			damage_sub(dmg, "Very close! Gauges smashed, leaks forward. Hull at %d%%." % int(s.hull - dmg))
		elif dmg > 0.0:
			damage_sub(dmg, "Close one. Hull at %d%%." % int(s.hull - dmg))
		elif d3 < 250.0:
			report("Depth charge, not close.", "info", "dcfar", 6.0)
	charges = keep


# -------------------------------------------------------------- sensors
func _observe(dt: float) -> void:
	var s := sub
	var see := s.can_see()
	var own := absf(s.spd)
	var hydro: float = s.sys["hydrophones"] / 100.0
	var hear_r := (6000.0 if own > 7.0 else 13000.0) * (0.5 if s.flood < 1.0 else 1.0) * (0.3 + 0.7 * hydro)
	for sh in ships:
		if sh.dead:
			sh.heard = false
			continue
		var r := s.pos.distance_to(sh.pos)
		sh.heard = r < hear_r and (sh.spd > 0.6 or r < 2500.0 or sh.sinking > 0.0)
		if sh.heard and not sh.ever_heard:
			sh.ever_heard = true
			var b := U.p3(U.brg(s.pos, sh.pos))
			match sh.type:
				"dd":
					report("Sonar: fast, light screws bearing %s. Destroyer." % b)
				"pc":
					report("Sonar: high-pitched screws bearing %s. Small escort, maybe a sub-chaser." % b)
				_:
					report("Sonar: heavy screws bearing %s. Big ship!" % b, "good")
		if see and r < vis:
			sh.plot = {"pos": sh.pos, "hdg": sh.hdg, "spd": sh.spd, "t": t}
			if not sh.ever_seen:
				sh.ever_seen = true
				var b := U.p3(U.brg(s.pos, sh.pos))
				if sh.kind == "target":
					report("Conn: %s in sight, bearing %s! Range %.1f km." % [sh.name, b, r / 1000.0], "good")
				elif sh.kind == "chaser":
					report("Conn: small escort in sight, bearing %s." % b)
				else:
					report("Conn: escort destroyer in sight, bearing %s." % b)
	if lock != null:
		if not lock.alive():
			lock = null
		elif see and s.pos.distance_to(lock.pos) < vis:
			lock_obs += dt


func threat() -> Array:
	var s := sub
	var attacking := false
	var searching := false
	for e in ships:
		if e.kind == "target" or not e.alive():
			continue
		if e.hunting() and e.pos.distance_to(s.pos) < 3500.0:
			attacking = true
		elif e.state != "screen":
			searching = true
		if e.aware and s.surfaced():
			attacking = true
	for p in planes:
		if not p.dead and (p.state == "attack" or p.state == "climb"):
			attacking = true
		elif not p.dead and p.state == "shadow":
			searching = true
	if attacking:
		return ["UNDER ATTACK", "alarm"]
	if searching:
		return ["HUNTED", "warn"]
	return ["UNDETECTED", "good"]


# ---------------------------------------------------------------- endings
func _end(kind: String, delay: float) -> void:
	if result != "":
		return
	result = kind
	end_delay = delay
	tc = 1


func _check_end() -> void:
	if result != "":
		return
	var s := sub
	var tg := target
	if s.hull <= 0.0:
		report("We're breaking up! All hands...", "alarm")
		sound("breakup", 1.0)
		_end("lost", 3.0)
	elif tg.alive() and s.pos.distance_to(tg.pos) > float(nat.get("escape", ESCAPE)):
		report("Sonar: lost %s's screws. She got away." % tg.short, "warn")
		_end("escaped", 2.5)
	elif tg.alive() and torps.is_empty():
		var empty := true
		for v in s.tubes:
			if v >= 0.0:
				empty = false
		if empty and (s.gun_ammo <= 0 or tg.type in ["bb", "cv", "ca"]):
			report("Torpedo room: that was our last fish.", "warn")
			_end("dry", 2.5)
