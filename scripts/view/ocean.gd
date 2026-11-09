extends Node3D
## The sea: one radial grid centred on the camera, dense underfoot and coarse
## at the horizon, carrying a long swell and a wind sea (shaders/ocean.gdshader).
## height() mirrors the shader so the boats, the periscope and the cameras ride
## the same waves.

const Gfx := preload("res://scripts/view/gfx.gd")

## Each wave: direction off the wind (degrees), steepness, wavelength (m). The
## first two are swell from a distant storm, the rest the local wind sea. At a
## sea state of 1.0 this is a moderate sea, about 2.5 m significant wave height.
const SPECTRUM := [
	[-40.0, 0.020, 170.0], [-30.0, 0.022, 118.0],
	[0.0, 0.036, 62.0], [22.0, 0.042, 44.0], [-18.0, 0.049, 31.0], [45.0, 0.053, 22.0],
	[-52.0, 0.056, 15.5], [12.0, 0.056, 11.0], [63.0, 0.053, 7.6], [-27.0, 0.049, 5.3],
	[36.0, 0.046, 3.7], [-66.0, 0.042, 2.6]]

static var _meshes := {}
static var _detail: NoiseTexture2D
static var _foam: NoiseTexture2D

var mat: ShaderMaterial
var mesh: MeshInstance3D
var amp := 1.0
var t := 0.0
var wind := Vector2(1, 0)
var cam_xz := Vector2.ZERO
var _w := PackedVector4Array()
var _k := PackedFloat32Array()
var _om := PackedFloat32Array()


func _init() -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/ocean.gdshader")
	mat.set_shader_parameter("detail", detail_tex())
	mat.set_shader_parameter("foam_tex", foam_tex())
	mesh = MeshInstance3D.new()
	mesh.mesh = radial(192 if Gfx.quality >= 1 else 128)
	mesh.material_override = mat
	mesh.extra_cull_margin = 16.0
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	set_sea(1.0, 0.0)


## Rings of vertices whose spacing grows with distance so every cell is
## roughly square, out to 95 km.
static func radial(segs: int) -> ArrayMesh:
	if _meshes.has(segs):
		return _meshes[segs]
	var growth := 1.0 + TAU / segs
	var radii := PackedFloat32Array()
	var r := 0.6
	while r < 95000.0:
		radii.append(r)
		r *= growth
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.append(Vector3.ZERO)
	var cs := PackedFloat32Array()
	var sn := PackedFloat32Array()
	for i in segs:
		cs.append(cos(TAU * i / segs))
		sn.append(sin(TAU * i / segs))
	for rr in radii:
		for i in segs:
			verts.append(Vector3(cs[i] * rr, 0.0, sn[i] * rr))
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var idx := PackedInt32Array()
	for i in segs:
		idx.append(0)
		idx.append(1 + i)
		idx.append(1 + (i + 1) % segs)
	for j in radii.size() - 1:
		var b0 := 1 + j * segs
		var b1 := b0 + segs
		for i in segs:
			var i2 := (i + 1) % segs
			idx.append(b0 + i)
			idx.append(b1 + i2)
			idx.append(b0 + i2)
			idx.append(b0 + i)
			idx.append(b1 + i)
			idx.append(b1 + i2)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[segs] = m
	return m


## Tileable ripple normals, generated once.
static func detail_tex() -> NoiseTexture2D:
	if _detail == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.011
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 5
		n.seed = 7
		_detail = NoiseTexture2D.new()
		_detail.width = 512
		_detail.height = 512
		_detail.seamless = true
		_detail.as_normal_map = true
		_detail.bump_strength = 5.0
		_detail.generate_mipmaps = true
		_detail.noise = n
	return _detail


## Tileable lacy bubble pattern for foam, generated once.
static func foam_tex() -> NoiseTexture2D:
	if _foam == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		n.frequency = 0.03
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		n.fractal_gain = 0.55
		n.seed = 11
		_foam = NoiseTexture2D.new()
		_foam.width = 512
		_foam.height = 512
		_foam.seamless = true
		_foam.normalize = true
		_foam.generate_mipmaps = true
		_foam.noise = n
	return _foam


func set_colors(deep: Color, shallow: Color, under: Color, sea_amp: float) -> void:
	mat.set_shader_parameter("deep", deep)
	mat.set_shader_parameter("scatter", shallow)
	mat.set_shader_parameter("under", under)
	set_sea(sea_amp, rad_to_deg(wind.angle()))


## Sea state (1.0 is moderate) and the direction the wind blows toward, as a
## Godot-space angle in degrees around +Y from +X.
func set_sea(sea_amp: float, wind_deg: float) -> void:
	amp = sea_amp
	wind = Vector2.from_angle(deg_to_rad(wind_deg))
	_w.clear()
	_k.clear()
	_om.clear()
	for w in SPECTRUM:
		var d := wind.rotated(deg_to_rad(w[0]))
		var k: float = TAU / w[2]
		_w.append(Vector4(d.x, d.y, float(w[1]) * amp, w[2]))
		_k.append(k)
		_om.append(sqrt(9.81 * k))
	mat.set_shader_parameter("waves", _w)
	mat.set_shader_parameter("amp", amp)
	mat.set_shader_parameter("wind", wind)
	mat.set_shader_parameter("crest_foam", clampf((amp - 0.45) * 1.6, 0.0, 1.4))


func set_sun(dir: Vector3, col: Color, energy: float) -> void:
	mat.set_shader_parameter("sun_dir", dir.normalized())
	mat.set_shader_parameter("sun_col", col)
	mat.set_shader_parameter("sun_e", energy)


func set_wake(tex: Texture2D, center: Vector2, size: float) -> void:
	mat.set_shader_parameter("wake_tex", tex)
	mat.set_shader_parameter("wake_rect", Vector4(center.x, center.y, size, 1.0 if tex != null else 0.0))


func follow(cam_pos: Vector3, time_s: float) -> void:
	t = time_s
	cam_xz = Vector2(cam_pos.x, cam_pos.z)
	mesh.global_position = Vector3(cam_pos.x, 0.0, cam_pos.z)
	mat.set_shader_parameter("t", time_s)


## Surface height at a world (Godot) x/z position, matching the shader,
## including the fade of short waves far from the camera.
func height(x: float, z: float) -> float:
	var dist := Vector2(x, z).distance_to(cam_xz)
	var n := _w.size()
	var fades := PackedFloat32Array()
	fades.resize(n)
	var any := false
	for i in n:
		var l := _w[i].w
		fades[i] = 1.0 - smoothstep(l * 5.0, l * 8.0, dist)
		any = any or fades[i] > 0.0
	if not any:
		return 0.0
	# Undo the waves' sideways shift to find the crest that sits over (x, z).
	var px := x
	var pz := z
	for it in 2:
		var dx := 0.0
		var dz := 0.0
		for i in n:
			if fades[i] <= 0.0:
				continue
			var w := _w[i]
			var f := _k[i] * (w.x * px + w.y * pz) - _om[i] * t
			var a := w.z * fades[i] / _k[i] * cos(f)
			dx += w.x * a
			dz += w.y * a
		px = x - dx
		pz = z - dz
	var y := 0.0
	for i in n:
		if fades[i] <= 0.0:
			continue
		var w := _w[i]
		y += w.z * fades[i] / _k[i] * sin(_k[i] * (w.x * px + w.y * pz) - _om[i] * t)
	return y
