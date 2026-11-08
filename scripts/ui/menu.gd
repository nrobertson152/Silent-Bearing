extends CanvasLayer
## Main menu: pick a navy, pick a famous warship, read the orders, sail.

const GameData := preload("res://scripts/data.gd")
const Style := preload("res://scripts/ui/style.gd")

var game
var root: Control
var body: VBoxContainer
var nat_id := ""
var tgt_id := ""
var step := "nation"


func build(g) -> void:
	game = g
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = Style.theme()
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.035, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.09, 0.11, 0.12, 0.94), Style.SEAM, 2, 6, 26))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -560
	panel.offset_right = 560
	panel.offset_top = -380
	panel.offset_bottom = 380
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(Style.label(Style.spaced("SILENT BEARING"), 48, Style.BRASS))
	v.add_child(Style.label("Take the conn of a wartime submarine. Find the warship, slip the escorts and the aircraft, and sink her.", 17, Style.TEXT))
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 14)
	v.add_child(sep)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	v.add_child(body)
	show_step("nation")


func show_step(s: String) -> void:
	step = s
	for c in body.get_children():
		c.queue_free()
	match s:
		"nation":
			_nations()
		"target":
			_targets()
		"brief":
			_brief()


func _nations() -> void:
	body.add_child(Style.label(Style.spaced("CHOOSE YOUR NAVY"), 14, Style.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	var nations := GameData.nations()
	for i in GameData.NATION_ORDER.size():
		var nid: String = GameData.NATION_ORDER[i]
		var nat: Dictionary = nations[nid]
		var card := Button.new()
		card.custom_minimum_size = Vector2(250, 520)
		card.pressed.connect(func(): _pick_nation(nid))
		row.add_child(card)
		var cv := VBoxContainer.new()
		cv.set_anchors_preset(Control.PRESET_FULL_RECT)
		cv.offset_left = 14
		cv.offset_right = -14
		cv.offset_top = 14
		cv.offset_bottom = -14
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)
		var bc := CenterContainer.new()
		bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bd := Style.badge(nid)
		bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bc.add_child(bd)
		cv.add_child(bc)
		var nl := Style.label(nat["name"], 22, Style.TEXT)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nl)
		var bl := Style.label(nat["boat"], 15, Style.BRASS)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(bl)
		var g := GridContainer.new()
		g.columns = 2
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for kv in [["Submerged", "%s kn" % str(nat["sub_kn"])], ["Surfaced", "%s kn" % str(nat["surf_kn"])], ["Test depth", "%d m" % int(nat["test"])],
				["Dive time", "%d s" % int(nat["dive_time"])], ["Tubes / load", "%d / %d" % [nat["tubes"], nat["torps"]]],
				["Torpedo", nat["torp"]["name"]], ["Run", "%.1f km, %d kn" % [float(nat["torp"]["range"]) / 1000.0, int(nat["torp"]["kn"])]],
				["Wake", "visible" if nat["torp"]["wake"] else "none"], ["Deck gun", nat["gun"]["name"]]]:
			var k := Style.label(kv[0], 13, Style.MUTED)
			k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			g.add_child(k)
			var val := Style.label(kv[1], 13, Style.TEXT)
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			g.add_child(val)
		cv.add_child(g)
		var blurb := Style.label(nat["blurb"], 13, Style.TEXT, true)
		blurb.custom_minimum_size = Vector2(220, 0)
		cv.add_child(blurb)
		var press := Style.label("Press %d" % (i + 1), 13, Style.MUTED)
		press.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		press.size_flags_vertical = Control.SIZE_EXPAND_FILL
		press.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		cv.add_child(press)
	if game.in_patrol:
		body.add_child(Style.button("Resume patrol", func(): game.resume(), 16))


func _pick_nation(nid: String) -> void:
	nat_id = nid
	show_step("target")


func _targets() -> void:
	var nat: Dictionary = GameData.nations()[nat_id]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var bd := Style.badge(nat_id)
	bd.custom_minimum_size = Vector2(36, 36)
	head.add_child(bd)
	head.add_child(Style.label("%s.   %s" % [nat["boat"], Style.spaced("CHOOSE YOUR TARGET")], 16, Style.TEXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(Style.button("Back", func(): show_step("nation")))
	body.add_child(head)
	for i in nat["targets"].size():
		var tg: Dictionary = nat["targets"][i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(1060, 104)
		card.pressed.connect(func(): _pick_target(tg["id"]))
		body.add_child(card)
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 16
		hb.offset_right = -16
		hb.offset_top = 8
		hb.offset_bottom = -8
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_theme_constant_override("separation", 16)
		card.add_child(hb)
		hb.add_child(Style.label(str(i + 1), 30, Style.BRASS_LO))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 0)
		hb.add_child(v)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override("separation", 12)
		top.add_child(Style.label(GameData.PREFIX[tg["nation"]] + tg["name"], 22, Style.TEXT))
		top.add_child(Style.label("HISTORICAL" if tg["historical"] else "WHAT IF", 12, Style.GOOD if tg["historical"] else Style.AMBER))
		top.add_child(Style.label(tg["credit"], 14, Style.BRASS))
		v.add_child(top)
		var note := Style.label(tg["note"], 13, Style.TEXT, true)
		note.custom_minimum_size = Vector2(640, 0)
		note.max_lines_visible = 2
		v.add_child(note)
		var info := GridContainer.new()
		info.columns = 2
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.custom_minimum_size = Vector2(220, 0)
		for kv in [["Type", GameData.TYPE_NAMES[tg["type"]]], ["Escorts", "%d DD, %d small" % [tg["escorts"], tg["chasers"]]],
				["Aircraft", "none" if tg["air"].is_empty() or tg["tod"] == "night" else str(tg["air"].size())],
				["Conditions", tg["tod"].capitalize()], ["Hits to sink", str(tg["hp"])]]:
			info.add_child(Style.label(kv[0], 12, Style.MUTED))
			info.add_child(Style.label(kv[1], 12, Style.TEXT))
		hb.add_child(info)


func _pick_target(tid: String) -> void:
	tgt_id = tid
	show_step("brief")


func _brief() -> void:
	var nat: Dictionary = GameData.nations()[nat_id]
	var tg: Dictionary = {}
	for t in nat["targets"]:
		if t["id"] == tgt_id:
			tg = t
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 40)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(hb)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)
	left.add_child(Style.label(Style.spaced("PATROL ORDERS"), 14, Style.MUTED))
	left.add_child(Style.label(GameData.PREFIX[tg["nation"]] + tg["name"], 36, Style.TEXT))
	left.add_child(Style.label("%s   |   %s" % [GameData.TYPE_NAMES[tg["type"]], tg["credit"]], 15, Style.BRASS))
	var note := Style.label(tg["note"], 15, Style.TEXT, true)
	note.custom_minimum_size = Vector2(520, 0)
	left.add_child(note)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 20)
	var air := "none"
	if not tg["air"].is_empty() and tg["tod"] != "night":
		var names := []
		for a in tg["air"]:
			names.append(GameData.AIRCRAFT[a]["name"])
		air = ", ".join(names)
	for kv in [["Your boat", "%s, %d %s torpedoes" % [nat["boat"], nat["torps"], nat["torp"]["name"]]],
			["Conditions", tg["tod"].capitalize() + (", red lighting below" if tg["tod"] == "night" else "")],
			["Target", ("at anchor" if tg["kn"] == 0 else "about %d knots" % int(tg["kn"])) + (", zigzagging" if tg["zig"] else "")],
			["Screen", "%d destroyers, %d sub-chasers" % [tg["escorts"], tg["chasers"]]], ["Air cover", air],
			["Draft", "about %d m: set torpedoes shallower than that" % int(tg["draft"])],
			["To sink her", "%d torpedo hits (shellfire helps a little)" % tg["hp"]]]:
		g.add_child(Style.label(kv[0], 14, Style.MUTED))
		g.add_child(Style.label(kv[1], 14, Style.TEXT))
	left.add_child(g)
	var tip := Style.label("Approach at periscope depth and keep the scope up only in short looks. Lock her on the TDC and let the solution settle. Fire from 1,000 to 2,500 metres off her beam. When escorts turn on you, go deep, slow down and change course. Planes spot surfaced boats from far away: dive when the lookouts call them.", 14, Style.MUTED, true)
	tip.custom_minimum_size = Vector2(520, 0)
	left.add_child(tip)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	hb.add_child(right)
	right.add_child(Style.label(Style.spaced("CONTROLS"), 14, Style.MUTED))
	var cg := GridContainer.new()
	cg.columns = 2
	cg.add_theme_constant_override("h_separation", 16)
	for row in GameData.HELP:
		cg.add_child(Style.label(row[0], 13, Style.AMBER))
		cg.add_child(Style.label(row[1], 13, Style.TEXT))
	right.add_child(cg)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(Style.button("Back", func(): show_step("target")))
	buttons.add_child(Style.button("Begin patrol", func(): game.start_mission(nat_id, tgt_id), 20, true))
	body.add_child(buttons)


func key(k: int) -> void:
	if k >= KEY_1 and k <= KEY_9:
		var i := k - KEY_1
		if step == "nation" and i < GameData.NATION_ORDER.size():
			_pick_nation(GameData.NATION_ORDER[i])
		elif step == "target":
			var ts: Array = GameData.nations()[nat_id]["targets"]
			if i < ts.size():
				_pick_target(ts[i]["id"])
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		if step == "brief":
			game.start_mission(nat_id, tgt_id)
	elif k == KEY_ESCAPE or k == KEY_BACKSPACE:
		if step == "brief":
			show_step("target")
		elif step == "target":
			show_step("nation")
		elif game.in_patrol:
			game.resume()
