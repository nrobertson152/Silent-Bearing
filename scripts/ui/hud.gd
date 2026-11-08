extends CanvasLayer
## In-patrol interface: status bar, crew reports, interaction prompts, the
## sights overlay, station panels, help, pause and the end-of-patrol report.

const GameData := preload("res://scripts/data.gd")
const Instruments := preload("res://scripts/ui/instruments.gd")
const Style := preload("res://scripts/ui/style.gd")
const U := preload("res://scripts/util.gd")
const ViewOverlay := preload("res://scripts/ui/view_overlay.gd")
const World := preload("res://scripts/sim/world.gd")

var game
var root: Control
var overlay: ViewOverlay
var top_left: Label
var top_mid: Label
var top_right: Label
var threat: Label
var log_box: VBoxContainer
var prompt: Label
var station_panel: PanelContainer
var station_title: Label
var station_ins: Instruments
var help: PanelContainer
var pause: PanelContainer
var result: PanelContainer
var _last_log := -1


func build(g) -> void:
	game = g
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Style.theme()
	add_child(root)
	overlay = ViewOverlay.new()
	overlay.game = g
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Style.box(Color(0.05, 0.06, 0.065, 0.82), Style.SEAM, 0, 0, 12))
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	bar.add_child(hb)
	top_left = Style.label("", 15, Style.BRASS)
	hb.add_child(top_left)
	top_mid = Style.label("", 15, Style.TEXT)
	top_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(top_mid)
	threat = Style.label("", 15, Style.GOOD)
	hb.add_child(threat)
	top_right = Style.label("", 15, Style.AMBER)
	hb.add_child(top_right)

	log_box = VBoxContainer.new()
	log_box.anchor_top = 1.0
	log_box.anchor_bottom = 1.0
	log_box.offset_left = 16
	log_box.offset_top = -230
	log_box.offset_right = 760
	log_box.offset_bottom = -16
	log_box.alignment = BoxContainer.ALIGNMENT_END
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_box)

	prompt = Style.label("", 18, Style.BRASS)
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.offset_top = -260
	prompt.offset_bottom = -230
	root.add_child(prompt)

	station_panel = PanelContainer.new()
	station_panel.set_anchors_preset(Control.PRESET_CENTER)
	station_panel.offset_left = -470
	station_panel.offset_right = 470
	station_panel.offset_top = -340
	station_panel.offset_bottom = 340
	var sv := VBoxContainer.new()
	station_panel.add_child(sv)
	station_title = Style.label("", 20, Style.BRASS)
	sv.add_child(station_title)
	station_ins = Instruments.new()
	station_ins.custom_minimum_size = Vector2(900, 600)
	sv.add_child(station_ins)
	sv.add_child(Style.label("E or Esc to step away.   Orders still work: arrows, R / F, C, [ ].", 14, Style.MUTED))
	station_panel.visible = false
	root.add_child(station_panel)

	help = _help_panel()
	help.visible = false
	root.add_child(help)
	pause = _pause_panel()
	pause.visible = false
	root.add_child(pause)
	result = PanelContainer.new()
	result.visible = false
	root.add_child(result)


func _help_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -430
	p.offset_right = 430
	p.offset_top = -310
	p.offset_bottom = 310
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 4)
	p.add_child(g)
	for row in GameData.HELP:
		g.add_child(Style.label(row[0], 15, Style.AMBER))
		g.add_child(Style.label(row[1], 15, Style.TEXT))
	return p


func _pause_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -210
	p.offset_right = 210
	p.offset_top = -150
	p.offset_bottom = 150
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var t := Style.label(Style.spaced("PATROL PAUSED"), 26, Style.BRASS)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(Style.button("Resume patrol", func(): game.resume(), 18, true))
	v.add_child(Style.button("Abandon patrol", func(): game.to_menu("target")))
	v.add_child(Style.button("Quit to desktop", func(): game.get_tree().quit()))
	return p


func show_result() -> void:
	var w: World = game.world
	var tg := w.target
	for c in result.get_children():
		c.queue_free()
	result.set_anchors_preset(Control.PRESET_CENTER)
	result.offset_left = -380
	result.offset_right = 380
	result.offset_top = -280
	result.offset_bottom = 280
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	result.add_child(v)
	var heads := {
		"win": ["SUNK", "%s is going to the bottom. Take her down and slip away." % tg.name, Style.GOOD],
		"lost": ["LOST WITH ALL HANDS", "The enemy broke your hull.", Style.ALARM],
		"crushed": ["CRUSH DEPTH", "The pressure hull gave way below %d metres." % int(w.nat["crush"]), Style.ALARM],
		"escaped": ["TARGET ESCAPED", "%s outran you and slipped away." % tg.name, Style.AMBER],
		"dry": ["OUT OF TORPEDOES", "Every tube is empty and %s is still afloat." % tg.short, Style.AMBER],
	}
	var h: Array = heads.get(w.result, ["PATROL OVER", "", Style.TEXT])
	v.add_child(Style.label(Style.spaced(h[0]), 34, h[2]))
	v.add_child(Style.label(h[1], 17, Style.TEXT, true))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 30)
	for kv in [["Patrol time", U.clock(w.t)], ["Torpedoes fired", str(w.fired)], ["Torpedo hits", str(w.hits)], ["Duds", str(w.duds)],
			["Shell hits", str(w.gun_hits)], ["Escorts sunk", str(w.esc_sunk)], ["Aircraft shot down", str(w.planes_down)], ["Hull", "%d%%" % int(w.sub.hull)]]:
		var vb := VBoxContainer.new()
		vb.add_child(Style.label(kv[0].to_upper(), 12, Style.MUTED))
		vb.add_child(Style.label(kv[1], 20, Style.TEXT))
		g.add_child(vb)
	v.add_child(g)
	v.add_child(HSeparator.new())
	v.add_child(Style.label(Style.spaced("IN HISTORY" if w.spec["historical"] else "WHAT REALLY HAPPENED"), 13, Style.BRASS))
	v.add_child(Style.label(w.spec["credit"], 16, Style.TEXT))
	var note := Style.label(w.spec["note"], 15, Style.TEXT, true)
	note.custom_minimum_size = Vector2(700, 0)
	v.add_child(note)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.add_child(Style.button("Try again", func(): game.restart(), 17, true))
	hb.add_child(Style.button("New target", func(): game.to_menu("target"), 17))
	hb.add_child(Style.button("Quit", func(): game.get_tree().quit(), 17))
	v.add_child(hb)
	result.visible = true


func open_station(kind: String, title: String) -> void:
	station_ins.kind = kind
	station_ins.world = game.world
	station_ins.chart_r = game.chart_r
	station_title.text = Style.spaced(title.to_upper())
	station_panel.visible = true


func close_station() -> void:
	station_panel.visible = false


func update(dt: float) -> void:
	var w: World = game.world
	if w == null:
		return
	var s := w.sub
	top_left.text = "%s  vs  %s" % [w.nat["boat"], w.target.name]
	var dep := "SURFACED" if s.surfaced() else ("%d m (ordered %s)" % [int(s.depth), "SURFACE" if s.dep_ord <= 0.0 else "%d" % int(s.dep_ord)])
	top_mid.text = "%s   %s   %s   %.1f kn   HDG %s   BAT %d%%   HULL %d%%" % [World.TELEGRAPH[s.tel][0], World.RUDDER[s.rud_i][1], dep,
		s.spd, U.p3(s.hdg), int(s.bat), int(s.hull)]
	var th := w.threat()
	threat.text = th[0]
	threat.add_theme_color_override("font_color", Style.kind_color(th[1]))
	top_right.text = "%s   %dx" % [U.clock(w.t), w.tc]
	if w.msgs.size() != _last_log:
		_last_log = w.msgs.size()
		for c in log_box.get_children():
			c.queue_free()
		var n := mini(7, w.msgs.size())
		for i in range(w.msgs.size() - n, w.msgs.size()):
			var m: Array = w.msgs[i]
			var l := Style.label("%s  %s" % [U.clock(m[0]).substr(3), m[1]], 15, Style.kind_color(m[2]), true)
			l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
			l.add_theme_constant_override("shadow_offset_x", 1)
			l.add_theme_constant_override("shadow_offset_y", 1)
			log_box.add_child(l)
	if station_panel.visible:
		station_ins.chart_r = game.chart_r
