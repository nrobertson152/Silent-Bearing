## Your boat's exterior: hull and casing, conning tower, periscopes, deck gun
## and AA mount on traversing nodes, hydroplanes, screws, jumping wires and
## class-specific details (Gato shears, Type VII wintergarten, I-boat hangar).
## Model space: bow toward -Z, waterline at y = 0 when surfaced.

const MeshKit := preload("res://scripts/build/mesh_kit.gd")
const ModernSubBuilder := preload("res://scripts/build/modern_sub_builder.gd")
const Paint := preload("res://scripts/build/paint.gd")


static func materials(nation: String, length := 80.0) -> Dictionary:
	var hull := Color(0.12, 0.13, 0.14)
	var deck := Color(0.20, 0.20, 0.21)
	match nation:
		"de":
			hull = Color(0.38, 0.40, 0.42)
			deck = Color(0.33, 0.30, 0.26)
		"uk":
			hull = Color(0.17, 0.18, 0.19)
			deck = Color(0.24, 0.24, 0.24)
		"jp":
			hull = Color(0.09, 0.09, 0.10)
			deck = Color(0.30, 0.25, 0.20)
	var painted := Paint.sub(nation, hull, deck, length)
	return {
		"hull": painted["hull"],
		"deck": painted["deck"],
		"bottom": painted["bottom"],
		"metal": painted["metal"],
		"gun": MeshKit.mat(Color(0.22, 0.23, 0.24) if nation != "de" else Color(0.40, 0.42, 0.44), 0.5, 0.5),
		"black": MeshKit.mat(Color(0.03, 0.03, 0.03), 0.9),
		"glass": MeshKit.mat(Color(0.2, 0.25, 0.3), 0.05, 0.4),
		"brass": MeshKit.mat(Color(0.55, 0.45, 0.25), 0.35, 0.8),
		"plane": MeshKit.mat(Color(0.3, 0.36, 0.28), 0.7),
	}


static func build(nat: Dictionary) -> Node3D:
	var sd: Dictionary = nat["sub"]
	var style: String = sd["style"]
	if ModernSubBuilder.CLASSES.has(style):
		return ModernSubBuilder.build(nat)
	var L: float = sd["len"]
	var B: float = sd["beam"]
	var mats := materials(nat["id"], L)
	var root := Node3D.new()
	root.name = "PlayerSub"
	var k := MeshKit.new(mats)
	var deck_y := 1.6 if style != "vii" else 1.3
	var top_y := deck_y - 0.4
	# Pressure hull and outer hull.
	var us := [0.0, 0.01, 0.03, 0.06, 0.1, 0.15, 0.22, 0.3, 0.4, 0.5, 0.6, 0.7, 0.78, 0.85, 0.9, 0.94, 0.97, 0.99, 1.0]
	var rows := []
	var segs := 14
	for u in us:
		var f := 1.0
		if u < 0.16:
			f = pow(u / 0.16, 0.5)
		elif u > 0.7:
			f = maxf(0.04, 1.0 - pow((u - 0.7) / 0.3, 1.4) * 0.96)
		var w := B * 0.5 * f
		if style == "vii" and u > 0.28 and u < 0.74:
			w *= 1.0 + 0.18 * sin((u - 0.28) / 0.46 * PI)
		var h := B * 0.45 * maxf(f, 0.08)
		var yc := top_y - h
		var z: float = (u - 0.5) * L
		var row := []
		for i in segs + 1:
			var a := TAU * float(i) / segs
			var sx := sin(a)
			var cy := cos(a)
			var e := 2.6
			var px := signf(sx) * pow(absf(sx), 2.0 / e) * w
			var py := signf(cy) * pow(absf(cy), 2.0 / e) * h
			row.append(Vector3(px, yc + py, z))
		rows.append(row)
	for i in rows.size() - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		var zc: float = (r0[0].z + r1[0].z) * 0.5
		for j in segs:
			var mid: Vector3 = (r0[j] + r0[j + 1]) * 0.5
			var m := "bottom" if mid.y < -0.2 else "hull"
			var center := Vector3(0, top_y - B * 0.45, zc)
			k.quad(m, r0[j], r1[j], r1[j + 1], r0[j + 1], center)
	# Casing deck.
	var dw := B * (0.36 if style != "vii" else 0.32)
	var poly := []
	var cu := [0.02, 0.06, 0.12, 0.2, 0.8, 0.88, 0.94, 0.975]
	for u in cu:
		var f := 1.0
		if u < 0.2:
			f = 0.25 + 0.75 * (u / 0.2)
		elif u > 0.8:
			f = 1.0 - (u - 0.8) / 0.2 * 0.7
		poly.append(Vector2(dw * 0.5 * f, (u - 0.5) * L))
	for i in range(cu.size() - 1, -1, -1):
		var u: float = cu[i]
		var f := 1.0
		if u < 0.2:
			f = 0.25 + 0.75 * (u / 0.2)
		elif u > 0.8:
			f = 1.0 - (u - 0.8) / 0.2 * 0.7
		poly.append(Vector2(-dw * 0.5 * f, (u - 0.5) * L))
	k.prism("hull", poly, top_y - 0.6, deck_y, "deck")
	# Limber holes along the casing.
	var z := -L * 0.38
	while z < L * 0.36:
		for s in [-1.0, 1.0]:
			k.box("black", Vector3(s * dw * 0.5, deck_y - 0.45, z), Vector3(0.05, 0.25, 0.8))
		z += 1.6
	# Bow stem / net cutter and the jumping wires.
	var bow := Vector3(0, deck_y + 0.6, -L * 0.49)
	k.hexa("hull", [Vector3(-0.08, top_y - 1.0, -L * 0.48), Vector3(0.08, top_y - 1.0, -L * 0.48),
		Vector3(0.08, deck_y, -L * 0.45), Vector3(-0.08, deck_y, -L * 0.45),
		Vector3(-0.06, deck_y + 0.6, -L * 0.495), Vector3(0.06, deck_y + 0.6, -L * 0.495),
		Vector3(0.06, deck_y + 0.6, -L * 0.47), Vector3(-0.06, deck_y + 0.6, -L * 0.47)])

	# Conning tower.
	var tz := (float(sd["tower"]) - 0.5) * L
	var tl := L * (0.17 if style == "gato" else (0.15 if style == "b1" else 0.13))
	var th := 3.6 if style != "vii" else 3.2
	var tw := B * (0.36 if style != "vii" else 0.42)
	k.hexa("hull", [Vector3(-tw * 0.5, deck_y - 0.2, tz - tl * 0.5), Vector3(tw * 0.5, deck_y - 0.2, tz - tl * 0.5),
		Vector3(tw * 0.5, deck_y - 0.2, tz + tl * 0.5), Vector3(-tw * 0.5, deck_y - 0.2, tz + tl * 0.5),
		Vector3(-tw * 0.42, deck_y + th, tz - tl * 0.40), Vector3(tw * 0.42, deck_y + th, tz - tl * 0.40),
		Vector3(tw * 0.42, deck_y + th, tz + tl * 0.38), Vector3(-tw * 0.42, deck_y + th, tz + tl * 0.38)])
	k.hexa("hull", [Vector3(-tw * 0.3, deck_y - 0.2, tz - tl * 0.5), Vector3(tw * 0.3, deck_y - 0.2, tz - tl * 0.5),
		Vector3(tw * 0.42, deck_y + th, tz - tl * 0.40), Vector3(-tw * 0.42, deck_y + th, tz - tl * 0.40),
		Vector3(-0.05, deck_y + 0.2, tz - tl * 0.62), Vector3(0.05, deck_y + 0.2, tz - tl * 0.62),
		Vector3(0.05, deck_y + th - 0.3, tz - tl * 0.48), Vector3(-0.05, deck_y + th - 0.3, tz - tl * 0.48)])
	# Open bridge: bulwark lip, cockpit floor and a windscreen.
	var by := deck_y + th
	k.block("deck", 0, tz - tl * 0.01, by - 0.2, by - 0.1, tw * 0.84, tl * 0.78, tw * 0.84, tl * 0.78)
	k.cyl("metal", Vector3(0, by - 0.1, tz - tl * 0.08), Vector3(0, by - 0.02, tz - tl * 0.08), 0.42, 0.42, 14)
	k.cyl("black", Vector3(0, by - 0.02, tz - tl * 0.08), Vector3(0, by, tz - tl * 0.08), 0.32, 0.32, 14)
	k.box("hull", Vector3(0, by + 0.45, tz - tl * 0.40), Vector3(tw * 0.86, 0.9, 0.12))
	for s in [-1.0, 1.0]:
		k.box("hull", Vector3(s * tw * 0.42, by + 0.45, tz - tl * 0.05), Vector3(0.12, 0.9, tl * 0.72))
	k.box("glass", Vector3(0, by + 1.05, tz - tl * 0.40), Vector3(tw * 0.7, 0.3, 0.05))
	# Periscope standards and masts.
	var pz := tz + tl * 0.12
	k.cyl("metal", Vector3(0, by - 0.5, pz), Vector3(0, by + 3.2, pz), 0.35, 0.25, 10)
	k.cyl("metal", Vector3(0, by - 0.5, pz + 1.2), Vector3(0, by + 2.4, pz + 1.2), 0.3, 0.2, 10)
	if style == "gato":
		for dz in [-0.6, 1.8]:
			for s in [-1.0, 1.0]:
				k.cyl("metal", Vector3(s * 0.6, by, pz + dz), Vector3(s * 0.35, by + 5.5, pz + dz * 0.6), 0.12, 0.1, 6, false)
		k.box("metal", Vector3(0, by + 5.4, pz + 0.6), Vector3(1.0, 0.25, 2.8))
		k.box("metal", Vector3(0, by + 6.4, pz + 1.6), Vector3(1.4, 0.8, 0.2))
	if style == "vii":
		# Wintergarten flak platform aft of the bridge.
		k.block("hull", 0, tz + tl * 0.62, deck_y + th - 0.9, deck_y + th - 0.7, tw * 0.8, tl * 0.5, tw * 0.8, tl * 0.5)
		for s in [-1.0, 1.0]:
			k.cyl("metal", Vector3(s * tw * 0.38, by - 0.7, tz + tl * 0.4), Vector3(s * tw * 0.38, by - 0.7, tz + tl * 0.86), 0.04, 0.04, 4, false)
			k.cyl("metal", Vector3(s * tw * 0.38, by - 1.6, tz + tl * 0.86), Vector3(s * tw * 0.38, by - 0.7, tz + tl * 0.86), 0.04, 0.04, 4, false)
		k.cyl("metal", Vector3(-tw * 0.38, by - 0.7, tz + tl * 0.86), Vector3(tw * 0.38, by - 0.7, tz + tl * 0.86), 0.04, 0.04, 4, false)
	# Jumping wires from bow over the tower to the stern.
	var ttop := Vector3(0, by + 3.0, pz)
	k.cyl("black", bow, ttop, 0.03, 0.03, 3, false)
	k.cyl("black", ttop, Vector3(0, deck_y + 0.6, L * 0.47), 0.03, 0.03, 3, false)

	# Lifelines along the casing: stanchions and two wires each side.
	var tz0 := tz - tl * 0.62
	var tz1 := tz + tl * 0.5
	for side in [-1.0, 1.0]:
		var zz := -L * 0.3
		var prev := Vector3.INF
		while zz < L * 0.36:
			var u := zz / L + 0.5
			var f := 1.0
			if u < 0.2:
				f = 0.25 + 0.75 * (u / 0.2)
			elif u > 0.8:
				f = 1.0 - (u - 0.8) / 0.2 * 0.7
			var x: float = side * (dw * 0.5 * f - 0.12)
			var base := Vector3(x, deck_y, zz)
			if zz > tz0 - 0.5 and zz < tz1 + 0.5:
				prev = Vector3.INF
			else:
				k.cyl("metal", base, base + Vector3(0, 1.05, 0), 0.025, 0.02, 4, false)
				if prev != Vector3.INF:
					for hy in [0.5, 1.0]:
						k.cyl("black", prev + Vector3(0, hy, 0), base + Vector3(0, hy, 0), 0.01, 0.01, 3, false)
				prev = base
			zz += 2.2
	# Rungs up the after face of the tower and the forward fairing.
	var ry := deck_y + 0.3
	while ry < by - 0.2:
		k.cyl("metal", Vector3(-0.22, ry, tz1 + 0.06), Vector3(0.22, ry, tz1 + 0.06), 0.02, 0.02, 4, false)
		if style != "b1":
			var fz := lerpf(tz - tl * 0.62, tz - tl * 0.48, (ry - deck_y) / th) - 0.06
			k.cyl("metal", Vector3(-0.22, ry, fz), Vector3(0.22, ry, fz), 0.02, 0.02, 4, false)
		ry += 0.32
	# Deck access hatch near the gun, on the side away from the tower.
	var gz0 := (0.5 - float(sd["gun_x"])) * -L
	var hz := gz0 + (2.6 if gz0 > tz else -2.6)
	k.cyl("metal", Vector3(0, deck_y, hz), Vector3(0, deck_y + 0.12, hz), 0.42, 0.42, 14)
	k.cyl("black", Vector3(0, deck_y + 0.12, hz), Vector3(0, deck_y + 0.13, hz), 0.32, 0.32, 14)
	k.box("metal", Vector3(0.28, deck_y + 0.16, hz), Vector3(0.18, 0.06, 0.05))

	# I-boat hangar and catapult.
	if style == "b1":
		var hz0 := tz - tl * 0.5 - 13.0
		k.cyl("hull", Vector3(0, deck_y + 1.4, hz0), Vector3(0, deck_y + 1.4, tz - tl * 0.5), 1.6, 1.6, 14)
		k.sphere("hull", Vector3(0, deck_y + 1.4, hz0), 1.6, 12, 6, Vector3(1, 1, 0.6))
		k.box("metal", Vector3(0, deck_y + 0.1, (hz0 - L * 0.46) * 0.5), Vector3(0.9, 0.25, absf(hz0 + L * 0.46)))
	# Hydroplanes, rudder and screws.
	for s in [-1.0, 1.0]:
		k.box("metal", Vector3(s * B * 0.55, -1.2, L * 0.44), Vector3(B * 0.4, 0.12, 1.6))
		k.box("metal", Vector3(s * B * 0.5, -0.4, -L * 0.42), Vector3(B * 0.35, 0.12, 1.4))
		k.cyl("brass", Vector3(s * B * 0.22, -1.6, L * 0.49), Vector3(s * B * 0.22, -1.6, L * 0.5), 1.0, 0.2, 6)
	k.box("metal", Vector3(0, -1.0, L * 0.495), Vector3(0.15, 2.4, 1.6))

	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	root.add_child(mi)

	# Deck gun on traversing and elevating nodes.
	var gz := (0.5 - float(sd["gun_x"])) * -L
	var gun := _gun(mats, nat, Vector3(0, deck_y, gz), style)
	root.add_child(gun[0])
	root.set_meta("gun_yaw", gun[0])
	root.set_meta("gun_pitch", gun[1])
	# AA mount on the bridge.
	var az := (0.5 - float(sd["aa_x"])) * -L
	var aa_y := by - 0.7
	if style == "vii":
		az = tz + tl * 0.62
	else:
		var kp := MeshKit.new(mats)
		kp.block("hull", 0, az, deck_y, aa_y, tw * 0.5, 2.2, tw * 0.75, 2.6)
		var pm := MeshInstance3D.new()
		pm.mesh = kp.commit()
		root.add_child(pm)
	var aa := _aa(mats, Vector3(0, aa_y, az))
	root.add_child(aa[0])
	root.set_meta("aa_yaw", aa[0])
	root.set_meta("aa_pitch", aa[1])
	root.set_meta("bridge_eye", Vector3(0, by + 1.5, tz - tl * 0.22))
	root.set_meta("scope_head", Vector3(0, by + 3.4, pz))
	root.set_meta("deck_y", deck_y)
	root.set_meta("deck_geo", {"L": L, "deck_y": deck_y, "dw": dw, "tz": tz, "tl": tl, "tw": tw, "th": th, "by": by,
		"gun_z": gz, "aa_z": az, "aa_y": aa_y, "pz": pz, "hatch_z": hz, "style": style})
	return root


static func _gun(mats: Dictionary, nat: Dictionary, base: Vector3, style: String) -> Array:
	var yaw := Node3D.new()
	yaw.name = "GunYaw"
	yaw.position = base
	var k := MeshKit.new(mats)
	k.cyl("gun", Vector3(0, 0, 0), Vector3(0, 1.0, 0), 0.45, 0.35, 10)
	k.box("gun", Vector3(0, 1.1, 0), Vector3(1.2, 0.3, 1.2))
	k.box("deck", Vector3(0, -0.02, 0.8), Vector3(3.2, 0.06, 4.0))
	if style == "b1" or style == "tclass":
		k.hexa("gun", [Vector3(-1.1, 1.1, -0.7), Vector3(1.1, 1.1, -0.7), Vector3(1.1, 1.1, -0.6), Vector3(-1.1, 1.1, -0.6),
			Vector3(-0.9, 2.8, -0.4), Vector3(0.9, 2.8, -0.4), Vector3(0.9, 2.8, -0.3), Vector3(-0.9, 2.8, -0.3)])
	var m := MeshInstance3D.new()
	m.mesh = k.commit()
	yaw.add_child(m)
	var pitch := Node3D.new()
	pitch.name = "GunPitch"
	pitch.position = Vector3(0, 1.55, 0)
	yaw.add_child(pitch)
	var kp := MeshKit.new(mats)
	var cal: float = nat["gun"]["cal"]
	var bl := cal * 0.045
	var br := cal * 0.0011
	kp.box("gun", Vector3(0, 0, 0.5), Vector3(0.7, 0.6, 1.5))
	kp.cyl("gun", Vector3(0, 0, -0.2), Vector3(0, 0, -bl * 0.4), br * 1.8, br * 1.5, 10)
	kp.cyl("gun", Vector3(0, 0, -bl * 0.4), Vector3(0, 0, -bl), br * 1.15, br * 1.0, 10, true, "black")
	kp.cyl("gun", Vector3(0, -0.35, -0.2), Vector3(0, -0.35, -1.6), 0.12, 0.12, 6)
	kp.box("black", Vector3(-0.55, 0.15, 0.2), Vector3(0.12, 0.12, 0.6))
	var pm := MeshInstance3D.new()
	pm.mesh = kp.commit()
	pitch.add_child(pm)
	return [yaw, pitch]


static func _aa(mats: Dictionary, base: Vector3) -> Array:
	var yaw := Node3D.new()
	yaw.name = "AAYaw"
	yaw.position = base
	var k := MeshKit.new(mats)
	k.cyl("gun", Vector3(0, 0, 0), Vector3(0, 1.1, 0), 0.2, 0.15, 8)
	var m := MeshInstance3D.new()
	m.mesh = k.commit()
	yaw.add_child(m)
	var pitch := Node3D.new()
	pitch.position = Vector3(0, 1.2, 0)
	yaw.add_child(pitch)
	var kp := MeshKit.new(mats)
	kp.box("gun", Vector3(0, 0, 0.2), Vector3(0.3, 0.35, 0.9))
	kp.cyl("gun", Vector3(0, 0.05, -0.2), Vector3(0, 0.05, -2.2), 0.05, 0.04, 6)
	kp.cyl("black", Vector3(0, 0.05, -0.3), Vector3(0, 0.05, -0.9), 0.09, 0.09, 8)
	kp.hexa("gun", [Vector3(-0.7, -0.6, -0.4), Vector3(0.7, -0.6, -0.4), Vector3(0.7, -0.6, -0.35), Vector3(-0.7, -0.6, -0.35),
		Vector3(-0.6, 0.5, -0.45), Vector3(0.6, 0.5, -0.45), Vector3(0.6, 0.5, -0.4), Vector3(-0.6, 0.5, -0.4)])
	kp.box("black", Vector3(0, 0.3, 0.1), Vector3(0.25, 0.25, 0.08))
	var pm := MeshInstance3D.new()
	pm.mesh = kp.commit()
	pitch.add_child(pm)
	return [yaw, pitch]
