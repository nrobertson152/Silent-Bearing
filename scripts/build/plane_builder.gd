## Aircraft models: fuselage or flying-boat hull, tapered wings, tail,
## engine nacelles with spinning propellers, floats and national markings;
## and for the near future, carrier jets and anti-submarine helicopters.
## Model space: nose toward -Z, right wing +X.

const MeshKit := preload("res://scripts/build/mesh_kit.gd")


static func materials(nation: String) -> Dictionary:
	var body := Color(0.36, 0.43, 0.50)
	match nation:
		"jp":
			body = Color(0.30, 0.37, 0.27)
		"cn":
			body = Color(0.55, 0.58, 0.6)
		"uk":
			body = Color(0.42, 0.43, 0.38)
		"de":
			body = Color(0.40, 0.43, 0.40)
	var prop := MeshKit.mat(Color(0.1, 0.1, 0.1, 0.35), 0.5)
	prop.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return {
		"plane": MeshKit.mat(body, 0.65, 0.1),
		"under": MeshKit.mat(body.lightened(0.35), 0.65, 0.1),
		"glass": MeshKit.mat(Color(0.12, 0.16, 0.2), 0.1, 0.3),
		"black": MeshKit.mat(Color(0.05, 0.05, 0.05), 0.6),
		"white": MeshKit.mat(Color(0.9, 0.9, 0.88), 0.7),
		"red": MeshKit.mat(Color(0.75, 0.1, 0.1), 0.7),
		"blue": MeshKit.mat(Color(0.12, 0.18, 0.45), 0.7),
		"prop": prop,
	}


static func build(info: Dictionary, nation: String) -> Node3D:
	if info["kind"] == "helo":
		return _helo(info, nation)
	var mats := materials(nation)
	var root := Node3D.new()
	var k := MeshKit.new(mats)
	var span: float = info["span"]
	var length: float = info["len"]
	var props := _parts(k, Transform3D.IDENTITY, info["kind"], span, length, "plane", int(info["engines"]))
	_markings(k, nation, span, length, info["kind"])
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	root.add_child(mi)
	var prop_nodes := []
	for p in props:
		var pn := Node3D.new()
		pn.position = p
		var pk := MeshKit.new(mats)
		var pr := span * 0.06 if int(info["engines"]) > 1 else span * 0.11
		pk.cyl("prop", Vector3(0, 0, 0), Vector3(0, 0, -0.08), pr, pr, 16)
		pk.box("black", Vector3.ZERO, Vector3(pr * 2.0, 0.15, 0.1))
		var pm := MeshInstance3D.new()
		pm.mesh = pk.commit()
		pn.add_child(pm)
		root.add_child(pn)
		prop_nodes.append(pn)
	root.set_meta("props", prop_nodes)
	return root


## Adds a static aircraft into an existing mesh (parked planes, catapult floatplanes).
static func add_simple(k: MeshKit, xf: Transform3D, kind: String, span: float, length: float, mat: String) -> void:
	_parts(k, xf, kind, span, length, mat, 1)


static func _parts(k: MeshKit, xf: Transform3D, kind: String, span: float, length: float, mat: String, engines: int) -> Array:
	if kind == "jet":
		_jet(k, xf, span, length, mat)
		return []
	var props := []
	var r := length * 0.06
	var nose := -length * 0.45
	var tail := length * 0.55
	var wing_y := -r * 0.5
	var wing_z := nose + length * 0.30
	var boat := kind.begins_with("boat")
	# Fuselage or flying-boat hull.
	if boat:
		r = length * 0.075
		k.hexa(mat, _x(xf, [Vector3(-r * 0.6, -r * 1.6, nose + 1.0), Vector3(r * 0.6, -r * 1.6, nose + 1.0),
			Vector3(r * 0.2, -r * 0.8, tail - 2.0), Vector3(-r * 0.2, -r * 0.8, tail - 2.0),
			Vector3(-r, r, nose), Vector3(r, r, nose), Vector3(r * 0.35, r * 0.6, tail), Vector3(-r * 0.35, r * 0.6, tail)]))
		wing_y = r * 1.2
		if kind == "boat_parasol":
			wing_y = r * 3.0
			k.box(mat, xf * Vector3(0, r * 1.9, wing_z + 1.0), Vector3(r * 0.7, r * 2.2, length * 0.18), xf.basis)
	else:
		k.cyl(mat, xf * Vector3(0, 0, nose), xf * Vector3(0, 0, wing_z + length * 0.1), r * 0.95, r, 10)
		k.cyl(mat, xf * Vector3(0, 0, wing_z + length * 0.1), xf * Vector3(0, r * 0.3, tail), r, r * 0.25, 10)
		if kind == "mpa":
			# A high wing over the cabin, a radome under the nose and a
			# magnetic-anomaly boom sticking out behind the tail.
			wing_y = r * 0.85
			k.sphere("black", xf * Vector3(0, -r * 0.75, nose + length * 0.12), r * 0.7, 10, 6)
			k.cyl(mat, xf * Vector3(0, r * 0.3, tail - 0.5), xf * Vector3(0, r * 0.3, tail + length * 0.12), r * 0.2, r * 0.08, 8)
	# Canopy.
	k.box("glass", xf * Vector3(0, r * (1.0 if not boat else 0.95), nose + length * (0.22 if not boat else 0.12)),
		Vector3(r * 0.9, r * 0.7, length * 0.16), xf.basis)
	# Wings.
	var c0 := span * 0.16
	var c1 := span * 0.08
	var th := maxf(0.25, span * 0.012)
	var wings := [wing_y]
	if kind == "biplane":
		wings = [-r * 0.6, r * 1.8]
	for wy in wings:
		k.hexa(mat, _x(xf, [Vector3(-span / 2, wy - th, wing_z - c1 / 2), Vector3(span / 2, wy - th, wing_z - c1 / 2),
			Vector3(span / 2, wy - th, wing_z + c1 / 2), Vector3(-span / 2, wy - th, wing_z + c1 / 2),
			Vector3(-span / 2, wy, wing_z - c1 / 2), Vector3(span / 2, wy, wing_z - c1 / 2),
			Vector3(span / 2, wy, wing_z + c1 / 2), Vector3(-span / 2, wy, wing_z + c1 / 2)]))
		k.hexa(mat, _x(xf, [Vector3(-span * 0.22, wy - th * 1.3, wing_z - c0 / 2), Vector3(span * 0.22, wy - th * 1.3, wing_z - c0 / 2),
			Vector3(span * 0.22, wy - th * 1.3, wing_z + c0 / 2), Vector3(-span * 0.22, wy - th * 1.3, wing_z + c0 / 2),
			Vector3(-span * 0.22, wy, wing_z - c0 / 2), Vector3(span * 0.22, wy, wing_z - c0 / 2),
			Vector3(span * 0.22, wy, wing_z + c0 / 2), Vector3(-span * 0.22, wy, wing_z + c0 / 2)]))
	if kind == "biplane":
		for s in [-1.0, 1.0]:
			for dz in [-0.3, 0.3]:
				k.cyl("black", xf * Vector3(s * span * 0.33, -r * 0.6, wing_z + dz * c1), xf * Vector3(s * span * 0.33, r * 1.8, wing_z + dz * c1), 0.05, 0.05, 4, false)
	# Tail surfaces.
	var hs := span * 0.33
	k.hexa(mat, _x(xf, [Vector3(-hs / 2, r * 0.2, tail - length * 0.12), Vector3(hs / 2, r * 0.2, tail - length * 0.08),
		Vector3(hs / 2, r * 0.2, tail - 0.3), Vector3(-hs / 2, r * 0.2, tail - 0.3),
		Vector3(-hs / 2, r * 0.32, tail - length * 0.12), Vector3(hs / 2, r * 0.32, tail - length * 0.08),
		Vector3(hs / 2, r * 0.32, tail - 0.3), Vector3(-hs / 2, r * 0.32, tail - 0.3)]))
	var fh := length * 0.17
	k.hexa(mat, _x(xf, [Vector3(-0.12, r * 0.3, tail - length * 0.16), Vector3(0.12, r * 0.3, tail - length * 0.16),
		Vector3(0.12, r * 0.3, tail), Vector3(-0.12, r * 0.3, tail),
		Vector3(-0.08, r * 0.3 + fh, tail - length * 0.06), Vector3(0.08, r * 0.3 + fh, tail - length * 0.06),
		Vector3(0.08, r * 0.3 + fh, tail - 0.4), Vector3(-0.08, r * 0.3 + fh, tail - 0.4)]))
	# Engines.
	if engines <= 1:
		k.cyl("black", xf * Vector3(0, 0, nose - 0.4), xf * Vector3(0, 0, nose + length * 0.08), r * 1.05, r * 1.05, 12)
		props.append(Vector3(0, 0, nose - 0.5))
	else:
		var xs := [-0.2, 0.2] if engines == 2 else [-0.34, -0.16, 0.16, 0.34]
		for f in xs:
			var x: float = f * span
			var ny := wing_y - th * 0.5
			k.cyl(mat, xf * Vector3(x, ny, wing_z - c0 * 0.9), xf * Vector3(x, ny, wing_z + c0 * 0.6), span * 0.022, span * 0.016, 10)
			k.cyl("black", xf * Vector3(x, ny, wing_z - c0 * 0.95), xf * Vector3(x, ny, wing_z - c0 * 0.7), span * 0.024, span * 0.024, 10)
			props.append(Vector3(x, ny, wing_z - c0 * 1.0))
	# Floats.
	if kind == "float":
		for s in [-1.0, 1.0]:
			k.cyl(mat, xf * Vector3(s * span * 0.16, -r * 3.2, nose + 0.5), xf * Vector3(s * span * 0.16, -r * 3.2, wing_z + length * 0.25), r * 0.55, r * 0.35, 8)
			k.cyl("black", xf * Vector3(s * span * 0.16, -r * 3.0, wing_z - 0.5), xf * Vector3(s * span * 0.16, wing_y, wing_z - 0.5), 0.06, 0.06, 4, false)
	if boat:
		for s in [-1.0, 1.0]:
			var fx: float = s * span * 0.42
			k.cyl(mat, xf * Vector3(fx, wing_y - 3.0, wing_z - 1.2), xf * Vector3(fx, wing_y - 3.0, wing_z + 1.5), 0.45, 0.3, 8)
			k.cyl("black", xf * Vector3(fx, wing_y - 2.8, wing_z), xf * Vector3(fx, wing_y, wing_z), 0.06, 0.06, 4, false)
	return props


## A carrier fighter parked with its wings folded: slim fuselage, chined
## nose, swept wings, twin fins and stabilators.
static func _jet(k: MeshKit, xf: Transform3D, span: float, length: float, mat: String) -> void:
	var r := length * 0.045
	var nose := -length * 0.5
	var tail := length * 0.5
	k.cyl(mat, xf * Vector3(0, 0, nose), xf * Vector3(0, 0, nose + length * 0.18), 0.05, r * 0.85, 10)
	k.cyl(mat, xf * Vector3(0, 0, nose + length * 0.18), xf * Vector3(0, 0, tail - 1.0), r * 0.85, r * 1.1, 10)
	k.cyl("black", xf * Vector3(0, 0, tail - 1.0), xf * Vector3(0, 0, tail), r * 0.9, r * 0.8, 10)
	k.box("glass", xf * Vector3(0, r * 0.75, nose + length * 0.22), Vector3(r * 0.8, r * 0.6, length * 0.12), xf.basis)
	# Folded wings: the inner panels only, with the tips standing up.
	var wz := nose + length * 0.55
	var wi := span * 0.28
	for sd in [-1.0, 1.0]:
		var s: float = sd
		k.hexa(mat, _x(xf, [Vector3(s * r, 0, wz - length * 0.12), Vector3(s * wi, 0, wz), Vector3(s * wi, 0, wz + length * 0.12),
			Vector3(s * r, 0, wz + length * 0.16), Vector3(s * r, 0.15, wz - length * 0.12), Vector3(s * wi, 0.15, wz),
			Vector3(s * wi, 0.15, wz + length * 0.12), Vector3(s * r, 0.15, wz + length * 0.16)]))
		k.box(mat, xf * Vector3(s * wi, span * 0.1, wz + length * 0.06), Vector3(0.15, span * 0.2, length * 0.11), xf.basis)
		# Fins and stabilators.
		k.box(mat, xf * Vector3(s * r * 0.9, r + length * 0.06, tail - length * 0.1), Vector3(0.12, length * 0.13, length * 0.13),
			xf.basis * Basis(Vector3(0, 0, 1), s * 0.25))
		k.box(mat, xf * Vector3(s * (r + span * 0.08), 0, tail - length * 0.06), Vector3(span * 0.16, 0.12, length * 0.1), xf.basis)


## An anti-submarine helicopter: cabin, tail boom and fin, wheels, a sonar
## and torpedo station, and rotors on their own nodes so they can turn.
static func _helo(info: Dictionary, nation: String) -> Node3D:
	var mats := materials(nation)
	var root := Node3D.new()
	var k := MeshKit.new(mats)
	var span: float = info["span"]
	var length: float = info["len"]
	var cab := length * 0.42
	var w := 2.3
	var h := 2.2
	# Cabin: a rounded box with a sloped nose and glazing.
	k.block("plane", 0, -length * 0.12, -h * 0.5, h * 0.5, w, cab, w * 0.9, cab * 0.92, -0.2)
	k.block("glass", 0, -length * 0.12 - cab * 0.5 - 0.6, -h * 0.25, h * 0.35, w * 0.86, 1.4, w * 0.7, 0.4, 0.4)
	k.block("plane", 0, -length * 0.06, h * 0.5, h * 0.5 + 0.8, w * 0.7, cab * 0.55, w * 0.6, cab * 0.45)
	# Tail boom, fin and stabilizer.
	k.cyl("plane", Vector3(0, h * 0.2, length * 0.08), Vector3(0, h * 0.45, length * 0.5), 0.75, 0.35, 10)
	k.block("plane", 0, length * 0.52, h * 0.3, h * 0.3 + 2.4, 0.3, 1.8, 0.25, 1.2, 0.5)
	k.box("plane", Vector3(0.6, h * 0.5, length * 0.48), Vector3(2.4, 0.12, 0.8))
	# Wheels and the torpedo carried on the side.
	for s in [-1.0, 1.0]:
		k.cyl("black", Vector3(s * w * 0.6, -h * 0.75, -length * 0.02), Vector3(s * w * 0.66, -h * 0.75, -length * 0.02), 0.35, 0.35, 8)
		k.cyl("white", Vector3(s * (w * 0.5 + 0.35), -h * 0.2, -length * 0.25), Vector3(s * (w * 0.5 + 0.35), -h * 0.2, -length * 0.25 + 2.6), 0.16, 0.16, 8)
	k.cyl("black", Vector3(0, -h * 0.5, -length * 0.25), Vector3(0, -h * 0.75, -length * 0.25), 0.1, 0.1, 6)
	_markings_helo(k, nation, w, h, length)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	root.add_child(mi)
	# Main rotor: four blades on a hub, turning about the vertical.
	var rotor := Node3D.new()
	rotor.position = Vector3(0, h * 0.5 + 1.2, -length * 0.08)
	var rk := MeshKit.new(mats)
	rk.cyl("black", Vector3(0, -0.4, 0), Vector3(0, 0.25, 0), 0.35, 0.3, 8)
	for i in 4:
		var a := TAU * i / 4.0
		var b := Basis(Vector3.UP, a)
		rk.box("black", b * Vector3(span * 0.25, 0, 0), Vector3(span * 0.5, 0.08, 0.5), b)
	var rm := MeshInstance3D.new()
	rm.mesh = rk.commit()
	rotor.add_child(rm)
	root.add_child(rotor)
	var tail_r := Node3D.new()
	tail_r.position = Vector3(0.35, h * 0.3 + 1.6, length * 0.53)
	var tk := MeshKit.new(mats)
	for i in 4:
		var b := Basis(Vector3.RIGHT, TAU * i / 4.0)
		tk.box("black", b * Vector3(0, 0.75, 0), Vector3(0.05, 1.5, 0.25), b)
	var tm := MeshInstance3D.new()
	tm.mesh = tk.commit()
	tail_r.add_child(tm)
	root.add_child(tail_r)
	root.set_meta("props", [])
	root.set_meta("rotors", [rotor, tail_r])
	return root


static func _markings_helo(k: MeshKit, nation: String, w: float, h: float, length: float) -> void:
	if nation != "cn":
		return
	# A red star roundel on each side of the tail boom.
	for s in [-1.0, 1.0]:
		var c := Vector3(s * 0.62, h * 0.3, length * 0.22)
		k.cyl("red", c, c + Vector3(s * 0.03, 0, 0), 0.55, 0.55, 12)
		k.cyl("white", c + Vector3(s * 0.035, 0, 0), c + Vector3(s * 0.05, 0, 0), 0.25, 0.25, 5)


static func _markings(k: MeshKit, nation: String, span: float, length: float, kind: String) -> void:
	var r := length * (0.075 if kind.begins_with("boat") else 0.06)
	var wy := r * 1.2 if kind.begins_with("boat") else -r * 0.5
	if kind == "boat_parasol":
		wy = r * 3.0
	if kind == "biplane":
		wy = r * 1.8
	var wz := -length * 0.45 + length * 0.30
	for s in [-1.0, 1.0]:
		var c := Vector3(s * span * 0.38, wy + 0.02, wz)
		var cr := span * 0.035
		match nation:
			"jp":
				k.cyl("red", c, c + Vector3(0, 0.03, 0), cr, cr, 14)
			"us":
				k.cyl("white", c, c + Vector3(0, 0.03, 0), cr, cr, 14)
				k.cyl("blue", c + Vector3(0, 0.035, 0), c + Vector3(0, 0.05, 0), cr * 0.45, cr * 0.45, 10)
			"uk":
				k.cyl("blue", c, c + Vector3(0, 0.03, 0), cr, cr, 14)
				k.cyl("red", c + Vector3(0, 0.035, 0), c + Vector3(0, 0.05, 0), cr * 0.45, cr * 0.45, 10)
			"de":
				k.box("white", c + Vector3(0, 0.02, 0), Vector3(cr * 1.6, 0.03, cr * 0.5))
				k.box("white", c + Vector3(0, 0.02, 0), Vector3(cr * 0.5, 0.03, cr * 1.6))
				k.box("black", c + Vector3(0, 0.04, 0), Vector3(cr * 1.2, 0.03, cr * 0.25))
				k.box("black", c + Vector3(0, 0.04, 0), Vector3(cr * 0.25, 0.03, cr * 1.2))


static func _x(xf: Transform3D, pts: Array) -> Array:
	var out := []
	for p in pts:
		out.append(xf * p)
	return out
