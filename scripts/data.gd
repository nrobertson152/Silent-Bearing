## Navies, player boats, torpedoes, deck guns, aircraft and the target warships.
##
## Figures are rounded from published wartime specifications and adjusted for
## play. Ship layouts are positions along the hull as fractions of length
## (0 = bow, 1 = stern) and sizes in metres. ShipBuilder turns them into meshes.
##
## The near-future missions are a fictional war in the Western Pacific. Their
## boats, ships and weapons are modelled on public figures, rounded and
## adjusted for play.

const PREFIX := {"us": "USS ", "uk": "HMS ", "jp": "", "de": "", "cn": ""}

const ESCORT_NAMES := {
	"jp": ["Isokaze", "Yukikaze", "Hamakaze", "Urakaze", "Hatsukaze"],
	"uk": ["Legion", "Laforey", "Hesperus", "Vanoc", "Walker"],
	"us": ["Hammann", "Balch", "Benham", "Gwin", "Monssen"],
	"de": ["Z23", "Z28", "Z30", "Z33", "Z24"],
}

const CHASER_NAMES := {
	"jp": ["CH-17", "CH-33", "CH-38"],
	"uk": ["HMT Lady Shirley", "HMT Northern Gem", "HMT Cayton Wyke"],
	"us": ["PC-487", "SC-521", "PC-565"],
	"de": ["UJ-1708", "UJ-1209", "UJ-1404"],
}

## Aircraft flown by each navy's air cover.
const AIRCRAFT := {
	"catalina": {"name": "PBY Catalina", "kn": 110, "span": 31.7, "len": 19.5, "engines": 2, "kind": "boat_parasol", "hp": 6, "bombs": 4},
	"dauntless": {"name": "SBD Dauntless", "kn": 190, "span": 12.7, "len": 10.1, "engines": 1, "kind": "single", "hp": 3, "bombs": 1},
	"sunderland": {"name": "Short Sunderland", "kn": 130, "span": 34.4, "len": 26.0, "engines": 4, "kind": "boat", "hp": 8, "bombs": 4},
	"swordfish": {"name": "Fairey Swordfish", "kn": 90, "span": 13.9, "len": 11.1, "engines": 1, "kind": "biplane", "hp": 3, "bombs": 2},
	"condor": {"name": "Fw 200 Condor", "kn": 170, "span": 32.8, "len": 23.5, "engines": 4, "kind": "land", "hp": 7, "bombs": 4},
	"arado": {"name": "Ar 196", "kn": 140, "span": 12.4, "len": 11.0, "engines": 1, "kind": "float", "hp": 3, "bombs": 2},
	"emily": {"name": "H8K Emily", "kn": 160, "span": 38.0, "len": 28.1, "engines": 4, "kind": "boat", "hp": 8, "bombs": 4},
	"kate": {"name": "B5N Kate", "kn": 160, "span": 15.5, "len": 10.3, "engines": 1, "kind": "single", "hp": 3, "bombs": 1},
	# Near future: anti-submarine helicopters carry homing torpedoes, not bombs.
	"z20": {"name": "Z-20F helicopter", "kn": 140, "span": 16.4, "len": 15.4, "engines": 2, "kind": "helo", "hp": 2, "bombs": 2},
}

## The boats you can command.
static func nations() -> Dictionary:
	return {
		"us": {
			"id": "us", "name": "United States", "boat": "Gato-class fleet boat",
			"sub_kn": 9.0, "surf_kn": 20.0, "test": 90.0, "crush": 150.0, "dive_time": 35.0,
			"tubes": 6, "torps": 24,
			"torp": {"name": "Mk 14", "kn": 46.0, "range": 4100.0, "dud": 0.06, "wake": true, "kg": 292.0},
			"gun": {"name": "4-inch/50 deck gun", "v": 850.0, "reload": 4.0, "ammo": 100, "dmg": 9, "cal": 102.0, "max_elev": 20.0},
			"aa": {"name": "20 mm Oerlikon", "rate": 7.5, "v": 840.0},
			"sub": {"len": 95.0, "beam": 8.3, "tower": 0.42, "gun_x": 0.60, "aa_x": 0.515, "style": "gato"},
			"bt": true,
			"blurb": "Long-legged Pacific fleet boat with a deep magazine. By 1944 the Mk 14's worst problems were fixed, but some still fail.",
			"targets": [
				_t("shinano", "Shinano", "jp", "cv", 266, 36, 10.5, 20, 4, 3, 2, "night", true, true, "USS Archerfish, 29 Nov 1944",
					"Archerfish shadowed her through the night off Honshu and hit with four torpedoes. Ten days after commissioning, she became the largest warship ever sunk by a submarine.", [], "shinano"),
				_t("kongo", "Kongo", "jp", "bb", 222, 31, 9.7, 16, 3, 2, 1, "night", true, true, "USS Sealion, 21 Nov 1944",
					"Sealion's night attack in the Formosa Strait made Kongo the only Japanese battleship sunk by a submarine. The destroyer Urakaze went down in the same attack.", [], "kongo"),
				_t("taiho", "Taiho", "jp", "cv", 260, 30, 9.6, 22, 2, 3, 1, "day", true, true, "USS Albacore, 19 Jun 1944",
					"One torpedo during the Battle of the Philippine Sea cracked her fuel lines. Vapour spread through the ship and exploded hours later.", ["kate", "kate"], "taiho"),
				_t("shokaku", "Shokaku", "jp", "cv", 257, 26, 8.9, 22, 3, 2, 1, "day", true, true, "USS Cavalla, 19 Jun 1944",
					"Cavalla hit the Pearl Harbor veteran with at least three torpedoes on the same morning Taiho was struck.", ["kate", "kate"], "shokaku"),
				_t("yamato", "Yamato", "jp", "bb", 263, 39, 11.0, 22, 8, 4, 2, "day", true, false, "Never sunk by a submarine",
					"USS Skate torpedoed her in December 1943 but she shrugged it off. Carrier aircraft sank her in April 1945. Here, it's up to you.", ["emily"], "yamato"),
			],
		},
		"uk": {
			"id": "uk", "name": "United Kingdom", "boat": "T-class patrol submarine",
			"sub_kn": 9.0, "surf_kn": 15.0, "test": 90.0, "crush": 150.0, "dive_time": 40.0,
			"tubes": 6, "torps": 16,
			"torp": {"name": "Mk VIII", "kn": 45.0, "range": 4570.0, "dud": 0.04, "wake": true, "kg": 340.0},
			"gun": {"name": "4-inch QF Mk XII", "v": 800.0, "reload": 4.5, "ammo": 100, "dmg": 9, "cal": 102.0, "max_elev": 30.0},
			"aa": {"name": "20 mm Oerlikon", "rate": 7.5, "v": 840.0},
			"sub": {"len": 84.0, "beam": 8.1, "tower": 0.45, "gun_x": 0.33, "aa_x": 0.52, "style": "tclass"},
			"bt": false,
			"blurb": "Rugged patrol boat with a heavy six-tube bow salvo. The Mk VIII was a famously dependable torpedo.",
			"targets": [
				_t("karlsruhe", "Karlsruhe", "de", "cl", 174, 15, 6.3, 15, 2, 2, 1, "dusk", true, true, "HMS Truant, 9 Apr 1940",
					"Truant hit her off Kristiansand during the invasion of Norway. Too badly damaged to save, she was scuttled by her own escort.", ["arado"], "karlsruhe", "coast"),
				_t("ashigara", "Ashigara", "jp", "ca", 204, 21, 6.4, 16, 3, 1, 2, "day", true, true, "HMS Trenchant, 8 Jun 1945",
					"In the shallow Bangka Strait, Trenchant fired eight torpedoes at the heavy cruiser and hit with five.", ["emily"], "ashigara", "strait"),
				_t("kuma", "Kuma", "jp", "cl", 162, 14, 4.8, 14, 2, 1, 1, "day", true, true, "HMS Tally-Ho, 11 Jan 1944",
					"Tally-Ho caught the light cruiser off Penang and sank her with two hits.", ["emily"], "kuma", "coast"),
				_t("prinz", "Prinz Eugen", "de", "ca", 207, 22, 7.2, 22, 3, 3, 1, "day", true, false, "Damaged by HMS Trident, Feb 1942",
					"Trident's torpedo wrecked her stern off Norway, but she survived the war and ended her days as an atomic bomb target at Bikini Atoll.", ["arado", "condor"], "prinz", "coast"),
				_t("tirpitz", "Tirpitz", "de", "bb", 251, 36, 10.6, 20, 7, 3, 2, "dusk", true, false, "Never sunk by a submarine",
					"British X-craft midget submarines crippled her in her fjord in 1943. RAF Lancasters finally sank her in November 1944.", ["arado"], "tirpitz", "coast"),
			],
		},
		"de": {
			"id": "de", "name": "Germany", "boat": "Type VIIC U-boat",
			"sub_kn": 7.6, "surf_kn": 17.7, "test": 220.0, "crush": 260.0, "dive_time": 27.0,
			"tubes": 4, "torps": 14,
			"torp": {"name": "G7e (electric)", "kn": 30.0, "range": 5000.0, "dud": 0.08, "wake": false, "kg": 280.0},
			"gun": {"name": "8.8 cm SK C/35", "v": 700.0, "reload": 3.5, "ammo": 220, "dmg": 7, "cal": 88.0, "max_elev": 30.0},
			"aa": {"name": "2 cm Flak 30", "rate": 4.0, "v": 900.0},
			"sub": {"len": 67.0, "beam": 6.2, "tower": 0.47, "gun_x": 0.32, "aa_x": 0.53, "style": "vii"},
			"bt": false,
			"blurb": "The workhorse of the Atlantic. Slow underwater but dives fast and very deep, and the electric G7e leaves no bubble wake.",
			"targets": [
				_t("royaloak", "Royal Oak", "uk", "bb", 190, 27, 8.7, 0, 3, 1, 0, "night", false, true, "U-47, 14 Oct 1939",
					"Gunther Prien slipped U-47 into the fleet anchorage at Scapa Flow and torpedoed the battleship at anchor. More than 800 of her crew were lost.", [], "royaloak", "harbor"),
				_t("courageous", "Courageous", "uk", "cv", 240, 27, 8.4, 16, 2, 2, 1, "dusk", true, true, "U-29, 17 Sep 1939",
					"Sunk southwest of Ireland two weeks into the war, the first major British warship lost in the conflict.", ["swordfish"], "courageous"),
				_t("arkroyal", "Ark Royal", "uk", "cv", 244, 29, 8.5, 18, 1, 4, 1, "day", true, true, "U-81, 13 Nov 1941",
					"A single torpedo off Gibraltar flooded her boiler rooms. She capsized under tow the next day with the loss of just one man.", ["swordfish", "swordfish"], "arkroyal", "coast"),
				_t("barham", "Barham", "uk", "bb", 196, 32, 9.2, 17, 3, 4, 1, "day", true, true, "U-331, 25 Nov 1941",
					"U-331 slipped through the destroyer screen off Egypt. Three hits set off a magazine explosion that was caught on newsreel film.", ["sunderland"], "barham"),
				_t("hood", "Hood", "uk", "bb", 262, 32, 9.8, 22, 3, 3, 1, "day", true, false, "Never sunk by a submarine",
					"The pride of the Royal Navy blew up under Bismarck's guns in May 1941. Here, you meet her at sea first.", ["sunderland"], "hood"),
			],
		},
		"jp": {
			"id": "jp", "name": "Japan", "boat": "Type B1 cruiser submarine",
			"sub_kn": 8.0, "surf_kn": 23.5, "test": 100.0, "crush": 160.0, "dive_time": 55.0,
			"tubes": 6, "torps": 17,
			"torp": {"name": "Type 95", "kn": 49.0, "range": 9000.0, "dud": 0.03, "wake": false, "kg": 405.0},
			"gun": {"name": "14 cm/40 deck gun", "v": 700.0, "reload": 6.0, "ammo": 80, "dmg": 14, "cal": 140.0, "max_elev": 30.0},
			"aa": {"name": "25 mm Type 96", "rate": 3.5, "v": 900.0},
			"sub": {"len": 108.0, "beam": 9.3, "tower": 0.40, "gun_x": 0.60, "aa_x": 0.47, "style": "b1"},
			"bt": false,
			"blurb": "Big, fast ocean raider with a seaplane hangar. Slow to dive. The oxygen-fuelled Type 95 runs far, fast and nearly wakeless.",
			"targets": [
				_t("yorktown", "Yorktown", "us", "cv", 247, 33, 7.9, 2, 2, 5, 0, "day", false, true, "I-168, 6 Jun 1942",
					"Crippled at Midway and under tow, she was hit by I-168, which also sank the destroyer Hammann alongside. Yorktown rolled over the next morning.", ["catalina"], "yorktown"),
				_t("wasp", "Wasp", "us", "cv", 225, 33, 7.5, 16, 3, 3, 1, "day", true, true, "I-19, 15 Sep 1942",
					"A single spread from I-19 sank Wasp and also hit the battleship North Carolina and the destroyer O'Brien.", ["dauntless", "dauntless"], "wasp"),
				_t("indianapolis", "Indianapolis", "us", "ca", 186, 20, 6.4, 17, 2, 0, 0, "night", false, true, "I-58, 30 Jul 1945",
					"Sailing alone after delivering atomic bomb components to Tinian, she was hit by two torpedoes and sank in about twelve minutes.", [], "indianapolis"),
				_t("juneau", "Juneau", "us", "cl", 165, 16, 6.3, 13, 1, 2, 1, "day", true, true, "I-26, 13 Nov 1942",
					"Already damaged off Guadalcanal, she blew apart after a single hit. The five Sullivan brothers were among the dead.", ["catalina"], "juneau", "coast"),
				_t("enterprise", "Enterprise", "us", "cv", 247, 33, 7.9, 22, 5, 4, 2, "day", true, false, "Never sunk",
					"The 'Big E' fought in nearly every major Pacific carrier battle and survived the war as the most decorated US warship.", ["dauntless", "dauntless", "catalina"], "enterprise"),
			],
		},
		# ------------------------------------------------------ near future
		"us_ssn": {
			"id": "us_ssn", "era": "modern", "navy": "us", "name": "United States", "boat": "Virginia-class attack submarine",
			"sub_kn": 28.0, "surf_kn": 15.0, "test": 240.0, "crush": 400.0, "dive_time": 22.0,
			"nuclear": true, "escape": 60000.0, "fire_max": 240.0,
			"tubes": 4, "torps": 26, "decoys": 14,
			"torp": {"name": "Mk 48 ADCAP", "kn": 55.0, "range": 38000.0, "dud": 0.0, "wake": false, "kg": 295.0,
				"homing": true, "wire": true, "seeker": 2800.0, "cone": 45.0},
			"gun": {}, "aa": {},
			"sub": {"len": 115.0, "beam": 10.4, "tower": 0.27, "style": "virginia"},
			"bt": true,
			"blurb": "Nuclear attack boat: no battery to nurse and no need to surface. Very quiet below about 10 knots. Wire-guided Mk 48s home on what they hear.",
			"targets": [
				_t("fujian", "Fujian", "cn", "cv", 316, 40, 12.0, 26, 4, 4, 0, "day", true, false, "Fictional scenario",
					"China's first catapult carrier, screened by a Type 055 cruiser, two Type 052D destroyers and a Type 054A frigate towing its sonar astern. Two Z-20F helicopters hunt ahead of the group.",
					["z20", "z20"], "fujian").merged({"group": [
						_m("t055", "Lhasa", "cg", 180, 20, 6.6, 30, 2, Vector2(5000, 0)),
						_m("t052d", "Kunming", "ddg", 157, 18, 6.5, 30, 1.5, Vector2(1500, 5000)),
						_m("t052d", "Changsha", "ddg", 157, 18, 6.5, 30, 1.5, Vector2(1500, -5000)),
						_m("t054a", "Xuzhou", "ffg", 134, 16, 5.0, 27, 1, Vector2(-6000, 1000)),
					]}),
				_t("nanchang", "Nanchang", "cn", "cg", 180, 20, 6.6, 28, 2, 2, 0, "dusk", true, false, "Fictional scenario",
					"The first Type 055, a 12,000-ton cruiser with 112 missile cells, leading a surface action group. A Type 052D and a Type 054A sweep for submarines on her flanks.",
					["z20"], "t055").merged({"group": [
						_m("t052d", "Huainan", "ddg", 157, 18, 6.5, 30, 1.5, Vector2(3000, 3000)),
						_m("t054a", "Yulin", "ffg", 134, 16, 5.0, 27, 1, Vector2(-3500, -2500)),
					]}),
			],
		},
	}


## A ship in a modern group: layout, name, type, size, top speed, hits to sink
## and her station (metres ahead, metres to starboard of the main target).
static func _m(lay: String, name: String, type: String, length: float, beam: float, draft: float, kn: float,
		hp: float, station: Vector2) -> Dictionary:
	return {"layout": lay, "name": name, "type": type, "length": length, "beam": beam, "draft": draft, "kn": kn,
		"hp": hp, "station": station}


static func _t(id: String, name: String, nation: String, type: String, length: float, beam: float, draft: float,
		kn: float, hp: int, escorts: int, chasers: int, tod: String, zig: bool, historical: bool,
		credit: String, note: String, air: Array, layout: String, terrain: String = "open") -> Dictionary:
	return {"id": id, "name": name, "nation": nation, "type": type, "length": length, "beam": beam,
		"draft": draft, "kn": kn, "hp": hp, "escorts": escorts, "chasers": chasers, "tod": tod, "zig": zig,
		"historical": historical, "credit": credit, "note": note, "air": air, "layout": layout,
		"terrain": terrain}


const HELP := [
	["W A S D, Shift", "Walk around inside the boat or on deck"],
	["Mouse", "Look, train the periscope, aim the guns"],
	["E", "Use the station, ladder or hatch you're facing; leave a gun"],
	["1  2  3  4  5", "Control room, periscope, go on deck, deck gun, AA gun"],
	["6  7  8  9", "Plot table, hydrophones, TDC, damage board"],
	["V or 0", "Third-person view of the boat (drag the mouse, wheel to zoom)"],
	["Up / Down", "Engine telegraph"],
	["Left / Right", "Rudder"],
	["R / F", "Order shallower / deeper (all the way up surfaces)"],
	["C", "Crash dive. Get below first: anyone on deck drowns"],
	["P", "Raise or lower the periscope"],
	["Z, mouse wheel", "Periscope power"],
	["L, left click", "Lock target on the TDC (periscope or binoculars)"],
	["Space / X", "Fire one torpedo / a spread of three"],
	["[  ]", "Torpedo running depth"],
	["Left / right mouse", "Fire / aim through the sight (guns, binoculars)"],
	["T", "Time compression 1x, 4x, 16x"],
	["Tab", "Plot table"],
	["M", "Sound on or off"],
	["F1", "Show or hide this help"],
	["F9", "Graphics quality: low, medium, high"],
	["F11", "Fullscreen"],
	["Esc", "Leave a station or pause"],
]

## Keys that work differently in the near-future boats.
const HELP_MODERN := [
	["W A S D, Shift", "Walk around the control room"],
	["Mouse", "Look, train the mast"],
	["E", "Use the station you're facing"],
	["1  2", "Control room, photonics mast"],
	["6  7  8  9", "Plot, sonar, fire control, status"],
	["V or 0", "Outside view of the boat"],
	["Up / Down", "Engine order"],
	["Left / Right", "Rudder"],
	["R / F", "Order shallower / deeper"],
	["C", "Emergency deep"],
	["P", "Raise or lower the mast"],
	["Z, mouse wheel", "Mast zoom"],
	["L, left click", "Track a ship (mast or sonar)"],
	["Space / X", "Fire one Mk 48 / two"],
	["G", "Cut the guidance wires"],
	["N", "Launch a decoy"],
	["T", "Time compression 1x, 4x, 16x"],
	["Tab", "Plot"],
	["M", "Sound on or off"],
	["F1", "Show or hide this help"],
	["F9", "Graphics quality: low, medium, high"],
	["F11", "Fullscreen"],
	["Esc", "Leave a station or pause"],
]

const NATION_ORDER := ["us", "uk", "de", "jp"]
## Near-future boats, in menu order.
const MODERN_ORDER := ["us_ssn"]

const TYPE_NAMES := {"bb": "Battleship", "cv": "Aircraft carrier", "ca": "Heavy cruiser",
	"cl": "Light cruiser", "dd": "Destroyer", "pc": "Sub-chaser",
	"cg": "Guided-missile cruiser", "ddg": "Guided-missile destroyer", "ffg": "Guided-missile frigate"}


static func is_modern(nat: Dictionary) -> bool:
	return nat.get("era", "") == "modern"


# ---------------------------------------------------------------- layouts
# Turret: x, barrels, width, barrel length, lift (superfiring height), dir (1 faces bow, -1 stern)
static func _tur(x: float, n: int, w: float, bl: float, lift: float = 0.0, dir: int = 1) -> Dictionary:
	return {"x": x, "n": n, "w": w, "bl": bl, "lift": lift, "dir": dir}

# Funnel: x, radius, height, rake degrees, style
static func _fun(x: float, r: float, h: float, rake: float = 0.0, style: String = "round") -> Dictionary:
	return {"x": x, "r": r, "h": h, "rake": rake, "style": style}

# Superstructure block: x0, x1, width fraction of beam, height above deck
static func _sup(x0: float, x1: float, wf: float, h: float) -> Dictionary:
	return {"x0": x0, "x1": x1, "wf": wf, "h": h}


## Detailed layout for each ship class used in the game.
static func layout(key: String) -> Dictionary:
	match key:
		"yamato":
			return {"hull": "bb", "fb": 10.0, "fb_bow": 14.0, "sheer": "jp", "paint": "jp",
				"turrets": [_tur(0.18, 3, 14.0, 20.0), _tur(0.26, 3, 14.0, 20.0, 3.5), _tur(0.70, 3, 14.0, 20.0, 0.0, -1),
					_tur(0.33, 3, 7.0, 9.0, 8.0), _tur(0.62, 3, 7.0, 9.0, 6.0, -1)],
				"supers": [_sup(0.31, 0.62, 0.55, 5.0), _sup(0.34, 0.58, 0.40, 9.0)],
				"tower": {"x": 0.385, "type": "tower_jp", "h": 40.0, "w": 9.0},
				"funnels": [_fun(0.50, 5.5, 17.0, 20.0, "jp_big")],
				"masts": [{"x": 0.56, "h": 30.0, "type": "pole"}],
				"aa": 24, "boats": true, "catapult": 0.88}
		"kongo":
			return {"hull": "bb", "fb": 8.0, "fb_bow": 11.0, "sheer": "jp", "paint": "jp",
				"turrets": [_tur(0.19, 2, 10.0, 16.0), _tur(0.265, 2, 10.0, 16.0, 3.0), _tur(0.62, 2, 10.0, 16.0, 0.0, -1),
					_tur(0.78, 2, 10.0, 16.0, 0.0, -1)],
				"supers": [_sup(0.32, 0.58, 0.45, 4.0)],
				"tower": {"x": 0.36, "type": "pagoda", "h": 42.0, "w": 8.0},
				"funnels": [_fun(0.45, 3.4, 15.0, 0.0), _fun(0.53, 3.4, 14.0, 0.0)],
				"masts": [{"x": 0.585, "h": 28.0, "type": "tripod"}],
				"aa": 14, "boats": true, "catapult": 0.70}
		"tirpitz":
			return {"hull": "bb", "fb": 9.0, "fb_bow": 13.0, "sheer": "atlantic", "paint": "de",
				"turrets": [_tur(0.19, 2, 11.0, 19.0), _tur(0.265, 2, 11.0, 19.0, 3.5), _tur(0.70, 2, 11.0, 19.0, 3.5, -1),
					_tur(0.775, 2, 11.0, 19.0, 0.0, -1)],
				"supers": [_sup(0.31, 0.66, 0.55, 5.0), _sup(0.33, 0.48, 0.40, 9.0)],
				"tower": {"x": 0.355, "type": "tower_de", "h": 32.0, "w": 8.0},
				"funnels": [_fun(0.47, 5.0, 12.0, 0.0, "cap")],
				"masts": [{"x": 0.58, "h": 30.0, "type": "pole"}],
				"aa": 18, "boats": true, "catapult": 0.53}
		"royaloak", "barham":
			return {"hull": "bb", "fb": 7.5, "fb_bow": 10.0, "sheer": "rn", "paint": "uk", "bulges": true,
				"turrets": [_tur(0.20, 2, 10.0, 16.0), _tur(0.275, 2, 10.0, 16.0, 3.0), _tur(0.68, 2, 10.0, 16.0, 3.0, -1),
					_tur(0.76, 2, 10.0, 16.0, 0.0, -1)],
				"supers": [_sup(0.32, 0.60, 0.45, 4.0)],
				"tower": {"x": 0.355, "type": "tripod_rn", "h": 34.0, "w": 7.0},
				"funnels": [_fun(0.45 if key == "royaloak" else 0.47, 3.6, 14.0, 0.0, "cap")],
				"masts": [{"x": 0.56, "h": 26.0, "type": "pole"}],
				"aa": 8, "boats": true}
		"hood":
			return {"hull": "bb", "fb": 8.0, "fb_bow": 10.0, "sheer": "rn", "paint": "uk",
				"turrets": [_tur(0.20, 2, 10.0, 16.0), _tur(0.27, 2, 10.0, 16.0, 3.0), _tur(0.71, 2, 10.0, 16.0, 3.0, -1),
					_tur(0.78, 2, 10.0, 16.0, 0.0, -1)],
				"supers": [_sup(0.31, 0.64, 0.45, 4.0), _sup(0.34, 0.45, 0.35, 8.0)],
				"tower": {"x": 0.345, "type": "tower_rn", "h": 30.0, "w": 8.0},
				"funnels": [_fun(0.44, 3.6, 13.0, 0.0, "cap"), _fun(0.53, 3.6, 13.0, 0.0, "cap")],
				"masts": [{"x": 0.40, "h": 36.0, "type": "tripod"}, {"x": 0.60, "h": 26.0, "type": "pole"}],
				"aa": 12, "boats": true}
		"prinz":
			return {"hull": "ca", "fb": 7.5, "fb_bow": 11.0, "sheer": "atlantic", "paint": "de",
				"turrets": [_tur(0.19, 2, 8.0, 12.0), _tur(0.255, 2, 8.0, 12.0, 3.0), _tur(0.72, 2, 8.0, 12.0, 3.0, -1),
					_tur(0.785, 2, 8.0, 12.0, 0.0, -1)],
				"supers": [_sup(0.30, 0.68, 0.55, 4.0), _sup(0.32, 0.44, 0.40, 8.0)],
				"tower": {"x": 0.345, "type": "tower_de", "h": 26.0, "w": 6.0},
				"funnels": [_fun(0.47, 4.2, 11.0, 0.0, "cap")],
				"masts": [{"x": 0.62, "h": 24.0, "type": "pole"}],
				"aa": 10, "catapult": 0.55}
		"karlsruhe":
			return {"hull": "ca", "fb": 6.5, "fb_bow": 9.0, "sheer": "atlantic", "paint": "de",
				"turrets": [_tur(0.20, 3, 7.0, 9.0), _tur(0.72, 3, 7.0, 9.0, 3.0, -1), _tur(0.80, 3, 7.0, 9.0, 0.0, -1)],
				"supers": [_sup(0.27, 0.62, 0.45, 3.5)],
				"tower": {"x": 0.30, "type": "tower_de", "h": 22.0, "w": 5.0},
				"funnels": [_fun(0.42, 2.6, 10.0, 0.0, "cap"), _fun(0.53, 2.6, 10.0, 0.0, "cap")],
				"masts": [{"x": 0.60, "h": 20.0, "type": "pole"}],
				"aa": 6}
		"ashigara":
			return {"hull": "ca", "fb": 7.0, "fb_bow": 11.0, "sheer": "jp", "paint": "jp",
				"turrets": [_tur(0.15, 2, 7.0, 10.0), _tur(0.21, 2, 7.0, 10.0, 2.5), _tur(0.27, 2, 7.0, 10.0),
					_tur(0.72, 2, 7.0, 10.0, 0.0, -1), _tur(0.79, 2, 7.0, 10.0, 0.0, -1)],
				"supers": [_sup(0.30, 0.64, 0.50, 4.0)],
				"tower": {"x": 0.33, "type": "pagoda", "h": 28.0, "w": 7.0},
				"funnels": [_fun(0.43, 4.0, 11.0, 15.0, "jp_trunk"), _fun(0.53, 2.6, 10.0, 15.0)],
				"masts": [{"x": 0.40, "h": 30.0, "type": "tripod"}, {"x": 0.62, "h": 22.0, "type": "pole"}],
				"aa": 12, "catapult": 0.58}
		"kuma":
			return {"hull": "ca", "fb": 6.0, "fb_bow": 8.5, "sheer": "jp", "paint": "jp",
				"turrets": [_tur(0.14, 1, 3.0, 7.0), _tur(0.20, 1, 3.0, 7.0, 2.0), _tur(0.80, 1, 3.0, 7.0, 0.0, -1),
					_tur(0.86, 1, 3.0, 7.0, 0.0, -1)],
				"supers": [_sup(0.24, 0.70, 0.45, 3.0)],
				"tower": {"x": 0.26, "type": "bridge_old", "h": 18.0, "w": 5.0},
				"funnels": [_fun(0.40, 2.0, 11.0, 8.0), _fun(0.48, 2.0, 11.0, 8.0), _fun(0.56, 2.0, 11.0, 8.0)],
				"masts": [{"x": 0.30, "h": 24.0, "type": "tripod"}, {"x": 0.68, "h": 20.0, "type": "pole"}],
				"aa": 4}
		"indianapolis":
			return {"hull": "ca", "fb": 8.0, "fb_bow": 10.0, "sheer": "us", "paint": "us",
				"turrets": [_tur(0.20, 3, 8.0, 10.0), _tur(0.27, 3, 8.0, 10.0, 3.0), _tur(0.76, 3, 8.0, 10.0, 0.0, -1)],
				"supers": [_sup(0.31, 0.68, 0.50, 4.0), _sup(0.33, 0.42, 0.40, 8.0)],
				"tower": {"x": 0.34, "type": "tripod_us", "h": 30.0, "w": 6.0},
				"funnels": [_fun(0.47, 2.6, 11.0, 0.0), _fun(0.56, 2.6, 11.0, 0.0)],
				"masts": [{"x": 0.64, "h": 24.0, "type": "tripod"}],
				"aa": 12, "catapult": 0.52}
		"juneau":
			return {"hull": "ca", "fb": 7.0, "fb_bow": 9.0, "sheer": "us", "paint": "us",
				"turrets": [_tur(0.16, 2, 4.5, 5.5), _tur(0.21, 2, 4.5, 5.5, 2.4), _tur(0.26, 2, 4.5, 5.5, 4.8),
					_tur(0.72, 2, 4.5, 5.5, 4.8, -1), _tur(0.77, 2, 4.5, 5.5, 2.4, -1), _tur(0.82, 2, 4.5, 5.5, 0.0, -1)],
				"supers": [_sup(0.30, 0.68, 0.5, 4.0), _sup(0.31, 0.40, 0.4, 8.0)],
				"tower": {"x": 0.33, "type": "block_us", "h": 20.0, "w": 6.0},
				"funnels": [_fun(0.46, 2.2, 9.0, 0.0), _fun(0.56, 2.2, 9.0, 0.0)],
				"masts": [{"x": 0.38, "h": 26.0, "type": "pole"}],
				"aa": 10}
		"shinano":
			return {"hull": "cv", "fb": 9.0, "fb_bow": 11.0, "sheer": "jp", "paint": "jp_cv",
				"deck": {"h": 21.0, "x0": 0.04, "x1": 0.96, "w": 40.0, "bow": "enclosed"},
				"island": {"x": 0.42, "l": 30.0, "w": 7.0, "h": 13.0, "funnel": _fun(0.0, 5.0, 10.0, 26.0, "jp_out")},
				"planes": 0, "aa": 30}
		"taiho":
			return {"hull": "cv", "fb": 9.0, "fb_bow": 11.0, "sheer": "jp", "paint": "jp_cv",
				"deck": {"h": 19.0, "x0": 0.03, "x1": 0.96, "w": 30.0, "bow": "enclosed"},
				"island": {"x": 0.40, "l": 26.0, "w": 6.0, "h": 13.0, "funnel": _fun(0.0, 4.0, 9.0, 26.0, "jp_out")},
				"planes": 8, "aa": 20}
		"shokaku":
			return {"hull": "cv", "fb": 8.5, "fb_bow": 11.0, "sheer": "jp", "paint": "jp_cv",
				"deck": {"h": 17.0, "x0": 0.05, "x1": 0.96, "w": 29.0, "bow": "open"},
				"island": {"x": 0.30, "l": 14.0, "w": 5.0, "h": 9.0},
				"side_funnels": 0.50, "planes": 9, "aa": 16}
		"courageous":
			return {"hull": "cv", "fb": 8.0, "fb_bow": 10.0, "sheer": "rn", "paint": "uk",
				"deck": {"h": 18.0, "x0": 0.08, "x1": 0.97, "w": 28.0, "bow": "open", "flyoff": true},
				"island": {"x": 0.42, "l": 30.0, "w": 6.0, "h": 13.0, "funnel": _fun(0.0, 3.5, 9.0, 0.0, "cap")},
				"planes": 6, "aa": 8}
		"arkroyal":
			return {"hull": "cv", "fb": 9.0, "fb_bow": 12.0, "sheer": "rn", "paint": "uk",
				"deck": {"h": 20.0, "x0": 0.03, "x1": 0.99, "w": 29.0, "bow": "enclosed"},
				"island": {"x": 0.42, "l": 32.0, "w": 6.0, "h": 15.0, "funnel": _fun(0.0, 3.6, 10.0, 0.0, "cap")},
				"planes": 8, "aa": 14}
		"yorktown", "enterprise", "wasp":
			var l := {"hull": "cv", "fb": 8.0, "fb_bow": 10.0, "sheer": "us", "paint": "us_cv",
				"deck": {"h": 17.0, "x0": 0.03, "x1": 0.98, "w": 33.0, "bow": "open"},
				"island": {"x": 0.42, "l": 36.0, "w": 7.0, "h": 15.0, "funnel": _fun(0.0, 4.5, 10.0, 0.0, "us_trunk"),
					"tripod": true},
				"planes": 10, "aa": 18}
			if key == "wasp":
				l["deck"]["w"] = 30.0
				l["island"]["l"] = 26.0
				l["planes"] = 8
			return l
		"dd_jp":
			return {"hull": "dd", "fb": 5.0, "fb_bow": 8.0, "sheer": "jp", "paint": "jp",
				"turrets": [_tur(0.13, 2, 4.0, 6.0), _tur(0.70, 2, 4.0, 6.0, 2.2, -1), _tur(0.78, 2, 4.0, 6.0, 0.0, -1)],
				"supers": [_sup(0.18, 0.32, 0.5, 2.5)],
				"tower": {"x": 0.22, "type": "bridge_dd", "h": 10.0, "w": 4.5},
				"funnels": [_fun(0.37, 1.6, 7.0, 10.0, "jp_trunk"), _fun(0.50, 1.6, 7.0, 10.0)],
				"masts": [{"x": 0.28, "h": 17.0, "type": "tripod"}],
				"tubes": [0.44, 0.57], "dc": true, "aa": 4}
		"dd_us":
			return {"hull": "dd", "fb": 5.0, "fb_bow": 7.0, "sheer": "us", "paint": "us",
				"turrets": [_tur(0.13, 1, 3.4, 5.5), _tur(0.20, 1, 3.4, 5.5, 2.0), _tur(0.72, 1, 3.4, 5.5, 2.0, -1),
					_tur(0.80, 1, 3.4, 5.5, 0.0, -1)],
				"supers": [_sup(0.23, 0.33, 0.5, 2.5)],
				"tower": {"x": 0.25, "type": "bridge_dd", "h": 9.0, "w": 4.5},
				"funnels": [_fun(0.42, 1.7, 7.0, 0.0)],
				"masts": [{"x": 0.31, "h": 17.0, "type": "pole"}],
				"tubes": [0.50, 0.58], "dc": true, "aa": 4}
		"dd_uk":
			return {"hull": "dd", "fb": 5.0, "fb_bow": 7.5, "sheer": "rn", "paint": "uk",
				"turrets": [_tur(0.14, 2, 4.0, 5.6), _tur(0.21, 2, 4.0, 5.6, 2.0), _tur(0.78, 2, 4.0, 5.6, 0.0, -1)],
				"supers": [_sup(0.24, 0.34, 0.5, 2.5)],
				"tower": {"x": 0.26, "type": "bridge_dd", "h": 9.0, "w": 4.5},
				"funnels": [_fun(0.44, 1.8, 7.0, 0.0, "cap")],
				"masts": [{"x": 0.33, "h": 18.0, "type": "pole"}],
				"tubes": [0.52, 0.62], "dc": true, "aa": 4}
		"dd_de":
			return {"hull": "dd", "fb": 5.2, "fb_bow": 8.5, "sheer": "atlantic", "paint": "de",
				"turrets": [_tur(0.12, 1, 3.6, 6.5), _tur(0.20, 1, 3.6, 6.5, 2.0), _tur(0.70, 1, 3.6, 6.5, 2.0, -1),
					_tur(0.78, 1, 3.6, 6.5, 0.0, -1), _tur(0.86, 1, 3.6, 6.5, 0.0, -1)],
				"supers": [_sup(0.22, 0.32, 0.5, 2.5)],
				"tower": {"x": 0.25, "type": "bridge_dd", "h": 9.0, "w": 4.5},
				"funnels": [_fun(0.40, 1.8, 7.0, 0.0, "cap"), _fun(0.52, 1.8, 7.0, 0.0, "cap")],
				"masts": [{"x": 0.30, "h": 18.0, "type": "pole"}],
				"tubes": [0.46, 0.60], "dc": true, "aa": 4}
		# ------------------------------------------------------ near future
		"fujian":
			return {"hull": "cv", "fb": 12.0, "fb_bow": 15.0, "sheer": "modern", "paint": "cn",
				"deck": {"h": 26.0, "x0": 0.0, "x1": 0.99, "w": 76.0, "bow": "enclosed", "angled": 9.0, "cats": 3},
				"island": {"x": 0.62, "l": 28.0, "w": 10.0, "h": 16.0, "modern": true, "side": 1.0},
				"planes": 12, "jets": true, "ciws": [0.06, 0.94], "hull_no": "18", "aa": 0}
		"t055":
			return {"hull": "ddg", "fb": 7.0, "fb_bow": 9.5, "sheer": "modern", "paint": "cn",
				"turrets": [_tur(0.12, 1, 5.0, 7.0).merged({"style": "stealth"})],
				"vls": [{"x0": 0.17, "x1": 0.27, "w": 0.6}, {"x0": 0.60, "x1": 0.68, "w": 0.62}],
				"stealth": [{"x0": 0.27, "x1": 0.60, "wf": 0.88, "h": 8.5, "slope": 0.14},
					{"x0": 0.29, "x1": 0.40, "wf": 0.62, "h": 7.5, "slope": 0.12, "on": 8.5}],
				"imast": {"x": 0.355, "h": 22.0, "w": 9.0, "base": 16.0},
				"funnels": [_fun(0.50, 3.2, 6.0, 0.0, "stealth")],
				"hangar": {"x0": 0.68, "x1": 0.80, "wf": 0.75, "h": 6.0},
				"helideck": {"x0": 0.80, "x1": 0.97},
				"ciws": [0.30, 0.69], "hull_no": "101", "aa": 0}
		"t052d":
			return {"hull": "ddg", "fb": 6.5, "fb_bow": 9.0, "sheer": "modern", "paint": "cn",
				"turrets": [_tur(0.12, 1, 5.0, 7.0).merged({"style": "stealth"})],
				"vls": [{"x0": 0.18, "x1": 0.26, "w": 0.55}, {"x0": 0.62, "x1": 0.69, "w": 0.55}],
				"stealth": [{"x0": 0.26, "x1": 0.36, "wf": 0.7, "h": 13.0, "slope": 0.12, "radar": true},
					{"x0": 0.36, "x1": 0.62, "wf": 0.7, "h": 6.5, "slope": 0.1}],
				"funnels": [_fun(0.48, 2.6, 5.5, 0.0, "stealth")],
				"masts": [{"x": 0.33, "h": 26.0, "type": "lattice_modern"}],
				"hangar": {"x0": 0.69, "x1": 0.80, "wf": 0.7, "h": 5.5},
				"helideck": {"x0": 0.80, "x1": 0.97},
				"ciws": [0.28, 0.70], "hull_no": "172", "aa": 0}
		"t054a":
			return {"hull": "ffg", "fb": 6.0, "fb_bow": 8.5, "sheer": "modern", "paint": "cn",
				"turrets": [_tur(0.13, 1, 4.0, 4.5).merged({"style": "stealth"})],
				"vls": [{"x0": 0.19, "x1": 0.25, "w": 0.45}],
				"stealth": [{"x0": 0.25, "x1": 0.66, "wf": 0.72, "h": 7.0, "slope": 0.12},
					{"x0": 0.28, "x1": 0.38, "wf": 0.5, "h": 4.0, "slope": 0.1, "on": 7.0}],
				"funnels": [_fun(0.50, 2.4, 5.0, 0.0, "stealth")],
				"masts": [{"x": 0.36, "h": 22.0, "type": "lattice_modern"}],
				"hangar": {"x0": 0.66, "x1": 0.78, "wf": 0.65, "h": 5.0},
				"helideck": {"x0": 0.78, "x1": 0.97},
				"ciws": [0.40, 0.65], "hull_no": "530", "towed": true, "aa": 0}
		"pc":
			return {"hull": "pc", "fb": 3.2, "fb_bow": 5.0, "sheer": "trawler", "paint": "grey",
				"turrets": [_tur(0.14, 1, 2.2, 3.0)],
				"supers": [_sup(0.30, 0.55, 0.6, 2.5)],
				"tower": {"x": 0.32, "type": "bridge_dd", "h": 6.0, "w": 3.5},
				"funnels": [_fun(0.48, 1.0, 4.0, 8.0)],
				"masts": [{"x": 0.36, "h": 12.0, "type": "pole"}],
				"dc": true, "aa": 1}
	return layout("dd_us")


static func escort_layout(nation: String) -> String:
	return "dd_" + nation
