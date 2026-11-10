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


var etorps: Array[Homer] = []
var decoys: Array[Decoy] = []
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
	_set_depths()


func _opening() -> void:
	report("Conn: on station at 60 metres, ahead one-third. Hunting %s and her group." % target.name, "good")
	report("Sonar: towed array streamed. Listening.")
	report("Bathythermograph: thermal layer near %d metres. Below it, their hull sonars hear us half as well." % int(layer_depth))


# ----------------------------------------------------------------- setup
## A main target with her group on stations kilometres out, and helicopters.
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
	tg.cruise = tg.max_kn * 0.7
	tg.hull = _make_hull(tg, float(spec["hp"]))
	var side := 1.0 if randf() < 0.5 else -1.0
	tg.pos = Vector2(-side * randf_range(20000, 25000), randf_range(14000, 19000))
	tg.hdg = U.wrap360((90.0 if side > 0 else 270.0) + randf_range(-20.0, 20.0))
	tg.base_hdg = tg.hdg
	tg.leg = tg.hdg
	tg.spd = tg.cruise
	tg.want_spd = tg.cruise
	tg.next_zig = randf_range(120, 240)
	target = tg
	ships.append(tg)
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
		e.to_drop = 6 if e.type == "ffg" else 4       # torpedoes in the deck tubes
		rocket_stock[e.id] = 3 if e.type in ["cg", "ddg"] else 0
		ships.append(e)
	# Helicopters fly day and night, from the carrier or the cruisers.
	var pads := []
	for e in ships:
		if e.type in ["cv", "cg", "ddg", "ffg"]:
			pads.append(e)
	for key in spec.get("air", []):
		_spawn_helo(key, pads[planes.size() % pads.size()])
	next_plane = 1e9


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


func _set_depths() -> void:
	depths = [0.0, 12.0, 30.0, 60.0, 100.0, 150.0, 200.0, float(nat["test"])]


# ------------------------------------------------------------- listening
## How far the towed array hears a ship: bigger and faster is louder, and
## your own speed drowns everything out.
func _hear_range(sh: Ship) -> float:
	var base: float = {"cv": 42000.0, "cg": 30000.0, "ddg": 27000.0, "ffg": 21000.0}.get(sh.type, 24000.0)
	var loud := 0.45 + 0.55 * clampf(sh.spd / 20.0, 0.0, 1.5)
	var own := clampf(1.15 - (absf(sub.spd) - 8.0) / 14.0, 0.12, 1.0)
	var layer := 0.6 if (sub.depth > layer_depth) else 1.0
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
		if see and r < vis and sh.alive():
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
			if not e.alive():
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
	if sub.can_see() and sub.scope_up and sub.pos.distance_to(sh.pos) < vis:
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
		report("Countermeasures: no decoys left!", "warn")
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
			if sh.alive() and _inside(sh, tp.pos):
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
	for e in ships:
		if e.kind != "target" and e.alive() and e.state == "screen":
			e.state = "hunt"
			e.search_until = t + 600.0


func _mk48_hit(tp: Homer, sh: Ship) -> void:
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


# ------------------------------------------------------- their ASW ships
## The screen holds station until something gives you away, then hunts the
## datum: pinging, flying helicopters out, and firing homing torpedoes.
func _escort_ai(e: Ship, dt: float) -> void:
	var s := sub
	var tg := target
	var r := e.pos.distance_to(s.pos)
	_listen(e, r, dt)
	match e.state:
		"screen":
			var st := _station(tg, e.off)
			var want := U.brg(e.pos, st + U.dirv(tg.hdg) * 800.0)
			_steer(e, want, dt, 3.0)
			var dist := e.pos.distance_to(st)
			e.want_spd = clampf(tg.spd + dist / 600.0, 4.0, e.max_kn) if absf(U.adiff(want, tg.hdg)) < 90.0 else tg.spd * 0.6
		"hunt", "attack":
			if t - datum_t > 420.0:
				e.state = "screen"
				report("Sonar: %s is heading back to her station." % e.short, "info", "back%d" % e.id, 60.0)
				return
			var d := e.pos.distance_to(datum)
			# Close to sonar range of the datum, then slow to listen.
			_steer(e, U.brg(e.pos, datum), dt, 4.0)
			e.want_spd = e.max_kn * 0.85 if d > 7000.0 else 12.0
			e.state = "attack" if t - datum_t < 90.0 and datum_err < 1200.0 else "hunt"
			if e.state == "attack" and t > e.next_dc:
				_shoot_at_datum(e, d)
	if e.state != "screen" and t > e.run_until:
		# Active sonar while hunting.
		e.run_until = t + 12.0
		_ping(e, r)


## Passive listening on the hull sonar and towed array.
func _listen(e: Ship, r: float, dt: float) -> void:
	var s := sub
	if s.surfaced():
		if r < 20000.0 and randf() < dt * 0.3:
			_new_datum(s.pos, 100.0, e)
		return
	var noise := 0.14 + 0.86 * pow(clampf((absf(s.spd) - 5.0) / 23.0, 0.0, 1.0), 1.3)
	if s.depth < 30.0 and absf(s.spd) > 12.0:
		noise *= 1.4
	var base: float = {"ffg": 26000.0, "ddg": 22000.0, "cg": 22000.0}.get(e.type, 15000.0)
	if e.spd > 20.0:
		base *= 0.5
	var layer := 0.55 if s.depth > layer_depth else 1.0
	if e.type == "ffg" or e.type == "ddg":
		layer = maxf(layer, 0.8)   # towed arrays and variable-depth sonar go under the layer
	var rng := base * noise * layer * (0.5 if e.hull.health() < 0.6 else 1.0)
	if r < rng and randf() < dt * 0.25 * (1.0 - r / rng):
		_new_datum(s.pos, 300.0 + r * 0.06, e)
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
func _drop_torpedo(at: Vector2, toward: Vector2, owner: int, msg: String) -> void:
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
	sound("splash", 0.4)
	tc = 1
	emit({"type": "etorp", "pos": Vector3(at.x, 0.0, at.y)})


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


# ---------------------------------------------------- the carrier group
## The main target zigzags on her base course; once she knows torpedoes are
## about she turns her stern to the threat and runs at full speed.
func _target_ai(sh: Ship, dt: float) -> void:
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
	for e in ships:
		if e.kind != "target" and e.alive() and e.state == "attack":
			return ["HUNTED", "warn"]
	if t - datum_t < 300.0:
		return ["SEARCHING FOR US", "warn"]
	return ["UNDETECTED", "good"]


func _check_end() -> void:
	super._check_end()
