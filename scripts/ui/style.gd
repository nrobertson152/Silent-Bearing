class_name Style
## Shared colours, theme and small widget helpers for the control-room UI.

const HULL := Color(0.07, 0.085, 0.09)
const PLATE := Color(0.12, 0.145, 0.155)
const PLATE2 := Color(0.165, 0.195, 0.21)
const SEAM := Color(0.04, 0.05, 0.055)
const BRASS := Color(0.79, 0.65, 0.36)
const BRASS_LO := Color(0.47, 0.38, 0.22)
const TEXT := Color(0.86, 0.84, 0.78)
const MUTED := Color(0.55, 0.58, 0.55)
const PHOS := Color(0.56, 0.86, 0.66)
const AMBER := Color(0.94, 0.71, 0.30)
const ALARM := Color(0.91, 0.35, 0.25)
const GOOD := Color(0.59, 0.80, 0.50)


static func kind_color(k: String) -> Color:
	match k:
		"alarm":
			return ALARM
		"warn":
			return AMBER
		"good":
			return GOOD
	return TEXT


static func box(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 4, pad := 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


static func theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 16
	th.set_color("font_color", "Label", TEXT)
	th.set_stylebox("normal", "Button", box(PLATE2, SEAM, 1))
	th.set_stylebox("hover", "Button", box(PLATE2.lightened(0.08), BRASS_LO, 1))
	th.set_stylebox("pressed", "Button", box(Color(0.25, 0.21, 0.13), BRASS, 1))
	th.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), BRASS, 2))
	th.set_stylebox("disabled", "Button", box(PLATE, SEAM, 1))
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", BRASS)
	th.set_color("font_pressed_color", "Button", AMBER)
	th.set_stylebox("panel", "PanelContainer", box(PLATE, SEAM, 2, 6, 18))
	th.set_stylebox("panel", "Panel", box(PLATE, SEAM, 2, 6))
	return th


static func label(text: String, size := 16, color := TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, cb: Callable, size := 16, big := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if big:
		b.add_theme_stylebox_override("normal", box(BRASS, BRASS_LO, 2, 4, 16))
		b.add_theme_stylebox_override("hover", box(BRASS.lightened(0.12), BRASS_LO, 2, 4, 16))
		b.add_theme_stylebox_override("pressed", box(BRASS.darkened(0.1), BRASS_LO, 2, 4, 16))
		b.add_theme_color_override("font_color", Color(0.12, 0.1, 0.07))
		b.add_theme_color_override("font_hover_color", Color(0.12, 0.1, 0.07))
		b.add_theme_color_override("font_pressed_color", Color(0.12, 0.1, 0.07))
	b.pressed.connect(cb)
	return b


static func spaced(s: String) -> String:
	var out := ""
	for i in s.length():
		out += s[i]
		if i < s.length() - 1:
			out += " "
	return out


static func badge(nation: String) -> Control:
	var c := BadgeDraw.new()
	c.nation = nation
	c.custom_minimum_size = Vector2(72, 72)
	return c
