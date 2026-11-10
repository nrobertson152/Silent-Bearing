## Near-future warship parts for ShipBuilder: stealthy superstructures with
## sloped sides, phased-array radar faces, the Type 055's integrated mast,
## vertical launch cells, single stealth gun mounts, close-in weapons,
## hangars and helicopter decks, hull numbers, and a catapult carrier's
## angled flight deck and island.
##
## Same model space as ShipBuilder: bow toward -Z, starboard +X, waterline
## at y = 0. Positions along the hull are fractions of length (0 bow, 1 stern).

const MeshKit := preload("res://scripts/build/mesh_kit.gd")
const PlaneBuilder := preload("res://scripts/build/plane_builder.gd")


static func z_of(u: float, L: float) -> float:
	return (u - 0.5) * L


## Everything modern a layout asks for. `deck_h` and `hb` come from
## ShipBuilder (deck height and half-beam at u).
static func build(k: MeshKit, lay: Dictionary, L: float, B: float, deck_h: Callable, hb: Callable) -> Array:
	var tops := []
	for s in lay.get("stealth", []):
		_stealth(k, s, L, B, deck_h, hb)
	if lay.has("imast"):
		_imast(k, lay["imast"], L, deck_h)
	for v in lay.get("vls", []):
		_vls(k, v, L, B, deck_h, hb)
	if lay.has("hangar"):
		_hangar(k, lay["hangar"], L, B, deck_h, hb)
	if lay.has("helideck"):
		_helideck(k, lay["helideck"], L, B, deck_h, hb)
	for u in lay.get("ciws", []):
		_ciws(k, float(u), L, B, lay, deck_h, hb)
	if lay.has("hull_no"):
		_hull_number(k, String(lay["hull_no"]), L, B, deck_h, hb)
	if lay.get("towed", false):
		# The towed sonar's winch and fairlead on the transom.
		var y: float = deck_h.call(0.99)
		k.box("metal", Vector3(0, y - 1.2, z_of(1.0, L) + 0.4), Vector3(3.0, 1.6, 0.8))
	return tops


# ------------------------------------------------------- superstructure
## A deckhouse with sides sloped inward to scatter radar, optionally
## stacked on another (`on` metres above the deck) and carrying radar faces.
static func _stealth(k: MeshKit, s: Dictionary, L: float, B: float, deck_h: Callable, hb: Callable) -> void:
	var u0: float = s["x0"]
	var u1: float = s["x1"]
	var um := (u0 + u1) * 0.5
	var y0: float = float(deck_h.call(um)) + float(s.get("on", 0.0))
	var h: float = s["h"]
	var w: float = minf(B * float(s["wf"]), float(hb.call(um)) * 1.9)
	var z0 := z_of(u0, L)
	var z1 := z_of(u1, L)
	var len := z1 - z0
	var slope: float = s.get("slope", 0.12)
	var wt := w * (1.0 - slope * 2.0)
	# Raked front, near-vertical back.
	var lt := len - h * 0.35
	k.block("super", 0, (z0 + z1) * 0.5, y0 - 0.2, y0 + h, w, len, wt, lt, h * 0.175)
	k.box("super", Vector3(0, y0 + h + 0.08, (z0 + z1) * 0.5 + h * 0.175), Vector3(wt + 0.3, 0.16, lt + 0.3))
	if s.get("bridge", true) and not s.has("on"):
		# Bridge windows across the raked front near the top.
		var yb := y0 + h - 1.6
		var zf := z0 + (yb - y0) / h * h * 0.35 + 0.08
		var wb := lerpf(w, wt, (yb - y0) / h) * 0.86
		k.box("window", Vector3(0, yb, zf), Vector3(wb, 0.9, 0.12),
			Basis(Vector3.RIGHT, -atan2(h * 0.35, h)))
	if s.get("radar", false):
		# Four phased-array faces on the corners of the upper block.
		var yr := y0 + h * 0.62
		var fz := z0 + h * 0.62 * 0.35 + 1.0
		var bz := z1 - 1.0
		var hw := lerpf(w, wt, 0.62) * 0.5
		for c in [[-1.0, fz, PI * 0.25], [1.0, fz, -PI * 0.25], [-1.0, bz, PI * 0.75], [1.0, bz, -PI * 0.75]]:
			_face(k, Vector3(float(c[0]) * hw, yr, float(c[1])), float(c[2]), 4.2)


## An octagonal radar face standing on the side of a deckhouse, turned by
## `yaw` (0 = facing forward, -Z).
static func _face(k: MeshKit, c: Vector3, yaw: float, size: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var r := size * 0.5
	var n := b * Vector3(0, 0.15, -1).normalized()
	var pts := []
	for i in 8:
		var a := PI / 8.0 + TAU * float(i) / 8.0
		pts.append(c + b * Vector3(cos(a) * r, sin(a) * r * 1.0, -0.12))
	for i in 8:
		k.tri("panel", c + b * Vector3(0, 0, -0.14), pts[i], pts[(i + 1) % 8], n)
	# Frame.
	for i in 8:
		var a: Vector3 = pts[i]
		var bb: Vector3 = pts[(i + 1) % 8]
		k.quad("metal", a, bb, bb + b * Vector3(0, 0, 0.12), a + b * Vector3(0, 0, 0.12), c + b * Vector3(0, 0, 1.0))


## The Type 055's integrated mast: a tall tapered tower with the four big
## radar faces and smaller arrays above.
static func _imast(k: MeshKit, m: Dictionary, L: float, deck_h: Callable) -> void:
	var u: float = m["x"]
	var z := z_of(u, L)
	var y0: float = float(deck_h.call(u)) + float(m["base"])
	var h: float = m["h"]
	var w: float = m["w"]
	k.block("super", 0, z, y0 - 1.0, y0 + h, w, w * 1.15, w * 0.55, w * 0.62)
	# Main faces on the four diagonals, part way up.
	var yf := y0 + h * 0.42
	var hw := lerpf(w, w * 0.55, 0.42) * 0.5
	var hl := lerpf(w * 1.15, w * 0.62, 0.42) * 0.5
	for c in [[-1.0, -1.0, PI * 0.25], [1.0, -1.0, -PI * 0.25], [-1.0, 1.0, PI * 0.75], [1.0, 1.0, -PI * 0.75]]:
		_face(k, Vector3(float(c[0]) * hw * 0.72, yf, z + float(c[1]) * hl * 0.72), float(c[2]), w * 0.48)
	# Smaller arrays near the top.
	var ys := y0 + h * 0.82
	var sw := lerpf(w, w * 0.55, 0.82) * 0.5
	for c in [[0.0, -1.0, 0.0], [0.0, 1.0, PI], [-1.0, 0.0, PI * 0.5], [1.0, 0.0, -PI * 0.5]]:
		_face(k, Vector3(float(c[0]) * sw, ys, z + float(c[1]) * sw * 1.12), float(c[2]), w * 0.22)
	# Top: a sensor drum and a short pole.
	k.cyl("metal", Vector3(0, y0 + h, z), Vector3(0, y0 + h + 1.8, z), w * 0.2, w * 0.18, 12)
	k.cyl("metal", Vector3(0, y0 + h + 1.8, z), Vector3(0, y0 + h + 6.0, z), 0.18, 0.1, 6)


# ------------------------------------------------------------ weapons
## Vertical launch cells flush with the deck: a grid of square hatches.
static func _vls(k: MeshKit, v: Dictionary, L: float, B: float, deck_h: Callable, hb: Callable) -> void:
	var u0: float = v["x0"]
	var u1: float = v["x1"]
	var um := (u0 + u1) * 0.5
	var y: float = deck_h.call(um)
	var w: float = minf(B * float(v["w"]), float(hb.call(u0)) * 1.7)
	var z0 := z_of(u0, L) + 0.6
	var z1 := z_of(u1, L) - 0.6
	k.box("metal", Vector3(0, y + 0.08, (z0 + z1) * 0.5), Vector3(w, 0.16, z1 - z0))
	var pitch := 1.3
	var nx := maxi(2, int(w / pitch))
	var nz := maxi(2, int((z1 - z0) / pitch))
	for i in nx:
		for j in nz:
			var x := -w * 0.5 + (i + 0.5) * w / nx
			var z := z0 + (j + 0.5) * (z1 - z0) / nz
			k.box("panel", Vector3(x, y + 0.17, z), Vector3(w / nx - 0.22, 0.02, (z1 - z0) / nz - 0.22))


## A close-in weapon system on a raised pedestal: a squat mount with a
## barrel cluster, on the deck edge or the superstructure.
static func _ciws(k: MeshKit, u: float, L: float, B: float, lay: Dictionary, deck_h: Callable, hb: Callable) -> void:
	var z := z_of(u, L)
	var y: float = float(deck_h.call(u))
	var x := 0.0
	if lay["hull"] == "cv":
		y = float(lay["deck"]["h"]) - 3.0
		x = (float(lay["deck"]["w"]) * 0.5 + 1.0) * (1.0 if u < 0.5 else -1.0)
	else:
		# On top of whatever deckhouse is there.
		for s in lay.get("stealth", []):
			if u >= float(s["x0"]) and u <= float(s["x1"]):
				y = maxf(y, float(deck_h.call(u)) + float(s.get("on", 0.0)) + float(s["h"]))
		for h in [lay.get("hangar", {})]:
			if not h.is_empty() and u >= float(h["x0"]) - 0.01 and u <= float(h["x1"]) + 0.01:
				y = maxf(y, float(deck_h.call(u)) + float(h["h"]))
	k.cyl("super", Vector3(x, y, z), Vector3(x, y + 1.2, z), 1.2, 1.1, 10)
	k.block("super", x, z, y + 1.2, y + 2.6, 2.2, 2.4, 1.7, 1.9)
	k.cyl("metal", Vector3(x, y + 2.0, z - 1.0), Vector3(x, y + 2.0, z - 4.2), 0.32, 0.26, 8, true, "black")


# ------------------------------------------------------------ aviation
static func _hangar(k: MeshKit, h: Dictionary, L: float, B: float, deck_h: Callable, hb: Callable) -> void:
	var u0: float = h["x0"]
	var u1: float = h["x1"]
	var um := (u0 + u1) * 0.5
	var y: float = deck_h.call(um)
	var w: float = minf(B * float(h["wf"]), float(hb.call(um)) * 1.9)
	var z0 := z_of(u0, L)
	var z1 := z_of(u1, L)
	var ht: float = h["h"]
	k.block("super", 0, (z0 + z1) * 0.5, y - 0.2, y + ht, w, z1 - z0, w * 0.88, z1 - z0)
	# The door facing the flight deck.
	k.box("metal", Vector3(0, y + ht * 0.45, z1 + 0.05), Vector3(w * 0.62, ht * 0.85, 0.12))
	for i in 5:
		k.box("black", Vector3(0, y + ht * (0.12 + 0.16 * i), z1 + 0.12), Vector3(w * 0.6, 0.06, 0.04))


## A flight deck aft with its landing circle and lines.
static func _helideck(k: MeshKit, d: Dictionary, L: float, B: float, deck_h: Callable, hb: Callable) -> void:
	var u0: float = d["x0"]
	var u1: float = d["x1"]
	var um := (u0 + u1) * 0.5
	var y: float = float(deck_h.call(um)) + 0.03
	var z := z_of(um, L)
	var r: float = minf(float(hb.call(um)) * 0.62, (u1 - u0) * L * 0.3)
	var segs := 28
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		k.quad("white", p0 * r + Vector3(0, y, z), p1 * r + Vector3(0, y, z), p1 * (r - 0.35) + Vector3(0, y, z),
			p0 * (r - 0.35) + Vector3(0, y, z), Vector3(0, y - 1.0, z))
	k.box("white", Vector3(0, y, (z_of(u0, L) + z_of(u1, L)) * 0.5), Vector3(0.3, 0.02, (u1 - u0) * L * 0.95))
	k.box("yellow", Vector3(0, y + 0.005, z), Vector3(r * 1.4, 0.02, 0.3))


# ----------------------------------------------------------- markings
## Segments lit for each digit in a seven-segment layout: top, upper right,
## lower right, bottom, lower left, upper left, middle.
const SEGS := {"0": "1111110", "1": "0110000", "2": "1101101", "3": "1111001", "4": "0110011",
	"5": "1011011", "6": "1011111", "7": "1110000", "8": "1111111", "9": "1111011"}


## Big white hull numbers with a dark shadow on both sides of the bow, as
## the PLAN paints them.
static func _hull_number(k: MeshKit, num: String, L: float, B: float, deck_h: Callable, hb: Callable) -> void:
	var u := 0.11
	var h := clampf(L * 0.022, 2.6, 7.0)
	var w := h * 0.55
	var gap := w * 0.35
	var total := num.length() * w + (num.length() - 1) * gap
	var y: float = float(deck_h.call(u)) * 0.55
	var z0 := z_of(u, L)
	for sd in [-1.0, 1.0]:
		var side: float = sd
		for i in num.length():
			# Left to right as you look at her side: toward the bow on the
			# starboard side, toward the stern on the port side.
			var along := -total * 0.5 + i * (w + gap) + w * 0.5
			var z := z0 - along if side > 0.0 else z0 + along
			var uu := z / L + 0.5
			# The bow flares out: stand clear of the hull at the top of the digit.
			var flare := B * 0.5 * 0.2 * maxf(0.0, 1.0 - uu / 0.25) * ((y + h * 0.55) / maxf(float(deck_h.call(uu)), 0.1))
			var x: float = side * (float(hb.call(uu)) + flare + 0.12)
			_digit(k, num[i], Vector3(x, y, z), side, w, h)


static func _digit(k: MeshKit, d: String, c: Vector3, side: float, w: float, h: float) -> void:
	var on: String = SEGS.get(d, "0000000")
	var t := maxf(0.25, h * 0.12)
	# Segment centres in (along, up) and whether they lie along or up.
	var segs := [[0.0, h * 0.5, true], [w * 0.5, h * 0.25, false], [w * 0.5, -h * 0.25, false], [0.0, -h * 0.5, true],
		[-w * 0.5, -h * 0.25, false], [-w * 0.5, h * 0.25, false], [0.0, 0.0, true]]
	for i in 7:
		if on[i] != "1":
			continue
		var sg: Array = segs[i]
		var along: float = sg[0]
		# Numbers read forward (toward -Z) on the starboard side.
		var z := c.z - along if side > 0.0 else c.z + along
		var size := Vector3(0.1, t, w + t) if sg[2] else Vector3(0.1, h * 0.5 + t * 0.5, t)
		k.box("black", Vector3(c.x + side * 0.02, c.y + float(sg[1]) - 0.15, z + 0.15 * side), size)
		k.box("white", Vector3(c.x + side * 0.08, c.y + float(sg[1]), z), size)


# ------------------------------------------------------------- carrier
## A catapult carrier's flight deck: wide, with the landing area angled off
## to port, two catapults on the bow and one in the waist, deck-edge lifts,
## and the island well aft on the starboard side.
static func carrier(k: MeshKit, lay: Dictionary, L: float, B: float, deck_h: Callable, hb: Callable) -> Array:
	var d: Dictionary = lay["deck"]
	var dh: float = d["h"]
	var dw: float = d["w"]
	var ang := deg_to_rad(float(d.get("angled", 9.0)))
	var ski := float(d.get("ski", 0.0))
	var fb: float = lay["fb"]
	# Hull sides up to the flight deck, following the hull's plan.
	var poly := []
	var steps := 20
	for i in steps + 1:
		var u := lerpf(0.0, 0.97, float(i) / steps)
		poly.append(Vector2(maxf(float(hb.call(u)) * 0.99, 0.3), z_of(u, L)))
	for i in range(steps, -1, -1):
		var u := lerpf(0.0, 0.97, float(i) / steps)
		poly.append(Vector2(-maxf(float(hb.call(u)) * 0.99, 0.3), z_of(u, L)))
	k.prism("hull", poly, fb - 0.5, dh - 0.6)
	# The flight deck outline (x to starboard, by fraction of length).
	var half := dw * 0.5
	var outline := [
		[0.0, -0.36, 0.30], [0.05, -0.50, 0.44], [0.16, -0.58, 0.56], [0.33, -0.62, 0.60],
		[0.45, -0.93, 0.66], [0.62, -1.0, 0.74], [0.80, -1.0, 0.74], [0.93, -0.92, 0.62], [1.0, -0.80, 0.52]]
	if ski > 0.0:
		# A narrower bow that runs up into the ski-jump.
		outline = [
			[0.0, -0.24, 0.24], [0.05, -0.34, 0.36], [0.16, -0.47, 0.52], [0.33, -0.6, 0.6],
			[0.45, -0.93, 0.66], [0.62, -1.0, 0.74], [0.80, -1.0, 0.74], [0.93, -0.92, 0.62], [1.0, -0.80, 0.52]]
	var fd := []
	for o in outline:
		fd.append(Vector2(float(o[2]) * half, z_of(float(o[0]), L)))
	for i in range(outline.size() - 1, -1, -1):
		var o: Array = outline[i]
		fd.append(Vector2(float(o[1]) * half, z_of(float(o[0]), L)))
	# Prism needs a convex-ish shape around its centre; split port and
	# starboard so the angled overhang triangulates cleanly.
	k.prism("metal", fd, dh - 0.6, dh, "flight")
	if ski > 0.0:
		_ski_jump(k, outline, half, dh, ski, L)
	# Sponson supports under the angled deck overhang.
	for u in [0.5, 0.62, 0.74, 0.86]:
		var xo: float = -half * 0.9
		k.block("hull", (xo - float(hb.call(u))) * 0.5, z_of(u, L), dh - 6.0, dh - 0.6, absf(xo) - float(hb.call(u)) + 1.0, 3.0,
			absf(xo) - float(hb.call(u)) + 1.0, 3.0)
	var y := dh + 0.02
	# Landing area: a centreline angled to port, with edge lines.
	var a0 := Vector3(-half * 0.25, y, z_of(1.0, L) - 4.0)
	var dir := Vector3(-sin(ang), 0, -cos(ang))
	var len := L * 0.62
	var mid := a0 + dir * len * 0.5
	var bas := Basis(Vector3.UP, ang)
	var dash := 0.0
	while dash < len:
		k.box("white", a0 + dir * (dash + 3.0) + Vector3(0, 0.01, 0), Vector3(0.5, 0.03, 6.0), bas)
		dash += 14.0
	for s in [-1.0, 1.0]:
		var off: Vector3 = Vector3(cos(ang), 0, -sin(ang)) * 14.0 * float(s)
		k.box("white", mid + off, Vector3(0.4, 0.03, len), bas)
	k.box("red", a0 + dir * len * 0.05 + Vector3(0, 0.012, 0), Vector3(30.0, 0.03, 0.6), bas)
	if ski > 0.0:
		# Three take-off spots, two forward and one in the waist, each with a
		# blast deflector raised behind it and a line forward to the ramp.
		for spot in [[-half * 0.16, 0.30], [half * 0.16, 0.30], [-half * 0.3, 0.55]]:
			var xs: float = spot[0]
			var zs := z_of(float(spot[1]), L)
			var z_ramp := z_of(0.15, L)
			k.box("white", Vector3(xs, y + 0.01, (zs + z_ramp) * 0.5), Vector3(0.35, 0.03, absf(zs - z_ramp)))
			k.box("metal", Vector3(xs, dh + 1.2, zs + 5.0), Vector3(10.0, 2.6, 0.4), Basis(Vector3.RIGHT, deg_to_rad(-50.0)))
	else:
		# Catapult tracks: two on the bow, one in the waist along the angled deck.
		for xc in [-half * 0.22, half * 0.22]:
			k.box("black", Vector3(xc, y + 0.01, z_of(0.15, L)), Vector3(0.6, 0.03, L * 0.27))
			k.box("metal", Vector3(xc, dh + 1.2, z_of(0.30, L) + 2.0), Vector3(9.0, 2.4, 0.4),
				Basis(Vector3.RIGHT, deg_to_rad(-50.0)))
		var wc := Vector3(-half * 0.55, y + 0.01, z_of(0.45, L))
		k.box("black", wc, Vector3(0.6, 0.03, L * 0.28), bas)
	# Yellow taxi lines and the deck number at the bow.
	k.box("yellow", Vector3(half * 0.35, y + 0.01, z_of(0.5, L)), Vector3(0.3, 0.03, L * 0.5))
	if lay.has("hull_no"):
		var num := String(lay["hull_no"])
		var hh := 9.0
		for i in num.length():
			var xx := (float(i) - (num.length() - 1) * 0.5) * hh * 0.8
			_deck_digit(k, num[i], Vector3(xx, y + 0.02, z_of(0.19 if ski > 0.0 else 0.05, L) + hh * 0.6), hh * 0.5, hh)
	# Deck-edge lifts (dark plates) on the starboard side and port aft.
	for u in [0.42, 0.78]:
		k.box("black", Vector3(half * 0.62, y, z_of(u, L)), Vector3(16.0, 0.03, 18.0))
	k.box("black", Vector3(-half * 0.86, y, z_of(0.9, L)), Vector3(14.0, 0.03, 16.0))
	# The island: a sleek block with radar faces and a stack aft.
	var tops := []
	if lay.has("island"):
		var isl: Dictionary = lay["island"]
		var iz := z_of(float(isl["x"]), L)
		var il: float = isl["l"]
		var iw: float = isl["w"]
		var ih: float = isl["h"]
		var ix := half * 0.62
		k.block("super", ix, iz, dh, dh + ih, iw, il, iw * 0.8, il * 0.8, 0.0)
		k.block("super", ix, iz - il * 0.15, dh + ih, dh + ih * 1.55, iw * 0.78, il * 0.5, iw * 0.55, il * 0.36)
		k.box("window", Vector3(ix, dh + ih * 0.88, iz - il * 0.4), Vector3(iw * 0.82, 1.2, 0.2))
		for c in [[-1.0, -1.0, PI * 0.25], [1.0, -1.0, -PI * 0.25], [-1.0, 1.0, PI * 0.75], [1.0, 1.0, -PI * 0.75]]:
			_face(k, Vector3(ix + float(c[0]) * iw * 0.34, dh + ih * 1.25, iz - il * 0.15 + float(c[1]) * il * 0.16),
				float(c[2]), iw * 0.36)
		k.cyl("metal", Vector3(ix, dh + ih * 1.55, iz - il * 0.15), Vector3(ix, dh + ih * 1.55 + 9.0, iz - il * 0.15), 0.25, 0.12, 6)
		# Exhaust stack at the back of the island.
		var stack := Vector3(ix, dh + ih, iz + il * 0.32)
		k.block("super", ix, iz + il * 0.32, dh + ih * 0.8, dh + ih + 3.5, iw * 0.7, il * 0.28, iw * 0.6, il * 0.22)
		k.box("black", stack + Vector3(0, 3.55, 0), Vector3(iw * 0.55, 0.1, il * 0.2))
		tops.append(stack + Vector3(0, 3.6, 0))
	# Jets parked along the starboard side forward of the island and aft.
	var n := int(lay.get("planes", 0))
	for i in n:
		var u := 0.2 + 0.06 * (i % 6) + (0.5 if i >= 6 else 0.0)
		if u > 0.92:
			continue
		var x := half * (0.48 if i % 2 == 0 else 0.3)
		var t := Transform3D(Basis(Vector3.UP, deg_to_rad(-120.0)), Vector3(x, dh + 0.9, z_of(u, L)))
		PlaneBuilder.add_simple(k, t, "jet", 15.0, 21.0, "plane")
	return tops


## The ski-jump: the forward flight deck curving up to `deg` degrees at the
## bow, so jets leave the deck climbing.
static func _ski_jump(k: MeshKit, outline: Array, half: float, dh: float, deg: float, L: float) -> void:
	var u_end := 0.15
	var rise := u_end * L * tan(deg_to_rad(deg)) * 0.5
	var steps := 10
	for i in steps:
		var ua := u_end * float(i) / steps
		var ub := u_end * float(i + 1) / steps
		var ha := dh + rise * pow(1.0 - ua / u_end, 2.0)
		var hb := dh + rise * pow(1.0 - ub / u_end, 2.0)
		var wa := _deck_width(outline, ua, half)
		var wb := _deck_width(outline, ub, half)
		var za := z_of(ua, L)
		var zb := z_of(ub, L)
		k.hexa("hull", [Vector3(wa.x, dh - 0.6, za), Vector3(wa.y, dh - 0.6, za), Vector3(wb.y, dh - 0.6, zb), Vector3(wb.x, dh - 0.6, zb),
			Vector3(wa.x, ha, za), Vector3(wa.y, ha, za), Vector3(wb.y, hb, zb), Vector3(wb.x, hb, zb)])
		k.quad("flight", Vector3(wa.x, ha + 0.03, za), Vector3(wa.y, ha + 0.03, za), Vector3(wb.y, hb + 0.03, zb),
			Vector3(wb.x, hb + 0.03, zb), Vector3(0.0, dh - 10.0, (za + zb) * 0.5))


## Port and starboard edges of the flight deck at `u`, in metres.
static func _deck_width(outline: Array, u: float, half: float) -> Vector2:
	for i in outline.size() - 1:
		var a: Array = outline[i]
		var b: Array = outline[i + 1]
		if u <= float(b[0]):
			var f := (u - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-4)
			return Vector2(lerpf(float(a[1]), float(b[1]), f), lerpf(float(a[2]), float(b[2]), f)) * half
	var last: Array = outline[-1]
	return Vector2(float(last[1]), float(last[2])) * half


## A painted deck number, seven-segment style, read from aft.
static func _deck_digit(k: MeshKit, d: String, c: Vector3, w: float, h: float) -> void:
	var on: String = SEGS.get(d, "0000000")
	var t := h * 0.12
	var segs := [[0.0, -h * 0.5, true], [w * 0.5, -h * 0.25, false], [w * 0.5, h * 0.25, false], [0.0, h * 0.5, true],
		[-w * 0.5, h * 0.25, false], [-w * 0.5, -h * 0.25, false], [0.0, 0.0, true]]
	for i in 7:
		if on[i] != "1":
			continue
		var sg: Array = segs[i]
		var size := Vector3(w + t, 0.03, t) if sg[2] else Vector3(t, 0.03, h * 0.5 + t * 0.5)
		k.box("white", c + Vector3(float(sg[0]), 0, float(sg[1])), size)
