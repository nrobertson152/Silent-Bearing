## Simple crewmen for the stations: seated or standing, in their navy's working dress.

const MeshKit := preload("res://scripts/build/mesh_kit.gd")


static func build(uniform: Color, nation: String, seated: bool) -> Node3D:
	var skin := Color(0.80, 0.64, 0.50)
	var mats := {
		"cloth": MeshKit.mat(uniform, 0.95),
		"trousers": MeshKit.mat(uniform.darkened(0.25), 0.95),
		"skin": MeshKit.mat(skin, 0.8),
		"cap": MeshKit.mat(Color(0.9, 0.9, 0.88) if nation == "us" else uniform.darkened(0.35), 0.9),
		"boot": MeshKit.mat(Color(0.08, 0.07, 0.06), 0.7),
		"stool": MeshKit.mat(Color(0.25, 0.26, 0.27), 0.6, 0.5),
	}
	var k := MeshKit.new(mats)
	var hip := 0.62 if seated else 0.92
	if seated:
		k.cyl("stool", Vector3(0, 0, 0.25), Vector3(0, 0.55, 0.25), 0.04, 0.04, 6)
		k.cyl("stool", Vector3(0, 0.55, 0.25), Vector3(0, 0.6, 0.25), 0.2, 0.2, 10)
		for s in [-1.0, 1.0]:
			k.cyl("trousers", Vector3(s * 0.1, hip, 0.2), Vector3(s * 0.1, hip, -0.2), 0.075, 0.07, 8)
			k.cyl("trousers", Vector3(s * 0.1, hip, -0.2), Vector3(s * 0.1, 0.08, -0.25), 0.07, 0.06, 8)
			k.box("boot", Vector3(s * 0.1, 0.05, -0.3), Vector3(0.11, 0.1, 0.26))
	else:
		for s in [-1.0, 1.0]:
			k.cyl("trousers", Vector3(s * 0.1, hip, 0), Vector3(s * 0.1, 0.08, 0), 0.08, 0.065, 8)
			k.box("boot", Vector3(s * 0.1, 0.05, -0.05), Vector3(0.11, 0.1, 0.26))
	k.cyl("cloth", Vector3(0, hip - 0.05, 0.05), Vector3(0, hip + 0.55, 0.02), 0.17, 0.2, 10)
	k.sphere("cloth", Vector3(0, hip + 0.55, 0.02), 0.2, 10, 5, Vector3(1.05, 0.5, 0.8))
	k.cyl("skin", Vector3(0, hip + 0.6, 0.02), Vector3(0, hip + 0.68, 0.02), 0.06, 0.06, 8)
	k.sphere("skin", Vector3(0, hip + 0.8, 0.0), 0.11, 10, 6, Vector3(0.9, 1.05, 1.0))
	k.cyl("cap", Vector3(0, hip + 0.86, 0.0), Vector3(0, hip + 0.94, 0.0), 0.11, 0.1, 10)
	if nation == "us":
		k.cyl("cap", Vector3(0, hip + 0.9, 0.0), Vector3(0, hip + 0.92, 0.0), 0.16, 0.16, 12)
	for s in [-1.0, 1.0]:
		var sh := Vector3(s * 0.22, hip + 0.5, 0.02)
		var el := Vector3(s * 0.26, hip + 0.25, -0.12)
		var hand := Vector3(s * 0.18, hip + 0.3, -0.38)
		k.cyl("cloth", sh, el, 0.06, 0.055, 6)
		k.cyl("cloth", el, hand, 0.055, 0.045, 6)
		k.sphere("skin", hand, 0.05, 6, 4)
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	n.add_child(mi)
	return n
