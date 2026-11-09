## Paint schemes and deck finishes for every ship and boat, built on
## shaders/paint.gdshader, shaders/deck.gdshader and shaders/plain.gdshader.
##
## Each target wears the camouflage she carried at the time of the attack
## where that is known: Measure 12 graded bands on Yorktown at Midway,
## Measure 12 (Modified) splotches on Wasp and Juneau, Measure 22 on
## Indianapolis in July 1945, Measure 21 navy blue on Enterprise, a light and
## dark grey splinter scheme on Tirpitz in Norway in 1942, Baltic stripes on
## Prinz Eugen after the Channel Dash, and plain fleet greys elsewhere.

const MeshKit := preload("res://scripts/build/mesh_kit.gd")

# Paint colours (sRGB), after wartime references.
const US_NAVY_BLUE := Color(0.21, 0.25, 0.32)      # 5-N
const US_OCEAN_GRAY := Color(0.38, 0.41, 0.45)     # 5-O
const US_HAZE_GRAY := Color(0.55, 0.58, 0.60)      # 5-H
const US_DECK_BLUE := Color(0.17, 0.20, 0.25)      # 20-B
const US_FLIGHT_STAIN := Color(0.24, 0.27, 0.31)   # Flight Deck Stain 21
const RN_507A := Color(0.33, 0.35, 0.37)           # Home Fleet dark grey
const RN_507B := Color(0.43, 0.45, 0.47)           # medium grey
const RN_507C := Color(0.57, 0.59, 0.60)           # Mediterranean light grey
const RN_WHITE := Color(0.80, 0.82, 0.82)
const RN_B55 := Color(0.56, 0.62, 0.66)            # light blue-grey
const RN_B5 := Color(0.25, 0.31, 0.38)             # dark blue-grey
const KM_HELLGRAU := Color(0.58, 0.60, 0.61)       # 50
const KM_DUNKELGRAU := Color(0.37, 0.39, 0.41)     # 51
const KM_BLACK := Color(0.07, 0.07, 0.075)
const KM_WHITE := Color(0.86, 0.87, 0.87)
const IJN_GREY := Color(0.40, 0.42, 0.43)          # Kure grey
const TEAK := Color(0.56, 0.49, 0.39)
const HINOKI := Color(0.62, 0.55, 0.43)
const PINE := Color(0.55, 0.49, 0.39)
const FIR := Color(0.50, 0.42, 0.32)
const LINOLEUM := Color(0.36, 0.27, 0.20)

## scheme: 0 plain, 1 two bands, 2 three bands, 3 splotch, 4 splinter, 5 Baltic, 6 light disruptive.
## Band heights are in metres; "fd" adds the flight deck height for carriers.
static func scheme(key: String) -> Dictionary:
	match key:
		"yorktown":  # Measure 12, graded: navy blue, ocean gray from the hangar deck, haze gray up top
			return {"scheme": 2, "c": [US_NAVY_BLUE, US_OCEAN_GRAY, US_HAZE_GRAY], "y0": 8.5, "y1": 9.0, "fd": true,
				"top": US_DECK_BLUE, "deck": "us", "flight": "us", "rust": 0.45}
		"wasp", "juneau":  # Measure 12 (Modified) splotches
			return {"scheme": 3, "c": [US_NAVY_BLUE, US_OCEAN_GRAY, US_HAZE_GRAY], "y0": 8.0, "y1": 9.0 if key == "wasp" else 16.0,
				"fd": key == "wasp", "top": US_DECK_BLUE, "deck": "us", "flight": "us", "rust": 0.35, "scale": 1.0 if key == "wasp" else 0.7}
		"enterprise", "dd_us":  # Measure 21: navy blue overall
			return {"scheme": 0, "c": [US_NAVY_BLUE], "top": US_DECK_BLUE, "deck": "us", "flight": "us",
				"rust": 0.4 if key == "enterprise" else 0.55}
		"indianapolis":  # Measure 22: navy blue to the lowest deck line, haze gray above
			return {"scheme": 1, "c": [US_NAVY_BLUE, US_HAZE_GRAY], "y0": 8.0, "top": US_DECK_BLUE, "deck": "us", "rust": 0.3}
		"tirpitz":  # Norway 1942: light and dark grey splinter
			return {"scheme": 4, "c": [KM_DUNKELGRAU, KM_HELLGRAU, Color(0.48, 0.5, 0.51)], "top": Color(0.4, 0.4, 0.4),
				"deck": "teak_km", "rust": 0.3, "scale": 1.3}
		"prinz":  # February 1942: Baltic stripes
			return {"scheme": 5, "c": [KM_HELLGRAU, KM_HELLGRAU, KM_WHITE, KM_BLACK], "top": Color(0.42, 0.42, 0.42),
				"deck": "teak_km", "rust": 0.25}
		"karlsruhe", "dd_de":
			return {"scheme": 1, "c": [KM_DUNKELGRAU, KM_HELLGRAU], "y0": 1.6, "top": Color(0.42, 0.42, 0.42),
				"deck": "teak_km" if key == "karlsruhe" else "steel_km", "rust": 0.3 if key == "karlsruhe" else 0.5}
		"royaloak", "courageous":
			return {"scheme": 0, "c": [RN_507A], "top": Color(0.36, 0.37, 0.38), "deck": "teak_rn", "flight": "steel_rn", "rust": 0.35}
		"hood", "arkroyal":
			return {"scheme": 0, "c": [RN_507B], "top": Color(0.4, 0.41, 0.42), "deck": "teak_rn", "flight": "steel_rn", "rust": 0.3}
		"barham":
			return {"scheme": 0, "c": [RN_507C], "top": Color(0.45, 0.46, 0.46), "deck": "teak_rn", "rust": 0.35}
		"dd_uk":  # Admiralty light disruptive
			return {"scheme": 6, "c": [RN_WHITE, RN_B55, RN_B5], "top": Color(0.4, 0.42, 0.44), "deck": "steel_rn", "rust": 0.55, "scale": 0.6}
		"shinano", "taiho":
			return {"scheme": 0, "c": [IJN_GREY], "top": Color(0.36, 0.37, 0.37), "deck": "hinoki", "flight": "jp", "rust": 0.1}
		"shokaku":
			return {"scheme": 0, "c": [IJN_GREY], "top": Color(0.36, 0.37, 0.37), "deck": "hinoki", "flight": "jp", "rust": 0.3}
		"yamato", "kongo":
			return {"scheme": 0, "c": [IJN_GREY], "top": Color(0.36, 0.37, 0.37), "deck": "hinoki", "rust": 0.3 if key == "yamato" else 0.4}
		"ashigara", "kuma", "dd_jp":
			return {"scheme": 0, "c": [IJN_GREY], "top": Color(0.36, 0.37, 0.37), "deck": "linoleum", "rust": 0.5}
		"pc":
			return {"scheme": 0, "c": [Color(0.44, 0.45, 0.46)], "top": Color(0.38, 0.38, 0.38), "deck": "pine", "rust": 0.75}
	return {"scheme": 0, "c": [Color(0.45, 0.47, 0.49)], "top": Color(0.38, 0.39, 0.4), "deck": "teak_rn", "rust": 0.4}


static func _shader(path: String) -> Shader:
	return load(path)


static func paint_mat(s: Dictionary, part: int, lay: Dictionary, L: float, seed_v: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/paint.gdshader")
	var c: Array = s["c"]
	m.set_shader_parameter("part", part)
	m.set_shader_parameter("scheme", s["scheme"])
	m.set_shader_parameter("c0", c[0])
	m.set_shader_parameter("c1", c[1] if c.size() > 1 else c[0])
	m.set_shader_parameter("c2", c[2] if c.size() > 2 else (c[1] if c.size() > 1 else c[0]))
	m.set_shader_parameter("c3", c[3] if c.size() > 3 else KM_BLACK)
	m.set_shader_parameter("top_col", s.get("top", Color(0.35, 0.36, 0.37)))
	var y0: float = s.get("y0", 8.0)
	var y1: float = s.get("y1", 22.0)
	if s.get("fd", false) and lay.has("deck"):
		y1 += float(lay["deck"]["h"])
	m.set_shader_parameter("y0", y0)
	m.set_shader_parameter("y1", y1)
	m.set_shader_parameter("hull_len", L)
	m.set_shader_parameter("fb", float(lay.get("fb", 8.0)))
	m.set_shader_parameter("fb_bow", float(lay.get("fb_bow", 10.0)))
	m.set_shader_parameter("seed", seed_v)
	m.set_shader_parameter("rust", float(s.get("rust", 0.4)) * (0.6 if part == 1 else 1.0))
	m.set_shader_parameter("scale", float(s.get("scale", 1.0)))
	return m


## Deck finish by name.
static func deck_mat(kind: String, rust: float, seed_v: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/deck.gdshader")
	m.set_shader_parameter("seed", seed_v)
	m.set_shader_parameter("rust", rust)
	match kind:
		"us":  # Wooden decks stained Deck Blue
			m.set_shader_parameter("wood", TEAK)
			m.set_shader_parameter("stain", US_DECK_BLUE)
			m.set_shader_parameter("stained", 1.0)
			m.set_shader_parameter("steel_col", US_DECK_BLUE)
			m.set_shader_parameter("wear", 0.6)
		"flight_us":  # Douglas fir laid athwartships, Flight Deck Stain
			m.set_shader_parameter("wood", FIR)
			m.set_shader_parameter("stain", US_FLIGHT_STAIN)
			m.set_shader_parameter("stained", 1.0)
			m.set_shader_parameter("across", 1.0)
			m.set_shader_parameter("plank", 0.16)
			m.set_shader_parameter("plank_len", 9.0)
			m.set_shader_parameter("wear", 0.7)
		"flight_jp":  # bare wooden flight deck
			m.set_shader_parameter("wood", Color(0.48, 0.42, 0.34))
			m.set_shader_parameter("plank", 0.16)
			m.set_shader_parameter("plank_len", 9.0)
			m.set_shader_parameter("wear", 0.5)
		"teak_km", "teak_rn":
			m.set_shader_parameter("wood", TEAK.lightened(0.08) if kind == "teak_km" else TEAK)
			m.set_shader_parameter("wear", 0.55)
		"hinoki":
			m.set_shader_parameter("wood", HINOKI)
			m.set_shader_parameter("wear", 0.5)
		"pine":
			m.set_shader_parameter("wood", PINE.darkened(0.15))
			m.set_shader_parameter("wear", 0.8)
		"linoleum":
			m.set_shader_parameter("steel", 1.0)
			m.set_shader_parameter("steel_col", LINOLEUM)
			m.set_shader_parameter("wear", 0.5)
		"steel_rn", "flight_rn":
			m.set_shader_parameter("steel", 1.0)
			m.set_shader_parameter("steel_col", Color(0.36, 0.37, 0.38))
		"steel_km":
			m.set_shader_parameter("steel", 1.0)
			m.set_shader_parameter("steel_col", Color(0.4, 0.4, 0.41))
		_:
			m.set_shader_parameter("steel", 1.0)
	return m


## Plain paint for small fittings, which can be torn in two with the hull.
static func plain(color: Color, rough := 0.85, metal := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/plain.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	return m


## The full material set ShipBuilder expects for one ship.
static func ship(key: String, lay: Dictionary, L: float) -> Dictionary:
	var s := scheme(key)
	var seed_v := float(hash(key) % 1000) * 0.137
	var rust: float = s.get("rust", 0.4)
	var hull := paint_mat(s, 0, lay, L, seed_v)
	if lay["hull"] in ["bb", "ca", "cv"]:
		hull.set_shader_parameter("scuttle_y", float(lay["fb"]) - 1.6)
	var c: Array = s["c"]
	var base: Color = c[0]
	var fitting := paint_mat({"scheme": 0, "c": [base.darkened(0.2)], "rust": rust}, 2, lay, L, seed_v)
	fitting.set_shader_parameter("rough", 0.6)
	fitting.set_shader_parameter("metal", 0.25)
	var fl := String(s.get("flight", "jp"))
	var flight_kind := "flight_rn" if fl == "steel_rn" else "flight_" + fl
	return {
		"hull": hull,
		"boot": paint_mat({"scheme": 0, "c": [Color(0.07, 0.07, 0.08)], "rust": rust}, 4, lay, L, seed_v),
		"bottom": paint_mat({"scheme": 0, "c": [Color(0.40, 0.13, 0.10)], "rust": rust}, 3, lay, L, seed_v),
		"super": paint_mat(s, 1, lay, L, seed_v),
		"deck": deck_mat(String(s.get("deck", "teak_rn")), rust, seed_v),
		"flight": deck_mat(flight_kind, rust, seed_v + 3.0),
		"metal": fitting,
		"black": plain(Color(0.04, 0.04, 0.04), 0.9),
		"window": plain(Color(0.04, 0.05, 0.06), 0.12, 0.2),
		"white": plain(Color(0.86, 0.86, 0.82), 0.8),
		"boat": plain(Color(0.70, 0.71, 0.68), 0.8),
		"red": plain(Color(0.72, 0.10, 0.10), 0.8),
		"wood": plain(Color(0.45, 0.33, 0.22), 0.9),
		"plane": plain(Color(0.32, 0.38, 0.30) if String(lay.get("paint", "")).begins_with("jp") else Color(0.36, 0.43, 0.50), 0.7),
	}


## Your own boat. Patrol boats came home streaked with rust and salt.
static func sub(nation: String, hull: Color, deck: Color, L := 80.0) -> Dictionary:
	var lay := {"fb": 1.3, "fb_bow": 1.3}
	var seed_v := float(hash(nation) % 1000) * 0.21
	var rust := {"de": 0.75, "us": 0.45, "uk": 0.55, "jp": 0.5}.get(nation, 0.5) as float
	var hm := paint_mat({"scheme": 0, "c": [hull], "rust": rust}, 0, lay, L, seed_v)
	hm.set_shader_parameter("rough", 0.7)
	hm.set_shader_parameter("metal", 0.1)
	hm.set_shader_parameter("grime", 0.8)
	hm.set_shader_parameter("band", 0.7)
	var deck_kind := {"us": "pine", "de": "pine", "uk": "steel_rn", "jp": "pine"}.get(nation, "pine") as String
	var dm := deck_mat(deck_kind, rust, seed_v)
	if deck_kind == "pine":
		dm.set_shader_parameter("wood", deck)
		dm.set_shader_parameter("plank", 0.12)
		dm.set_shader_parameter("plank_len", 4.0)
	else:
		dm.set_shader_parameter("steel_col", deck)
	return {"hull": hm, "deck": dm,
		"bottom": paint_mat({"scheme": 0, "c": [Color(0.38, 0.12, 0.10)], "rust": rust}, 3, lay, L, seed_v),
		"metal": paint_mat({"scheme": 0, "c": [hull.lightened(0.12)], "rust": rust}, 2, lay, L, seed_v)}
