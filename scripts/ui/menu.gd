extends CanvasLayer
## Main menu: pick the war (1939-45 or the near future), a navy or boat, a
## target, read the orders, sail.

const GameData := preload("res://scripts/data.gd")
const Style := preload("res://scripts/ui/style.gd")

var game
var root: Control
var body: VBoxContainer
var nat_id := ""
var tgt_id := ""
var step := "nation"
var era := "ww2"


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
	v.add_child(Style.label("Take the conn of a submarine. Find the warship, slip the escorts and the aircraft, and sink her.", 17, Style.TEXT))
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


func _order() -> Array:
	return GameData.MODERN_ORDER if era == "modern" else GameData.NATION_ORDER


func _set_era(e: String) -> void:
	era = e
	show_step("nation")


func _nations() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	for e in [["ww2", "WORLD WAR II, 1939-45"], ["modern", "NEAR FUTURE: WESTERN PACIFIC"]]:
		var b := Style.button(e[1], func(): _set_era(e[0]), 15, era == e[0])
		tabs.add_child(b)
	var hint := Style.label("Tab switches", 13, Style.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tabs.add_child(hint)
	body.add_child(tabs)
	if era == "modern":
		body.add_child(Style.label("A fictional war at sea in the 2030s. Nuclear boats with wire-guided torpedoes and cruise missiles, against a screen that hunts you with sonar and helicopters and shoots missiles down.", 14, Style.TEXT, true))
	body.add_child(Style.label(Style.spaced("CHOOSE YOUR BOAT" if era == "modern" else "CHOOSE YOUR NAVY"), 14, Style.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	var nations := GameData.nations()
	var order := _order()
	for i in order.size():
		var nid: String = order[i]
		var nat: Dictionary = nations[nid]
		var modern := GameData.is_modern(nat)
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
		var bd := Style.badge(String(nat.get("navy", nid)))
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
		var rows := [["Submerged", "%s kn" % str(nat["sub_kn"])], ["Surfaced", "%s kn" % str(nat["surf_kn"])], ["Test depth", "%d m" % int(nat["test"])],
				["Dive time", "%d s" % int(nat["dive_time"])], ["Tubes / load", "%d / %d" % [nat["tubes"], nat["torps"]]],
				["Torpedo", nat["torp"]["name"]], ["Run", "%.1f km, %d kn" % [float(nat["torp"]["range"]) / 1000.0, int(nat["torp"]["kn"])]],
				["Wake", "visible" if nat["torp"]["wake"] else "none"], ["Deck gun", (nat["gun"] as Dictionary).get("name", "none")]]
		if modern:
			rows = [["Submerged", "%s kn" % str(nat["sub_kn"])], ["Test depth", "%d m" % int(nat["test"])], ["Power", "nuclear"],
				["Tubes / load", "%d / %d" % [nat["tubes"], nat["torps"]]], ["Torpedo", nat["torp"]["name"]],
				["Run", "%d km, %d kn, wire" % [int(float(nat["torp"]["range"]) / 1000.0), int(nat["torp"]["kn"])]],
				["Missiles", _missile_text(nat)], ["Decoys", str(nat.get("decoys", 0))]]
		for kv in rows:
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


## "4 Harpoon, 12 Tomahawk" for a boat's missile load.
static func _missile_text(nat: Dictionary) -> String:
	var ms: Dictionary = nat.get("missiles", {})
	var parts := []
	for k in ["harpoon", "tomahawk"]:
		if int(ms.get(k, 0)) > 0:
			parts.append("%d %s" % [int(ms[k]), GameData.MISSILES[k]["name"]])
	if int(ms.get("trident", 0)) > 0:
		parts.append("%d Trident test round" % int(ms["trident"]))
	return ", ".join(parts) if not parts.is_empty() else "none"


func _pick_nation(nid: String) -> void:
	nat_id = nid
	show_step("target")


func _targets() -> void:
	var nat: Dictionary = GameData.nations()[nat_id]
	var modern := GameData.is_modern(nat)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var bd := Style.badge(String(nat.get("navy", nat_id)))
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
		if modern:
			top.add_child(Style.label("SCENARIO", 12, Style.AMBER))
		else:
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
		var rows := [["Type", GameData.TYPE_NAMES[tg["type"]]], ["Escorts", "%d DD, %d small" % [tg["escorts"], tg["chasers"]]],
				["Aircraft", "none" if tg["air"].is_empty() or tg["tod"] == "night" else str(tg["air"].size())],
				["Conditions", tg["tod"].capitalize()], ["Hits to sink", str(tg["hp"])]]
		if modern:
			rows = [["Type", GameData.TYPE_NAMES[tg["type"]]], ["Screen", "%d warships" % tg.get("group", []).size()],
				["Helicopters", str(tg["air"].size())], ["Conditions", tg["tod"].capitalize()],
				["Out of action", "about 5 missile hits"] if tg.get("goal", "") == "disable" else ["Mk 48 hits", str(tg["hp"])]]
			if tg.has("start"):
				rows.insert(1, ["Range", "about %d km" % int(float(tg["start"][0]) / 1000.0)])
			if tg.get("goal", "") == "patrol":
				rows = [["Mission", "Test launch"], ["Launch box", "%d km north" % int((tg["box"] as Vector2).length() / 1000.0)],
					["Hunters", "2 submarines, a frigate"], ["Aircraft", "%d" % tg["air"].size()], ["Conditions", tg["tod"].capitalize()]]
		for kv in rows:
			info.add_child(Style.label(kv[0], 12, Style.MUTED))
			info.add_child(Style.label(kv[1], 12, Style.TEXT))
		hb.add_child(info)


func _pick_target(tid: String) -> void:
	tgt_id = tid
	show_step("brief")


func _brief() -> void:
	var nat: Dictionary = GameData.nations()[nat_id]
	var modern := GameData.is_modern(nat)
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
	var kind_txt: String = "Test launch" if tg.get("goal", "") == "patrol" else GameData.TYPE_NAMES[tg["type"]]
	left.add_child(Style.label("%s   |   %s" % [kind_txt, tg["credit"]], 15, Style.BRASS))
	var note := Style.label(tg["note"], 15, Style.TEXT, true)
	note.custom_minimum_size = Vector2(520, 0)
	left.add_child(note)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 20)
	var air := "none"
	if not tg["air"].is_empty() and (tg["tod"] != "night" or modern):
		var names := []
		for a in tg["air"]:
			names.append(GameData.AIRCRAFT[a]["name"])
		air = ", ".join(names)
	var rows := [["Your boat", "%s, %d %s torpedoes" % [nat["boat"], nat["torps"], nat["torp"]["name"]]],
			["Conditions", tg["tod"].capitalize() + (", red lighting below" if tg["tod"] == "night" else "")],
			["Target", ("at anchor" if tg["kn"] == 0 else "about %d knots" % int(tg["kn"])) + (", zigzagging" if tg["zig"] else "")],
			["Screen", "%d destroyers, %d sub-chasers" % [tg["escorts"], tg["chasers"]]], ["Air cover", air],
			["Draft", "about %d m: set torpedoes shallower than that" % int(tg["draft"])],
			["To sink her", "about %d torpedo hits, fewer all down one side" % tg["hp"]]]
	if modern:
		# "Yan'an (cruiser), Guiyang and Chengdu (destroyers), Yueyang (frigate)"
		var kinds := {"cg": "cruiser", "ddg": "destroyer", "ffg": "frigate", "cv": "carrier", "ssn": "attack submarine"}
		var by_type := {}
		var order := []
		for e in tg.get("group", []):
			if not by_type.has(e["type"]):
				by_type[e["type"]] = []
				order.append(e["type"])
			by_type[e["type"]].append(e["name"])
		var screen := []
		for ty in order:
			var names: Array = by_type[ty]
			screen.append("%s (%s%s)" % [" and ".join(names), kinds.get(ty, "warship"), "s" if names.size() > 1 else ""])
		var helos := {}
		for a in tg["air"]:
			helos[a] = int(helos.get(a, 0)) + 1
		var hl := []
		for a in helos:
			var nm: String = GameData.AIRCRAFT[a]["name"]
			hl.append("a %s" % nm if int(helos[a]) == 1 else "%s %ss" % [["", "one", "two", "three", "four"][mini(int(helos[a]), 4)], nm])
		air = ", ".join(hl) if not hl.is_empty() else "none"
		var boat := "%s, %d %ss" % [nat["boat"], nat["torps"], nat["torp"]["name"]]
		if (nat.get("missiles", {}) as Dictionary).size() > 0:
			boat += ", " + _missile_text(nat)
		rows = [["Your boat", boat + ", %d decoys" % nat.get("decoys", 0)],
			["Conditions", tg["tod"].capitalize()],
			["Target", "about 6 knots, deep, below the layer" if tg["type"] in ["ssn", "ssbn"] else "about %d knots, zigzagging" % int(float(tg["kn"]) * 0.7)],
			["Screen", ", ".join(screen)], ["Helicopters", air]]
		if tg.has("start") and tg["type"] in ["ssn", "ssbn"]:
			rows.insert(2, ["Range", "about %d km, deep and slow. Intelligence gives a rough bearing; find her by ear." % int(float(tg["start"][0]) / 1000.0)])
		elif tg.has("start"):
			rows.insert(2, ["Range", "about %d km, far beyond sonar. The satellite link gives her position." % int(float(tg["start"][0]) / 1000.0)])
		if tg.get("goal", "") == "patrol":
			var hunters := ["%s (Type 093)" % tg["target_name"]]
			for e in tg.get("group", []):
				hunters.append("%s (%s)" % [e["name"], "Type 093" if e["type"] == "ssn" else "frigate"])
			rows = [["Your boat", boat + ", %d decoys" % nat.get("decoys", 0)],
				["Conditions", tg["tod"].capitalize()],
				["Launch box", "%d km north, %d km across. Hover at 25 to 45 m, under 3 knots, for a minute." % [
					int((tg["box"] as Vector2).length() / 1000.0), int(float(tg["box_r"]) * 2.0 / 1000.0)]],
				["Hunters", ", ".join(hunters)], ["Aircraft", air],
				["Weapons", "Mk 48s and decoys to defend yourself. Better not to be found at all."],
				["To win", "fire the test round from the box"]]
		if tg.get("goal", "") == "patrol":
			pass
		elif tg.get("goal", "") == "disable":
			rows.append(["Weapons", "Tomahawks: a big salvo arriving together swamps their air defence. Mk 48s for close in."])
			rows.append(["To win", "wreck her: about 5 Tomahawk hits put her out of action, or sink her with about %d Mk 48s" % tg["hp"]])
		else:
			var wpn := "Mk 48s run out on the wire, then home on what they hear and burst under her keel"
			if tg["type"] in ["ssn", "ssbn"]:
				wpn += ". Missiles are no use against a boat that stays deep."
			elif (nat.get("missiles", {}) as Dictionary).size() > 0:
				wpn += ". Missiles reach much farther, but a handful won't get through this screen."
			rows.append(["Weapons", wpn])
			rows.append(["To sink her", "about %d Mk 48 hits" % tg["hp"]])
	for kv in rows:
		g.add_child(Style.label(kv[0], 14, Style.MUTED))
		var val := Style.label(kv[1], 14, Style.TEXT, true)
		val.custom_minimum_size = Vector2(440, 0)
		g.add_child(val)
	left.add_child(g)
	var tip_text := "Approach at periscope depth and keep the scope up only in short looks. Lock her on the TDC and let the solution settle. Fire from 1,000 to 2,500 metres off her beam. When escorts turn on you, go deep, slow down and change course. Planes spot surfaced boats from far away: dive when the lookouts call them."
	if modern and tg.get("goal", "") == "patrol":
		tip_text = "Stay deep, below the layer, and slow: under about 6 knots an Ohio is almost silent. Listen for the hunters on the towed array and give them a wide berth; their attack boats sprint and then drift to listen. Small splashes mean the patrol aircraft is laying sonobuoys: go round the line or creep through it. In the box, come up to 30 to 40 m, slow to a hover, pick the Trident (Q) and press X. The launch takes a minute, and once she goes, everyone knows where you are."
	elif modern and tg["type"] in ["ssn", "ssbn"]:
		tip_text = "She's deep and quiet, and her escort is quieter still. Go slow and listen: the array hears her before she hears you. Track her (L), change legs to firm up the range, and get under the layer with her. The Mk 48s run out at her depth and home in three dimensions. If a launch transient comes, decoys and a hard turn, then answer down its bearing."
	elif modern and tg.has("start"):
		tip_text = "Come up to periscope depth, raise the mast (P) and take the link: it gives the whole group's positions every few minutes. Pick Tomahawks (Q), set the salvo ([ ]) and fire (X) from above 45 m at under 10 knots. Their missiles and guns will knock down most of a small salvo; it takes around 60 arriving together to swamp them. Their picket will see the launch, so go deep and slow afterwards. Leaving the mast up lets the Tomahawks take fresher aim points."
	elif modern:
		tip_text = "Close in deep and slow: under about 10 knots the escorts' sonar can barely hear you. Listen on the towed array, lock her on sonar (L) and change course now and then so fire control can work out her range. A short look through the photonics mast firms it up, but their radars may see it. Fire from 8 to 20 km and keep the wire on. When a torpedo comes for you: launch decoys (N), turn away, run deep across the layer, then slow down and creep off."
	var tip := Style.label(tip_text, 14, Style.MUTED, true)
	tip.custom_minimum_size = Vector2(520, 0)
	left.add_child(tip)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	hb.add_child(right)
	right.add_child(Style.label(Style.spaced("CONTROLS"), 14, Style.MUTED))
	var cg := GridContainer.new()
	cg.columns = 2
	cg.add_theme_constant_override("h_separation", 16)
	for row in (GameData.HELP_MODERN if modern else GameData.HELP):
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
		if step == "nation" and i < _order().size():
			_pick_nation(_order()[i])
		elif step == "target":
			var ts: Array = GameData.nations()[nat_id]["targets"]
			if i < ts.size():
				_pick_target(ts[i]["id"])
	elif k == KEY_TAB:
		if step == "nation":
			_set_era("ww2" if era == "modern" else "modern")
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
