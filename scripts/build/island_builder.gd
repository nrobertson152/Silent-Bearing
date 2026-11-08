## Low-poly islands from noise: beach, grass, scrub and bare rock by height.


static func build(r: float, h: float, seed_v: int, style: String) -> MeshInstance3D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 0.9 / r
	noise.fractal_octaves = 4
	var rings := 14
	var segs := 56
	var pts := []
	for j in rings + 1:
		var row := []
		var f := float(j) / rings
		for i in segs:
			var a := TAU * i / segs
			var edge := 1.0 + 0.35 * noise.get_noise_2d(cos(a) * r * 0.6, sin(a) * r * 0.6)
			var rr := r * (1.0 - f) * edge
			var x := cos(a) * rr
			var z := sin(a) * rr
			var base := pow(clampf(f, 0.0, 1.0), 0.8)
			var y := h * base * (0.65 + 0.6 * noise.get_noise_2d(x, z)) - 6.0 * (1.0 - f) * (1.0 if j == 0 else 0.0)
			if j == 0:
				y = -8.0
			row.append(Vector3(x, y, z))
		pts.append(row)
	var top := Vector3(0, h * (0.9 + 0.3 * noise.get_noise_2d(0, 0)), 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rings:
		for i in segs:
			var i2 := (i + 1) % segs
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i2]
			var c: Vector3 = pts[j + 1][i2] if j + 1 < rings else top
			var d: Vector3 = pts[j + 1][i] if j + 1 < rings else top
			_tri(st, a, c, b, h, style)
			if j + 1 < rings:
				_tri(st, a, d, c, h, style)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, h: float, style: String) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var y := (a.y + b.y + c.y) / 3.0
	var slope := 1.0 - n.y
	var col: Color
	if y < 2.0:
		col = Color(0.62, 0.57, 0.45) if style != "north" else Color(0.35, 0.34, 0.32)
	elif slope > 0.45 or y > h * 0.75:
		col = Color(0.38, 0.37, 0.35) if style != "north" else Color(0.30, 0.31, 0.32)
	else:
		col = Color(0.24, 0.33, 0.18) if style != "north" else Color(0.22, 0.27, 0.20)
	col = col.lightened(randf() * 0.06)
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)
