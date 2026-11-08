## Aircraft models: fuselage or flying-boat hull, tapered wings, tail,
## engine nacelles with spinning propellers, floats and national markings.
## Model space: nose toward -Z, right wing +X.

const MeshKit := preload("res://scripts/build/mesh_kit.gd")


static func materials(nation: String) -> Dictionary:
	var body := Color(0.36, 0.43, 0.50)
	match nation:
		"jp":
			body = Color(0.30, 0.37, 0.27)
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
