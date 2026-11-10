## The near-future boats' exteriors: a smooth teardrop hull in black
## anechoic tiles, a tall sail with photonics masts, cruciform stern planes
## with end plates, and a pump-jet (Virginia) or seven-bladed screw and
## missile deck (Ohio).
## Model space: bow toward -Z, waterline at y = 0 when surfaced.

const MeshKit := preload("res://scripts/build/mesh_kit.gd")
const Paint := preload("res://scripts/build/paint.gd")

## Per class: diameter, surfaced draft, where the parallel midbody starts and
## ends (fraction of length), the sail, and the stern.
const CLASSES := {
	"virginia": {"draft": 9.4, "bow": 0.14, "aft": 0.58, "tail_r": 0.17,
		"sail": {"u": 0.255, "l": 11.0, "w": 2.6, "h": 6.6, "planes": false},
		"bow_planes": 0.085, "pumpjet": true, "missile_deck": false},
	"ohio": {"draft": 10.8, "bow": 0.09, "aft": 0.66, "tail_r": 0.16,
		"sail": {"u": 0.205, "l": 14.0, "w": 2.9, "h": 8.0, "planes": true},
		"bow_planes": 0.0, "pumpjet": false, "missile_deck": true},
}


static func materials(L: float) -> Dictionary:
	var lay := {"fb": 1.0, "fb_bow": 1.0}
	var hull := Paint.paint_mat({"scheme": 0, "c": [Color(0.045, 0.047, 0.05)], "rust": 0.05}, 0, lay, L, 3.7)
	hull.set_shader_parameter("tile", 0.62)
	hull.set_shader_parameter("rough", 0.82)
	hull.set_shader_parameter("grime", 0.35)
	hull.set_shader_parameter("band", 0.4)
	hull.set_shader_parameter("rust", 0.04)
	var fit := Paint.paint_mat({"scheme": 0, "c": [Color(0.06, 0.062, 0.066)], "rust": 0.04}, 2, lay, L, 3.7)
	fit.set_shader_parameter("rough", 0.6)
	return {
		"hull": hull,
		"deck": hull,
		"bottom": hull,
		"metal": fit,
		"gun": fit,
		"black": MeshKit.mat(Color(0.02, 0.02, 0.022), 0.9),
		"glass": MeshKit.mat(Color(0.15, 0.2, 0.25), 0.05, 0.4),
		"brass": MeshKit.mat(Color(0.5, 0.42, 0.26), 0.35, 0.8),
		"plane": MeshKit.mat(Color(0.3, 0.36, 0.28), 0.7),
	}


## Hull radius at u (0 bow, 1 stern) for a class.
static func radius(c: Dictionary, R: float, u: float) -> float:
	var b: float = c["bow"]
	var a: float = c["aft"]
	if u < b:
		var t := 1.0 - u / b
		return R * pow(maxf(0.0, 1.0 - t * t), 0.5)
	if u > a:
		var t := clampf((u - a) / (0.985 - a), 0.0, 1.0)
		return R * maxf(float(c["tail_r"]), 1.0 - pow(t, 1.7) * (1.0 - float(c["tail_r"])))
	return R


static func build(nat: Dictionary) -> Node3D:
	var sd: Dictionary = nat["sub"]
	var style: String = sd["style"]
	var c: Dictionary = CLASSES.get(style, CLASSES["virginia"])
	var L: float = sd["len"]
	var R: float = float(sd["beam"]) * 0.5
	var mats := materials(L)
	var root := Node3D.new()
	root.name = "PlayerSub"
	var k := MeshKit.new(mats)
	var yc: float = R - float(c["draft"])
	var top := yc + R
	_hull(k, c, L, R, yc)
	var s: Dictionary = c["sail"]
	var sz: float = (float(s["u"]) - 0.5) * L
	var sl: float = s["l"]
	var sw: float = s["w"]
	var sh: float = s["h"]
	_sail(k, c, sz, sl, sw, sh, top, R, yc, L)
	if c["missile_deck"]:
		_missile_deck(k, c, L, R, yc, top)
	_stern(k, c, L, R, yc)
	if float(c["bow_planes"]) > 0.0:
		var bz := (float(c["bow_planes"]) - 0.5) * L
		for side in [-1.0, 1.0]:
			var x0: float = side * radius(c, R, float(c["bow_planes"])) * 0.92
			_fin(k, Vector3(x0, yc - R * 0.35, bz), Vector3(side, 0, 0), 2.3, 2.2, 1.3, 0.28)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	root.add_child(mi)
	# No deck gun or AA mount on these boats: empty nodes keep the rest of the
	# game happy.
	for key in ["gun_yaw", "gun_pitch", "aa_yaw", "aa_pitch"]:
		var n := Node3D.new()
		n.name = key
		root.add_child(n)
		root.set_meta(key, n)
	var by := top + sh - 0.9
	var pz := sz + sl * 0.05
	root.set_meta("bridge_eye", Vector3(0, by + 1.5, sz - sl * 0.32))
	root.set_meta("scope_head", Vector3(0, top + sh + 3.2, pz))
	root.set_meta("deck_y", top)
	root.set_meta("deck_geo", {"L": L, "deck_y": top, "dw": R * 0.7, "tz": sz, "tl": sl, "tw": sw, "th": sh, "by": by,
		"gun_z": sz + sl * 1.4, "aa_z": sz + sl * 0.62, "aa_y": by, "pz": pz, "hatch_z": sz + sl * 1.1, "style": style})
	return root


## The pressure hull as a smooth body of revolution.
static func _hull(k: MeshKit, c: Dictionary, L: float, R: float, yc: float) -> void:
	var us := []
	var n := 64
	for i in n + 1:
		var u := float(i) / n
		# Finer near the bow, where the radius changes fastest.
		us.append(pow(u, 1.0) if u > 0.2 else u * u / 0.2 * 0.5 + u * 0.5)
	var segs := 28
	var prev := []
	var prev_n := []
	for ui in us.size():
		var u: float = us[ui]
		var r := radius(c, R, u)
		var z := (u - 0.5) * L
		# Slope of the radius along the hull tilts the normals fore and aft.
		var du := 0.002
		var dr := (radius(c, R, minf(u + du, 1.0)) - radius(c, R, maxf(u - du, 0.0))) / (2.0 * du * L)
		var ring := []
		var norms := []
		for j in segs + 1:
			var a := TAU * float(j) / segs
			var dir := Vector3(cos(a), sin(a), 0.0)
			ring.append(Vector3(dir.x * r, yc + dir.y * r, z))
			norms.append(Vector3(dir.x, dir.y, -dr).normalized())
		if ui > 0:
			for j in segs:
				k.quad_n("hull", prev[j], prev[j + 1], ring[j + 1], ring[j], prev_n[j], prev_n[j + 1], norms[j + 1], norms[j])
		prev = ring
		prev_n = norms
	# Close the tail behind the propulsor hub.
	var zt := 0.5 * L
	var rt := radius(c, R, 1.0)
	for j in segs:
		var a0 := TAU * float(j) / segs
		var a1 := TAU * float(j + 1) / segs
		k.tri("metal", Vector3(0, yc, zt + rt * 1.6), Vector3(cos(a1) * rt, yc + sin(a1) * rt, zt),
			Vector3(cos(a0) * rt, yc + sin(a0) * rt, zt), Vector3(0, 0, 1))


## The sail: a streamlined fin with a fillet into the hull, masts on top.
static func _sail(k: MeshKit, c: Dictionary, sz: float, sl: float, sw: float, sh: float, top: float, R: float,
		yc: float, L: float) -> void:
	var poly := []
	var pts := 18
	for i in pts:
		# A blunt airfoil: round nose, long taper aft.
		var t := float(i) / (pts - 1)
		var z := sz - sl * 0.5 + sl * t
		var w := sw * 0.5 * (pow(sin(clampf(t / 0.32, 0.0, 1.0) * PI * 0.5), 0.6) * (1.0 - 0.75 * pow(maxf(t - 0.35, 0.0) / 0.65, 1.6)))
		poly.append(Vector2(maxf(w, 0.05), z))
	var outline := []
	for p in poly:
		outline.append(Vector2(p.x, p.y))
	for i in range(poly.size() - 1, -1, -1):
		outline.append(Vector2(-poly[i].x, poly[i].y))
	k.prism("hull", outline, top - 0.6, top + sh, "metal")
	# Fillet blending the sail's leading edge into the hull.
	var f0 := sz - sl * 0.5
	for side in [-1.0, 1.0]:
		k.quad("hull", Vector3(0, top + sh * 0.35, f0), Vector3(side * sw * 0.42, top - 0.1, f0 + 1.0),
			Vector3(side * sw * 0.5, top - 0.1, f0 + sl * 0.3), Vector3(0, top + sh * 0.35, f0 + 0.6),
			Vector3(-side * 2.0, top, f0 + 2.0))
		k.tri("hull", Vector3(0, top + sh * 0.35, f0), Vector3(0, top - 0.35, f0 - 2.2), Vector3(side * sw * 0.42, top - 0.1, f0 + 1.0),
			Vector3(side, 0.3, -0.6).normalized())
	# Masts: photonics masts, ESM and radar, standing proud of the sail.
	var my := top + sh
	var masts := [[0.0, -0.18, 3.2, 0.24], [0.0, 0.02, 2.6, 0.22], [-0.25, 0.2, 1.6, 0.16], [0.25, 0.28, 1.2, 0.14]]
	for m in masts:
		var mz: float = sz + sl * float(m[1])
		k.cyl("metal", Vector3(m[0], my - 0.2, mz), Vector3(m[0], my + float(m[2]), mz), m[3], float(m[3]) * 0.85, 10)
		k.cyl("black", Vector3(m[0], my + float(m[2]) - 0.5, mz), Vector3(m[0], my + float(m[2]), mz), float(m[3]) * 1.15,
			float(m[3]) * 1.05, 10)
	if c["sail"]["planes"]:
		for side in [-1.0, 1.0]:
			_fin(k, Vector3(side * sw * 0.45, top + sh * 0.62, sz - sl * 0.12), Vector3(side, 0, 0), 4.4, 2.6, 1.6, 0.3)


## Ohio-class missile deck: a flat fairing over the tubes with two rows of hatches.
static func _missile_deck(k: MeshKit, c: Dictionary, L: float, R: float, yc: float, top: float) -> void:
	var z0 := (0.26 - 0.5) * L
	var z1 := (0.60 - 0.5) * L
	var h := 1.1
	k.block("hull", 0, (z0 + z1) * 0.5, top - 0.8, top + h, R * 1.35, z1 - z0, R * 1.05, z1 - z0 - 6.0)
	var n := 12
	for i in n:
		var z := lerpf(z0 + 4.5, z1 - 4.5, float(i) / (n - 1))
		for side in [-1.0, 1.0]:
			k.cyl("metal", Vector3(side * R * 0.27, top + h, z), Vector3(side * R * 0.27, top + h + 0.08, z), 1.2, 1.2, 16)


## Stern planes and rudders in a cross, with end plates, and the propulsor.
static func _stern(k: MeshKit, c: Dictionary, L: float, R: float, yc: float) -> void:
	var u := 0.9
	var z := (u - 0.5) * L
	var r := radius(c, R, u)
	var span := R * 0.95
	for dv in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0)]:
		var dir: Vector3 = dv
		var base: Vector3 = Vector3(0, yc, z) + dir * r * 0.9
		var sp: float = span * (0.85 if dir.y < 0.0 else 1.0)
		_fin(k, base, dir, sp, 4.2, 2.6, 0.32)
		if absf(dir.x) > 0.5:
			# End plate standing up and down from the tip of each stern plane.
			var tip: Vector3 = base + dir * sp
			k.block("hull", tip.x, tip.z + 0.4, tip.y - 1.3, tip.y + 1.3, 0.22, 3.0, 0.18, 2.0)
	var zt := 0.5 * L
	if c["pumpjet"]:
		# Pump-jet: a shroud ring around the tail cone, with stator vanes.
		var zs0 := zt - 3.6
		var zs1 := zt - 0.2
		var ro0 := radius(c, R, (zs0 / L) + 0.5) + 0.9
		k.cyl("hull", Vector3(0, yc, zs0), Vector3(0, yc, zs1), ro0, ro0 * 0.86, 28, false)
		k.cyl("black", Vector3(0, yc, zs1), Vector3(0, yc, zs0), ro0 * 0.8, ro0 * 0.92, 28, false)
		for i in 8:
			var a := TAU * float(i) / 8.0
			var d := Vector3(cos(a), sin(a), 0)
			var rin := radius(c, R, (zs0 / L) + 0.5)
			k.quad("metal", Vector3(0, yc, zs0 + 0.6) + d * rin, Vector3(0, yc, zs0 + 2.2) + d * rin * 0.9,
				Vector3(0, yc, zs0 + 2.2) + d * ro0 * 0.88, Vector3(0, yc, zs0 + 0.6) + d * ro0 * 0.95, Vector3(0, yc, zs0 + 1.4))
	else:
		# Seven skewed blades on a hub.
		var hub := Vector3(0, yc, zt + 0.6)
		k.cyl("metal", Vector3(0, yc, zt - 0.6), Vector3(0, yc, zt + 1.8), 0.9, 0.4, 14)
		for i in 7:
			var a := TAU * float(i) / 7.0
			var d := Vector3(cos(a), sin(a), 0)
			var e := Vector3(cos(a + 0.5), sin(a + 0.5), 0)
			k.quad("brass", hub + d * 0.7, hub + d * 2.8 + Vector3(0, 0, 0.35), hub + e * 3.4 + Vector3(0, 0, 0.1),
				hub + e * 0.8 + Vector3(0, 0, -0.3), hub + Vector3(0, 0, -2.0))


## A fin (plane or rudder) from `base` along `dir`: span, root and tip chord, thickness.
static func _fin(k: MeshKit, base: Vector3, dir: Vector3, span: float, root: float, tip: float, thick: float) -> void:
	var side := Vector3(0, 0, 1).cross(dir).normalized()
	var a := base + Vector3(0, 0, -root * 0.45)
	var b := base + Vector3(0, 0, root * 0.55)
	var tc := base + dir * span
	var ct := tc + Vector3(0, 0, -tip * 0.3 + (root - tip) * 0.25)
	var dt := tc + Vector3(0, 0, tip * 0.7 + (root - tip) * 0.25)
	for sgn in [-1.0, 1.0]:
		var o: Vector3 = side * thick * 0.5 * sgn
		var ot: Vector3 = side * thick * 0.3 * sgn
		k.quad("hull", a + o, b + o, dt + ot, ct + ot, base - side * sgn * 2.0)
	k.quad("hull", ct + side * thick * 0.3, dt + side * thick * 0.3, dt - side * thick * 0.3, ct - side * thick * 0.3,
		base)
	k.quad("hull", a + side * thick * 0.5, ct + side * thick * 0.3, ct - side * thick * 0.3, a - side * thick * 0.5,
		base + Vector3(0, 0, 2.0))
