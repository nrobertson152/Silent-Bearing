extends RefCounted
## Ship damage, compartment by compartment. Pure simulation, no rendering.
##
## The hull is split into watertight compartments along its length, each with
## a port and a starboard half. Holes let the sea into a half-compartment;
## water spreads through strained bulkheads, across to the other side and,
## once the deck edge nears the sea, everywhere. The water aboard settles the
## ship, trims her toward the flooded end and lists her toward the flooded
## side, and the list grows faster as she loses stability. She founders when
## her reserve buoyancy is gone, or capsizes first if the list passes the
## point of no return. Hits can also wreck machinery, jam the rudder, start
## fires and set off a magazine. Damage control patches holes, pumps,
## counterfloods against a list, fights fires and floods threatened magazines;
## how well depends on the navy.
##
## Water volumes are in units of reserve buoyancy (1.0 = founders). They are
## scaled per ship so that, on average, the number of torpedo hits it takes
## matches the hits-to-sink figure in scripts/data.gd, and then vary with
## where the hits land.

const Ballistics := preload("res://scripts/sim/ballistics.gd")
const GameData := preload("res://scripts/data.gd")

## Main belt armour (mm) over the machinery and magazines.
const BELT := {"yamato": 410.0, "kongo": 203.0, "tirpitz": 320.0, "royaloak": 330.0, "barham": 330.0,
	"hood": 305.0, "shinano": 205.0, "taiho": 152.0, "shokaku": 165.0, "yorktown": 102.0, "enterprise": 102.0,
	"wasp": 16.0, "courageous": 76.0, "arkroyal": 114.0, "indianapolis": 102.0, "ashigara": 102.0,
	"prinz": 80.0, "juneau": 95.0, "kuma": 63.0, "karlsruhe": 50.0}
## How well each navy's damage control worked (patching, pumping, counterflooding, firefighting).
const DC := {"us": 1.0, "uk": 0.9, "de": 0.85, "jp": 0.6}
## How much of a torpedo's blast gets past the underwater protection.
const PROT := {"bb": 0.7, "cv": 0.85, "ca": 1.0, "cl": 1.0, "dd": 1.3, "pc": 1.5}
## Chance per full-power torpedo hit next to a magazine that it goes up.
const MAG_RISK := {"bb": 0.05, "cv": 0.05, "ca": 0.1, "cl": 0.14, "dd": 0.2, "pc": 0.1}
## How hard water on one side heels her. Battleships flood their wide side
## protection far off the centreline, and big carriers carry their weight
## high, so one-sided damage tends to roll them over before they founder.
const HEEL := {"bb": 0.8, "cv": 0.76, "ca": 0.66, "cl": 0.62, "dd": 0.55, "pc": 0.55}
## Heel (degrees) past which a ship rolls over.
const CAPSIZE := 33.0
const FILL_S := 32.0   # seconds for a torpedo hole to fill its compartment if left alone

var n := 10
var length := 100.0
var beam := 10.0
var draft := 3.0
var freeboard := 6.0
var type := "dd"
var nation := "us"
var hp := 1.0
var vol := PackedFloat32Array()     # per half-compartment: index = i * 2 + (0 port, 1 starboard)
var water := PackedFloat32Array()   # fill of each half-compartment, 0..1
var holes := PackedFloat32Array()   # inflow, fill per second into an empty half-compartment
var limit := PackedFloat32Array()   # how full the hole can bring it (strained bulkheads get shored up)
var fire := PackedFloat32Array()    # per compartment, 0..1
var mags := {}                      # compartment -> "ready" (or "flooded")
var mach := {}                      # machinery compartments
var belt := 25.0
var citadel := Vector2(0.18, 0.8)
var dc := 1.0
var prot := 1.0
var mag_risk := 0.08
var heel := 0.62
var flooded := 0.0                  # water aboard / reserve buoyancy
var list := 0.0                     # heel, degrees, + = down to starboard
var trim := 0.0                     # degrees, + = down by the bow
var settle := 0.0                   # metres of extra draft
var engines := 1.0                  # propulsion left, 0..1
var rudder_jam := 0.0               # degrees the rudder is jammed at (0 = free)
var structure := 1.0                # topside and structural integrity, 0..1
var mode := ""                      # "" afloat, else "founder", "capsize" or "explode"
var break_u := -1.0                 # where she broke in two, if she did
var events: Array = []              # what happened this tick, for the world to report and show
var _counter := 0                   # side being counterflooded (+1 starboard, -1 port)
var _down_at := 0.85                # flooding at which the deck edge reaches the sea
var _said := {}


func setup(layout_key: String, ship_type: String, nat: String, L: float, B: float, D: float, hits_to_sink: float) -> void:
	type = ship_type
	nation = nat
	length = L
	beam = B
	draft = D
	hp = maxf(hits_to_sink, 0.4)
	var lay := GameData.layout(layout_key)
	freeboard = float(lay.get("fb", 6.0))
	n = {"bb": 14, "cv": 14, "ca": 12, "cl": 12, "dd": 9, "pc": 6}.get(type, 10) as int
	dc = DC.get(nation, 0.9) as float
	prot = PROT.get(type, 1.0) as float
	mag_risk = MAG_RISK.get(type, 0.1) as float
	heel = HEEL.get(type, 0.62) as float
	if layout_key == "juneau":
		mag_risk = 0.6   # she blew apart from a single hit
	belt = BELT.get(layout_key, 25.0 if type != "pc" else 8.0) as float
	if type in ["dd", "pc"]:
		citadel = Vector2(0.3, 0.7)
	# Compartments are fuller amidships and fine at the ends.
	var shape := PackedFloat32Array()
	var total := 0.0
	for i in n:
		var u := (i + 0.5) / n
		var f := 0.3 + 0.7 * pow(sin(PI * u), 0.6)
		shape.append(f)
		total += f * 2.0
	# Scale so a typical hit (its half-compartment, what seeps past the
	# bulkheads either side, and the counterflooding that follows) costs 1/hp
	# of the reserve buoyancy.
	var cells_per_hit := (1.0 + 0.84 * prot) * (1.0 + 0.55 * dc * clampf(3.0 / hp, 0.3, 1.0))
	var cap := 2.0 * n / (hp * cells_per_hit)
	_down_at = clampf(1.0 - 0.6 / hp, 0.4, 0.88)
	vol.resize(n * 2)
	water.resize(n * 2)
	holes.resize(n * 2)
	limit.resize(n * 2)
	fire.resize(n)
	for i in n:
		for s in 2:
			vol[i * 2 + s] = shape[i] / total * cap
	water.fill(0.0)
	holes.fill(0.0)
	limit.fill(0.0)
	fire.fill(0.0)
	for t in lay.get("turrets", []):
		mags[_comp(float(t["x"]))] = "ready"
	if type == "cv":
		# Bomb rooms and aviation fuel fore and aft.
		mags[_comp(0.18)] = "ready"
		mags[_comp(0.78)] = "ready"
	for i in n:
		var u := (i + 0.5) / n
		if u > 0.38 and u < 0.74:
			mach[i] = true


func _comp(u: float) -> int:
	return clampi(int(u * n), 0, n - 1)


## Compartment centre as a fraction of length (0 bow, 1 stern).
func comp_u(i: int) -> float:
	return (i + 0.5) / n


func health() -> float:
	return clampf(minf(1.0 - flooded, structure), 0.0, 1.0)


func afloat() -> bool:
	return mode == ""


## Fraction of the ship's speed she can still make.
func speed_factor() -> float:
	var f := engines * (1.0 - 0.45 * flooded) * clampf(cos(deg_to_rad(list)) * 1.15 - 0.15, 0.0, 1.0)
	return clampf(f, 0.0, 1.0)


## Water still to come in from open holes, for estimating hits left.
func projected() -> float:
	var w := 0.0
	for c in vol.size():
		w += minf(1.0, water[c] + holes[c] * 60.0) * vol[c]
	return w


func hits_left() -> int:
	return maxi(1, int(ceil((1.0 - minf(projected(), 0.99)) * hp - 0.15)))


func burning() -> float:
	var m := 0.0
	for f in fire:
		m = maxf(m, f)
	return m


func _event(what: String, data := {}) -> void:
	var e := data.duplicate()
	e["what"] = what
	events.append(e)


## A torpedo hit at u along the hull (0 bow, 1 stern) on `side` (-1 port,
## +1 starboard). `power` is the warhead against a 300 kg standard.
func torpedo(u: float, side: int, power: float) -> void:
	if not afloat():
		return
	var i := _comp(u)
	var s := 0 if side < 0 else 1
	var r := power * prot / FILL_S
	holes[i * 2 + s] += r
	limit[i * 2 + s] = 1.0
	for j in [i - 1, i + 1]:
		if j >= 0 and j < n:
			var cj: int = j * 2 + s
			holes[cj] += r * 0.5
			limit[cj] = clampf(limit[cj] + randf_range(0.25, 0.6) * prot * power, 0.0, 1.0)
	# The blast vents up through the decks and lights the fuel oil.
	fire[i] = minf(1.0, fire[i] + 0.35 * power)
	structure -= 0.05 * power * (100.0 / maxf(hp * 100.0, 100.0)) * (3.0 if type in ["dd", "pc"] else 1.0)
	_event("hit", {"u": u, "side": side})
	if mach.has(i):
		engines = maxf(0.0, engines - 0.35 * power)
		_event("engines")
	if u > 0.84:
		engines = maxf(0.0, engines - 0.25 * power)
		if randf() < 0.6:
			rudder_jam = signf(randf() - 0.5) * randf_range(12.0, 35.0)
			_event("rudder")
	if type in ["dd", "pc"] and power > 0.5:
		# A destroyer's back breaks.
		mode = "explode"
		break_u = clampf(u, 0.25, 0.75)
		structure = 0.0
		_event("broken", {"u": break_u})
		return
	for j in [i - 1, i, i + 1]:
		if mags.get(j, "") == "ready" and randf() < mag_risk * power * (1.0 if j == i else 0.4):
			_explode(j)
			return


## A shell hit. `height` is metres above the waterline, `cal` the calibre,
## `v` the striking speed, `cos_ob` how squarely it hit (1 = face on),
## `points` the shell's damage figure and `max_struct` the ship's.
## Returns what happened: {"pen": bool, "where": "belt"|"hull"|"super", ...}.
func shell(u: float, side: int, height: float, cal: float, v: float, cos_ob: float, points: float, max_struct: float) -> Dictionary:
	var out := {"pen": false, "where": "super", "fire": false, "flood": false}
	if not afloat():
		return out
	var i := _comp(u)
	var s := 0 if side < 0 else 1
	var armour := 20.0
	if height < 2.6 and height > -1.8:
		if u >= citadel.x and u <= citadel.y:
			armour = belt
			out["where"] = "belt"
		else:
			armour = 25.0 if type not in ["dd", "pc"] else 10.0
			out["where"] = "hull"
	elif height <= -1.8:
		armour = belt * 0.6
		out["where"] = "belt"
	var pen := Ballistics.penetration(cal, v)
	var eff := armour / maxf(cos_ob, 0.33)
	var frac := points / maxf(max_struct, 1.0)
	if cos_ob < 0.34 and armour > 30.0:
		return out   # glanced off
	if pen < eff:
		structure -= frac * 0.15
		return out
	out["pen"] = true
	structure -= frac * (1.0 if out["where"] == "super" else 0.7)
	if height < 1.2:
		var c := i * 2 + s
		holes[c] += cal / 100.0 * 0.0016
		limit[c] = minf(1.0, limit[c] + cal / 100.0 * 0.3)
		out["flood"] = true
	if randf() < (0.3 if out["where"] == "super" else 0.2):
		fire[i] = minf(1.0, fire[i] + 0.3)
		out["fire"] = true
	if mach.has(i) and out["where"] != "super" and randf() < 0.3:
		engines = maxf(0.0, engines - 0.12)
		_event("engines")
	if mags.get(i, "") == "ready" and out["where"] != "super" and randf() < (0.06 if type in ["dd", "pc"] else 0.02):
		_explode(i)
	return out


func _explode(i: int) -> void:
	mags[i] = "gone"
	mode = "explode"
	break_u = comp_u(i)
	structure = 0.0
	# Both broken ends are left burning.
	for j in range(maxi(i - 1, 0), mini(i + 2, n)):
		fire[j] = maxf(fire[j], 1.0 if j == i else 0.75)
	_event("magazine", {"u": comp_u(i)})


func step(dt: float) -> void:
	if not afloat():
		return
	var power_ok := engines > 0.15   # the pumps need steam
	# Water in through the holes, along through strained bulkheads while the
	# hole is still open, slowly across through doors and ducts, and
	# everywhere once the deck edge is at the sea.
	var down := maxf(0.0, (flooded - _down_at) / maxf(1.0 - _down_at, 0.05))
	for i in n:
		for s in 2:
			var c := i * 2 + s
			var w := water[c]
			if w < limit[c]:
				w = minf(limit[c], w + holes[c] * (1.0 - w) * dt)
			w += 0.012 * down * (1.0 - w) * dt
			if w > 0.9 and holes[c] > 0.004:
				for j in [i - 1, i + 1]:
					if j >= 0 and j < n:
						var cj: int = j * 2 + s
						water[cj] = minf(1.0, water[cj] + 0.0006 * dt * vol[c] / vol[cj])
			water[c] = clampf(w, 0.0, 1.0)
		var a := i * 2
		var b := a + 1
		var x := (water[a] - water[b]) * 0.0008 * dc * dt
		water[a] -= x
		water[b] += x
	# Damage control: patch the holes, then pump out what they can. The pumps
	# shift about a sixth of one hit's flooding in ten minutes.
	var patch := dt / (150.0 / dc)
	var n_wet := 0
	for c in holes.size():
		if holes[c] > 0.0:
			holes[c] = maxf(0.0, holes[c] - holes[c] * patch - 0.00002 * dt)
		if water[c] > 0.02 and holes[c] < 0.004:
			n_wet += 1
	if power_ok and n_wet > 0:
		var pump := 0.17 / (hp * 600.0) * dc * engines / n_wet
		for c in holes.size():
			if water[c] > 0.02 and holes[c] < 0.004:
				water[c] = maxf(0.0, water[c] - pump / vol[c] * dt)
	_hydrostatics()
	# Counterflood the high side when she lists: flood the compartments
	# opposite the damage, at the cost of buoyancy.
	if absf(list) > 6.0 and _counter == 0 and randf() < 0.3 * dc * dt:
		_counter = -int(signf(list))
		_event("counterflood", {"side": _counter})
	if _counter != 0:
		if absf(list) < 4.0 or signf(list) == float(_counter):
			_counter = 0
		else:
			var hi := 0 if _counter < 0 else 1
			for i in n:
				var c := i * 2 + hi
				var low := water[i * 2 + 1 - hi]
				if holes[c] <= 0.004 and water[c] < low * 0.5:
					water[c] = minf(low * 0.5, water[c] + 0.006 * dc * dt)
	# Fires: grow, spread, scorch, burn out under firefighting or flooding.
	for i in n:
		var f := fire[i]
		if f <= 0.0:
			continue
		var wet := (water[i * 2] + water[i * 2 + 1]) * 0.5
		f += (0.006 - 0.009 * dc) * dt - wet * 0.02 * dt
		if f > 0.55:
			for j in [i - 1, i + 1]:
				if j >= 0 and j < n and fire[j] < f:
					fire[j] = minf(1.0, fire[j] + 0.0015 * dt)
		structure -= f * 0.00035 * dt * (300.0 / maxf(hp * 100.0, 100.0))
		if mags.get(i, "") == "ready" and f > 0.5:
			if randf() < 0.02 * dc * dt * 10.0:
				# Damage control floods the magazine before it cooks off.
				mags[i] = "flooded"
				water[i * 2] = maxf(water[i * 2], 0.7)
				water[i * 2 + 1] = maxf(water[i * 2 + 1], 0.7)
				_event("mag_flooded", {"u": comp_u(i)})
			elif randf() < 0.0004 * f * dt * 10.0:
				_explode(i)
				return
		fire[i] = clampf(f, 0.0, 1.0)
	if engines < 0.15 and not _said.has("dead"):
		_said["dead"] = true
		_event("dead_in_water")
	# The end.
	if absf(list) > CAPSIZE:
		mode = "capsize"
		_event("capsize", {"side": signf(list)})
	elif flooded >= 1.0:
		mode = "founder"
		_event("founder")
	elif structure <= 0.0:
		mode = "founder"
		_event("wrecked")


## Settling, trim and list from the water aboard.
func _hydrostatics() -> void:
	var w := 0.0
	var mt := 0.0
	var ml := 0.0
	var machine_water := 0.0
	var machine_vol := 0.0
	for i in n:
		var u := comp_u(i)
		for s in 2:
			var c := i * 2 + s
			var m := water[c] * vol[c]
			w += m
			mt += m * (0.5 - u)
			ml += m * (1.0 if s == 1 else -1.0)
			if mach.has(i):
				machine_water += m
				machine_vol += vol[c]
	flooded = w
	settle = minf(w, 1.0) * freeboard
	trim = rad_to_deg(atan(mt * 0.3))
	# Stability drains away as she settles and water sloshes.
	var gm := maxf(0.2, 1.0 - 0.7 * w)
	list = rad_to_deg(atan(ml * heel / gm))
	if machine_vol > 0.0:
		engines = minf(engines, 1.0 - 0.8 * clampf(machine_water / machine_vol, 0.0, 1.0))

