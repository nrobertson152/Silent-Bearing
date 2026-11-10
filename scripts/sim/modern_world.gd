extends "res://scripts/sim/world.gd"
## The near-future war in the Western Pacific. Same boat handling, damage
## model and ballistics as the wartime game, with modern groups of ships
## spread over tens of kilometres:
## - you listen on a towed array and work out a target's range from
##   bearings as you change course; the photonics mast gives a quick fix but
##   their radars may see it;
## - wire-guided Mk 48s run out on the fire control's latest solution, then
##   home on what they hear and burst under the keel;
## - the screen hunts with towed arrays, active sonar and helicopters dipping
##   sonar, and answers with homing torpedoes, dropped, fired from tubes or
##   flown out by rocket;
## - you fight back with decoys, speed, depth and the thermal layer.

## Faster than this the guidance wires part; farther than this they run out.
const WIRE_KN := 18.0
const WIRE_LEN := 22000.0
const DECOY_LIFE := 55.0
## Enemy lightweight torpedo (Yu-7 class).
const LW_KN := 43.0
const LW_RANGE := 9000.0
const LW_SEEKER := 1500.0
## Rocket-delivered torpedo reach and flight time.
const ROCKET_RANGE := 18000.0
## Missile launches: deepest and fastest the boat can be, seconds between
## missiles in a salvo, seconds of booster climb, and salvo sizes to pick.
const MISSILE_DEPTH := 45.0
const MISSILE_KN := 10.0
const LAUNCH_EVERY := 3.0
const BOOST_T := 6.0
const SALVOS := [1, 2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 154]
## Offboard contact reports (satellites, patrol aircraft) come this often.
const LINK_EVERY := 150.0
## Escorts only leave the screen to hunt a datum closer than this.
const HUNT_RADIUS := 35000.0
## Their submarines, and the heavyweight torpedoes they fire (Yu-6 class).
const SUBS := ["ssn", "ssbn"]
const HW_KN := 50.0
const HW_RANGE := 40000.0
const HW_SEEKER := 2500.0
## The Trident test launch: depth window, hover speed, and how long the
## launch sequence takes.
const LAUNCH_DEPTH := Vector2(25.0, 45.0)
const HOVER_KN := 3.0
const LAUNCH_T := 60.0


## A homing torpedo: your Mk 48s, and the enemy's lightweight torpedoes.
class Homer extends Torpedo:
	var owner := -1            # -1 your boat; otherwise the ship or helicopter that launched it
	var kind := "mk48"         # mk48, yu7
	var unit := 1              # number for reports
	var state := "run"         # run, search, home, decoy
	var course := 0.0          # heading it is turning to
	var wire := false
	var seeker := 2800.0
	var cone := 45.0
	var enable := 1500.0       # run distance at which the seeker switches on
	var aim_id := -1           # guidance target (ship id), or what it is homing on
	var turn := 20.0           # degrees per second
	var spin := 1.0            # search circle direction
	var fake := Vector2.ZERO   # where a decoy led it
	var next_guide := 0.0
	var deaf_until := 0.0      # seeker swamped after running through a decoy
	var told := {}


## A noisemaker you launched: it hangs in the water and screams.
class Decoy:
	var id := 0
	var pos := Vector2.ZERO
	var depth := 30.0
	var life := DECOY_LIFE


## A missile in the air: your Harpoons and Tomahawks, and their
## surface-to-air missiles going after them.
class Missile:
	var id := 0
	var kind := "tomahawk"     # harpoon, tomahawk, sam
	var unit := 0              # number for reports
	var salvo := 0
	var owner := -1            # -1 your boat; else the ship that fired it
	var pos := Vector2.ZERO
	var alt := 0.0
	var hdg := 0.0
	var spd := 0.0             # m/s
	var top := 240.0           # full speed, m/s
	var state := "boost"       # yours: boost, dive, cruise, seek, home, decoyed; theirs: fly
	var cruise_alt := 12.0
	var way := Vector2.ZERO    # dogleg turn point, so a salvo arrives together
	var has_way := false
	var aim := Vector2.ZERO    # where its target should be when it gets there
	var aim_id := -1           # the ship it was fired at, or is homing on
	var arrive := 0.0          # planned time on target
	var seeker := 20000.0
	var cone := 40.0
	var flown := 0.0
	var reach := 100000.0
	var kg := 450.0
	var link := false          # takes new aim points over the link
	var origin := Vector2.ZERO
	var t0 := 0.0
	var seen := false          # their radars have it
	var engaged := 0           # their missiles in the air after it
	var chaffed := false
	var fake := Vector2.ZERO   # the chaff cloud that pulled it off
	var next_aim := 0.0
	var dead := false
	var tgt := -1              # theirs: the missile it is after
	var layer := 0             # theirs: which of the ship's layers fired it
	var pk := 0.5              # theirs: chance it kills
	var trail: Array = []


## A sonobuoy a patrol aircraft has laid: it floats and listens.
class Buoy:
	var id := 0
	var pos := Vector2.ZERO
	var life := 3600.0
	var heard := false         # we heard it splash in, so it is on our plot


var etorps: Array[Homer] = []
var decoys: Array[Decoy] = []
var buoys: Array[Buoy] = []
var mpa_route := {}              # patrol aircraft id -> its racetrack waypoints
var mpa_wp := {}                 # patrol aircraft id -> index of the waypoint it is flying to
var mpa_buoys := {}              # patrol aircraft id -> sonobuoys left
var trident := 0                 # test rounds aboard
var launch_seq := -1.0           # when the launch sequence started, or -1
var launched := false
var box := Vector2.ZERO          # the launch box
var box_r := 0.0
var missiles: Array[Missile] = []
var weapon := "mk48"             # mk48, harpoon, tomahawk
var salvo := 4
var harpoons := 0
var vls := 0                     # Tomahawks left in the launch cells
var launch_queue: Array = []     # missiles of a salvo still to leave: {"kind", "at", "aim", "aim_id", "arrive", "side", "salvo"}
var salvos := {}                 # salvo number -> tally for the report at the end
var oth := {}                    # ship id -> {"pos", "vel", "t", "err"}: offboard reports over the link
var link_t := -999.0             # when we last took the link
var m_units := 0
var m_fired := 0
var m_hits := 0
var m_down := 0                  # shot down
var adef := {}                   # ship id -> {"stock": [], "busy": [], "next": [], "fx": 0.0}
var air_alert := -999.0          # when their radars last saw a missile
var _mindex := {}                # missile id -> Missile, rebuilt every tick
var rockets: Array = []          # {"from", "to", "t", "dur", "id"} rocket-thrown torpedoes in flight
var datum := Vector2.ZERO        # where the enemy thinks you are
var datum_t := -999.0
var datum_err := 4000.0
var alarm_t := -999.0            # when the group last knew it was under attack
var lock_rng_err := 0.0
var leg_hdg := 0.0
var leg_t := 0.0
var legs_done := 0
var decoy_cool := 0.0
var units := 0
var mast_t := 0.0                # how long the mast has been up this time
var helo_pad := {}               # helicopter id -> ship it flies from
var rocket_stock := {}           # ship id -> rocket-thrown torpedoes left
var next_weapon := 0.0           # the group spaces its torpedo shots out


func _init(nation: Dictionary, target_spec: Dictionary, is_demo := false) -> void:
	super(nation, target_spec, is_demo)
	vis = {"day": 22000.0, "dusk": 16000.0, "night": 11000.0}.get(tod, 20000.0)
	leg_hdg = sub.hdg
	sub.depth = 60.0
	sub.dep_ord = 60.0
	sub.scope_up = false
	sub.tel = 3
	sub.spd = 0.3 * float(nat["sub_kn"])
	var ms: Dictionary = nat.get("missiles", {})
	harpoons = int(ms.get("harpoon", 0))
	vls = int(ms.get("tomahawk", 0))
	trident = int(ms.get("trident", 0))
	if spec.get("goal", "") == "patrol":
		# Deep below the layer, creeping.
		sub.depth = 150.0
		sub.dep_ord = 150.0
		sub.tel = 3
		sub.spd = 0.24 * float(nat["sub_kn"])
	if spec.has("start") and spec.get("type", "") not in SUBS:
		# A missile strike from beyond sonar range: Tomahawks up first.
		weapon = "tomahawk" if vls > 0 else "mk48"
		salvo = 64 if vls >= 64 else 4
	_set_depths()


func _opening() -> void:
	if spec.get("goal", "") == "patrol":
		var b: Vector2 = spec["box"]
		report("Conn: on patrol at 150 metres. The launch box is bearing %s, %d km. Hunters about: keep it slow and deep." % [
			U.p3(U.brg(sub.pos, b)), int(sub.pos.distance_to(b) / 1000.0)], "good")
		report("Sonar: towed array streamed. Listening.")
		report("Bathythermograph: thermal layer near %d metres. Stay below it and their hull sonars and buoys hear us half as well." % int(layer_depth))
		return
	report("Conn: on station at 60 metres, ahead one-third. Hunting %s and her group." % target.name, "good")
	if spec.has("start") and target.type in SUBS:
		report("Intelligence puts %s about %d km off, bearing %s. She's deep and slow: listen for her on the array." % [
			target.short, int(round(sub.pos.distance_to(target.pos) / 1000.0)), U.p3(U.wrap360(U.brg(sub.pos, target.pos) + randf_range(-12.0, 12.0)))], "info")
	elif spec.has("start"):
		report("Radio: %s's group is about %d km off, too far to hear. Come up, raise the mast and take the link for her position." % [
			target.short, int(sub.pos.distance_to(target.pos) / 5000.0) * 5], "info")
	report("Sonar: towed array streamed. Listening.")
	report("Bathythermograph: thermal layer near %d metres. Below it, their hull sonars hear us half as well." % int(layer_depth))


# ----------------------------------------------------------------- setup
## A main target with her group on stations kilometres out, and helicopters.
func _spawn() -> void:
	var tg := Ship.new()
	tg.id = _new_id()
	tg.kind = "target"
	tg.name = String(spec.get("target_name", GameData.PREFIX[spec["nation"]] + spec["name"]))
	tg.short = String(spec.get("target_name", spec["name"]))
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
	tg.cruise = tg.max_kn * 0.7
	tg.hull = _make_hull(tg, float(spec["hp"]))
	var start: Array = spec.get("start", [])
	var line: Array = spec.get("patrol", [])
	if line.size() == 2:
		# A hunter sweeping a line across our way.
		tg.route = line
		tg.home = "patrol"
		tg.state = "patrol"
		tg.pos = (line[0] as Vector2).lerp(line[1], randf())
		tg.hdg = U.brg(tg.pos, line[1])
	elif start.size() == 2:
		# Far out, more or less ahead, steaming toward us (or across).
		tg.pos = U.dirv(sub.hdg + randf_range(-35.0, 35.0)) * randf_range(float(start[0]), float(start[1]))
		tg.hdg = U.wrap360(U.brg(tg.pos, sub.pos) + randf_range(-25.0, 25.0))
		if spec.get("approach", "") == "crossing":
			tg.hdg = U.wrap360(tg.hdg + (90.0 if randf() < 0.5 else -90.0))
	else:
		var side := 1.0 if randf() < 0.5 else -1.0
		tg.pos = Vector2(-side * randf_range(20000, 25000), randf_range(14000, 19000))
		tg.hdg = U.wrap360((90.0 if side > 0 else 270.0) + randf_range(-20.0, 20.0))
	tg.base_hdg = tg.hdg
	tg.leg = tg.hdg
	tg.spd = tg.cruise
	tg.want_spd = tg.cruise
	tg.next_zig = randf_range(120, 240)
	if tg.type in SUBS:
		_make_sub(tg)
	target = tg
	ships.append(tg)
	box = spec.get("box", Vector2.ZERO)
	box_r = float(spec.get("box_r", 0.0))
	for g in spec.get("group", []):
		var e := Ship.new()
		e.id = _new_id()
		e.kind = "escort"
		e.nation = spec["nation"]
		e.short = g["name"]
		e.name = GameData.PREFIX[spec["nation"]] + String(g["name"])
		e.type = g["type"]
		e.layout = g["layout"]
		e.length = g["length"]
		e.beam = g["beam"]
		e.draft = g["draft"]
		e.max_kn = g["kn"]
		e.max_struct = float(g["hp"]) * 100.0
		e.struct = e.max_struct
		e.hull = _make_hull(e, float(g["hp"]))
		e.off = g["station"]
		e.pos = _station(tg, e.off)
		e.hdg = tg.hdg
		e.spd = tg.cruise
		e.want_spd = tg.cruise
		var route: Array = g.get("patrol", [])
		if route.size() == 2:
			e.route = route
			e.home = "patrol"
			e.state = "patrol"
			e.pos = (route[0] as Vector2).lerp(route[1], randf())
			e.hdg = U.brg(e.pos, route[1])
			e.spd = 12.0
			e.want_spd = 12.0
		if e.type in SUBS:
			_make_sub(e)
		e.to_drop = 6 if e.type == "ffg" else 4       # torpedoes in the deck tubes
		rocket_stock[e.id] = 3 if e.type in ["cg", "ddg"] else 0
		ships.append(e)
	# Helicopters fly day and night, from the carrier or the cruisers.
	var pads := []
	for e in ships:
		if e.type in ["cv", "cg", "ddg", "ffg"]:
			pads.append(e)
	for key in spec.get("air", []):
		if GameData.AIRCRAFT[key]["kind"] == "mpa":
			_spawn_mpa(key)
		elif not pads.is_empty():
			_spawn_helo(key, pads[planes.size() % pads.size()])
	next_plane = 1e9
	# Missile magazines for their air defence.
	for sh in ships:
		var ad := GameData.air_defence(sh.layout)
		if ad.is_empty():
			continue
		var st := {"stock": [], "busy": [], "next": [], "fx": 0.0}
		for L in ad["sams"]:
			st["stock"].append(int(L["n"]))
			st["busy"].append(0)
			st["next"].append(0.0)
		adef[sh.id] = st


func _spawn_helo(key: String, pad: Ship) -> void:
	var info: Dictionary = GameData.AIRCRAFT[key]
	var p := Aircraft.new()
	p.id = _new_id()
	p.key = key
	p.info = info
	p.name = info["name"]
	p.kn = info["kn"]
	p.hp = info["hp"]
	p.bombs = info["bombs"]
	p.state = "patrol"
	p.center = target.pos
	p.orb_r = randf_range(7000, 11000)
	p.orb_dir = 1 if randf() < 0.5 else -1
	var a := deg_to_rad(target.hdg + randf_range(-70.0, 70.0))
	p.pos = target.pos + Vector2(sin(a), cos(a)) * p.orb_r
	p.hdg = randf_range(0, 360)
	p.alt = 150.0
	planes.append(p)
	helo_pad[p.id] = pad.id


## A submarine of theirs: deep, slow and quiet until it has reason not to be.
func _make_sub(sh: Ship) -> void:
	sh.depth = randf_range(120.0, 180.0) if sh.type == "ssn" else 110.0
	sh.want_depth = sh.depth
	sh.cruise = 6.0 if sh.type == "ssbn" else 8.0
	sh.spd = sh.cruise
	sh.want_spd = sh.cruise
	sh.zig = false
	sh.to_drop = 6 if sh.type == "ssn" else 0       # heavyweight torpedoes ready in the tubes
	sh.next_zig = t + randf_range(300.0, 600.0)


## A patrol aircraft flying a racetrack across our way, laying sonobuoy
## lines as it goes.
func _spawn_mpa(key: String) -> void:
	var info: Dictionary = GameData.AIRCRAFT[key]
	var p := Aircraft.new()
	p.id = _new_id()
	p.key = key
	p.info = info
	p.name = info["name"]
	p.kn = info["kn"]
	p.hp = info["hp"]
	p.bombs = info["bombs"]
	p.state = "patrol"
	p.alt = 500.0
	# Two legs across the way to the box, at a third and two thirds of the way.
	var goal: Vector2 = spec.get("box", target.pos)
	var d := goal - sub.pos
	var across := U.dirv(U.brg(sub.pos, goal) + 90.0) * 13000.0
	var n1 := sub.pos + d * 0.38
	var n2 := sub.pos + d * 0.68
	mpa_route[p.id] = [n1 - across, n1 + across, n2 + across, n2 - across]
	mpa_wp[p.id] = 1
	mpa_buoys[p.id] = int(info.get("buoys", 40))
	p.pos = n1 - across - U.dirv(U.brg(n1 - across, n1 + across)) * 4000.0
	p.hdg = U.brg(p.pos, n1 + across)
	planes.append(p)


func _set_depths() -> void:
	depths = [0.0, 12.0, 30.0, 60.0, 100.0, 150.0, 200.0, float(nat["test"])]


# ------------------------------------------------------------- listening
## How far the towed array hears a ship: bigger and faster is louder, and
## your own speed drowns everything out.
func _hear_range(sh: Ship) -> float:
	var base: float = {"cv": 42000.0, "cg": 30000.0, "ddg": 27000.0, "ffg": 21000.0, "ssn": 11000.0, "ssbn": 16000.0}.get(sh.type, 24000.0)
	var loud := 0.45 + 0.55 * clampf(sh.spd / 20.0, 0.0, 1.5)
	var own := clampf(1.15 - (absf(sub.spd) - 8.0) / 14.0, 0.12, 1.0)
	var layer := 0.6 if (sub.depth > layer_depth) else 1.0
	if sh.type in SUBS:
		# A quiet submarine creeping is far harder to hear than one sprinting;
		# across the layer from us, harder still. One that just fired is loud.
		loud = 0.3 + 0.7 * clampf(sh.spd / 16.0, 0.0, 1.8)
		layer = 0.55 if (sub.depth > layer_depth) != (sh.depth > layer_depth) else 1.0
		if t < sh.loud_until:
			loud *= 3.0
	if sub.surfaced():
		own *= 0.5
	return base * loud * own * layer * (0.3 + 0.7 * sub.sys["hydrophones"] / 100.0)


func _class_name(sh: Ship) -> String:
	match sh.type:
		"cv":
			return "Big, slow turbines: a carrier"
		"cg":
			return "Gas turbines, heavy: a cruiser"
		"ddg":
			return "Gas turbines: a destroyer"
		"ffg":
			return "Diesels: a frigate"
		"ssn":
			return "Reactor pumps and a seven-bladed screw, submerged: a Type 093 attack submarine"
		"ssbn":
			return "Big reactor plant, slow screw, submerged: a Type 094 missile submarine"
	return "A warship"


func _observe(dt: float) -> void:
	var s := sub
	var see := s.can_see() and (s.scope_up or s.surfaced())
	for sh in ships:
		if sh.dead:
			continue
		var r := s.pos.distance_to(sh.pos)
		sh.heard = sh.alive() and r < _hear_range(sh)
		if sh.heard and not sh.ever_heard:
			sh.ever_heard = true
			report("Sonar: new contact on the towed array, bearing %s. %s." % [U.p3(U.brg(s.pos, sh.pos)), _class_name(sh)])
		if see and r < vis and sh.alive() and sh.depth < 3.0:
			sh.plot = {"pos": sh.pos, "hdg": sh.hdg, "spd": sh.spd, "t": t}
			if not sh.ever_seen:
				sh.ever_seen = true
				report("Photonics: %s in view, bearing %s, %.1f km." % [sh.name, U.p3(U.brg(s.pos, sh.pos)), r / 1000.0], "good")
	# New legs: a firm course change while tracking lets fire control work
	# out the range from how the bearing moves.
	if absf(U.adiff(s.hdg, leg_hdg)) > 25.0:
		if t - leg_t > 60.0 and lock != null and lock.heard:
			lock_obs += 4.0
			legs_done += 1
			report("Fire control: new leg. The range on %s is firming up." % lock.short, "info", "leg", 30.0)
		leg_hdg = s.hdg
		leg_t = t
	if lock != null:
		if not lock.alive():
			lock = null
		elif see and s.pos.distance_to(lock.pos) < vis:
			lock_obs += dt * 2.0
		elif lock.heard:
			lock_obs += dt * 0.06
	# The mast up for long near their radars gets noticed.
	if s.scope_up and s.depth <= PERI_MAX and not s.surfaced():
		mast_t += dt
		for e in ships:
			if not e.alive() or e.depth > 3.0:
				continue
			var r := s.pos.distance_to(e.pos)
			if r < 16000.0 and randf() < dt * 0.02 * (1.0 - r / 16000.0) * clampf(mast_t / 20.0, 0.3, 2.0):
				report("ESM: they've got us on radar! %s's radar has locked our mast." % e.short, "alarm", "mastdet", 30.0)
				_new_datum(s.pos, 150.0, e)
				break
	else:
		mast_t = 0.0


func strobe(sh: Ship) -> float:
	var r := sub.pos.distance_to(sh.pos)
	return clampf(1.05 - r / maxf(_hear_range(sh), 1.0), 0.08, 1.0)


func threats() -> Array:
	var out := []
	for tp in etorps:
		if tp.pos.distance_to(sub.pos) < 9000.0:
			out.append(tp)
	return out


func fire_control_estimate() -> Array:
	if lock == null or not lock.alive():
		return []
	var est := _estimate()
	var err := (1.0 - float(est[2])) * sub.pos.distance_to(lock.pos) * 0.35 + 150.0
	return [est[0], est[1], err]


func lock_sonar() -> void:
	var best: Ship = null
	var score := 1e9
	for sh in ships:
		if not sh.alive() or not sh.heard:
			continue
		var sc := sub.pos.distance_to(sh.pos) / _hear_range(sh) - (0.3 if sh.kind == "target" else 0.0)
		if sc < score:
			score = sc
			best = sh
	if best == null:
		report("Sonar: nothing on the array to track.", "warn")
		return
	lock_ship(best)


func lock_ship(sh: Ship) -> void:
	if sh == null or not sh.alive():
		return
	if lock != sh:
		lock_obs = 0.0
		lock_err = Vector2(U.gauss(), U.gauss())
		lock_rng_err = U.gauss()
	lock = sh
	if sub.can_see() and sub.scope_up and sub.pos.distance_to(sh.pos) < vis and sh.depth < 3.0:
		report("Fire control: tracking %s on the mast. Laser range taken." % sh.name, "good")
		lock_obs = maxf(lock_obs, 6.0)
	else:
		report("Fire control: tracking %s, bearing %s. Hold her on the array and change course now and then to firm up the range." % [sh.name,
			U.p3(U.brg(sub.pos, sh.pos))], "good")


## Where fire control thinks the locked ship is and how she is moving, with
## errors that shrink as the solution firms up.
func _estimate() -> Array:
	var sh := lock
	var q := clampf(lock_obs / 12.0, 0.0, 1.0)
	var err := 1.0 - q
	var p := sub.pos + (sh.pos - sub.pos) * (1.0 + lock_rng_err * 0.35 * err)
	var v := U.dirv(sh.hdg + lock_err.y * 15.0 * err) * sh.spd * (1.0 + lock_err.x * 0.3 * err) * U.KN
	return [p, v, q]


## Heading from `from` at `speed` (m/s) to meet a ship at `p` moving at `v`.
static func _intercept(from: Vector2, speed: float, p: Vector2, v: Vector2) -> Dictionary:
	var d := p - from
	var a := v.dot(v) - speed * speed
	var b := 2.0 * d.dot(v)
	var c := d.dot(d)
	var tt := 1e18
	if absf(a) < 1e-9:
		if absf(b) > 1e-9 and -c / b > 0.0:
			tt = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var r := sqrt(disc)
			for x in [(-b - r) / (2.0 * a), (-b + r) / (2.0 * a)]:
				if x > 0.0 and x < tt:
					tt = x
	if tt > 1e17:
		return {}
	return {"hdg": U.brg(from, p + v * tt), "t": tt, "run": speed * tt}


func solution():
	if lock == null or not lock.alive():
		return null
	var est := _estimate()
	var S: float = float(nat["torp"]["kn"]) * U.KN
	var it := _intercept(sub.pos, S, est[0], est[1])
	if it.is_empty():
		return null
	return {"hdg": it["hdg"], "t": it["t"], "run": it["run"], "q": est[2], "gyro": U.adiff(it["hdg"], sub.hdg),
		"in_range": float(it["run"]) <= float(nat["torp"]["range"])}


# ---------------------------------------------------------------- Mk 48
func fire(n := 1, view_brg := -1.0) -> void:
	if result != "" or demo:
		return
	if weapon == "trident":
		start_test_launch()
		return
	if weapon != "mk48":
		fire_missiles(weapon, 1 if n <= 1 else salvo)
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
	var base: float = s.hdg
	if sol != null:
		base = sol["hdg"]
	elif view_brg >= 0.0:
		base = view_brg
	var offs := [-5.0, 5.0] if n >= 2 else [0.0]
	var used := []
	for o in offs:
		if loaded.is_empty():
			break
		var i: int = loaded.pop_front()
		units += 1
		var tp := Homer.new()
		tp.id = _new_id()
		tp.unit = units
		tp.owner = -1
		tp.kind = "mk48"
		tp.pos = s.pos + U.dirv(s.hdg) * (float(nat["sub"]["len"]) * 0.45)
		tp.hdg = s.hdg
		tp.course = U.wrap360(base + o)
		tp.kn = nat["torp"]["kn"]
		tp.rng = nat["torp"]["range"]
		tp.wake = false
		tp.depth = clampf(s.depth, 20.0, 80.0)
		if lock != null and lock.depth > 3.0:
			# Against a submarine, run out near the depth we think she's at.
			tp.depth = clampf(lock.depth + randf_range(-30.0, 30.0), 30.0, 300.0)
		tp.wire = true
		tp.seeker = nat["torp"]["seeker"]
		tp.cone = nat["torp"]["cone"]
		tp.enable = maxf(1200.0, float(sol["run"]) - 3000.0) if sol != null else 1500.0
		tp.aim_id = lock.id if lock != null else -1
		tp.trail = [tp.pos]
		torps.append(tp)
		if s.spares > 0:
			s.tubes[i] = RELOAD
			s.spares -= 1
		else:
			s.tubes[i] = -1.0
		used.append(str(tp.unit))
	fired += used.size()
	sound("launch", 0.8)
	var aim := "on the fire control solution" if sol != null else "bearing %s" % U.p3(base)
	report("Unit%s %s away, %s, on the wire. Seeker enables in %.1f km." % ["s" if used.size() > 1 else "",
		" and ".join(used), aim, (torps[-1] as Homer).enable / 1000.0], "good")
	if sol != null and not sol["in_range"]:
		report("Fire control: she's beyond the Mk 48's reach. It may run dry.", "warn")
	# The launch itself can be heard by anyone close.
	for e in ships:
		if e.alive() and e.kind != "target" and e.pos.distance_to(s.pos) < 5000.0 and randf() < 0.5:
			_new_datum(s.pos, 400.0, e)
			report("Sonar: %s may have heard the launch transient." % e.short, "warn")
			break


func cut_wires() -> void:
	var n := 0
	for tp in torps:
		var h := tp as Homer
		if h.wire:
			h.wire = false
			n += 1
	report("Fire control: wires cut on %d unit%s. They're on their own." % [n, "" if n == 1 else "s"] if n > 0 else "Fire control: no units on the wire.")


func launch_decoy() -> void:
	var s := sub
	if s.surfaced():
		report("We can't launch decoys on the surface.", "warn")
		return
	if s.decoys <= 0:
		report("Countermeasures: no decoys left!", "warn", "nodecoys", 10.0)
		return
	if t < decoy_cool:
		return
	decoy_cool = t + 3.0
	s.decoys -= 1
	var d := Decoy.new()
	d.id = _new_id()
	d.pos = s.pos - U.dirv(s.hdg) * float(nat["sub"]["len"]) * 0.6
	d.depth = s.depth
	decoys.append(d)
	sound("launch", 0.4)
	report("Countermeasures: decoy away. %d left." % s.decoys, "info")
	emit({"type": "decoy", "pos": Vector3(d.pos.x, -d.depth, d.pos.y)})


func _update_torps(dt: float) -> void:
	_update_mk48(dt)
	_update_rockets(dt)
	_update_enemy_torps(dt)
	_update_missiles(dt)
	_update_buoys(dt)
	_update_launch(dt)
	var keep: Array[Decoy] = []
	for d in decoys:
		d.life -= dt
		if d.life > 0.0:
			keep.append(d)
	decoys = keep


func _update_mk48(dt: float) -> void:
	var keep: Array[Torpedo] = []
	var s := sub
	for t0 in torps:
		var tp := t0 as Homer
		var step: float = tp.kn * U.KN * dt
		# The wires part if we go too fast, too far or are hit.
		if tp.wire and (absf(s.spd) > WIRE_KN or tp.run > WIRE_LEN or s.hull <= 0.0):
			tp.wire = false
			report("Fire control: wire's parted on unit %d." % tp.unit, "warn")
		match tp.state:
			"run":
				if tp.wire and lock != null and lock.id == tp.aim_id and t > tp.next_guide:
					tp.next_guide = t + 2.0
					var est := _estimate()
					var it := _intercept(tp.pos, tp.kn * U.KN, est[0], est[1])
					if not it.is_empty():
						tp.course = it["hdg"]
						# Enable the seeker about 2.5 km short of where she'll be.
						tp.enable = tp.run + maxf(0.0, float(it["run"]) - 2500.0)
				if tp.run >= tp.enable:
					tp.state = "search"
					tp.spin = 1.0 if randf() < 0.5 else -1.0
					if not tp.told.has("enable"):
						tp.told["enable"] = true
						report("Fire control: unit %d has enabled. Searching." % tp.unit)
			"search":
				# Straight on for a while (she should be ahead), then circle.
				tp.course = tp.hdg if tp.run - tp.enable < 1500.0 else U.wrap360(tp.hdg + tp.spin * 7.0 * dt * 3.0)
			"home":
				var sh := _ship_by_id(tp.aim_id)
				if sh == null or not sh.alive() or tp.pos.distance_to(sh.pos) > tp.seeker * 1.4 \
						or absf(U.adiff(U.brg(tp.pos, sh.pos), tp.hdg)) > 80.0:
					tp.state = "search"
					report("Fire control: unit %d has lost contact. Re-attacking." % tp.unit, "warn", "relost%d" % tp.unit, 20.0)
				else:
					var lead := sh.pos + U.dirv(sh.hdg) * sh.spd * U.KN * (tp.pos.distance_to(sh.pos) / (tp.kn * U.KN)) * 0.6
					tp.course = U.brg(tp.pos, lead)
					if sh.depth > 3.0:
						tp.depth = move_toward(tp.depth, sh.depth, 10.0 * dt)
			"decoy":
				tp.course = U.brg(tp.pos, tp.fake)
				if tp.pos.distance_to(tp.fake) < 40.0:
					tp.state = "search"
					report("Fire control: unit %d was pulled off by a decoy. Searching again." % tp.unit, "warn")
		# Seeker: look for the biggest echo in the cone.
		if tp.state == "search" or (tp.state == "home" and randf() < dt * 0.5):
			var best: Ship = null
			var score := -1.0
			for sh in ships:
				if not sh.alive() or sh.sinking > 0.0:
					continue
				var r := tp.pos.distance_to(sh.pos)
				if r > tp.seeker or absf(U.adiff(U.brg(tp.pos, sh.pos), tp.hdg)) > tp.cone:
					continue
				if sh.depth > 3.0 and absf(sh.depth - tp.depth) > 220.0:
					continue
				var sc := sh.length / maxf(r, 50.0) * (1.4 if sh.id == tp.aim_id else 1.0)
				if sc > score:
					score = sc
					best = sh
			if best != null and (tp.state != "home" or best.id != tp.aim_id):
				tp.state = "home"
				tp.aim_id = best.id
				if not tp.told.has("acq%d" % best.id):
					tp.told["acq%d" % best.id] = true
					report("Fire control: unit %d has acquired %s! Homing." % [tp.unit, best.short], "good")
				# Their own torpedo countermeasures.
				if time_alarmed() and randf() < 0.25:
					tp.state = "decoy"
					tp.fake = best.pos + U.dirv(best.hdg + 180.0 + randf_range(-60, 60)) * randf_range(300, 600)
		var rate := tp.turn * dt
		tp.hdg = U.wrap360(tp.hdg + clampf(U.adiff(tp.course, tp.hdg), -rate, rate))
		tp.pos += U.dirv(tp.hdg) * step
		tp.run += step
		if tp.pos.distance_to(tp.trail[-1]) > 60.0:
			tp.trail.append(tp.pos)
		var hit: Ship = null
		for sh in ships:
			if sh.alive() and _inside(sh, tp.pos) and (sh.depth < 3.0 or absf(tp.depth - sh.depth) < 15.0):
				hit = sh
				break
		if hit != null and tp.run > ARM_DIST:
			_mk48_hit(tp, hit)
			continue
		if tp.run > tp.rng:
			if result == "":
				report("Fire control: unit %d is out of fuel. Shutting down." % tp.unit, "warn")
			continue
		# Anyone close hears a torpedo coming: from about 3 km while it runs
		# out quietly, twice that once it starts pinging.
		var heard_at := 3200.0 if tp.state == "run" else 6500.0
		for e in ships:
			if e.alive() and tp.pos.distance_to(e.pos) < heard_at and not tp.told.has("heard"):
				tp.told["heard"] = true
				_torpedo_alarm(tp)
		keep.append(tp)
	torps = keep


func _ship_by_id(id: int) -> Ship:
	for sh in ships:
		if sh.id == id:
			return sh
	return null


func time_alarmed() -> bool:
	return t - alarm_t < 900.0


## A torpedo heard in the water: the group turns away, speeds up and works
## out roughly where it came from.
func _torpedo_alarm(tp: Homer) -> void:
	if not time_alarmed():
		report("Sonar: they've heard our fish. The whole group's increasing speed and turning away!", "alarm")
	alarm_t = t
	alert = true
	# The launch point lies back along its track; fire control on their side
	# can only guess how far.
	var back: Vector2 = tp.trail[0] if tp.trail.size() > 0 else sub.pos
	_new_datum(back + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 1500.0, 2500.0, null)


## The group's estimate of where you are; `err` is how far off it may be.
func _new_datum(p: Vector2, err: float, by: Ship) -> void:
	if err < datum_err or t - datum_t > 120.0:
		datum = p + Vector2(U.gauss(), U.gauss()) * err * 0.5
		datum_err = err
	datum_t = t
	alarm_t = t
	alert = true
	# Escorts close enough go hunting; the rest keep the screen round her.
	for e in ships:
		if (e.kind != "target" or e.type == "ssn") and e.alive() and e.state in ["screen", "patrol"] \
				and e.pos.distance_to(datum) < HUNT_RADIUS:
			e.state = "hunt"
			e.search_until = t + 600.0


func _mk48_hit(tp: Homer, sh: Ship) -> void:
	if sh.depth > 3.0:
		_sub_hit(tp, sh)
		return
	var r := sub.pos.distance_to(sh.pos)
	var spot := hull_spot(sh, tp.pos)
	sh.hits_taken += 1
	hits += 1
	emit({"type": "boom", "pos": Vector3(tp.pos.x, 0.0, tp.pos.y), "size": sh.length / 14.0, "kind": "torpedo", "ship": sh.id})
	sound("torp_hit", clampf(1.3 - r / 15000.0, 0.25, 1.0))
	tc = 1
	sh.hull.torpedo(spot.x, int(spot.y), float(nat["torp"].get("kg", 295.0)) / 300.0, true)
	sh.struct = sh.max_struct * sh.hull.health()
	var blew := sh.hull.mode == "explode"
	_hull_news(sh)
	if not blew and sh.struct > 0.0:
		var left := sh.hull.hits_left()
		report("Unit %d: detonation under %s, %s! Estimate %d more hit%s to sink her." % [tp.unit, sh.short, where(spot.x), left,
			"s" if left > 1 else ""], "good")
	elif sh.struct <= 0.0 and not blew and sh.kind == "target" and result == "":
		_ship_sunk(sh, "torpedo")
	_torpedo_alarm(tp)


# --------------------------------------------------------------- missiles
## Weapons Q steps through.
func weapons() -> Array:
	var out := ["mk48"]
	if harpoons > 0:
		out.append("harpoon")
	if vls > 0:
		out.append("tomahawk")
	if trident > 0:
		out.append("trident")
	return out


func weapon_name(w := "") -> String:
	var k := weapon if w == "" else w
	return "Mk 48" if k == "mk48" else String(GameData.MISSILES[k]["name"])


## Rounds left of a weapon.
func stock(w := "") -> int:
	match weapon if w == "" else w:
		"harpoon":
			return harpoons
		"tomahawk":
			return vls
		"trident":
			return trident
	return sub.spares + sub.tubes.count(0.0)


func weapon_line() -> String:
	var out := []
	for k in weapons():
		var short: String = {"mk48": "MK 48", "harpoon": "HARPOON", "tomahawk": "TLAM", "trident": "TRIDENT"}[k]
		var txt := "%s x%d" % [short, stock(k)]
		out.append("[%s]" % txt if k == weapon else txt)
	out.append("DECOYS %d" % sub.decoys)
	return "  ".join(out)


func cycle_weapon() -> void:
	var ws := weapons()
	weapon = ws[(ws.find(weapon) + 1) % ws.size()]
	if weapon == "mk48":
		report("Weapons: Mk 48s. Space fires one, X two.")
	elif weapon == "trident":
		report("Weapons: the Trident test round. In the launch box, at %d to %d metres and a hover, X starts the launch." % [
			int(LAUNCH_DEPTH.x), int(LAUNCH_DEPTH.y)])
	else:
		salvo = clampi(salvo, 1, maxi(stock(), 1))
		report("Weapons: %ss, %d left. X fires a salvo of %d; [ and ] change it." % [weapon_name(), stock(), salvo])


func salvo_step(d: int) -> void:
	if weapon in ["mk48", "trident"]:
		report("Weapons: press Q to pick a missile first.")
		return
	var i := 0
	while i < SALVOS.size() - 1 and int(SALVOS[i]) < salvo:
		i += 1
	i = clampi(i + d, 0, SALVOS.size() - 1)
	salvo = mini(int(SALVOS[i]), maxi(stock(), 1))
	report("Weapons: salvo of %d %s%s." % [salvo, weapon_name(), "s" if salvo > 1 else ""])


## Is the boat taking the satellite link (mast up at periscope depth)?
func linked() -> bool:
	var s := sub
	return s.surfaced() or (s.scope_up and s.depth <= PERI_MAX and s.sys["periscope"] > 25.0)


## Offboard contact reports for the whole group, every few minutes, if
## we're up to take them.
func _link() -> void:
	if not linked() or (link_t > -900.0 and t - link_t < LINK_EVERY):
		return
	link_t = t
	var n := 0
	for sh in ships:
		if not sh.alive() or sh.depth > 3.0:
			continue
		var vel := U.dirv(sh.hdg) * sh.spd * U.KN
		var age := randf_range(20.0, 90.0)
		var err := 600.0 if sh.kind == "target" else 1000.0
		oth[sh.id] = {"pos": sh.pos - vel * age + Vector2(U.gauss(), U.gauss()) * err * 0.5, "vel": vel, "t": t - age, "err": err}
		n += 1
	var tg := target
	if tg.depth > 3.0:
		# Satellites and patrol planes don't see submarines.
		if n > 0:
			report("Radio: link update. %d surface ship%s plotted; nothing on the submarines." % [n, "" if n == 1 else "s"])
		return
	if not tg.alive():
		return
	var est := aim_estimate(tg)
	var p: Vector2 = est[0]
	report("Radio: link update. %s bearing %s, %.0f km, course %s, %d knots, %d ships with her." % [tg.name,
		U.p3(U.brg(sub.pos, p)), sub.pos.distance_to(p) / 1000.0, U.p3(tg.hdg), int(round(tg.spd)), n - 1], "good")
	if lock == null or not lock.alive():
		lock = tg
		lock_obs = 0.0
		lock_err = Vector2(U.gauss(), U.gauss())
		lock_rng_err = U.gauss()


## Best guess of where a ship is now: our own fire control solution if we
## are tracking her, or the last link report run forward, whichever is
## tighter. [position, velocity, error radius], or [] if we know nothing.
func aim_estimate(sh: Ship) -> Array:
	var best: Array = []
	if sh == null:
		return best
	if lock == sh:
		best = fire_control_estimate()
	if oth.has(sh.id):
		var o: Dictionary = oth[sh.id]
		var age := t - float(o["t"])
		var err := float(o["err"]) + age * sh.max_kn * U.KN * 0.15
		if best.is_empty() or err < float(best[2]):
			best = [(o["pos"] as Vector2) + (o["vel"] as Vector2) * age, o["vel"], err]
	return best


## Order a salvo. Missiles leave one every few seconds and fly doglegs so
## they all arrive together, which is what swamps a ship's defences.
func fire_missiles(kind: String, n: int) -> void:
	if result != "" or demo:
		return
	var s := sub
	var info: Dictionary = GameData.MISSILES[kind]
	var nm := String(info["name"])
	if s.depth > MISSILE_DEPTH:
		report("Too deep to launch missiles. Come above %d metres." % int(MISSILE_DEPTH), "warn")
		return
	if absf(s.spd) > MISSILE_KN:
		report("Too fast to launch. Slow below %d knots." % int(MISSILE_KN), "warn")
		return
	if not launch_queue.is_empty():
		report("Weapons: still launching, %d to go." % launch_queue.size(), "warn")
		return
	if s.hull <= 25.0 or (kind == "harpoon" and s.sys["tubes"] <= 25.0):
		report("Weapons: launch systems damaged. We can't fire.", "warn")
		return
	var tg := lock
	var est: Array = aim_estimate(tg) if tg != null and tg.alive() else []
	if est.is_empty():
		report("Fire control: no target for the missiles. Track a ship (L) or take the link.", "warn")
		return
	var left := stock(kind)
	if kind == "harpoon":
		left = mini(left, s.tubes.count(0.0))
	n = mini(n, left)
	if n <= 0:
		report("Weapons: no %s ready." % nm if kind == "harpoon" and harpoons > 0 else "Weapons: no %ss left." % nm, "warn")
		return
	var speed := float(info["kn"]) * U.KN
	var p: Vector2 = est[0]
	var v: Vector2 = est[1]
	var last := (n - 1) * LAUNCH_EVERY
	var tof := 0.0
	for k in 3:
		tof = s.pos.distance_to(p + v * (last + tof)) / speed + 20.0
	var arrive := t + last + tof
	var aim := p + v * (arrive - t)
	var d := s.pos.distance_to(aim)
	if d > float(info["range"]) * 0.95:
		report("Fire control: %s is beyond the %s's reach." % [tg.short, nm], "warn")
		return
	if d < 5000.0:
		report("Fire control: she's too close for missiles. Use the Mk 48s.", "warn")
		return
	if kind == "harpoon":
		harpoons -= n
		var fired_tubes := 0
		for i in s.tubes.size():
			if fired_tubes < n and s.tubes[i] == 0.0:
				s.tubes[i] = RELOAD + i * LAUNCH_EVERY
				fired_tubes += 1
	else:
		vls -= n
	var sid := salvos.size() + 1
	salvos[sid] = {"kind": kind, "n": n, "left": n, "down": 0, "hits": {}, "lost": 0}
	for i in n:
		launch_queue.append({"kind": kind, "at": t + i * LAUNCH_EVERY, "aim": aim, "aim_id": tg.id, "arrive": arrive,
			"side": 1.0 if i % 2 == 0 else -1.0, "salvo": sid})
	report("Weapons: salvo of %d %s%s at %s, %.0f km. Time on target %s." % [n, nm, "s" if n > 1 else "", tg.short,
		d / 1000.0, U.clock(arrive - t).substr(3)], "good")
	if float(est[2]) > float(info["seeker"]) * 0.6:
		report("Fire control: her position is only good to %.0f km. The seekers may not find her." % (float(est[2]) / 1000.0), "warn")


func _launch_one(q: Dictionary) -> void:
	var s := sub
	var kind: String = q["kind"]
	var info: Dictionary = GameData.MISSILES[kind]
	var m := Missile.new()
	m.id = _new_id()
	m_units += 1
	m.unit = m_units
	m.salvo = int(q["salvo"])
	m.kind = kind
	var L: float = nat["sub"]["len"]
	# Tubes in the bow; the cells just abaft the bow (Virginia) or along the hull (Ohio).
	var along := 0.45 if kind == "harpoon" else (0.32 if L < 140.0 else randf_range(-0.05, 0.2))
	m.pos = s.pos + U.dirv(s.hdg) * L * along
	m.origin = m.pos
	m.hdg = U.brg(m.pos, q["aim"])
	m.top = float(info["kn"]) * U.KN
	m.spd = 25.0
	m.cruise_alt = info["cruise"]
	m.aim = q["aim"]
	m.aim_id = int(q["aim_id"])
	m.arrive = q["arrive"]
	m.seeker = info["seeker"]
	m.cone = info["cone"]
	m.reach = info["range"]
	m.kg = info["kg"]
	m.link = info["link"]
	m.t0 = t
	# A dogleg out to one side, as long as the time left needs.
	var d := m.pos.distance_to(m.aim)
	var need := m.top * maxf(float(q["arrive"]) - t - BOOST_T - 12.0, 0.0)
	if need > d * 1.02 + 800.0:
		var h := sqrt(maxf(need * need - d * d, 0.0)) * 0.5
		m.way = (m.pos + m.aim) * 0.5 + U.dirv(U.brg(m.pos, m.aim) + 90.0 * float(q["side"])) * h
		m.has_way = true
	m.trail = [m.pos]
	missiles.append(m)
	m_fired += 1
	emit({"type": "mlaunch", "pos": Vector3(m.pos.x, 0.0, m.pos.y), "kind": kind})
	sound("launch", 0.6)


func _update_missiles(dt: float) -> void:
	while not launch_queue.is_empty() and float(launch_queue[0]["at"]) <= t:
		var s := sub
		if s.depth > MISSILE_DEPTH + 5.0 or absf(s.spd) > MISSILE_KN + 3.0 or s.hull <= 25.0:
			var held := launch_queue.size()
			for q in launch_queue:
				if q["kind"] == "harpoon":
					harpoons += 1
				else:
					vls += 1
				salvos[int(q["salvo"])]["n"] = int(salvos[int(q["salvo"])]["n"]) - 1
				salvos[int(q["salvo"])]["left"] = int(salvos[int(q["salvo"])]["left"]) - 1
			launch_queue.clear()
			report("Weapons: launch aborted, %d missiles held in the cells." % held, "warn")
			break
		var q: Dictionary = launch_queue.pop_front()
		_launch_one(q)
		if launch_queue.is_empty():
			var sv: Dictionary = salvos[int(q["salvo"])]
			report("Weapons: %d %s%s away." % [int(sv["n"]), weapon_name(q["kind"]), "s" if int(sv["n"]) > 1 else ""], "good")
	_link()
	_mindex.clear()
	for m in missiles:
		if not m.dead:
			_mindex[m.id] = m
	var keep: Array[Missile] = []
	for m in missiles:
		var alive: bool = _fly_sam(m, dt) if m.owner >= 0 else (_fly_trident(m, dt) if m.kind == "trident" else _fly_missile(m, dt))
		if alive:
			keep.append(m)
	missiles = keep
	_detect_missiles()
	_air_defence(dt)


## Where a missile is heading: the ship it is homing on, or its aim point.
func _goal(m: Missile) -> Vector2:
	if m.state == "home":
		var sh := _ship_by_id(m.aim_id)
		if sh != null:
			return sh.pos
	return m.aim


func _missile_by_id(id: int) -> Missile:
	var m: Missile = _mindex.get(id)
	return m if m != null and not m.dead else null


## One of your missiles: climbs out on its booster, settles down to skim
## the sea, runs out to its dogleg and on to the aim point, switches on its
## seeker and homes on the best echo. Returns false when it is gone.
func _fly_missile(m: Missile, dt: float) -> bool:
	if m.dead:
		return false
	var top_alt := 150.0 if m.kind == "tomahawk" else 60.0
	match m.state:
		"boost":
			m.alt = move_toward(m.alt, top_alt, top_alt / BOOST_T * 1.4 * dt)
			m.spd = move_toward(m.spd, m.top * 0.7, 30.0 * dt)
			if t - m.t0 > BOOST_T:
				m.state = "dive"
		"dive":
			m.alt = move_toward(m.alt, m.cruise_alt, 14.0 * dt)
			m.spd = move_toward(m.spd, m.top, 12.0 * dt)
			_steer_missile(m, dt)
			if absf(m.alt - m.cruise_alt) < 0.5:
				m.state = "cruise"
		"cruise":
			_steer_missile(m, dt)
			# Seeker on once it is round the last turn and inside its reach.
			if not m.has_way and m.pos.distance_to(m.aim) < m.seeker * 0.85 \
					and absf(U.adiff(U.brg(m.pos, m.aim), m.hdg)) < 15.0:
				m.state = "seek"
		"seek":
			_seek(m)
			if m.state == "seek":
				# Nothing yet: on to the aim point, then straight on past it.
				if m.pos.distance_to(m.aim) > 600.0 and absf(U.adiff(U.brg(m.pos, m.aim), m.hdg)) < 90.0:
					m.hdg = U.wrap360(m.hdg + clampf(U.adiff(U.brg(m.pos, m.aim), m.hdg), -6.0 * dt, 6.0 * dt))
		"home":
			var sh := _ship_by_id(m.aim_id)
			if sh == null or not sh.alive() or sh.sinking > 0.3:
				m.state = "seek"
			else:
				var r := m.pos.distance_to(sh.pos)
				var lead := sh.pos + U.dirv(sh.hdg) * sh.spd * U.KN * (r / maxf(m.spd, 1.0))
				m.hdg = U.wrap360(m.hdg + clampf(U.adiff(U.brg(m.pos, lead), m.hdg), -15.0 * dt, 15.0 * dt))
				# Chaff, once their radars have seen it coming.
				if m.seen and not m.chaffed and r < 7000.0:
					m.chaffed = true
					var ad := GameData.air_defence(sh.layout)
					# The Tomahawk's seeker sees through chaff better.
					if randf() < float(ad.get("chaff", 0.1)) * (0.5 if m.link else 1.0):
						m.state = "decoyed"
						m.fake = sh.pos + U.dirv(randf_range(0.0, 360.0)) * randf_range(350.0, 700.0)
				if r < 2500.0:
					m.alt = move_toward(m.alt, 4.0, 4.0 * dt)
		"decoyed":
			m.hdg = U.wrap360(m.hdg + clampf(U.adiff(U.brg(m.pos, m.fake), m.hdg), -15.0 * dt, 15.0 * dt))
			if m.pos.distance_to(m.fake) < 60.0:
				m.state = "seek"
				m.cone = 20.0
	var prev := m.pos
	var step := m.spd * dt
	m.pos += U.dirv(m.hdg) * step
	m.flown += step
	if m.pos.distance_to(m.trail[-1]) > 1500.0:
		m.trail.append(m.pos)
	# Into a ship? Check along the step, low enough to hit her.
	if m.alt < 30.0 and m.state in ["home", "seek", "decoyed"]:
		for sh in ships:
			if not sh.alive() or m.pos.distance_to(sh.pos) > sh.length * 0.6 + step:
				continue
			for k in 4:
				var p := prev.lerp(m.pos, float(k + 1) / 4.0)
				if _inside(sh, p):
					_missile_hit(m, sh, p)
					return false
	if m.flown > m.reach or (m.state == "seek" and m.pos.distance_to(m.aim) > m.seeker * 1.2
			and absf(U.adiff(U.brg(m.pos, m.aim), m.hdg)) > 90.0):
		_missile_lost(m)
		return false
	return true


func _steer_missile(m: Missile, dt: float) -> void:
	if m.has_way and m.pos.distance_to(m.way) < 2000.0:
		m.has_way = false
	# Tomahawks take a fresher aim point over the link while we're up.
	if m.link and t >= m.next_aim and linked():
		m.next_aim = t + 20.0
		var est := aim_estimate(_ship_by_id(m.aim_id))
		if not est.is_empty():
			var path := (m.pos.distance_to(m.way) + m.way.distance_to(m.aim)) if m.has_way else m.pos.distance_to(m.aim)
			m.aim = (est[0] as Vector2) + (est[1] as Vector2) * (path / maxf(m.top, 1.0))
	var dest := m.way if m.has_way else m.aim
	m.hdg = U.wrap360(m.hdg + clampf(U.adiff(U.brg(m.pos, dest), m.hdg), -5.0 * dt, 5.0 * dt))


## The seeker looks ahead for the biggest echo near where she should be.
## A Harpoon takes the best it finds. A Tomahawk knows which ship it was
## sent for and holds out for her until it reaches the aim point.
func _seek(m: Missile) -> void:
	var best: Ship = null
	var score := 0.0
	var wanted: Ship = null
	for sh in ships:
		if not sh.alive() or sh.sinking > 0.2 or sh.depth > 3.0:
			continue
		var r := m.pos.distance_to(sh.pos)
		# The Tomahawk's passive seeker picks her radars up from any direction.
		if sh.id == m.aim_id and m.link and r <= m.seeker:
			wanted = sh
		if r > m.seeker or absf(U.adiff(U.brg(m.pos, sh.pos), m.hdg)) > m.cone:
			continue
		var sc := sh.length / maxf(r, 200.0) * clampf(1.6 - sh.pos.distance_to(m.aim) / m.seeker, 0.2, 1.6)
		if sh.id == m.aim_id:
			sc *= 1.5
		if sc > score:
			score = sc
			best = sh
	if m.link and wanted != null and not m.chaffed:
		best = wanted
	elif m.link and m.pos.distance_to(m.aim) > 4000.0 and not m.chaffed:
		best = null
	if best != null:
		m.state = "home"
		m.aim_id = best.id


func _tally(m: Missile, what: String, sh: Ship = null) -> void:
	if not salvos.has(m.salvo):
		return
	var sv: Dictionary = salvos[m.salvo]
	sv["left"] = int(sv["left"]) - 1
	if what == "hit":
		sv["hits"][sh.short] = int(sv["hits"].get(sh.short, 0)) + 1
	elif what == "down":
		sv["down"] = int(sv["down"]) + 1
	else:
		sv["lost"] = int(sv["lost"]) + 1
	if int(sv["left"]) <= 0:
		var hits := 0
		var parts := []
		for k in sv["hits"]:
			hits += int(sv["hits"][k])
			parts.append("%s %d" % [k, int(sv["hits"][k])])
		var txt := "Link: salvo over. %d %s%s: %d shot down, %d lost or decoyed, %d hit%s" % [int(sv["n"]), weapon_name(sv["kind"]),
			"s" if int(sv["n"]) > 1 else "", int(sv["down"]), int(sv["lost"]), hits, "s" if hits != 1 else ""]
		report(txt + (" (%s)." % ", ".join(parts) if hits > 0 else "."), "good" if hits > 0 else "warn")


func _missile_lost(m: Missile) -> void:
	m.dead = true
	_tally(m, "lost")


func _missile_hit(m: Missile, sh: Ship, at: Vector2) -> void:
	m.dead = true
	var spot := hull_spot(sh, at)
	var power := m.kg / 450.0
	sh.hits_taken += 1
	m_hits += 1
	emit({"type": "boom", "pos": Vector3(at.x, 6.0, at.y), "size": 3.0 + 4.0 * power, "kind": "missile", "ship": sh.id})
	var r := sub.pos.distance_to(sh.pos)
	if r < 25000.0:
		sound("torp_hit", clampf(0.8 - r / 30000.0, 0.1, 0.6))
	sh.hull.missile(spot.x, int(spot.y), power)
	sh.struct = sh.max_struct * sh.hull.health()
	_tally(m, "hit", sh)
	report("Link: %s %d hit %s %s!" % [weapon_name(m.kind), m.unit, sh.short, where(spot.x)], "good", "mhit%d" % sh.id, 5.0)
	_hull_news(sh)
	alarm_t = t
	alert = true


func _shot_down(m: Missile) -> void:
	if m.dead:
		return
	m.dead = true
	m_down += 1
	emit({"type": "boom", "pos": Vector3(m.pos.x, m.alt, m.pos.y), "size": 2.2, "kind": "air"})
	_tally(m, "down")
	report("Link: missiles being shot down. %d so far." % m_down, "warn", "mdown", 8.0)


## Their radars pick missiles up once they are over the horizon: a long way
## off while they climb out of the sea, about 30 km once they skim it.
## Helicopters aloft see farther. Seen climbing out, they know roughly where
## the boat fired from.
func _detect_missiles() -> void:
	for m in missiles:
		if m.owner >= 0 or m.seen or m.dead:
			continue
		var by: Ship = null
		var seen := false
		for sh in ships:
			if not sh.alive() or sh.depth > 3.0:
				continue
			var mast := float(GameData.air_defence(sh.layout).get("mast", 15.0))
			if m.pos.distance_to(sh.pos) < minf(4120.0 * (sqrt(mast) + sqrt(maxf(m.alt, 1.0))), 150000.0):
				seen = true
				by = sh
				break
		if not seen:
			for p in planes:
				if not p.dead and p.alt > 60.0 and m.pos.distance_to(p.pos) < minf(4120.0 * (sqrt(p.alt) + sqrt(maxf(m.alt, 1.0))), 45000.0):
					seen = true
					break
		if not seen:
			continue
		m.seen = true
		if t - air_alert > 300.0:
			report("ESM: their fire-control radars have come up. They've seen the missiles.", "warn")
		air_alert = t
		alarm_t = t
		alert = true
		if m.state in ["boost", "dive"] and m.flown < 4000.0:
			var r := m.origin.distance_to(by.pos) if by != null else 30000.0
			_new_datum(m.origin, 300.0 + r * 0.03, by)
			report("ESM: they saw the launch. Expect company.", "alarm", "launchseen", 90.0)


## Each ship fires its missile layers at the incoming missiles it can reach,
## the most urgent first, no more than its fire channels allow and never more
## than two at one missile at a time; its close-in guns take what gets
## through.
func _air_defence(dt: float) -> void:
	if t - air_alert > 600.0:
		return
	for sh in ships:
		if not sh.alive() or not adef.has(sh.id):
			continue
		var st: Dictionary = adef[sh.id]
		var ad := GameData.air_defence(sh.layout)
		var layers: Array = ad["sams"]
		for li in layers.size():
			var L: Dictionary = layers[li]
			if int(st["stock"][li]) <= 0 or int(st["busy"][li]) >= int(L["ch"]) or t < float(st["next"][li]):
				continue
			var best: Missile = null
			var urgent := 1e12
			for m in missiles:
				if m.owner >= 0 or m.dead or not m.seen or m.engaged >= 2 or m.state == "boost":
					continue
				var r := m.pos.distance_to(sh.pos)
				if r > float(L["rng"]) or r < float(L["min"]):
					continue
				var u := m.pos.distance_to(_goal(m))
				if u < urgent:
					urgent = u
					best = m
			if best != null:
				_fire_sam(sh, li, L, best)
				st["next"][li] = t + 2.5
		var mounts := int(ad.get("ciws", 0))
		if mounts > 0:
			_ciws(sh, st, mounts, dt)


func _fire_sam(sh: Ship, li: int, L: Dictionary, m: Missile) -> void:
	var st: Dictionary = adef[sh.id]
	var sam := Missile.new()
	sam.id = _new_id()
	sam.kind = "sam"
	sam.owner = sh.id
	sam.layer = li
	sam.tgt = m.id
	sam.pk = L["pk"]
	sam.pos = sh.pos + U.dirv(sh.hdg) * sh.length * randf_range(-0.2, 0.2)
	sam.alt = 12.0
	sam.hdg = U.brg(sh.pos, m.pos)
	sam.spd = 150.0
	sam.top = L["v"]
	sam.state = "fly"
	sam.reach = float(L["rng"]) * 1.4
	sam.t0 = t
	missiles.append(sam)
	st["stock"][li] = int(st["stock"][li]) - 1
	st["busy"][li] = int(st["busy"][li]) + 1
	m.engaged += 1
	emit({"type": "sam", "pos": Vector3(sam.pos.x, 10.0, sam.pos.y), "ship": sh.id})


func _sam_done(sam: Missile) -> void:
	sam.dead = true
	if adef.has(sam.owner):
		var st: Dictionary = adef[sam.owner]
		st["busy"][sam.layer] = maxi(0, int(st["busy"][sam.layer]) - 1)
	var m := _missile_by_id(sam.tgt)
	if m != null:
		m.engaged = maxi(0, m.engaged - 1)


## One of their missiles: out of its cell, lofts and leads the target, and
## either kills it or misses when they meet.
func _fly_sam(sam: Missile, dt: float) -> bool:
	if sam.dead:
		return false
	var m := _missile_by_id(sam.tgt)
	if m == null:
		_sam_done(sam)
		return false
	sam.spd = move_toward(sam.spd, sam.top, 500.0 * dt)
	var it := _intercept(sam.pos, sam.spd, m.pos, U.dirv(m.hdg) * m.spd)
	var want: float = it["hdg"] if not it.is_empty() else U.brg(sam.pos, m.pos)
	if t - sam.t0 > 1.0:
		sam.hdg = U.wrap360(sam.hdg + clampf(U.adiff(want, sam.hdg), -45.0 * dt, 45.0 * dt))
	var r := sam.pos.distance_to(m.pos)
	var want_alt := m.alt if r < 4000.0 else maxf(m.alt, minf(r * 0.06, 1500.0))
	sam.alt = move_toward(sam.alt, want_alt, (300.0 if t - sam.t0 > 1.0 else 120.0) * dt)
	var step := sam.spd * dt
	sam.pos += U.dirv(sam.hdg) * step
	sam.flown += step
	if sam.pos.distance_to(m.pos) < step + m.spd * dt + 40.0 and absf(sam.alt - m.alt) < 80.0:
		if randf() < sam.pk:
			_shot_down(m)
		_sam_done(sam)
		return false
	if sam.flown > sam.reach:
		_sam_done(sam)
		return false
	return true


## Close-in guns: each mount holds fire on one missile in reach, the one
## coming at her first, and chews at it until it dies or hits.
func _ciws(sh: Ship, st: Dictionary, mounts: int, dt: float) -> void:
	var used := 0
	for m in missiles:
		if used >= mounts:
			break
		if m.owner >= 0 or m.dead or not m.seen or m.kind == "trident":
			continue
		var r := m.pos.distance_to(sh.pos)
		if r > 3000.0:
			continue
		var at_her := m.state == "home" and m.aim_id == sh.id
		if not at_her and r > 1500.0:
			continue
		used += 1
		if t >= float(st["fx"]):
			st["fx"] = t + 0.3
			emit({"type": "ciws", "from": Vector3(sh.pos.x, 16.0, sh.pos.y), "to": Vector3(m.pos.x, m.alt, m.pos.y)})
		if randf() < 1.0 - exp(-(0.06 if at_her else 0.03) * dt):
			_shot_down(m)


## What fire control shows about the missiles.
func missile_status() -> Dictionary:
	var air := 0
	var seen := 0
	for m in missiles:
		if m.owner < 0 and not m.dead:
			air += 1
			if m.seen:
				seen += 1
	var out := {"weapon": weapon, "long": "Mk 48 ADCAP" if weapon == "mk48" else String(GameData.MISSILES[weapon]["long"]),
		"salvo": salvo, "stock": stock(), "air": air, "seen": seen, "queued": launch_queue.size(), "fired": m_fired,
		"hits": m_hits, "down": m_down, "linked": linked(), "link_age": t - link_t if link_t > -900.0 else -1.0,
		"has_missiles": harpoons + vls + trident > 0 or m_fired > 0,
		"strike": harpoons + vls > 0 or m_fired - (1 if launched else 0) > 0}
	if box_r > 0.0:
		out["box_brg"] = U.brg(sub.pos, box)
		out["box_d"] = sub.pos.distance_to(box)
		out["in_box"] = in_box()
		out["launch"] = t - launch_seq if launch_seq >= 0.0 else -1.0
	if weapon in ["harpoon", "tomahawk"] and lock != null and lock.alive():
		var est := aim_estimate(lock)
		if not est.is_empty():
			var d := sub.pos.distance_to(est[0])
			out["aim_err"] = est[2]
			out["aim_rng"] = d
			out["tof"] = d / (float(GameData.MISSILES[weapon]["kn"]) * U.KN) + 20.0
	return out


## Missiles of yours still flying or waiting to go.
func missiles_out() -> int:
	var n := launch_queue.size()
	for m in missiles:
		if m.owner < 0 and not m.dead:
			n += 1
	return n


## A Mk 48 bursting against a submerged submarine: one is usually the end
## of an attack boat; a big missile boat may take two, and blows for the
## surface after the first.
func _sub_hit(tp: Homer, sh: Ship) -> void:
	var r := sub.pos.distance_to(sh.pos)
	sh.hits_taken += 1
	hits += 1
	emit({"type": "boom", "pos": Vector3(tp.pos.x, -sh.depth, tp.pos.y), "size": sh.length / 14.0, "kind": "torpedo_sub", "ship": sh.id})
	sound("torp_hit", clampf(1.3 - r / 15000.0, 0.25, 1.0))
	tc = 1
	if sh.hits_taken >= int(round(float(sh.max_struct) / 100.0)):
		sh.hull.mode = "founder"
		sh.struct = 0.0
		report("Sonar: unit %d hit %s! Breaking-up noises on her bearing... she's going down." % [tp.unit, sh.short], "good")
		_ship_sunk(sh, "founder")
	else:
		sh.struct = sh.max_struct * 0.5
		sh.hull.engines = 0.35
		sh.want_depth = 0.0
		report("Sonar: unit %d hit %s! She's blowing ballast, coming up. Hit her again!" % [tp.unit, sh.short], "good")
	_torpedo_alarm(tp)


# ------------------------------------------------------- their ASW ships
## The screen holds station until something gives you away, then hunts the
## datum: pinging, flying helicopters out, and firing homing torpedoes.
func _escort_ai(e: Ship, dt: float) -> void:
	if e.type in SUBS:
		_sub_ai(e, dt)
		return
	var s := sub
	var tg := target
	var r := e.pos.distance_to(s.pos)
	_listen(e, r, dt)
	match e.state:
		"patrol":
			_patrol(e, dt)
			e.want_spd = 12.0
		"screen":
			var st := _station(tg, e.off)
			var want := U.brg(e.pos, st + U.dirv(tg.hdg) * 800.0)
			_steer(e, want, dt, 3.0)
			var dist := e.pos.distance_to(st)
			e.want_spd = clampf(tg.spd + dist / 600.0, 4.0, e.max_kn) if absf(U.adiff(want, tg.hdg)) < 90.0 else tg.spd * 0.6
		"hunt", "attack":
			if t - datum_t > 420.0:
				e.state = e.home
				report("Sonar: %s is heading back to her %s." % [e.short, "patrol line" if e.home == "patrol" else "station"],
					"info", "back%d" % e.id, 60.0)
				return
			var d := e.pos.distance_to(datum)
			# Close to sonar range of the datum, then slow to listen.
			_steer(e, U.brg(e.pos, datum), dt, 4.0)
			e.want_spd = e.max_kn * 0.85 if d > 7000.0 else 12.0
			e.state = "attack" if t - datum_t < 90.0 and datum_err < 1200.0 else "hunt"
			if e.state == "attack" and t > e.next_dc:
				_shoot_at_datum(e, d)
	if e.state in ["hunt", "attack"] and t > e.run_until:
		# Active sonar while hunting.
		e.run_until = t + 12.0
		_ping(e, r)


## Passive listening on the hull sonar and towed array.
## How loud the boat is, 0..1: slow and deep is near silent, fast and
## shallow carries a long way. Some boats are quieter than others.
func _own_noise() -> float:
	var s := sub
	var noise := 0.14 + 0.86 * pow(clampf((absf(s.spd) - 5.0) / 23.0, 0.0, 1.0), 1.3)
	if s.depth < 30.0 and absf(s.spd) > 12.0:
		noise *= 1.4
	return noise * float(nat.get("quiet", 1.0))


func _listen(e: Ship, r: float, dt: float) -> void:
	var s := sub
	if s.surfaced():
		if r < 20000.0 and randf() < dt * 0.3 and e.depth < 3.0:
			_new_datum(s.pos, 100.0, e)
		return
	var noise := _own_noise()
	var base: float = {"ffg": 26000.0, "ddg": 22000.0, "cg": 22000.0, "ssn": 20000.0, "ssbn": 9000.0}.get(e.type, 15000.0)
	if e.spd > 20.0:
		base *= 0.5
	var layer := 0.55 if s.depth > layer_depth else 1.0
	if e.type == "ffg" or e.type == "ddg":
		layer = maxf(layer, 0.8)   # towed arrays and variable-depth sonar go under the layer
	if e.type in SUBS:
		# A submarine sprinting hears nothing over its own flow noise; across
		# the layer from us it hears half as far.
		if e.spd > 12.0:
			base *= 0.35
		layer = 0.55 if (s.depth > layer_depth) != (e.depth > layer_depth) else 1.0
	var rng := base * noise * layer * (0.5 if e.hull.health() < 0.6 else 1.0)
	if r < rng and randf() < dt * 0.25 * (1.0 - r / rng):
		_new_datum(s.pos, 300.0 + r * 0.06, e)
		if e.heard:
			report("Sonar: %s has changed course toward us. I think she hears us." % e.short, "warn", "heard%d" % e.id, 45.0)


func _ping(e: Ship, r: float) -> void:
	var s := sub
	ping_flash = maxf(ping_flash, clampf(1.0 - r / 12000.0, 0.15, 1.0))
	sound("ping", clampf(1.0 - r / 15000.0, 0.15, 0.9))
	report("Sonar: active sonar, bearing %s. %s is pinging." % [U.p3(U.brg(s.pos, e.pos)), e.short], "warn", "ping", 50.0)
	var rng := 9000.0 * (0.6 if s.depth > layer_depth else 1.0) * (0.8 if e.type == "ffg" else 1.0)
	if r < rng and randf() < 0.55 * (1.0 - r / rng) + 0.2:
		_new_datum(s.pos, 60.0 + r * 0.015, e)
		report("Sonar: we've been painted. %s has us on active." % e.short, "alarm", "painted", 20.0)


## Torpedoes at the datum: from the deck tubes if close, flown out by rocket
## if not.
func _shoot_at_datum(e: Ship, d: float) -> void:
	if t < next_weapon:
		return
	if d < 7000.0 and e.to_drop > 0:
		next_weapon = t + randf_range(45.0, 75.0)
		e.to_drop -= 1
		e.next_dc = t + randf_range(50.0, 80.0)
		_drop_torpedo(e.pos, datum, e.id, "Sonar: torpedo in the water! %s fired from her tubes, bearing %s!" % [e.short,
			U.p3(U.brg(sub.pos, e.pos))])
	elif d < ROCKET_RANGE and int(rocket_stock.get(e.id, 0)) > 0:
		next_weapon = t + randf_range(60.0, 90.0)
		rocket_stock[e.id] = int(rocket_stock[e.id]) - 1
		e.next_dc = t + randf_range(90.0, 140.0)
		var fly := 20.0 + d / 400.0
		rockets.append({"from": e.pos, "to": datum, "t": 0.0, "dur": fly, "id": _new_id(), "owner": e.id})
		emit({"type": "rocket", "from": Vector3(e.pos.x, 10.0, e.pos.y), "to": Vector3(datum.x, 0.0, datum.y), "dur": fly})
		report("Sonar: missile launch from %s! Could be a rocket-thrown torpedo." % e.short, "alarm")
	else:
		e.next_dc = t + 30.0


func _update_rockets(dt: float) -> void:
	var keep := []
	for rk in rockets:
		rk["t"] = float(rk["t"]) + dt
		if float(rk["t"]) >= float(rk["dur"]):
			_drop_torpedo(rk["to"], rk["to"], int(rk["owner"]),
				"Sonar: splash, bearing %s! A torpedo's dropped in the water, it's pinging!" % U.p3(U.brg(sub.pos, rk["to"])))
		else:
			keep.append(rk)
	rockets = keep


## An enemy lightweight torpedo enters the water at `at` and runs toward
## `toward`, then circles searching.
func _drop_torpedo(at: Vector2, toward: Vector2, owner: int, msg: String, splash := true) -> Homer:
	var tp := Homer.new()
	tp.id = _new_id()
	tp.kind = "yu7"
	tp.owner = owner
	if at == toward:
		# Air-dropped: the splash lands near the aim point, not on it.
		at += Vector2(U.gauss(), U.gauss()) * (150.0 + datum_err * 0.35)
		toward = at
	tp.pos = at
	tp.hdg = U.brg(at, toward) if at.distance_to(toward) > 10.0 else randf_range(0, 360)
	tp.course = tp.hdg
	tp.kn = LW_KN
	tp.rng = LW_RANGE
	tp.wake = false
	tp.depth = clampf(sub.depth if datum_err < 600.0 else layer_depth + 20.0, 20.0, 250.0)
	tp.seeker = LW_SEEKER
	tp.cone = 45.0
	tp.turn = 25.0
	tp.enable = at.distance_to(toward) * 0.8
	tp.trail = [tp.pos]
	tp.spin = 1.0 if randf() < 0.5 else -1.0
	etorps.append(tp)
	report(msg, "alarm")
	tc = 1
	if splash:
		sound("splash", 0.4)
		emit({"type": "etorp", "pos": Vector3(at.x, 0.0, at.y)})
	else:
		sound("launch", 0.35)
	return tp


## Their torpedoes: run out, circle and listen, home on the loudest echo
## in the cone (you, or one of your decoys), and burst close aboard.
func _update_enemy_torps(dt: float) -> void:
	var keep: Array[Homer] = []
	var s := sub
	for tp in etorps:
		var step: float = tp.kn * U.KN * dt
		if tp.run >= tp.enable and tp.state == "run":
			tp.state = "search"
		if tp.state == "search" and t >= tp.deaf_until:
			tp.course = U.wrap360(tp.hdg + tp.spin * 9.0 * dt * 3.0)
		# Seeker: the sub or a decoy, whichever answers louder.
		if tp.state != "run" and t >= tp.deaf_until:
			var best_kind := ""
			var best_score := 0.0
			var best_pos := Vector2.ZERO
			var r_sub := tp.pos.distance_to(s.pos)
			var dz_sub := absf(tp.depth - s.depth)
			var across := 0.5 if (s.depth > layer_depth) != (tp.depth > layer_depth) else 1.0
			var gets_sub := tp.state == "home" and tp.fake.distance_to(s.pos) < 200.0 or randf() < dt * 0.6 * across
			if gets_sub and not s.surfaced() and r_sub < tp.seeker and absf(U.adiff(U.brg(tp.pos, s.pos), tp.hdg)) < tp.cone and dz_sub < 80.0:
				var aspect := 0.6 + 0.4 * absf(sin(deg_to_rad(U.adiff(s.hdg, U.brg(tp.pos, s.pos)))))
				best_score = across * aspect / maxf(r_sub, 30.0)
				best_kind = "sub"
				best_pos = s.pos
			for d in decoys:
				var rd := tp.pos.distance_to(d.pos)
				if rd < tp.seeker and absf(U.adiff(U.brg(tp.pos, d.pos), tp.hdg)) < tp.cone:
					var sc := 1.6 / maxf(rd, 30.0)
					if sc > best_score:
						best_score = sc
						best_kind = "decoy%d" % d.id
						best_pos = d.pos
			if best_kind != "":
				if tp.state != "home":
					tp.state = "home"
					if best_kind == "sub" and not tp.told.has("acq"):
						tp.told["acq"] = true
						report("Sonar: the torpedo's shifted to a homing ping! It's got us!", "alarm")
				tp.course = U.brg(tp.pos, best_pos)
				tp.fake = best_pos
				var want_z := s.depth if best_kind == "sub" else tp.depth
				tp.depth = move_toward(tp.depth, want_z, 6.0 * dt)
				if best_kind.begins_with("decoy") and tp.pos.distance_to(best_pos) < 25.0:
					# Through the decoy: deafened for a few seconds, it runs on,
					# then comes round to attack whatever is loudest.
					tp.state = "search"
					tp.course = tp.hdg
					tp.deaf_until = t + 8.0
					report("Sonar: the torpedo went for the decoy!", "good", "decoyed", 15.0)
			elif tp.state == "home":
				tp.state = "search"
				report("Sonar: the torpedo's lost us. It's searching again.", "good", "elost", 20.0)
		var rate := tp.turn * dt
		tp.hdg = U.wrap360(tp.hdg + clampf(U.adiff(tp.course, tp.hdg), -rate, rate))
		tp.pos += U.dirv(tp.hdg) * step
		tp.run += step
		if tp.pos.distance_to(tp.trail[-1]) > 40.0:
			tp.trail.append(tp.pos)
		if tp.pos.distance_to(s.pos) < 14.0 and absf(tp.depth - s.depth) < 12.0 and not s.surfaced():
			_etorp_hit(tp)
			continue
		if tp.run > tp.rng:
			report("Sonar: the torpedo's run out of fuel. It's sinking.", "good", "edry", 10.0)
			continue
		if not tp.told.has("near") and tp.pos.distance_to(s.pos) < 3000.0:
			tp.told["near"] = true
			report("Sonar: torpedo bearing %s, close! Decoys, now!" % U.p3(U.brg(s.pos, tp.pos)), "alarm")
		keep.append(tp)
	etorps = keep


func _etorp_hit(tp: Homer) -> void:
	emit({"type": "boom", "pos": Vector3(tp.pos.x, -sub.depth, tp.pos.y), "size": 3.0, "kind": "torpedo_sub"})
	shake = 1.6
	sound("torp_hit", 1.0)
	tc = 1
	damage_sub(randf_range(36.0, 52.0), "Torpedo hit! Flooding aft! All stations report damage!")


# --------------------------------------------------------- helicopters
## Helicopters patrol ahead of the group; sent to a datum they hover and dip
## their sonar, and drop a torpedo when they are sure.
func _update_planes(dt: float) -> void:
	var s := sub
	for p in planes:
		if p.dead:
			continue
		if p.info.get("kind", "") == "mpa":
			_mpa(p, dt)
			continue
		var spd: float = p.kn * U.KN
		match p.state:
			"patrol":
				p.center = target.pos + U.dirv(target.hdg) * 6000.0
				p.alt = move_toward(p.alt, 150.0, 5.0 * dt)
				var a := atan2(p.pos.x - p.center.x, p.pos.y - p.center.y) + p.orb_dir * 0.03
				var aim := p.center + Vector2(sin(a), cos(a)) * p.orb_r
				_steer(p, U.brg(p.pos, aim), dt, 6.0)
				p.kn = p.info["kn"] * 0.7
				if t - datum_t < 300.0 and datum_err < 3500.0 and p.bombs > 0:
					p.state = "transit"
					p.tgt = datum + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 800.0
					report("Sonar: helicopter heading our way, bearing %s." % U.p3(U.brg(s.pos, p.pos)), "warn", "helo%d" % p.id, 60.0)
			"transit":
				p.kn = p.info["kn"]
				p.alt = move_toward(p.alt, 120.0, 5.0 * dt)
				_steer(p, U.brg(p.pos, p.tgt), dt, 8.0)
				if p.pos.distance_to(p.tgt) < 150.0:
					p.state = "dip"
					p.leave_at = t + randf_range(50.0, 80.0)
					p.detect = 0.0
			"dip":
				p.kn = 0.0
				p.alt = move_toward(p.alt, 18.0, 6.0 * dt)
				if p.alt < 25.0 and t > p.strafe_next:
					p.strafe_next = t + 10.0
					var r := p.pos.distance_to(s.pos)
					var rng := 7000.0 * (0.55 if s.depth > layer_depth else 1.0)
					sound("ping", clampf(1.0 - r / 12000.0, 0.1, 0.8))
					if r < 12000.0:
						report("Sonar: dipping sonar, bearing %s! Helicopter's in the water close." % U.p3(U.brg(s.pos, p.pos)), "warn", "dip%d" % p.id, 50.0)
					if not s.surfaced() and r < rng and randf() < 0.45 * (1.0 - r / rng) + 0.1:
						_new_datum(s.pos, 50.0 + r * 0.02, null)
						p.state = "attack"
						p.tgt = datum
				if t > p.leave_at and p.state == "dip":
					p.state = "transit"
					p.alt = 30.0
					var hop := datum + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 2500.0
					p.tgt = hop if t - datum_t < 300.0 else target.pos
					if t - datum_t >= 300.0:
						p.state = "patrol"
			"attack":
				p.kn = p.info["kn"]
				p.alt = move_toward(p.alt, 90.0, 8.0 * dt)
				_steer(p, U.brg(p.pos, p.tgt), dt, 10.0)
				if p.pos.distance_to(p.tgt) < 120.0 and t >= next_weapon:
					next_weapon = t + randf_range(40.0, 60.0)
					p.bombs -= 1
					_drop_torpedo(p.pos, p.tgt, p.id, "Sonar: splash close aboard, bearing %s! Helicopter's dropped a torpedo!" % U.p3(U.brg(s.pos, p.pos)))
					if p.bombs > 0:
						p.state = "dip"
						p.tgt = p.pos + U.dirv(p.hdg) * 1500.0
						p.state = "transit"
					else:
						p.state = "rearm"
						p.leave_at = t + 420.0
			"rearm":
				var pad := _ship_by_id(int(helo_pad.get(p.id, target.id)))
				if pad == null or not pad.alive():
					pad = target
				p.kn = p.info["kn"]
				_steer(p, U.brg(p.pos, pad.pos), dt, 8.0)
				if p.pos.distance_to(pad.pos) < 300.0:
					p.pos = pad.pos
					p.alt = 15.0
					p.kn = 0.0
					if t > p.leave_at:
						p.bombs = int(p.info["bombs"])
						p.state = "patrol"
		p.roll = lerpf(p.roll, 0.0, dt)
		p.pos += U.dirv(p.hdg) * p.kn * U.KN * dt


# --------------------------------------------------- the patrol aircraft
## The patrol aircraft flies its racetrack laying sonobuoy lines across our
## way. When anything gives us away it comes to the datum, drops a tight
## pattern of buoys round it, and when they have us, a torpedo. Its radar
## sees a raised mast a long way off.
func _mpa(p: Aircraft, dt: float) -> void:
	var s := sub
	match p.state:
		"patrol":
			var route: Array = mpa_route[p.id]
			var i: int = mpa_wp[p.id]
			var goal: Vector2 = route[i]
			p.alt = move_toward(p.alt, 450.0, 10.0 * dt)
			_steer(p, U.brg(p.pos, goal), dt, 3.0)
			if p.pos.distance_to(goal) < 1500.0:
				mpa_wp[p.id] = (i + 1) % route.size()
			# Buoys along the legs that cross our way.
			if i in [1, 3] and _buoy_gap(p.pos) > 2500.0:
				_drop_buoy(p)
			if t - datum_t < 300.0 and datum_err < 5000.0 and p.pos.distance_to(datum) < 80000.0:
				p.state = "localize"
				p.tgt = datum
				p.leave_at = t + 480.0
				p.detect = 0.0
				report("ESM: patrol aircraft radar, bearing %s, getting stronger. It's coming our way." % U.p3(U.brg(s.pos, p.pos)),
					"warn", "mpa%d" % p.id, 120.0)
		"localize":
			p.alt = move_toward(p.alt, 200.0, 10.0 * dt)
			if t - datum_t < 60.0:
				p.tgt = datum
			if p.pos.distance_to(p.tgt) > 2500.0:
				_steer(p, U.brg(p.pos, p.tgt), dt, 4.0)
			else:
				var a := atan2(p.pos.x - p.tgt.x, p.pos.y - p.tgt.y) + 0.08
				_steer(p, U.brg(p.pos, p.tgt + Vector2(sin(a), cos(a)) * 2000.0), dt, 6.0)
				if p.detect < 4.0 and _buoy_gap(p.pos) > 1200.0:
					_drop_buoy(p)
					p.detect += 1.0
			if datum_err < 600.0 and t - datum_t < 90.0 and p.bombs > 0 and t >= next_weapon:
				p.state = "attack"
				p.tgt = datum
			elif t > p.leave_at:
				p.state = "patrol"
		"attack":
			p.alt = move_toward(p.alt, 120.0, 15.0 * dt)
			_steer(p, U.brg(p.pos, p.tgt), dt, 6.0)
			if p.pos.distance_to(p.tgt) < 200.0:
				next_weapon = t + randf_range(40.0, 60.0)
				p.bombs -= 1
				_drop_torpedo(p.pos, p.tgt, p.id, "Sonar: splash close aboard, bearing %s! The patrol plane's dropped a torpedo!" % U.p3(U.brg(s.pos, p.pos)))
				p.state = "localize" if p.bombs > 0 else "patrol"
				p.leave_at = t + 300.0
	# Its radar sees a raised mast.
	if s.scope_up and s.depth <= PERI_MAX and not s.surfaced():
		var r := p.pos.distance_to(s.pos)
		if r < 35000.0 and randf() < dt * 0.04 * (1.0 - r / 35000.0) * clampf(mast_t / 15.0, 0.3, 2.0):
			_new_datum(s.pos, 200.0, null)
			report("ESM: patrol aircraft radar, bearing %s. It's painting our mast!" % U.p3(U.brg(s.pos, p.pos)), "alarm", "mpamast", 45.0)
	p.roll = lerpf(p.roll, 0.0, dt)
	p.pos += U.dirv(p.hdg) * p.kn * U.KN * dt


func _buoy_gap(p: Vector2) -> float:
	var best := 1e9
	for b in buoys:
		best = minf(best, b.pos.distance_to(p))
	return best


func _drop_buoy(p: Aircraft) -> void:
	if int(mpa_buoys.get(p.id, 0)) <= 0:
		return
	mpa_buoys[p.id] = int(mpa_buoys[p.id]) - 1
	var b := Buoy.new()
	b.id = _new_id()
	b.pos = p.pos
	buoys.append(b)
	emit({"type": "buoy", "pos": Vector3(b.pos.x, 0.0, b.pos.y)})
	if b.pos.distance_to(sub.pos) < 9000.0 and not sub.surfaced():
		b.heard = true
		report("Sonar: small splashes, bearing %s. Sonobuoys going in." % U.p3(U.brg(sub.pos, b.pos)), "warn", "buoys", 40.0)


## Buoys listen for us, about as well as a frigate's hull sonar at short
## range: slow and below the layer, you can pass a few hundred metres off.
func _update_buoys(dt: float) -> void:
	var s := sub
	var keep: Array[Buoy] = []
	var noise := _own_noise()
	for b in buoys:
		b.life -= dt
		if b.life <= 0.0:
			continue
		keep.append(b)
		if s.surfaced():
			continue
		var rng := 5500.0 * noise * (0.55 if s.depth > layer_depth else 1.0)
		var r := b.pos.distance_to(s.pos)
		if r < rng and randf() < dt * (0.12 * (1.0 - r / rng) + 0.03):
			_new_datum(s.pos, 250.0 + r * 0.25, null)
			report("Sonar: there's a sonobuoy close aboard, bearing %s. It may have us." % U.p3(U.brg(s.pos, b.pos)), "warn", "buoyhear", 60.0)
	buoys = keep


# ---------------------------------------------------- the carrier group
## The main target zigzags on her base course; once she knows torpedoes are
## about she turns her stern to the threat and runs at full speed.
func _target_ai(sh: Ship, dt: float) -> void:
	if sh.type == "ssn":
		_sub_ai(sh, dt)
		return
	if sh.type == "ssbn":
		_ssbn_ai(sh, dt)
		return
	if time_alarmed() and t - datum_t < 600.0:
		var away := U.brg(datum, sh.pos)
		var zz := sin(t / 40.0) * 25.0
		_steer(sh, U.wrap360(away + zz), dt, 1.5)
		sh.want_spd = sh.max_kn
		sh.base_hdg = sh.hdg
		sh.leg = sh.hdg
		return
	super._target_ai(sh, dt)


func _pings() -> void:
	pass


# ------------------------------------------------------- the test launch
func in_box() -> bool:
	return box_r > 0.0 and sub.pos.distance_to(box) < box_r


## The launch sequence: battle stations missile, spin up, and about a minute
## later the test round goes, if the boat holds launch depth and a hover all
## that time. X again stops it.
func start_test_launch() -> void:
	var s := sub
	if trident <= 0 or launched:
		report("Weapons: no test round left.", "warn")
		return
	if launch_seq >= 0.0:
		launch_seq = -1.0
		report("Weapons: launch sequence stopped.", "warn")
		return
	if not in_box():
		report("Weapons: we're not in the launch box. It's bearing %s, %.1f km." % [U.p3(U.brg(s.pos, box)),
			s.pos.distance_to(box) / 1000.0], "warn")
		return
	if s.depth < LAUNCH_DEPTH.x or s.depth > LAUNCH_DEPTH.y:
		report("Weapons: come to launch depth first, %d to %d metres." % [int(LAUNCH_DEPTH.x), int(LAUNCH_DEPTH.y)], "warn")
		return
	if absf(s.spd) > HOVER_KN:
		report("Weapons: slow to a hover first, under %d knots." % int(HOVER_KN), "warn")
		return
	launch_seq = t
	report("Captain: man battle stations missile for the test flight. Spin up tube one.", "good")
	report("Weapons: hold launch depth and the hover. About a minute to launch.")


func _update_launch(dt: float) -> void:
	if launch_seq < 0.0 or result != "":
		return
	var s := sub
	var held := s.depth >= LAUNCH_DEPTH.x - 3.0 and s.depth <= LAUNCH_DEPTH.y + 3.0 and absf(s.spd) <= HOVER_KN + 1.0 and s.hull > 40.0
	if not held:
		launch_seq = -1.0
		report("Weapons: launch held. We came off the hover or the launch depth. Steady her and press X again.", "warn")
		return
	var e := t - launch_seq
	if e >= LAUNCH_T * 0.5 and e - dt < LAUNCH_T * 0.5:
		report("Weapons: tube one is pressurized. Test round ready. Thirty seconds.")
	if e >= LAUNCH_T:
		_launch_trident()


func _launch_trident() -> void:
	var s := sub
	launch_seq = -1.0
	trident -= 1
	launched = true
	m_units += 1
	var m := Missile.new()
	m.id = _new_id()
	m.unit = m_units
	m.kind = "trident"
	m.owner = -1
	m.pos = s.pos + U.dirv(s.hdg) * float(nat["sub"]["len"]) * 0.05
	m.origin = m.pos
	m.hdg = U.wrap360(s.hdg + 90.0)
	m.state = "boost"
	m.seen = true
	m.t0 = t
	m.trail = [m.pos]
	missiles.append(m)
	m_fired += 1
	emit({"type": "trident", "pos": Vector3(m.pos.x, 0.0, m.pos.y)})
	sound("launch", 1.0)
	shake = maxf(shake, 0.5)
	report("Weapons: test round away! First stage ignition... she's climbing.", "good")
	# The plume is seen a hundred kilometres off.
	_new_datum(s.pos, 250.0, null)
	_end("launched", 25.0)


## The test round: thrown clear of the sea by the gas charge, the first
## stage lights and she climbs away downrange, out of sight.
func _fly_trident(m: Missile, dt: float) -> bool:
	var e := t - m.t0
	if e < 1.5:
		m.alt = move_toward(m.alt, 25.0, 20.0 * dt)
	else:
		m.spd = minf(m.spd + 60.0 * dt, 2400.0)
		var climb := deg_to_rad(clampf(88.0 - (e - 1.5) * 0.35, 45.0, 88.0))
		m.alt += sin(climb) * m.spd * dt
		m.pos += U.dirv(m.hdg) * cos(climb) * m.spd * dt
	if e > 4.0 and not m.chaffed:
		m.chaffed = true
		report("Weapons: telemetry good. First stage burning normally.")
	if m.alt > 60000.0:
		m.dead = true
		return false
	return true


# ------------------------------------------------------- their submarines
## Back and forth along a patrol line.
func _patrol(e: Ship, dt: float) -> void:
	if e.route.size() < 2:
		return
	var goal: Vector2 = e.route[1] if e.orb_dir > 0 else e.route[0]
	if e.pos.distance_to(goal) < 900.0:
		e.orb_dir = -e.orb_dir
	_steer(e, U.brg(e.pos, goal), dt, 3.0)


## An attack submarine: sprint-and-drift along its line, or ride with the
## missile boat; when something gives us away, close the datum fast, then
## creep in to listen and fire heavyweight torpedoes.
func _sub_ai(e: Ship, dt: float) -> void:
	var s := sub
	var r := e.pos.distance_to(s.pos)
	_listen(e, r, dt)
	e.depth = move_toward(e.depth, e.want_depth, 2.0 * dt)
	match e.state:
		"patrol":
			_patrol(e, dt)
			var sprint := fmod(t + e.id * 97.0, 480.0) < 150.0
			e.want_spd = 16.0 if sprint else 6.0
			e.want_depth = clampf(layer_depth + 60.0, 100.0, 220.0)
		"screen":
			var st := _station(target, e.off)
			_steer(e, U.brg(e.pos, st + U.dirv(target.hdg) * 600.0), dt, 3.0)
			e.want_spd = clampf(target.spd + e.pos.distance_to(st) / 500.0, 3.0, 18.0)
			e.want_depth = clampf(target.depth + 30.0, 60.0, 250.0)
		"hunt", "attack":
			if t - datum_t > 600.0:
				e.state = e.home
				return
			var d := e.pos.distance_to(datum)
			_steer(e, U.brg(e.pos, datum), dt, 3.0)
			e.want_spd = 15.0 if d > 15000.0 else 7.0
			e.want_depth = clampf(s.depth if datum_err < 800.0 else layer_depth + 40.0, 60.0, 300.0)
			var was := e.state
			e.state = "attack" if t - datum_t < 180.0 and datum_err < 1500.0 else "hunt"
			if e.state == "attack" and was != "attack":
				# A minute or so to work up a firing solution.
				e.next_dc = maxf(e.next_dc, t + randf_range(45.0, 90.0))
			if e.state == "attack" and t > e.next_dc and d < 14000.0 and e.to_drop > 0:
				_sub_shoot(e)


func _sub_shoot(e: Ship) -> void:
	if t < next_weapon:
		return
	next_weapon = t + randf_range(50.0, 80.0)
	e.to_drop -= 1
	e.next_dc = t + randf_range(90.0, 150.0)
	e.loud_until = t + 45.0
	var who := e.short if e.ever_heard else "a submarine"
	var tp := _drop_torpedo(e.pos, datum, e.id, "Sonar: launch transient, bearing %s! That's %s. Torpedo in the water!" % [
		U.p3(U.brg(sub.pos, e.pos)), who], false)
	tp.kind = "yu6"
	tp.kn = HW_KN
	tp.rng = HW_RANGE
	tp.seeker = HW_SEEKER
	tp.turn = 20.0
	tp.depth = clampf(sub.depth if datum_err < 800.0 else layer_depth + 30.0, 30.0, 300.0)
	tp.enable = e.pos.distance_to(datum) * 0.8


## A missile submarine on patrol: slow, long legs in her bastion. Alarmed,
## she runs deep and away.
func _ssbn_ai(sh: Ship, dt: float) -> void:
	_listen(sh, sh.pos.distance_to(sub.pos), dt)
	sh.depth = move_toward(sh.depth, sh.want_depth, 2.0 * dt)
	if time_alarmed() and t - datum_t < 900.0:
		_steer(sh, U.brg(datum, sh.pos), dt, 1.5)
		sh.want_spd = 16.0
		if sh.hull.engines > 0.5:
			sh.want_depth = 220.0
		return
	if t > sh.next_zig:
		sh.next_zig = t + randf_range(420.0, 720.0)
		sh.base_hdg = U.wrap360(sh.base_hdg + randf_range(-70.0, 70.0))
	_steer(sh, sh.base_hdg, dt, 1.0)
	sh.want_spd = 6.0


func threat() -> Array:
	var s := sub
	for tp in etorps:
		if tp.state == "home" and tp.pos.distance_to(s.pos) < tp.seeker * 1.5:
			return ["TORPEDO HOMING", "alarm"]
	if not etorps.is_empty():
		return ["TORPEDO IN THE WATER", "alarm"]
	for p in planes:
		if not p.dead and p.state in ["dip", "attack"] and p.pos.distance_to(s.pos) < 9000.0:
			return ["HELICOPTER DIPPING", "warn"]
		if not p.dead and p.state == "localize" and p.pos.distance_to(s.pos) < 15000.0:
			return ["PATROL PLANE OVERHEAD", "warn"]
	for e in ships:
		if (e.kind != "target" or e.type == "ssn") and e.alive() and e.state == "attack":
			return ["HUNTED", "warn"]
	if t - datum_t < 300.0:
		return ["SEARCHING FOR US", "warn"]
	return ["UNDETECTED", "good"]


func _check_end() -> void:
	if result != "":
		return
	var s := sub
	var tg := target
	if s.hull <= 0.0:
		super._check_end()
		return
	if spec.get("goal", "") == "patrol":
		return
	if tg.alive() and spec.get("goal", "") == "disable" and tg.hull.out_of_action():
		report("Link: %s is burning end to end and losing way. She's out of action!" % tg.name, "good")
		sound("breakup", 0.6)
		_end("disabled", 10.0)
	elif tg.alive() and s.pos.distance_to(tg.pos) > float(spec.get("escape", nat.get("escape", ESCAPE))):
		report("Sonar: %s has opened the range. She got away." % tg.short, "warn")
		_end("escaped", 2.5)
	elif tg.alive() and torps.is_empty() and missiles_out() == 0 and harpoons + vls <= 0:
		var empty := true
		for v in s.tubes:
			if v >= 0.0:
				empty = false
		if empty:
			report("Weapons: that was the last of them. Nothing left to fire.", "warn")
			_end("dry", 2.5)
