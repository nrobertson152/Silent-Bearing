extends Node3D
## The walkable outside of the boat. An invisible collision copy of the casing,
## conning tower and bridge sits far below the world at DECK_ORIGIN; the player
## walks around in it and the camera is carried onto the real, rolling boat by
## the sub's transform. Also places the lookouts, the gun crew and, in the
## outside view, the player's own figure on the model.
##
## Local space matches the sub model: bow toward -Z, waterline at y = 0.

const CrewBuilder := preload("res://scripts/build/crew_builder.gd")

var g: Dictionary
var stations: Array = []
var spots := {}
var lookouts: Array = []
var gun_crew: Array = []
var me: Node3D
var me_holder: Node3D
var _body: StaticBody3D


func build(sub_node: Node3D, nat: Dictionary) -> void:
	g = sub_node.get_meta("deck_geo")
	var L: float = g["L"]
	var dy: float = g["deck_y"]
	var tz: float = g["tz"]
	var tl: float = g["tl"]
	var tw: float = g["tw"]
	var by: float = g["by"]
	var bf := by - 0.1
	var gz: float = g["gun_z"]
	var style: String = g["style"]
	_body = StaticBody3D.new()
	add_child(_body)
	# Casing: deck plates in 1 m strips with lifeline walls along the edges.
	var z := -L * 0.47
	while z < L * 0.46:
		var hw := minf(half_width(z), half_width(z + 1.0))
		if hw > 0.2:
			_box(Vector3(0, dy - 0.15, z + 0.5), Vector3(hw * 2.0, 0.3, 1.0))
			for s in [-1.0, 1.0]:
				_box(Vector3(s * (hw + 0.1), dy + 1.0, z + 0.5), Vector3(0.2, 2.0, 1.02))
		z += 1.0
	_box(Vector3(0, dy + 1.0, -L * 0.47 - 0.1), Vector3(4, 2, 0.2))
	_box(Vector3(0, dy + 1.0, L * 0.46 + 0.1), Vector3(4, 2, 0.2))
	# Conning tower, fairing and periscope standards.
	var f0 := tz - tl * 0.62
	var f1 := tz + tl * 0.5
	_box(Vector3(0, (dy + bf) * 0.5, (f0 + f1) * 0.5), Vector3(tw, bf - dy, f1 - f0))
	if style == "b1":
		var hz0 := tz - tl * 0.5 - 13.0
		_box(Vector3(0, dy + 1.4, (hz0 - 1.6 + tz) * 0.5), Vector3(3.3, 3.0, tz - hz0 + 1.6))
	# Bridge cockpit: floor and bulwarks.
	var bz0 := tz - tl * 0.40
	var bz1 := tz + tl * 0.38
	var bw := tw * 0.42
	_box(Vector3(0, bf - 0.15, (bz0 + bz1) * 0.5), Vector3(bw * 2.0, 0.3, bz1 - bz0))
	_box(Vector3(0, bf + 1.0, bz0 - 0.1), Vector3(bw * 2.0 + 0.4, 2.0, 0.2))
	_box(Vector3(0, bf + 1.0, bz1 + 0.1), Vector3(bw * 2.0 + 0.4, 2.0, 0.2))
	for s in [-1.0, 1.0]:
		_box(Vector3(s * (bw + 0.1), bf + 1.0, (bz0 + bz1) * 0.5), Vector3(0.2, 2.0, bz1 - bz0))
	var pz: float = g["pz"]
	_box(Vector3(0, bf + 1.5, pz), Vector3(0.7, 3.0, 0.7))
	_box(Vector3(0, bf + 1.5, pz + 1.2), Vector3(0.6, 3.0, 0.6))
	# Deck gun mount and the AA platform if it stands on the casing.
	_box(Vector3(0, dy + 0.7, gz), Vector3(1.2, 1.4, 1.2))
	var az: float = g["aa_z"]
	var on_casing := style != "vii" and (az > f1 or az < f0)
	if on_casing:
		_box(Vector3(0, (dy + float(g["aa_y"])) * 0.5, az), Vector3(tw * 0.75, float(g["aa_y"]) - dy, 2.6))
	# Where the player stands for each place, and the stations to use there.
	var aft_land := f1 + 0.9
	if on_casing and az > f1:
		aft_land = az + 2.2
	var fwd_land := f0 - 0.9
	if style == "b1":
		fwd_land = tz - tl * 0.5 - 13.0 - 2.4
	spots["bridge"] = Vector3(0, bf + 0.05, tz - tl * 0.22)
	spots["bridge_aft"] = Vector3(0, bf + 0.05, bz1 - 0.7)
	spots["bridge_fwd"] = Vector3(0, bf + 0.05, bz0 + 0.8)
	spots["casing_aft"] = Vector3(0, dy + 0.05, aft_land)
	spots["casing_fwd"] = Vector3(0, dy + 0.05, fwd_land)
	var side := 1.0 if gz > tz else -1.0
	spots["gun"] = Vector3(-0.85, dy + 0.05, gz - side * 1.4)
	spots["hatch"] = Vector3(0.0, dy + 0.05, float(g["hatch_z"]) + side * 0.9)
	spots["aa"] = spots["bridge_aft"]
	var hz: float = g["hatch_z"]
	_station("hatch", Vector3(0, bf + 0.3, tz - tl * 0.08), "Go below (conning tower hatch)", 1.6)
	_station("hatch_casing", Vector3(0, dy + 0.3, hz), "Go below (deck hatch)", 1.6)
	_station("gun", Vector3(0, dy + 1.5, gz), "Man the deck gun", 2.4)
	_station("aa", Vector3(0, float(g["aa_y"]) + 1.3, az), "Man the AA gun", 3.8)
	_station("down_aft", Vector3(0, bf + 1.0, bz1), "Climb down to the after deck", 1.8)
	_station("up_aft", Vector3(0, dy + 1.4, aft_land - 0.5), "Climb up to the bridge", 1.8)
	if style != "b1":
		_station("down_fwd", Vector3(0, bf + 1.0, bz0), "Climb down to the forward deck", 1.8)
		_station("up_fwd", Vector3(0, dy + 1.4, fwd_land + 0.5), "Climb up to the bridge", 1.8)
	_figures(sub_node, nat)


func half_width(z: float) -> float:
	var L: float = g["L"]
	var u := z / L + 0.5
	if u < 0.02 or u > 0.975:
		return 0.0
	var f := 1.0
	if u < 0.2:
		f = 0.25 + 0.75 * (u / 0.2)
	elif u > 0.8:
		f = 1.0 - (u - 0.8) / 0.2 * 0.7
	return float(g["dw"]) * 0.5 * f - 0.12


func _box(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = s
	cs.shape = b
	cs.position = c
	_body.add_child(cs)


func _station(name: String, pos: Vector3, prompt: String, reach: float) -> void:
	stations.append({"name": name, "pos": pos, "prompt": prompt, "reach": reach})


func _figures(sn: Node3D, nat: Dictionary) -> void:
	var id: String = nat["id"]
	var tz: float = g["tz"]
	var tl: float = g["tl"]
	var bf: float = float(g["by"]) - 0.1
	var bw: float = float(g["tw"]) * 0.42
	# Lookouts at the sides of the bridge, each watching his own sector.
	var look := [[-bw + 0.4, tz - tl * 0.06, PI * 0.38], [bw - 0.4, tz - tl * 0.06, -PI * 0.38],
		[-bw + 0.4, tz + tl * 0.3, PI * 0.72], [bw - 0.4, tz + tl * 0.3, -PI * 0.72]]
	for i in look.size():
		var l: Array = look[i]
		var hands := {"r": Vector3(0.07, 1.6, -0.25), "l": Vector3(-0.07, 1.6, -0.25)}
		var n := CrewBuilder.build(id, 40 + i, "stand", hands)
		n.position = Vector3(l[0], bf, l[1])
		n.rotation.y = l[2]
		sn.add_child(n)
		lookouts.append(n)
	var gz: float = g["gun_z"]
	var dy: float = g["deck_y"]
	var side := 1.0 if gz > tz else -1.0
	var crew := [[0.95, gz + 0.2, -PI / 2, "work"], [-1.0, gz + side * 1.2, PI * 0.5, "stand"], [0.5, gz + side * 1.8, 0.0 if side < 0 else PI, "stand"]]
	for i in crew.size():
		var c: Array = crew[i]
		var n := CrewBuilder.build(id, 50 + i, c[3])
		n.position = Vector3(c[0], dy, c[1])
		n.rotation.y = c[2]
		sn.add_child(n)
		gun_crew.append(n)
	me_holder = Node3D.new()
	sn.add_child(me_holder)
	me = CrewBuilder.build(id, 7, "stand")
	me_holder.add_child(me)
	me_holder.visible = false
	for f in lookouts + gun_crew:
		f.visible = false


## Shows or hides the figures. `me_pos` is the player's local position on the
## boat, or null when the player is inside or should not be drawn.
## `cam` is the camera's local position on the boat (or null); figures it would
## sit inside are hidden.
func update(surfaced: bool, gun_manned: bool, me_pos, me_yaw: float, cam = null) -> void:
	for f in lookouts:
		f.visible = surfaced and not _near(f, cam)
	for f in gun_crew:
		f.visible = surfaced and gun_manned and not _near(f, cam)
	me_holder.visible = me_pos != null
	if me_pos != null:
		me_holder.position = me_pos
		me_holder.rotation.y = me_yaw


func _near(f: Node3D, cam) -> bool:
	if cam == null:
		return false
	var d: Vector3 = f.position + Vector3(0, 1.2, 0) - cam
	return Vector2(d.x, d.z).length() < 1.1 and absf(d.y) < 1.5
