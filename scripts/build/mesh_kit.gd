extends RefCounted
## Collects primitive shapes into one ArrayMesh with a surface per material.
## Normals point away from each shape's centre so faces light correctly with
## back-face culling switched off.

var _tools := {}
var mats := {}
## Placement applied to everything drawn (rotation and translation only).
var xf := Transform3D.IDENTITY
## Optional Callable(world_pos: Vector3) -> Color, baked into vertex colours.
var shade := Callable()


func _init(materials: Dictionary = {}) -> void:
	mats = materials


func _st(mat: String) -> SurfaceTool:
	var st: SurfaceTool = _tools.get(mat)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[mat] = st
	return st


func _v(st: SurfaceTool, p: Vector3, n: Vector3) -> void:
	var wp := xf * p
	st.set_normal((xf.basis * n).normalized())
	if shade.is_valid():
		st.set_color(shade.call(wp))
	st.add_vertex(wp)


func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var st := _st(mat)
	_v(st, a, n)
	_v(st, b, n)
	_v(st, c, n)


## Flat quad; `inside` is any point on the inner side, used to orient the normal.
func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		n = (c - a).cross(d - a)
	n = n.normalized()
	if n.dot((a + b + c + d) * 0.25 - inside) < 0.0:
		n = -n
	tri(mat, a, b, c, n)
	tri(mat, a, c, d, n)


## Smooth quad with per-vertex normals.
func quad_n(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	var st := _st(mat)
	for pair in [[a, na], [b, nb], [c, nc], [a, na], [c, nc], [d, nd]]:
		_v(st, pair[0], pair[1])


## Textured disc facing `n` (gauge faces). UVs map the disc onto the whole texture.
func disc_uv(mat: String, c: Vector3, n: Vector3, r: float, segs := 16) -> void:
	var st := _st(mat)
	n = n.normalized()
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var u := ref.cross(n).normalized()
	var v := n.cross(u).normalized()
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		for pt in [[0.0, 0.0, true], [a0, 0.0, false], [a1, 0.0, false]]:
			var p := c
			var uv := Vector2(0.5, 0.5)
			if not pt[2]:
				p = c + (u * cos(pt[0]) + v * sin(pt[0])) * r
				uv = Vector2(0.5 + 0.5 * cos(pt[0]), 0.5 - 0.5 * sin(pt[0]))
			st.set_uv(uv)
			_v(st, p, n)


## Textured rectangle: centre, normal, up direction, size, UV rectangle.
func rect_uv(mat: String, c: Vector3, n: Vector3, up: Vector3, size: Vector2, uv := Rect2(0, 0, 1, 1)) -> void:
	var st := _st(mat)
	n = n.normalized()
	var r := up.cross(n).normalized()
	var u := n.cross(r).normalized()
	var hx := r * size.x * 0.5
	var hy := u * size.y * 0.5
	var corners := [[c - hx - hy, Vector2(uv.position.x, uv.end.y)], [c + hx - hy, uv.end],
		[c + hx + hy, Vector2(uv.end.x, uv.position.y)], [c - hx + hy, uv.position]]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(corners[i][1])
		_v(st, corners[i][0], n)


## Convex hexahedron from 8 corners: bottom face 0..3 then top face 4..7, same winding.
func hexa(mat: String, p: Array) -> void:
	var c := Vector3.ZERO
	for v in p:
		c += v
	c /= 8.0
	quad(mat, p[0], p[1], p[2], p[3], c)
	quad(mat, p[4], p[5], p[6], p[7], c)
	for i in 4:
		var j := (i + 1) % 4
		quad(mat, p[i], p[j], p[j + 4], p[i + 4], c)


## Box centred at `c` with full size `s`, optionally rotated.
func box(mat: String, c: Vector3, s: Vector3, basis := Basis.IDENTITY) -> void:
	var h := s * 0.5
	var p := []
	for v in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1),
			Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		p.append(c + basis * (v * h))
	hexa(mat, p)


## Tapered block: bottom size (w0, l0) at y0, top size (w1, l1) at y1, centred on (x, z).
## `shift` moves the top face along z (for raked fronts).
func block(mat: String, x: float, z: float, y0: float, y1: float, w0: float, l0: float,
		w1: float, l1: float, shift := 0.0) -> void:
	hexa(mat, [
		Vector3(x - w0 / 2, y0, z - l0 / 2), Vector3(x + w0 / 2, y0, z - l0 / 2),
		Vector3(x + w0 / 2, y0, z + l0 / 2), Vector3(x - w0 / 2, y0, z + l0 / 2),
		Vector3(x - w1 / 2, y1, z - l1 / 2 + shift), Vector3(x + w1 / 2, y1, z - l1 / 2 + shift),
		Vector3(x + w1 / 2, y1, z + l1 / 2 + shift), Vector3(x - w1 / 2, y1, z + l1 / 2 + shift)])


## Cylinder or cone from a to b. Elliptical when rz differs from r (rz runs along the
## `side` axis). Smooth sides, flat caps.
func cyl(mat: String, a: Vector3, b: Vector3, r0: float, r1: float, segs := 10, caps := true,
		cap_mat := "", stretch := 1.0) -> void:
	var axis := b - a
	if axis.length_squared() < 1e-10:
		return
	var up := axis.normalized()
	var ref := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var u := up.cross(ref).normalized()
	var v := up.cross(u).normalized()
	var ring0 := []
	var ring1 := []
	var norms := []
	for i in segs + 1:
		var ang := TAU * float(i) / segs
		var d := u * cos(ang) + v * sin(ang) * stretch
		var n := (u * cos(ang) + v * sin(ang) / maxf(stretch, 0.01)).normalized()
		ring0.append(a + d * r0)
		ring1.append(b + d * r1)
		norms.append(n)
	for i in segs:
		quad_n(mat, ring0[i], ring0[i + 1], ring1[i + 1], ring1[i], norms[i], norms[i + 1], norms[i + 1], norms[i])
	if caps:
		var cm := cap_mat if cap_mat != "" else mat
		for i in segs:
			if r1 > 0.0:
				tri(cm, b, ring1[i], ring1[i + 1], up)
			if r0 > 0.0:
				tri(cm, a, ring0[i + 1], ring0[i], -up)


## Vertical prism from a polygon given as Vector2(x, z) points.
func prism(mat: String, poly: Array, y0: float, y1: float, top_mat := "") -> void:
	var n := poly.size()
	var c := Vector3.ZERO
	for p in poly:
		c += Vector3(p.x, (y0 + y1) * 0.5, p.y)
	c /= n
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		quad(mat, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), c)
	var tm := top_mat if top_mat != "" else mat
	var ctop := Vector3(c.x, y1, c.z)
	var cbot := Vector3(c.x, y0, c.z)
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		tri(tm, ctop, Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3.UP)
		tri(mat, cbot, Vector3(b.x, y0, b.y), Vector3(a.x, y0, a.y), Vector3.DOWN)


func sphere(mat: String, c: Vector3, r: float, segs := 8, rings := 5, scale := Vector3.ONE) -> void:
	for j in rings:
		var t0 := PI * float(j) / rings - PI / 2
		var t1 := PI * float(j + 1) / rings - PI / 2
		for i in segs:
			var p0 := TAU * float(i) / segs
			var p1 := TAU * float(i + 1) / segs
			var n00 := Vector3(cos(t0) * cos(p0), sin(t0), cos(t0) * sin(p0))
			var n01 := Vector3(cos(t0) * cos(p1), sin(t0), cos(t0) * sin(p1))
			var n11 := Vector3(cos(t1) * cos(p1), sin(t1), cos(t1) * sin(p1))
			var n10 := Vector3(cos(t1) * cos(p0), sin(t1), cos(t1) * sin(p0))
			quad_n(mat, c + n00 * r * scale, c + n01 * r * scale, c + n11 * r * scale, c + n10 * r * scale,
				n00, n01, n11, n10)


func is_empty() -> bool:
	return _tools.is_empty()


func commit(into: ArrayMesh = null) -> ArrayMesh:
	var mesh := into if into != null else ArrayMesh.new()
	for key in _tools:
		var st: SurfaceTool = _tools[key]
		st.commit(mesh)
		var idx := mesh.get_surface_count() - 1
		if mats.has(key):
			mesh.surface_set_material(idx, mats[key])
	_tools.clear()
	return mesh


static func mat(color: Color, rough := 0.85, metal := 0.0, emit := Color.BLACK, emit_e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emit_e > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = emit_e
	return m
