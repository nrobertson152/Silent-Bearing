extends SceneTree
## Renders the ship, boat and aircraft models to PNG files for a quick look.
## xvfb-run godot --path . --rendering-driver opengl3 -s tools/model_preview.gd -- <out_dir> [layout]

var out_dir := "user://"
var frame := 0
var shots := []
var cam: Camera3D
var zoom := 1.0
var holder: Node3D


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var only: String = args[1] if args.size() > 1 else ""
	if args.size() > 2:
		zoom = float(args[2])
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.70, 0.76)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.65)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_energy = 1.3
	root.add_child(sun)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2000, 2000)
	sea.mesh = pm
	sea.material_override = MeshKit.mat(Color(0.12, 0.22, 0.27), 0.3)
	root.add_child(sea)
	cam = Camera3D.new()
	cam.fov = 40
	cam.far = 5000
	root.add_child(cam)
	holder = Node3D.new()
	root.add_child(holder)
	var nations := GameData.nations()
	for nid in GameData.NATION_ORDER:
		for t in nations[nid]["targets"]:
			if only == "" or only == t["layout"]:
				shots.append(["ship", t["layout"], t["length"], t["beam"], t["draft"]])
	for l in ["dd_jp", "dd_us", "dd_uk", "dd_de"]:
		if only == "" or only == l:
			shots.append(["ship", l, 115.0, 11.0, 3.6])
	if only == "" or only == "pc":
		shots.append(["ship", "pc", 52.0, 7.0, 2.4])
	for nid in GameData.NATION_ORDER:
		if only == "" or only == "sub_" + nid:
			shots.append(["sub", nid])
	for key in GameData.AIRCRAFT:
		if only == "" or only == "air_" + key:
			shots.append(["plane", key])


func _process(_d: float) -> bool:
	frame += 1
	if frame % 3 == 1:
		if shots.is_empty():
			return true
		for c in holder.get_children():
			c.queue_free()
		var s: Array = shots[0]
		var node: Node3D
		var size := 100.0
		match s[0]:
			"ship":
				node = ShipBuilder.build(s[1], s[2], s[3], s[4])
				size = s[2]
			"sub":
				node = SubBuilder.build(GameData.nations()[s[1]])
				size = float(GameData.nations()[s[1]]["sub"]["len"])
			"plane":
				var info: Dictionary = GameData.AIRCRAFT[s[1]]
				node = PlaneBuilder.build(info, "us")
				node.position.y = 10
				size = info["span"] * 1.4
		holder.add_child(node)
		cam.position = Vector3(size * 0.75, size * 0.28, -size * 0.55) * zoom + Vector3(0, 0, size * 0.1)
		cam.look_at(Vector3(0, size * 0.04 + (10.0 if s[0] == "plane" else 0.0), 0))
	elif frame % 3 == 0:
		var s: Array = shots.pop_front()
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [out_dir, s[0], s[1]])
	return false
