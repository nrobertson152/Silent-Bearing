extends RefCounted
## Shell flight with air drag, and how much armour a shell gets through.
##
## Shells slow down as they fly (a 4-inch shell has lost about a sixth of its
## speed by 1,500 m), so the range and time-of-flight tables are built by
## stepping a trajectory exactly the way the simulation flies its shells.

const G := 9.81
## Integration step for shells and for the tables (seconds).
const STEP := 0.02
## Elevation table resolution (degrees) and extent.
const E_STEP := 0.25
const E_MAX := 45.0

static var _tables := {}


## Drag constant (1/m) for a shell of calibre `cal_mm`: deceleration is
## k * v^2. Bigger shells are much heavier for their size and carry their
## speed further. Tuned so a 4-inch/50 reaches about 14 km at 20 degrees.
static func drag(cal_mm: float) -> float:
	return 1.15e-5 / maxf(cal_mm / 1000.0, 0.02)


## Advances a shell by dt with gravity and drag, in small fixed steps.
## Returns [position, velocity].
static func fly(p: Vector3, v: Vector3, k: float, dt: float) -> Array:
	var left := dt
	while left > 1e-6:
		var h := minf(STEP, left)
		v += (Vector3(0.0, -G, 0.0) - v * (k * v.length())) * h
		p += v * h
		left -= h
	return [p, v]


## Range (m) and time of flight (s) for each elevation step, from and to
## sea level, for a muzzle velocity and calibre.
static func _table(v0: float, cal_mm: float) -> Dictionary:
	var key := "%d|%d" % [int(v0), int(cal_mm)]
	if _tables.has(key):
		return _tables[key]
	var k := drag(cal_mm)
	var ranges := PackedFloat32Array()
	var times := PackedFloat32Array()
	var n := int(E_MAX / E_STEP) + 1
	for i in n:
		var e := deg_to_rad(i * E_STEP)
		var p := Vector3.ZERO
		var v := Vector3(cos(e), sin(e), 0.0) * v0
		var tt := 0.0
		if i == 0:
			ranges.append(0.0)
			times.append(0.0)
			continue
		while true:
			var p0 := p
			v += (Vector3(0.0, -G, 0.0) - v * (k * v.length())) * STEP
			p += v * STEP
			tt += STEP
			if p.y < 0.0:
				var f := p0.y / maxf(p0.y - p.y, 1e-6)
				ranges.append(lerpf(p0.x, p.x, f))
				times.append(tt - STEP * (1.0 - f))
				break
			if tt > 200.0:
				ranges.append(p.x)
				times.append(tt)
				break
	var tab := {"r": ranges, "t": times}
	_tables[key] = tab
	return tab


## Elevation (degrees) that lands a shell at range r on flat water, or -1 if
## it is out of reach. Takes the low (flat) solution.
static func elev_for_range(r: float, v0: float, cal_mm := 100.0) -> float:
	var tab := _table(v0, cal_mm)
	var ranges: PackedFloat32Array = tab["r"]
	if r <= 0.0:
		return 0.0
	for i in range(1, ranges.size()):
		if ranges[i] >= r:
			var f := (r - ranges[i - 1]) / maxf(ranges[i] - ranges[i - 1], 1e-6)
			return (i - 1 + f) * E_STEP
		if ranges[i] < ranges[i - 1]:
			break
	return -1.0


## Range (m) on flat water for an elevation in degrees.
static func range_for_elev(e: float, v0: float, cal_mm := 100.0) -> float:
	var ranges: PackedFloat32Array = _table(v0, cal_mm)["r"]
	var x := clampf(e, 0.0, E_MAX) / E_STEP
	var i := mini(int(x), ranges.size() - 2)
	return lerpf(ranges[i], ranges[i + 1], x - i)


## Time of flight (s) to range r, for the low solution.
static func time_for_range(r: float, v0: float, cal_mm := 100.0) -> float:
	var e := elev_for_range(r, v0, cal_mm)
	if e < 0.0:
		return -1.0
	var times: PackedFloat32Array = _table(v0, cal_mm)["t"]
	var x := e / E_STEP
	var i := mini(int(x), times.size() - 2)
	return lerpf(times[i], times[i + 1], x - i)


## Armour (mm) an armour-piercing shell of `cal_mm` gets through, face on,
## at striking velocity `v` (m/s). A simplified De Marre-style rule: about
## 80 mm for a 4-inch shell at 1,500 m, about 100 mm for a 14 cm at 2 km.
static func penetration(cal_mm: float, v: float) -> float:
	return 0.9 * cal_mm * pow(cal_mm / 100.0, 0.25) * pow(maxf(v, 0.0) / 800.0, 1.4)
