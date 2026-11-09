## Math helpers. Simulation space is metres with x east and y north. Bearings
## and headings are degrees clockwise from north. Godot space maps north to -Z.

const Ballistics := preload("res://scripts/sim/ballistics.gd")

const KN := 0.514444


static func wrap360(a: float) -> float:
	return fposmod(a, 360.0)


static func adiff(a: float, b: float) -> float:
	return fposmod(a - b + 180.0, 360.0) - 180.0


static func brg(a: Vector2, b: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(b.x - a.x, b.y - a.y)), 360.0)


static func dirv(h: float) -> Vector2:
	var r := deg_to_rad(h)
	return Vector2(sin(r), cos(r))


static func p3(a: float) -> String:
	return "%03d" % (int(round(fposmod(a, 360.0))) % 360)


static func clock(s: float) -> String:
	var i := int(s)
	return "%02d:%02d:%02d" % [i / 3600, (i / 60) % 60, i % 60]


## Simulation (x east, up, north) to Godot (x, y, z) with north = -Z.
static func to3(p: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(p.x, h, -p.y)


static func yaw(hdg: float) -> float:
	return -deg_to_rad(hdg)


static func gauss() -> float:
	return randfn(0.0, 1.0)


## Elevation angle (degrees) that lands a shell at range r on flat water, or -1 if
## out of reach. Shells feel air drag (scripts/sim/ballistics.gd).
static func elev_for_range(r: float, v: float, cal := 100.0) -> float:
	return Ballistics.elev_for_range(r, v, cal)


static func range_for_elev(e: float, v: float, cal := 100.0) -> float:
	return Ballistics.range_for_elev(e, v, cal)
