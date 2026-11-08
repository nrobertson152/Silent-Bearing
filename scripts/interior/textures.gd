## Procedural textures and the material library for the boat's interior.
## Everything is generated at startup; materials use triplanar mapping so the
## code-built meshes need no UVs (except gauge faces and labels).

static var _cache := {}


static func _noise(seed_v: int, freq: float, octaves := 4, kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = kind
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Height image to a normal map texture.
static func _normal(height: Image, strength: float) -> ImageTexture:
	var n := height.duplicate() as Image
	if n.is_compressed():
		n.decompress()
	n.convert(Image.FORMAT_RGBA8)
	n.bump_map_to_normal_map(strength)
	return _tex(n)


## Mottled paint with grime: two colours blended by noise, darker blotches.
static func paint_image(base: Color, grime: Color, seed_v: int, size := 256, blotch := 0.35) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n1 := _noise(seed_v, 0.02, 5)
	var n2 := _noise(seed_v + 7, 0.09, 3)
	var n3 := _noise(seed_v + 13, 0.35, 2, FastNoiseLite.TYPE_VALUE)
	for y in size:
		for x in size:
			var a := n1.get_noise_2d(x, y) * 0.5 + 0.5
			var b := n2.get_noise_2d(x, y) * 0.5 + 0.5
			var fleck := n3.get_noise_2d(x, y)
			var g := clampf((a - (1.0 - blotch)) * 3.0, 0.0, 1.0)
			var c := base.lerp(grime, g * 0.6 + b * 0.12)
			c = c.lightened(fleck * 0.04) if fleck > 0.0 else c.darkened(-fleck * 0.05)
			img.set_pixel(x, y, c)
	return img


static func height_image(seed_v: int, freq: float, size := 256) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_L8)
	var n := _noise(seed_v, freq, 4)
	for y in size:
		for x in size:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			img.set_pixel(x, y, Color(v, v, v))
	return img


## Diamond tread plate: raised lozenges in a herringbone.
static func tread_images(size := 256) -> Array:
	var col := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_L8)
	var n := _noise(41, 0.03, 4)
	var cell := 32.0
	for y in size:
		for x in size:
			var cx := fposmod(x, cell) - cell * 0.5
			var cy := fposmod(y, cell) - cell * 0.5
			var flip := (int(x / cell) + int(y / cell)) % 2 == 0
			var u := cx * 0.7 + cy * 0.7 if flip else cx * 0.7 - cy * 0.7
			var v := -cx * 0.7 + cy * 0.7 if flip else cx * 0.7 + cy * 0.7
			var d := (u * u) / 140.0 + (v * v) / 6.0
			var raised := clampf(1.4 - d, 0.0, 1.0)
			var wear := n.get_noise_2d(x, y) * 0.5 + 0.5
			var base := Color(0.33, 0.34, 0.34).lerp(Color(0.24, 0.24, 0.23), wear * 0.7)
			if raised > 0.0:
				base = base.lerp(Color(0.52, 0.53, 0.52), raised * (0.5 + wear * 0.4))
			col.set_pixel(x, y, base)
			hgt.set_pixel(x, y, Color(raised * 0.8 + wear * 0.1, 0, 0))
	return [col, hgt]


## Open steel grating for the engine room catwalk.
static func grating_images(size := 128) -> Array:
	var col := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_L8)
	var n := _noise(51, 0.06, 3)
	for y in size:
		for x in size:
			var bar := (x % 16) < 3 or (y % 32) < 3
			var w := n.get_noise_2d(x, y) * 0.5 + 0.5
			var c := Color(0.36, 0.36, 0.35).lerp(Color(0.18, 0.17, 0.15), w * 0.6) if bar else Color(0.04, 0.04, 0.04)
			col.set_pixel(x, y, c)
			hgt.set_pixel(x, y, Color(1.0 if bar else 0.0, 0, 0))
	return [col, hgt]


static func wood_image(base: Color, seed_v: int, size := 256) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n := _noise(seed_v, 0.012, 3)
	var fine := _noise(seed_v + 3, 0.2, 2)
	for y in size:
		for x in size:
			var warp := n.get_noise_2d(x * 0.15, y) * 20.0
			var ring := sin((x + warp) * 0.35) * 0.5 + 0.5
			var c := base.darkened(ring * 0.18 + fine.get_noise_2d(x, y * 0.1) * 0.06)
			if y % 64 == 0:
				c = c.darkened(0.35)
			img.set_pixel(x, y, c)
	return img


static func cloth_image(base: Color, seed_v: int, size := 128) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n := _noise(seed_v, 0.08, 3)
	for y in size:
		for x in size:
			var weave := 0.04 if (x + y) % 2 == 0 else -0.04
			var c := base.lightened(n.get_noise_2d(x, y) * 0.15 + weave)
			if (y % 40) < 3:
				c = c.lerp(Color(0.85, 0.8, 0.7), 0.35)
			img.set_pixel(x, y, c)
	return img


## Gauge face: cream dial, black ticks, red arc near the top of the range.
static func dial_image(size := 128, red := true, black_face := false) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var R := size * 0.5
	var face := Color(0.08, 0.08, 0.08) if black_face else Color(0.93, 0.9, 0.82)
	var ink := Color(0.9, 0.9, 0.85) if black_face else Color(0.1, 0.09, 0.08)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5) - c
			var r := d.length() / R
			var col := Color(0, 0, 0, 0)
			if r <= 1.0:
				col = face
				var ang := fposmod(rad_to_deg(atan2(d.x, -d.y)) + 360.0, 360.0)
				var in_scale := ang >= 225.0 or ang <= 135.0
				var a := fposmod(ang + 135.0, 360.0)
				if in_scale and r > 0.72 and r < 0.9:
					if fmod(a, 27.0) < 2.2:
						col = ink
					elif r > 0.8 and fmod(a, 5.4) < 1.0:
						col = ink
				if red and in_scale and a > 215.0 and a < 270.0 and r > 0.88 and r < 0.94:
					col = Color(0.75, 0.12, 0.08)
				if r > 0.95:
					col = Color(0.15, 0.13, 0.1)
				if absf(d.y + R * 0.3) < 2.0 and absf(d.x) < R * 0.25:
					col = ink.lerp(face, 0.5)
			img.set_pixel(x, y, col)
	return img


## Engraved placard: dark lines suggesting stencilled text.
static func label_image(size := Vector2i(128, 32), seed_v := 1) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	img.fill(Color(0.9, 0.88, 0.8))
	for row in 2:
		var y0 := 7 + row * 13
		var x := 6
		while x < size.x - 8:
			var w := rng.randi_range(3, 7)
			for yy in range(y0, y0 + 7):
				for xx in range(x, mini(x + w, size.x - 6)):
					if rng.randf() < 0.75:
						img.set_pixel(xx, yy, Color(0.12, 0.1, 0.08))
			x += w + (rng.randi_range(4, 9) if rng.randf() < 0.25 else 2)
	for x in size.x:
		img.set_pixel(x, 0, Color(0.3, 0.27, 0.2))
		img.set_pixel(x, size.y - 1, Color(0.3, 0.27, 0.2))
	return img


static func _triplanar(albedo: Texture2D, scale: float, rough := 0.8, metal := 0.0, normal: Texture2D = null,
		normal_scale := 0.6, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.uv1_triplanar_sharpness = 4.0
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if normal != null:
		m.normal_enabled = true
		m.normal_texture = normal
		m.normal_scale = normal_scale
	return m


static func _flat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Builds (once per navy) the dictionary of interior materials.
static func materials(nation: String) -> Dictionary:
	if _cache.has(nation):
		return _cache[nation]
	var paint := Color(0.86, 0.85, 0.79)
	var engine := Color(0.40, 0.45, 0.42)
	match nation:
		"uk":
			paint = Color(0.80, 0.84, 0.78)
			engine = Color(0.32, 0.38, 0.35)
		"de":
			paint = Color(0.86, 0.83, 0.72)
			engine = Color(0.42, 0.42, 0.40)
		"jp":
			paint = Color(0.78, 0.80, 0.76)
			engine = Color(0.36, 0.40, 0.36)
	var cork := paint_image(paint, paint.darkened(0.35), 3, 256, 0.3)
	var cork_h := height_image(4, 0.25, 256)
	var steel := paint_image(paint.darkened(0.05), Color(0.35, 0.3, 0.24), 9, 256, 0.45)
	var steel_h := height_image(10, 0.05, 128)
	var tread := tread_images()
	var grate := grating_images()
	var eng := paint_image(engine, Color(0.12, 0.11, 0.09), 21, 256, 0.5)
	var metal := paint_image(Color(0.5, 0.51, 0.5), Color(0.25, 0.24, 0.22), 31, 128, 0.4)
	var dark := paint_image(Color(0.2, 0.21, 0.22), Color(0.08, 0.08, 0.08), 33, 128, 0.4)
	var blanket_cols := [Color(0.42, 0.40, 0.35), Color(0.20, 0.24, 0.35), Color(0.36, 0.33, 0.25)]
	var m := {
		"cork": _triplanar(_tex(cork), 0.9, 0.95, 0.0, _normal(cork_h, 3.0), 0.5),
		"paint": _triplanar(_tex(steel), 0.7, 0.75, 0.05, _normal(steel_h, 2.0), 0.35),
		"rib": _triplanar(_tex(steel), 0.7, 0.7, 0.05, null, 0.0, Color(0.9, 0.9, 0.88)),
		"floor": _triplanar(_tex(tread[0]), 1.4, 0.55, 0.55, _normal(tread[1], 6.0), 1.0),
		"grate": _triplanar(_tex(grate[0]), 2.2, 0.6, 0.5, _normal(grate[1], 4.0), 0.8),
		"engine": _triplanar(_tex(eng), 0.6, 0.55, 0.2),
		"steel": _triplanar(_tex(metal), 1.0, 0.45, 0.6),
		"dark": _triplanar(_tex(dark), 1.0, 0.6, 0.3),
		"black": _flat(Color(0.03, 0.03, 0.03), 0.8),
		"brass": _flat(Color(0.72, 0.56, 0.28), 0.32, 0.9),
		"copper": _flat(Color(0.72, 0.42, 0.26), 0.35, 0.85),
		"chrome": _flat(Color(0.8, 0.8, 0.82), 0.2, 0.95),
		"red": _flat(Color(0.62, 0.10, 0.08), 0.55),
		"green": _flat(Color(0.20, 0.38, 0.26), 0.6),
		"yellow": _flat(Color(0.78, 0.62, 0.18), 0.6),
		"blue": _flat(Color(0.18, 0.28, 0.48), 0.6),
		"white": _flat(Color(0.9, 0.9, 0.87), 0.7),
		"rubber": _flat(Color(0.06, 0.06, 0.06), 0.95),
		"wood": _triplanar(_tex(wood_image(Color(0.50, 0.34, 0.20), 5)), 0.8, 0.7),
		"wood_lt": _triplanar(_tex(wood_image(Color(0.66, 0.52, 0.36), 6)), 0.8, 0.7),
		"linoleum": _triplanar(_tex(paint_image(Color(0.30, 0.26, 0.22), Color(0.18, 0.15, 0.12), 61, 128, 0.3)), 1.5, 0.5),
		"cloth": _triplanar(_tex(cloth_image(Color(0.36, 0.34, 0.28), 71)), 2.5, 1.0),
		"canvas": _triplanar(_tex(cloth_image(Color(0.64, 0.60, 0.50), 72)), 2.5, 1.0),
		"blanket0": _triplanar(_tex(cloth_image(blanket_cols[0], 73)), 2.0, 1.0),
		"blanket1": _triplanar(_tex(cloth_image(blanket_cols[1], 74)), 2.0, 1.0),
		"blanket2": _triplanar(_tex(cloth_image(blanket_cols[2], 75)), 2.0, 1.0),
		"mattress": _triplanar(_tex(cloth_image(Color(0.80, 0.78, 0.70), 76)), 3.0, 1.0),
		"felt": _triplanar(_tex(cloth_image(Color(0.18, 0.32, 0.22), 77)), 3.0, 1.0),
		"torp": _flat(Color(0.48, 0.50, 0.46), 0.35, 0.75),
		"warhead": _flat(Color(0.30, 0.32, 0.28), 0.5, 0.5),
		"glass": _flat(Color(0.75, 0.82, 0.85), 0.05, 0.3),
		"food": _flat(Color(0.55, 0.32, 0.20), 0.8),
		"bread": _flat(Color(0.72, 0.55, 0.32), 0.9),
		"tin": _flat(Color(0.65, 0.66, 0.64), 0.4, 0.8),
		"skin": _flat(Color(0.78, 0.62, 0.48), 0.8),
	}
	var dial := StandardMaterial3D.new()
	dial.albedo_texture = _tex(dial_image(128, true))
	dial.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	dial.alpha_scissor_threshold = 0.5
	dial.roughness = 0.25
	dial.vertex_color_use_as_albedo = true
	dial.cull_mode = BaseMaterial3D.CULL_DISABLED
	m["dial"] = dial
	var dial_b := dial.duplicate() as StandardMaterial3D
	dial_b.albedo_texture = _tex(dial_image(128, false, true))
	m["dial_black"] = dial_b
	var label := StandardMaterial3D.new()
	label.albedo_texture = _tex(label_image())
	label.roughness = 0.5
	label.vertex_color_use_as_albedo = true
	label.cull_mode = BaseMaterial3D.CULL_DISABLED
	m["label"] = label
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.95, 0.85)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.9, 0.72)
	lamp.emission_energy_multiplier = 3.0
	lamp.vertex_color_use_as_albedo = true
	m["lamp"] = lamp
	for key in ["led_red", "led_green", "led_amber"]:
		var e := StandardMaterial3D.new()
		var col: Color = {"led_red": Color(1.0, 0.15, 0.1), "led_green": Color(0.2, 1.0, 0.3), "led_amber": Color(1.0, 0.65, 0.15)}[key]
		e.albedo_color = col
		e.emission_enabled = true
		e.emission = col
		e.emission_energy_multiplier = 2.0
		e.vertex_color_use_as_albedo = true
		m[key] = e
	_cache[nation] = m
	return m
