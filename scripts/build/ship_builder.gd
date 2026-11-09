## Builds warship models from GameData layouts: a lofted hull with sheer,
## flare and a raked stem, then turrets, superstructure, towers, funnels,
## masts, AA mounts, boats, catapults and carrier flight decks.
##
## Model space: bow toward -Z, starboard +X, waterline at y = 0.

const GameData := preload("res://scripts/data.gd")
const MeshKit := preload("res://scripts/build/mesh_kit.gd")
const Paint := preload("res://scripts/build/paint.gd")
const PlaneBuilder := preload("res://scripts/build/plane_builder.gd")

const STATIONS := [0.0, 0.008, 0.02, 0.04, 0.07, 0.11, 0.16, 0.22, 0.29, 0.37, 0.46, 0.55, 0.64,
	0.72, 0.79, 0.85, 0.90, 0.94, 0.97, 0.99, 1.0]


static func z_of(u: float, L: float) -> float:
	return (u - 0.5) * L


static func hb(lay: Dictionary, u: float, B: float) -> float:
	var t: String = lay["hull"]
	var fine := 0.95 if t == "bb" else (0.75 if t in ["dd", "pc"] else 0.85)
	var f := 1.0
	if u < 0.38:
		f = pow(sin(u / 0.38 * PI * 0.5), fine)
	elif u > 0.72:
		var s := (u - 0.72) / 0.28
		f = 1.0 - s * s * (0.5 if t != "pc" else 0.35)
	return B * 0.5 * f


static func deck_h(lay: Dictionary, u: float) -> float:
	var F: float = lay["fb"]
	var Fb: float = lay["fb_bow"]
	var t: String = lay["hull"]
	if t == "dd" or t == "pc":
		if u <= 0.32:
			return Fb - (Fb - F) * 0.25 * (u / 0.32)
		return F + 0.3 * pow(maxf(0.0, (u - 0.85) / 0.15), 2.0)
	var h := F + (Fb - F) * pow(maxf(0.0, 1.0 - u / 0.32), 1.6)
	if lay.get("sheer", "") == "jp":
		h += 0.5 * pow(maxf(0.0, (u - 0.8) / 0.2), 2.0)
	if t == "cv" and lay.has("deck") and lay["deck"].get("bow", "open") == "enclosed":
		var dh: float = float(lay["deck"]["h"]) - 0.6
		var x0: float = float(lay["deck"]["x0"]) + 0.12
		if u < x0:
			h = lerpf(dh, h, smoothstep(0.0, x0, u))
	return h


static func build(lay_key: String, L: float, B: float, D: float) -> Node3D:
	var lay := GameData.layout(lay_key)
	var mats := Paint.ship(lay_key, lay, L)
	var root := Node3D.new()
	root.name = "Ship"
	var k := MeshKit.new(mats)
	_hull(k, lay, L, B, D)
	var turret_nodes := []
	for t in lay.get("turrets", []):
		var tn := _turret(mats, t, lay, L)
		root.add_child(tn)
		turret_nodes.append(tn)
	for s in lay.get("supers", []):
		_super(k, lay, s, L, B)
	if lay.has("tower"):
		_tower(k, lay, lay["tower"], L, B)
	var funnel_tops := []
	for f in lay.get("funnels", []):
		funnel_tops.append(_funnel(k, lay, f, L, B, Vector3(0, deck_h(lay, f["x"]), z_of(f["x"], L))))
	for m in lay.get("masts", []):
		_mast(k, m["type"], Vector3(0, deck_h(lay, m["x"]), z_of(m["x"], L)), m["h"], B * 0.35)
	for u in lay.get("tubes", []):
		_tubes(k, Vector3(0, deck_h(lay, u), z_of(u, L)))
	if lay.get("dc", false):
		_dc_racks(k, lay, L, B)
	if lay.get("boats", false):
		_boats(k, lay, L, B)
	if lay.has("catapult"):
		_catapult(k, lay, lay["catapult"], L)
	if lay["hull"] == "cv":
		funnel_tops.append_array(_carrier(k, lay, L, B))
	_aa(k, lay, int(lay.get("aa", 0)), L, B)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	root.add_child(mi)
	root.set_meta("turrets", turret_nodes)
	root.set_meta("funnels", funnel_tops)
	var top := 30.0
	if lay.has("tower"):
		top = float(lay["tower"]["h"])
	root.set_meta("height", top)
	root.set_meta("beam", B)
	root.set_meta("deck_y", float(lay["deck"]["h"]) if lay["hull"] == "cv" else float(lay["fb"]))
	return root


# ------------------------------------------------------------------- hull
static func _hull(k: MeshKit, lay: Dictionary, L: float, B: float, D: float) -> void:
	var us: Array = STATIONS.duplicate()
	if lay["hull"] == "dd" or lay["hull"] == "pc":
		us.append(0.3195)
		us.append(0.3205)
		us.sort()
	var rows := []
	for u in us:
		var h := deck_h(lay, u)
		var half := hb(lay, u, B)
		var ff := half / (B * 0.5)
		var kk := lerpf(1.8, 7.0, ff)
		var ys := [-D, -D * 0.85, -D * 0.6, -D * 0.3, 0.0, 0.7, h * 0.5, h]
		var row := []
		var rake := (h + D) * (0.42 if lay["hull"] != "cv" or lay["deck"].get("bow", "") != "enclosed" else 0.3)
		for y in ys:
			var w: float
			if y < 0.0:
				var v: float = (y + D) / D
				w = half * (1.0 - pow(1.0 - v, kk))
			else:
				var fl := 0.2 * maxf(0.0, 1.0 - u / 0.25) if u > 0.004 else 0.0
				w = half + B * 0.5 * fl * (y / maxf(h, 0.1))
			if lay.get("bulges", false) and u > 0.2 and u < 0.8 and y > -D * 0.7 and y < 1.0:
				w *= 1.07
			var zs: float = z_of(u, L) - rake * ((y + D) / (h + D)) * maxf(0.0, 1.0 - u / 0.05)
			row.append(Vector3(w, y, zs))
		rows.append(row)
	var mats_by_seg := ["bottom", "bottom", "bottom", "bottom", "boot", "hull", "hull"]
	for i in rows.size() - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		var zc: float = (r0[4].z + r1[4].z) * 0.5
		for j in 7:
			var m: String = mats_by_seg[j]
			var yc: float = (r0[j].y + r0[j + 1].y) * 0.5
			var inside := Vector3(0, yc, zc)
			for side in [1.0, -1.0]:
				var a := Vector3(r0[j].x * side, r0[j].y, r0[j].z)
				var b := Vector3(r1[j].x * side, r1[j].y, r1[j].z)
				var c := Vector3(r1[j + 1].x * side, r1[j + 1].y, r1[j + 1].z)
				var d := Vector3(r0[j + 1].x * side, r0[j + 1].y, r0[j + 1].z)
				k.quad(m, a, b, c, d, inside)
		var s0: Vector3 = r0[7]
		var s1: Vector3 = r1[7]
		k.quad("deck", Vector3(s0.x, s0.y, s0.z), Vector3(-s0.x, s0.y, s0.z), Vector3(-s1.x, s1.y, s1.z),
			Vector3(s1.x, s1.y, s1.z), Vector3(0, (s0.y + s1.y) * 0.5 - 2.0, (s0.z + s1.z) * 0.5))
	# Transom.
	var last: Array = rows[-1]
	for j in 7:
		var a: Vector3 = last[j]
		var b: Vector3 = last[j + 1]
		var m: String = mats_by_seg[j]
		k.quad(m, Vector3(a.x, a.y, a.z), Vector3(b.x, b.y, b.z), Vector3(-b.x, b.y, b.z), Vector3(-a.x, a.y, a.z),
			Vector3(0, (a.y + b.y) * 0.5, a.z - 3.0))
	# Bow anchors and a jack staff.
	var bz := z_of(0.03, L)
	var bh := deck_h(lay, 0.03)
	for side in [1.0, -1.0]:
		k.box("black", Vector3(side * hb(lay, 0.035, B) * 1.02, bh - 1.6, bz + 1.0), Vector3(0.15, 0.9, 0.9))
	k.cyl("metal", Vector3(0, bh, z_of(0.004, L) + 1.0), Vector3(0, bh + 4.0, z_of(0.004, L) + 1.0), 0.07, 0.05, 4)


# --------------------------------------------------------------- turrets
static func _turret(mats: Dictionary, t: Dictionary, lay: Dictionary, L: float) -> Node3D:
	var node := Node3D.new()
	var u: float = t["x"]
	var lift: float = t["lift"]
	node.position = Vector3(0, deck_h(lay, u) + lift, z_of(u, L))
	if int(t["dir"]) < 0:
		node.rotation.y = PI
	node.set_meta("dir", int(t["dir"]))
	var k := MeshKit.new(mats)
	var w: float = t["w"]
	var n: int = t["n"]
	var big := w >= 6.0
	var l := w * (1.25 if big else 1.1)
	var h := w * (0.33 if big else 0.45)
	k.cyl("super", Vector3(0, -lift - 0.3, 0), Vector3(0, 0.35, 0), w * 0.43, w * 0.43, 16)
	if big:
		k.hexa("super", [
			Vector3(-w * 0.42, 0.35, -l * 0.45), Vector3(w * 0.42, 0.35, -l * 0.45),
			Vector3(w * 0.5, 0.35, l * 0.5), Vector3(-w * 0.5, 0.35, l * 0.5),
			Vector3(-w * 0.36, 0.35 + h, -l * 0.30), Vector3(w * 0.36, 0.35 + h, -l * 0.30),
			Vector3(w * 0.46, 0.35 + h, l * 0.48), Vector3(-w * 0.46, 0.35 + h, l * 0.48)])
		k.box("metal", Vector3(0, 0.35 + h + 0.15, l * 0.15), Vector3(w * 0.5, 0.3, l * 0.3))
		if w >= 9.0:
			k.cyl("metal", Vector3(-w * 0.62, 0.35 + h * 0.75, l * 0.32), Vector3(w * 0.62, 0.35 + h * 0.75, l * 0.32), 0.45, 0.45, 8)
			for s in [-1.0, 1.0]:
				k.box("metal", Vector3(s * w * 0.6, 0.35 + h * 0.75, l * 0.32), Vector3(0.9, 1.2, 1.2))
	else:
		# Destroyer-style gunhouse with an open back.
		k.hexa("super", [
			Vector3(-w * 0.45, 0.35, -l * 0.42), Vector3(w * 0.45, 0.35, -l * 0.42),
			Vector3(w * 0.5, 0.35, l * 0.45), Vector3(-w * 0.5, 0.35, l * 0.45),
			Vector3(-w * 0.35, 0.35 + h, -l * 0.25), Vector3(w * 0.35, 0.35 + h, -l * 0.25),
			Vector3(w * 0.46, 0.35 + h, l * 0.40), Vector3(-w * 0.46, 0.35 + h, l * 0.40)])
	var mesh := MeshInstance3D.new()
	mesh.mesh = k.commit()
	node.add_child(mesh)
	# Barrels on an elevating cradle.
	var cradle := Node3D.new()
	cradle.name = "Cradle"
	cradle.position = Vector3(0, 0.35 + h * 0.45, -l * 0.30)
	node.add_child(cradle)
	var kb := MeshKit.new(mats)
	var bl: float = t["bl"]
	var rb := clampf(w * 0.032, 0.07, 0.5)
	var spacing := w * (0.3 if n == 3 else 0.36)
	for i in n:
		var x := 0.0 if n == 1 else (float(i) - (n - 1) * 0.5) * spacing
		kb.cyl("metal", Vector3(x, 0, 0.5), Vector3(x, 0, -bl * 0.25), rb * 1.5, rb * 1.25, 8)
		kb.cyl("metal", Vector3(x, 0, -bl * 0.25), Vector3(x, 0, -bl), rb * 1.05, rb * 0.85, 8)
		kb.cyl("metal", Vector3(x, 0, -bl + 0.4), Vector3(x, 0, -bl), rb * 1.05, rb * 1.05, 8, true, "black")
	var bm := MeshInstance3D.new()
	bm.mesh = kb.commit()
	cradle.add_child(bm)
	cradle.rotation.x = deg_to_rad(2.0)
	return node


# ------------------------------------------------------- superstructure
static func _super(k: MeshKit, lay: Dictionary, s: Dictionary, L: float, B: float) -> void:
	var u0: float = s["x0"]
	var u1: float = s["x1"]
	var um := (u0 + u1) * 0.5
	var y0 := deck_h(lay, um)
	var hgt: float = s["h"]
	var w: float = minf(B * float(s["wf"]), hb(lay, um, B) * 1.9)
	var z0 := z_of(u0, L)
	var z1 := z_of(u1, L)
	var zc := (z0 + z1) * 0.5
	var len := z1 - z0
	k.block("super", 0, zc, y0 - 0.2, y0 + hgt, w, len, w * 0.97, len * 0.98)
	# Scuttles along the sides and a platform lip on top.
	k.block("window", 0, zc, y0 + hgt - 1.1, y0 + hgt - 0.6, w * 0.975, len * 0.99, w * 0.975, len * 0.99)
	k.box("super", Vector3(0, y0 + hgt + 0.1, zc), Vector3(w + 0.6, 0.2, len + 0.6))
	# Ventilators.
	for i in 3:
		var z := z0 + len * (0.2 + 0.3 * i)
		for sx in [-1.0, 1.0]:
			k.cyl("metal", Vector3(sx * w * 0.35, y0 + hgt, z), Vector3(sx * w * 0.35, y0 + hgt + 1.2, z), 0.35, 0.35, 6)


static func _bridge_band(k: MeshKit, x: float, z: float, y: float, w: float, l: float) -> void:
	k.block("window", x, z, y, y + 0.8, w * 1.01, l * 1.01, w * 1.01, l * 1.01)


static func _rangefinder(k: MeshKit, c: Vector3, span: float) -> void:
	k.cyl("metal", c + Vector3(-span / 2, 0, 0), c + Vector3(span / 2, 0, 0), 0.45, 0.45, 8)
	k.box("metal", c + Vector3(0, -0.2, 0.3), Vector3(2.4, 1.6, 2.4))
	for s in [-1.0, 1.0]:
		k.box("metal", c + Vector3(s * span / 2, 0, 0), Vector3(0.7, 1.0, 1.0))


static func _tower(k: MeshKit, lay: Dictionary, t: Dictionary, L: float, B: float) -> void:
	var u: float = t["x"]
	var y0 := deck_h(lay, u) + 3.0
	var z := z_of(u, L)
	var H: float = t["h"]
	var w: float = t["w"]
	match t["type"]:
		"pagoda":
			var levels := 8
			for i in levels:
				var f := float(i) / levels
				var ya := y0 + H * f
				var yb := y0 + H * (f + 1.0 / levels) - 0.6
				var ww := w * (1.15 - 0.65 * f)
				var ll := w * (1.4 - 0.75 * f)
				k.block("super", 0, z + 1.0 * f, ya, yb, ww * 0.75, ll * 0.7, ww * 0.7, ll * 0.65)
				k.box("super", Vector3(0, yb + 0.1, z + 1.0 * f), Vector3(ww * 1.15, 0.2, ll))
				if i == levels - 3:
					_bridge_band(k, 0, z + 1.0 * f, ya + 0.6, ww * 0.75, ll * 0.7)
			for s in [-1.0, 1.0]:
				k.cyl("metal", Vector3(s * w * 0.3, y0, z + w * 0.3), Vector3(s * w * 0.12, y0 + H, z + 1.0), 0.35, 0.3, 6)
			_rangefinder(k, Vector3(0, y0 + H + 1.0, z + 1.0), w * 1.2)
		"tower_jp":
			k.block("super", 0, z, y0 - 3.0, y0 + H * 0.35, w * 1.4, w * 2.0, w * 1.0, w * 1.4, 0.8)
			k.block("super", 0, z + 0.8, y0 + H * 0.35, y0 + H * 0.8, w * 0.9, w * 1.3, w * 0.6, w * 0.9, 0.6)
			_bridge_band(k, 0, z + 0.9, y0 + H * 0.6, w * 0.78, w * 1.15)
			k.block("super", 0, z + 1.2, y0 + H * 0.8, y0 + H * 0.95, w * 0.55, w * 0.8, w * 0.45, w * 0.7)
			_rangefinder(k, Vector3(0, y0 + H + 0.4, z + 1.2), 15.0)
			for s in [-1.0, 1.0]:
				k.box("super", Vector3(s * w * 0.75, y0 + H * 0.45, z), Vector3(w * 0.5, 0.25, w * 0.8))
		"tower_de", "tower_rn":
			k.block("super", 0, z, y0 - 3.0, y0 + H * 0.35, w * 1.6, w * 2.0, w * 1.4, w * 1.6)
			_bridge_band(k, 0, z, y0 + H * 0.28, w * 1.42, w * 1.62)
			var segs := 8
			k.cyl("super", Vector3(0, y0 + H * 0.35, z + 0.5), Vector3(0, y0 + H * 0.85, z + 0.8), w * 0.45, w * 0.38, segs)
			k.box("super", Vector3(0, y0 + H * 0.65, z + 0.6), Vector3(w * 1.3, 0.25, w * 0.9))
			k.cyl("metal", Vector3(0, y0 + H * 0.85, z + 0.8), Vector3(0, y0 + H, z + 0.8), w * 0.32, w * 0.28, 10)
			_rangefinder(k, Vector3(0, y0 + H - 0.4, z + 0.8), w * 1.4)
			if t["type"] == "tower_rn":
				k.box("super", Vector3(0, y0 + H * 0.5, z - w * 0.6), Vector3(w * 1.6, 0.25, w * 0.8))
		"tripod_rn", "tripod_us", "tripod":
			k.block("super", 0, z, y0 - 3.0, y0 + H * 0.3, w * 1.5, w * 1.8, w * 1.3, w * 1.5)
			_bridge_band(k, 0, z, y0 + H * 0.22, w * 1.32, w * 1.52)
			k.box("super", Vector3(0, y0 + H * 0.3 + 0.1, z), Vector3(w * 1.6, 0.25, w * 1.8))
			_mast(k, "tripod", Vector3(0, y0 + H * 0.3, z + 0.5), H * 0.7, 0.0)
			k.block("super", 0, z + 0.5, y0 + H * 0.88, y0 + H, w * 0.9, w * 0.9, w * 0.85, w * 0.85)
			_bridge_band(k, 0, z + 0.5, y0 + H * 0.93, w * 0.86, w * 0.86)
		"block_us":
			k.block("super", 0, z, y0 - 3.0, y0 + H * 0.45, w * 1.4, w * 1.6, w * 1.2, w * 1.4)
			_bridge_band(k, 0, z, y0 + H * 0.36, w * 1.22, w * 1.42)
			k.block("super", 0, z + 0.4, y0 + H * 0.45, y0 + H * 0.7, w * 0.8, w * 0.9, w * 0.7, w * 0.8)
			k.box("metal", Vector3(0, y0 + H * 0.75, z + 0.4), Vector3(w * 0.6, 1.8, w * 0.7))
		"bridge_old":
			k.block("super", 0, z, y0 - 3.0, y0 + H * 0.45, w * 1.3, w * 1.4, w * 1.1, w * 1.2)
			_bridge_band(k, 0, z, y0 + H * 0.35, w * 1.12, w * 1.22)
			k.box("super", Vector3(0, y0 + H * 0.45, z), Vector3(w * 1.6, 0.25, w * 1.4))
		"bridge_dd":
			var y := deck_h(lay, u)
			k.block("super", 0, z, y - 0.2, y + H * 0.45, w * 1.0, w * 1.4, w * 0.95, w * 1.2, 0.3)
			_bridge_band(k, 0, z + 0.2, y + H * 0.35, w * 0.96, w * 1.22)
			k.block("super", 0, z + 0.4, y + H * 0.45, y + H * 0.62, w * 0.9, w * 1.0, w * 0.9, w * 1.0)
			k.box("metal", Vector3(0, y + H * 0.7, z + 0.6), Vector3(w * 0.45, 1.2, w * 0.45))
			k.cyl("metal", Vector3(-w * 0.4, y + H * 0.7, z + 0.8), Vector3(w * 0.4, y + H * 0.7, z + 0.8), 0.15, 0.15, 6)


# --------------------------------------------------------------- funnels
static func _funnel(k: MeshKit, lay: Dictionary, f: Dictionary, L: float, B: float, base: Vector3) -> Vector3:
	var r: float = f["r"]
	var h: float = f["h"]
	var rake := deg_to_rad(float(f["rake"]))
	var style: String = f["style"]
	var top := base + Vector3(0, h, h * tan(rake))
	match style:
		"jp_big":
			k.cyl("super", base, top, r * 1.05, r * 0.9, 14, false, "", 1.5)
			k.cyl("metal", top - Vector3(0, 0.5, 0), top + Vector3(0, 0.6, 0.3), r * 0.92, r * 0.92, 14, true, "black", 1.5)
		"us_trunk":
			k.block("super", base.x, base.z, base.y, top.y, r * 1.2, r * 2.6, r * 1.1, r * 2.4)
			k.block("black", base.x, base.z, top.y, top.y + 0.3, r * 1.1, r * 2.4, r * 1.1, r * 2.4)
		"jp_out":
			top = base + Vector3(h * tan(rake), h * 0.85, 0)
			k.cyl("super", base, top, r * 1.1, r * 0.95, 12, true, "black", 1.6)
		_:
			var stretch := 1.6 if style == "jp_trunk" else 1.35
			k.cyl("super", base, top, r, r * 0.95, 12, false, "", stretch)
			k.cyl("black", top - Vector3(0, 0.9, 0), top + Vector3(0, 0.05, 0), r * 0.97, r * 0.97, 12, true, "black", stretch)
			if style == "cap":
				k.cyl("metal", top + Vector3(0, 0.4, 0), top + Vector3(0, 0.7, 0), r * 1.25, r * 1.25, 12, true, "", stretch)
			for s in [-1.0, 1.0]:
				k.cyl("metal", base + Vector3(s * r * 0.9, h * 0.6, 0), top + Vector3(s * r * 0.85, 0.5, -r * 0.2), 0.08, 0.08, 4, false)
	return top


static func _mast(k: MeshKit, type: String, base: Vector3, h: float, yard: float) -> void:
	if type == "tripod":
		var apex := base + Vector3(0, h, 0)
		k.cyl("super", base + Vector3(0, 0, -1.0), apex, 0.45, 0.3, 6, false)
		for s in [-1.0, 1.0]:
			k.cyl("super", base + Vector3(s * h * 0.12, 0, h * 0.14), apex, 0.35, 0.25, 6, false)
		k.box("super", apex + Vector3(0, 0.6, 0), Vector3(3.0, 1.6, 3.0))
		k.cyl("metal", apex + Vector3(0, 1.4, 0), apex + Vector3(0, 6.0, 0), 0.15, 0.08, 4)
		if yard > 0.0:
			k.cyl("metal", apex + Vector3(-yard, -2.0, 0), apex + Vector3(yard, -2.0, 0), 0.1, 0.1, 4, false)
	else:
		k.cyl("super", base, base + Vector3(0, h, 0), 0.4, 0.15, 6)
		var yy := base + Vector3(0, h * 0.72, 0)
		var yw := maxf(yard, 3.0)
		k.cyl("metal", yy + Vector3(-yw, 0, 0), yy + Vector3(yw, 0, 0), 0.12, 0.12, 4, false)
		k.box("super", base + Vector3(0, h * 0.5, 0), Vector3(1.6, 0.2, 1.6))


# ------------------------------------------------------------- fittings
static func _tubes(k: MeshKit, base: Vector3) -> void:
	k.cyl("metal", base, base + Vector3(0, 0.6, 0), 1.4, 1.4, 10)
	for i in 4:
		var x := (float(i) - 1.5) * 0.65
		k.cyl("metal", base + Vector3(x, 1.0, 3.6), base + Vector3(x, 1.0, -3.6), 0.3, 0.3, 6, true, "black")
	k.box("super", base + Vector3(0, 1.0, 2.4), Vector3(2.8, 1.0, 1.2))


static func _dc_racks(k: MeshKit, lay: Dictionary, L: float, B: float) -> void:
	var u := 0.975
	var y := deck_h(lay, u)
	var z := z_of(u, L) - 2.0
	for s in [-1.0, 1.0]:
		var x: float = s * hb(lay, u, B) * 0.55
		k.box("metal", Vector3(x, y + 0.4, z), Vector3(0.9, 0.2, 5.0))
		for i in 5:
			k.cyl("black", Vector3(x - 0.35, y + 0.85, z - 2.0 + i), Vector3(x + 0.35, y + 0.85, z - 2.0 + i), 0.3, 0.3, 8)
	for s in [-1.0, 1.0]:
		var zz := z_of(0.88, L)
		k.cyl("metal", Vector3(s * hb(lay, 0.88, B) * 0.7, y, zz), Vector3(s * hb(lay, 0.88, B) * 0.7, y + 1.2, zz - 0.6), 0.25, 0.25, 6)


static func _boats(k: MeshKit, lay: Dictionary, L: float, B: float) -> void:
	for i in 2:
		var u := 0.52 + 0.06 * i
		var y := deck_h(lay, u) + 3.2
		for s in [-1.0, 1.0]:
			var x: float = s * hb(lay, u, B) * 0.62
			var z := z_of(u, L)
			k.hexa("boat", [Vector3(x - 0.9, y, z - 4.0), Vector3(x + 0.9, y, z - 4.0), Vector3(x + 1.0, y, z + 4.5),
				Vector3(x - 1.0, y, z + 4.5), Vector3(x - 1.1, y + 1.2, z - 5.0), Vector3(x + 1.1, y + 1.2, z - 5.0),
				Vector3(x + 1.2, y + 1.2, z + 4.8), Vector3(x - 1.2, y + 1.2, z + 4.8)])
			k.cyl("metal", Vector3(x, y - 3.2, z - 3.5), Vector3(x, y + 2.0, z - 3.5), 0.15, 0.15, 4, false)
			k.cyl("metal", Vector3(x, y - 3.2, z + 3.5), Vector3(x, y + 2.0, z + 3.5), 0.15, 0.15, 4, false)


static func _catapult(k: MeshKit, lay: Dictionary, u: float, L: float) -> void:
	var y := deck_h(lay, u) + 1.5
	var z := z_of(u, L)
	var b := Basis(Vector3.UP, deg_to_rad(30.0))
	k.cyl("metal", Vector3(0, y - 1.5, z), Vector3(0, y - 0.4, z), 1.0, 1.0, 10)
	k.box("metal", Vector3(0, y, z), Vector3(1.2, 0.8, 19.0), b)
	PlaneBuilder.add_simple(k, Transform3D(b, Vector3(0, y + 1.2, z)), "float", 12.0, 11.0, "plane")


static func _aa(k: MeshKit, lay: Dictionary, n: int, L: float, B: float) -> void:
	if n <= 0:
		return
	var turret_us := []
	for t in lay.get("turrets", []):
		turret_us.append(float(t["x"]))
	var placed := 0
	var u := 0.28
	var side := 1.0
	var tries := 0
	while placed < n and tries < 200:
		tries += 1
		u += 0.44 / maxf(1.0, n * 0.5)
		if u > 0.74:
			u = 0.28 + 0.01 * tries
		var clash := false
		for tu in turret_us:
			if absf(tu - u) < 0.035:
				clash = true
		if clash:
			continue
		var y := deck_h(lay, u)
		if lay["hull"] == "cv":
			y = float(lay["deck"]["h"]) - 1.6
		var half := hb(lay, u, B)
		if lay["hull"] == "cv":
			half = float(lay["deck"]["w"]) * 0.5
		var x := side * (half - 1.2)
		var z := z_of(u, L)
		k.cyl("super", Vector3(x, y, z), Vector3(x, y + 0.9, z), 1.3, 1.3, 10)
		k.box("metal", Vector3(x, y + 1.3, z), Vector3(0.9, 0.7, 1.2))
		for b in [-0.18, 0.18]:
			k.cyl("metal", Vector3(x + b, y + 1.4, z), Vector3(x + b, y + 3.0, z - 2.4), 0.06, 0.05, 4, false)
		side = -side
		placed += 1


# --------------------------------------------------------------- carriers
static func _carrier(k: MeshKit, lay: Dictionary, L: float, B: float) -> Array:
	var d: Dictionary = lay["deck"]
	var dh: float = d["h"]
	var x0: float = d["x0"]
	var x1: float = d["x1"]
	var dw: float = d["w"]
	var enclosed: bool = d.get("bow", "open") == "enclosed"
	var hx0 := 0.0 if enclosed else x0 + 0.07
	var hx1 := minf(x1, 0.93)
	# Hangar following the hull's plan shape.
	var poly := []
	var steps := 18
	for i in steps + 1:
		var u := lerpf(hx0, hx1, float(i) / steps)
		poly.append(Vector2(maxf(hb(lay, u, B) * 0.98, 0.3), z_of(u, L)))
	for i in range(steps, -1, -1):
		var u := lerpf(hx0, hx1, float(i) / steps)
		poly.append(Vector2(-maxf(hb(lay, u, B) * 0.98, 0.3), z_of(u, L)))
	k.prism("hull", poly, float(lay["fb"]) - 0.5, dh - 0.4)
	if not enclosed:
		for i in 6:
			var u := hx0 + 0.08 + i * (hx1 - hx0 - 0.16) / 5.0
			for s in [-1.0, 1.0]:
				k.box("black", Vector3(s * hb(lay, u, B) * 0.985, (float(lay["fb"]) + dh) * 0.5, z_of(u, L)),
					Vector3(0.2, (dh - float(lay["fb"])) * 0.55, L * 0.05))
	# Flight deck plate with rounded-off ends.
	var fz0 := z_of(x0, L)
	var fz1 := z_of(x1, L)
	var fd := []
	var nseg := 10
	for i in nseg + 1:
		var f := float(i) / nseg
		var z := lerpf(fz0, fz1, f)
		var taper := 1.0
		if f < 0.12:
			taper = lerpf(0.45, 1.0, f / 0.12)
		elif f > 0.92:
			taper = lerpf(1.0, 0.75, (f - 0.92) / 0.08)
		fd.append(Vector2(dw * 0.5 * taper, z))
	for i in range(nseg, -1, -1):
		var f := float(i) / nseg
		var z := lerpf(fz0, fz1, f)
		var taper := 1.0
		if f < 0.12:
			taper = lerpf(0.45, 1.0, f / 0.12)
		elif f > 0.92:
			taper = lerpf(1.0, 0.75, (f - 0.92) / 0.08)
		fd.append(Vector2(-dw * 0.5 * taper, z))
	k.prism("metal", fd, dh - 0.4, dh, "flight")
	# Markings.
	var mark := "white"
	var z := fz0 + 8.0
	while z < fz1 - 10.0:
		k.box(mark, Vector3(0, dh + 0.03, z), Vector3(0.5, 0.04, 5.0))
		z += 10.0
	for s in [-1.0, 1.0]:
		k.box(mark, Vector3(s * (dw * 0.5 - 1.2), dh + 0.03, (fz0 + fz1) * 0.5), Vector3(0.3, 0.04, (fz1 - fz0) * 0.8))
	for e in [0.3, 0.55, 0.8]:
		k.box("black", Vector3(0, dh + 0.02, z_of(lerpf(x0, x1, e), L)), Vector3(dw * 0.4, 0.03, dw * 0.4))
	if lay["paint"].begins_with("jp"):
		k.cyl("red", Vector3(0, dh + 0.02, fz1 - 18.0), Vector3(0, dh + 0.06, fz1 - 18.0), 4.0, 4.0, 18)
		k.cyl("white", Vector3(0, dh + 0.01, fz1 - 18.0), Vector3(0, dh + 0.05, fz1 - 18.0), 4.8, 4.8, 18)
	if not enclosed:
		for i in 4:
			var u := lerpf(x0, hx0, float(i) / 3.0)
			for s in [-1.0, 1.0]:
				k.cyl("metal", Vector3(s * hb(lay, u, B) * 0.5, deck_h(lay, u), z_of(u, L)),
					Vector3(s * hb(lay, u, B) * 0.5, dh - 0.4, z_of(u, L)), 0.3, 0.3, 6, false)
	if d.get("flyoff", false):
		var fz := z_of(0.02, L)
		k.prism("flight", [Vector2(7, fz), Vector2(10, z_of(x0, L)), Vector2(-10, z_of(x0, L)), Vector2(-7, fz)],
			float(lay["fb"]) + 1.0, float(lay["fb"]) + 1.6)
	# Gun sponsons below the deck edge.
	for i in 6:
		var u := 0.15 + i * 0.14
		for s in [-1.0, 1.0]:
			k.cyl("super", Vector3(s * (dw * 0.5 + 0.8), dh - 2.4, z_of(u, L)), Vector3(s * (dw * 0.5 + 0.8), dh - 1.4, z_of(u, L)), 1.8, 1.8, 10)
			for b in [-0.3, 0.3]:
				k.cyl("metal", Vector3(s * (dw * 0.5 + 0.8) + b, dh - 1.2, z_of(u, L)),
					Vector3(s * (dw * 0.5 + 0.8) + b, dh - 0.2, z_of(u, L) - 3.0), 0.09, 0.08, 4, false)
	var tops := []
	# Island on the starboard deck edge.
	if lay.has("island"):
		var isl: Dictionary = lay["island"]
		var iz := z_of(isl["x"], L)
		var il: float = isl["l"]
		var iw: float = isl["w"]
		var ih: float = isl["h"]
		var ix := dw * 0.5 - iw * 0.5 - 0.3
		k.block("super", ix, iz, dh, dh + ih * 0.55, iw, il, iw * 0.95, il * 0.9)
		k.block("super", ix, iz - il * 0.15, dh + ih * 0.55, dh + ih, iw * 0.85, il * 0.45, iw * 0.8, il * 0.4)
		_bridge_band(k, ix, iz - il * 0.15, dh + ih * 0.78, iw * 0.86, il * 0.46)
		k.box("super", Vector3(ix, dh + ih * 0.55, iz - il * 0.15), Vector3(iw * 1.4, 0.25, il * 0.6))
		if isl.has("funnel"):
			var f: Dictionary = isl["funnel"]
			tops.append(_funnel(k, lay, f, L, B, Vector3(ix + (iw * 0.3 if f["style"] == "jp_out" else 0.0), dh + ih * 0.5, iz + il * 0.2)))
		if isl.get("tripod", false):
			_mast(k, "tripod", Vector3(ix, dh + ih, iz - il * 0.05), 12.0, 4.0)
			k.box("metal", Vector3(ix, dh + ih + 13.0, iz - il * 0.05), Vector3(4.5, 2.6, 0.3))
		else:
			_mast(k, "pole", Vector3(ix, dh + ih, iz - il * 0.1), 10.0, 3.0)
	if lay.has("side_funnels"):
		var u: float = lay["side_funnels"]
		for i in 2:
			var zf := z_of(u + i * 0.03, L)
			var b0 := Vector3(hb(lay, u, B), dh - 4.0, zf)
			var b1 := b0 + Vector3(4.0, -2.5, 0)
			k.cyl("super", b0, b1, 1.6, 1.4, 10, true, "black")
			tops.append(b1)
	# Parked aircraft spotted aft.
	var n := int(lay.get("planes", 0))
	for i in n:
		var row := i / 3
		var col := i % 3
		var pz := fz1 - 14.0 - row * 13.0
		var px := (col - 1) * 9.0
		PlaneBuilder.add_simple(k, Transform3D(Basis.IDENTITY, Vector3(px, dh + 1.4, pz)), "single", 12.0, 10.0, "plane")
	return tops
