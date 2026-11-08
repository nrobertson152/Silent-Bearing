## Crewmen posed for their stations. Limbs are solved with simple two-bone IK
## from the hip and shoulder to wherever the feet and hands should be.
## Model space: the man faces -Z, feet on y = 0.

const MeshKit := preload("res://scripts/build/mesh_kit.gd")

const UPPER_ARM := 0.30
const FOREARM := 0.28
const THIGH := 0.44
const SHIN := 0.44


static func outfit(nation: String, i: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(nation) + i * 97
	var shirt: Color
	var trousers: Color
	var cap := ""
	var beard := false
	match nation:
		"us":
			shirt = [Color(0.55, 0.64, 0.75), Color(0.86, 0.86, 0.82), Color(0.50, 0.58, 0.70), Color(0.42, 0.44, 0.40)][i % 4]
			trousers = Color(0.16, 0.20, 0.30)
			cap = ["dixie", "none", "ball", "none"][i % 4]
		"uk":
			shirt = [Color(0.85, 0.83, 0.75), Color(0.16, 0.18, 0.26), Color(0.30, 0.30, 0.28), Color(0.62, 0.60, 0.52)][i % 4]
			trousers = Color(0.14, 0.15, 0.20)
			cap = ["none", "beret", "none", "none"][i % 4]
			beard = i % 3 != 2
		"de":
			shirt = [Color(0.32, 0.33, 0.28), Color(0.55, 0.52, 0.44), Color(0.25, 0.26, 0.24), Color(0.62, 0.60, 0.55)][i % 4]
			trousers = Color(0.22, 0.22, 0.20)
			cap = ["schiff", "none", "schiff", "none"][i % 4]
			beard = i % 4 != 3
		_:
			shirt = [Color(0.50, 0.48, 0.34), Color(0.84, 0.82, 0.74), Color(0.42, 0.42, 0.32), Color(0.46, 0.44, 0.30)][i % 4]
			trousers = Color(0.36, 0.35, 0.26)
			cap = ["field", "none", "field", "hachimaki"][i % 4]
	var skin: Color = [Color(0.80, 0.64, 0.50), Color(0.72, 0.56, 0.42), Color(0.86, 0.70, 0.56), Color(0.66, 0.50, 0.38)][rng.randi() % 4]
	var hair: Color = [Color(0.10, 0.07, 0.05), Color(0.35, 0.25, 0.15), Color(0.55, 0.42, 0.25), Color(0.18, 0.14, 0.10)][rng.randi() % 4]
	if nation == "jp":
		skin = Color(0.80, 0.66, 0.50).darkened(rng.randf() * 0.12)
		hair = Color(0.06, 0.05, 0.05)
	return {"shirt": shirt, "trousers": trousers, "cap": cap, "beard": beard, "skin": skin, "hair": hair}


static func _ik(a: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var d := target - a
	var L := clampf(d.length(), 0.05, l1 + l2 - 0.001)
	var dir := d.normalized()
	var x := (l1 * l1 - l2 * l2 + L * L) / (2.0 * L)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var side := (pole - dir * pole.dot(dir)).normalized()
	return a + dir * x + side * h


static func _limb(k: MeshKit, mat: String, a: Vector3, b: Vector3, c: Vector3, r0: float, r1: float, r2: float) -> void:
	k.cyl(mat, a, b, r0, r1, 8, false)
	k.cyl(mat, b, c, r1, r2, 8, false)
	k.sphere(mat, b, r1 * 1.05, 6, 4)
	k.sphere(mat, a, r0 * 1.02, 6, 4)


## pose: stand, work, scope, lean, sit_wheel, sit_panel, sit_table, sit_stool, lie
static func build(nation: String, index: int, pose: String, hands := {}) -> Node3D:
	var o := outfit(nation, index)
	var mats := {
		"shirt": MeshKit.mat(o["shirt"], 0.95),
		"trousers": MeshKit.mat(o["trousers"], 0.95),
		"skin": MeshKit.mat(o["skin"], 0.75),
		"hair": MeshKit.mat(o["hair"], 0.9),
		"shoe": MeshKit.mat(Color(0.07, 0.06, 0.05), 0.5),
		"cap": MeshKit.mat(Color(0.92, 0.92, 0.9) if o["cap"] == "dixie" else (Color(0.82, 0.8, 0.75) if o["cap"] == "hachimaki" else Color(0.14, 0.14, 0.16)), 0.9),
		"belt": MeshKit.mat(Color(0.12, 0.09, 0.06), 0.6),
		"eye": MeshKit.mat(Color(0.05, 0.05, 0.05), 0.3),
	}
	var k := MeshKit.new(mats)
	var seated := pose.begins_with("sit")
	var lying := pose == "lie"
	var hip_y := 0.52 if seated else 0.94
	var hip := Vector3(0, hip_y, 0.04 if seated else 0.0)
	var lean := 0.0
	match pose:
		"lean":
			lean = 0.35
		"work", "sit_panel":
			lean = 0.12
		"sit_table":
			lean = 0.18
		"scope":
			lean = 0.08
	var chest := hip + Vector3(0, 0.52 * cos(lean), -0.52 * sin(lean))
	var neck := hip + Vector3(0, 0.66 * cos(lean), -0.66 * sin(lean))
	var head := neck + Vector3(0, 0.13, -0.02)
	# Legs.
	for s in [-1.0, 1.0]:
		var hp := hip + Vector3(s * 0.1, 0, 0)
		var foot: Vector3
		var pole := Vector3(0, 0, -1)
		if seated:
			foot = Vector3(s * 0.13, 0.08, -0.42)
			pole = Vector3(0, 1, -0.3)
		elif lying:
			foot = Vector3(s * 0.12, 0.08, 0.02)
		else:
			foot = Vector3(s * 0.12, 0.08, -0.02 + (0.06 if s > 0 else -0.04))
		var knee := _ik(hp, foot, THIGH, SHIN, pole)
		_limb(k, "trousers", hp, knee, foot, 0.085, 0.065, 0.055)
		k.box("shoe", foot + Vector3(0, -0.04, -0.06), Vector3(0.1, 0.08, 0.26))
	# Torso, belt, collar.
	var up := (chest - hip).normalized()
	k.cyl("trousers", hip + Vector3(0, -0.06, 0), hip + up * 0.12, 0.17, 0.17, 10)
	k.cyl("belt", hip + up * 0.1, hip + up * 0.16, 0.172, 0.172, 10, false)
	k.cyl("shirt", hip + up * 0.14, chest, 0.16, 0.2, 10)
	k.sphere("shirt", chest, 0.2, 10, 5, Vector3(1.05, 0.55, 0.75))
	k.cyl("skin", chest + up * 0.06, neck + up * 0.05, 0.055, 0.05, 8)
	# Head.
	var hb := Node3D.new()
	hb.name = "Head"
	hb.position = neck
	var kh := MeshKit.new(mats)
	var hc := Vector3(0, 0.15, -0.01)
	kh.sphere("skin", hc, 0.105, 12, 7, Vector3(0.88, 1.08, 1.0))
	kh.box("skin", hc + Vector3(0, -0.01, -0.1), Vector3(0.03, 0.05, 0.04))
	for s in [-1.0, 1.0]:
		kh.sphere("skin", hc + Vector3(s * 0.093, 0.0, 0.0), 0.025, 6, 4, Vector3(0.5, 1, 0.8))
		kh.sphere("eye", hc + Vector3(s * 0.035, 0.025, -0.092), 0.012, 6, 3)
		kh.box("hair", hc + Vector3(s * 0.035, 0.052, -0.09), Vector3(0.04, 0.012, 0.012))
	kh.sphere("hair", hc + Vector3(0, 0.035, 0.012), 0.104, 12, 6, Vector3(0.92, 0.85, 1.0))
	if o["beard"]:
		kh.sphere("hair", hc + Vector3(0, -0.06, -0.04), 0.075, 10, 5, Vector3(1.1, 0.8, 0.9))
	match o["cap"]:
		"dixie":
			kh.cyl("cap", hc + Vector3(0, 0.07, 0), hc + Vector3(0, 0.15, 0), 0.105, 0.09, 12)
			kh.cyl("cap", hc + Vector3(0, 0.09, 0), hc + Vector3(0, 0.11, 0), 0.13, 0.13, 12)
		"ball", "field":
			kh.sphere("cap", hc + Vector3(0, 0.07, 0.0), 0.108, 10, 5, Vector3(1, 0.6, 1))
			kh.box("cap", hc + Vector3(0, 0.07, -0.13), Vector3(0.14, 0.012, 0.08))
		"beret":
			kh.sphere("cap", hc + Vector3(0.02, 0.09, 0.0), 0.12, 10, 4, Vector3(1.1, 0.35, 1.1))
		"schiff":
			kh.box("cap", hc + Vector3(0, 0.11, 0), Vector3(0.09, 0.07, 0.22))
		"hachimaki":
			kh.cyl("cap", hc + Vector3(0, 0.05, 0), hc + Vector3(0, 0.08, 0), 0.108, 0.108, 12, false)
	var hm := MeshInstance3D.new()
	hm.mesh = kh.commit()
	hb.add_child(hm)
	# Arms.
	var sh_w := 0.21
	var right := Vector3(1, 0, 0)
	for s in [-1.0, 1.0]:
		var sh: Vector3 = chest + right * s * sh_w + up * 0.04
		var hand: Vector3
		var key := "r" if s > 0 else "l"
		if hands.has(key):
			hand = hands[key]
		else:
			match pose:
				"stand":
					hand = Vector3(s * 0.26, hip_y - 0.05, -0.04)
				"work":
					hand = Vector3(s * 0.2, 1.2, -0.42)
				"scope":
					hand = Vector3(s * 0.26, 1.48, -0.32)
				"lean":
					hand = Vector3(s * 0.28, 0.92, -0.52)
				"sit_wheel":
					hand = Vector3(s * 0.24, 1.05, -0.45)
				"sit_panel":
					hand = Vector3(s * 0.22, 0.95, -0.48)
				"sit_table":
					hand = Vector3(s * 0.2, 0.8, -0.4)
				"sit_stool":
					hand = Vector3(s * 0.2, 0.62, -0.22)
				"lie":
					hand = Vector3(s * 0.26, hip_y - 0.05, 0.05)
		var elbow := _ik(sh, hand, UPPER_ARM, FOREARM, Vector3(s * 0.6, -1.0, 0.4))
		_limb(k, "shirt", sh, elbow, hand, 0.06, 0.05, 0.042)
		k.sphere("skin", hand, 0.045, 6, 4, Vector3(0.9, 0.8, 1.2))
	var n := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	n.add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	body.add_child(mi)
	body.add_child(hb)
	if lying:
		# On his back, head toward -Z, centred on the node.
		body.rotation = Vector3(PI / 2, PI, 0)
		body.position = Vector3(0, 0.14, 0.9)
	return n
