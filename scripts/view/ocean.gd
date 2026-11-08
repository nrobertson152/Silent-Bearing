extends Node3D
## Near wave grid that follows the camera, plus a flat ring out to the horizon.

const WAVES := [[Vector2(1.0, 0.3), 0.15, 71.0], [Vector2(0.6, 1.0), 0.12, 37.0],
	[Vector2(-0.45, 1.0), 0.10, 21.0], [Vector2(1.0, -0.7), 0.08, 12.7],
	[Vector2(-0.9, -0.35), 0.06, 7.3], [Vector2(0.2, -1.0), 0.05, 4.9]]

var mat: ShaderMaterial
var far_mat: ShaderMaterial
var near: MeshInstance3D
var far: MeshInstance3D
var amp := 1.0
var t := 0.0


func _init() -> void:
	var shader: Shader = load("res://shaders/ocean.gdshader")
	mat = ShaderMaterial.new()
	mat.shader = shader
	far_mat = ShaderMaterial.new()
	far_mat.shader = shader
	far_mat.set_shader_parameter("flat_far", 1.0)
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600, 1600)
	pm.subdivide_width = 159
	pm.subdivide_depth = 159
	near = MeshInstance3D.new()
	near.mesh = pm
	near.material_override = mat
	near.extra_cull_margin = 20.0
	near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(near)
	far = MeshInstance3D.new()
	far.mesh = _ring(700.0, 90000.0, 64)
	far.material_override = far_mat
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)


static func _ring(r0: float, r1: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radii := [r0, r0 * 1.4, r0 * 2.5, r0 * 6.0, r1 * 0.2, r1]
	for j in radii.size() - 1:
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var p := [Vector3(cos(a0) * radii[j], 0, sin(a0) * radii[j]), Vector3(cos(a1) * radii[j], 0, sin(a1) * radii[j]),
				Vector3(cos(a1) * radii[j + 1], 0, sin(a1) * radii[j + 1]), Vector3(cos(a0) * radii[j + 1], 0, sin(a0) * radii[j + 1])]
			for v in [p[0], p[2], p[1], p[0], p[3], p[2]]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	return st.commit()


func set_colors(deep: Color, shallow: Color, under: Color, sea_amp: float) -> void:
	amp = sea_amp
	for m in [mat, far_mat]:
		m.set_shader_parameter("deep", deep)
		m.set_shader_parameter("shallow", shallow)
		m.set_shader_parameter("under", under)
		m.set_shader_parameter("amp", sea_amp)


func follow(cam_pos: Vector3, time_s: float) -> void:
	t = time_s
	near.global_position = Vector3(snappedf(cam_pos.x, 10.0), 0.0, snappedf(cam_pos.z, 10.0))
	far.global_position = Vector3(cam_pos.x, -0.05, cam_pos.z)
	var c := Vector2(near.global_position.x, near.global_position.z)
	for m in [mat, far_mat]:
		m.set_shader_parameter("t", time_s)
		m.set_shader_parameter("center", c)


## Surface height at a world (Godot) x/z position, matching the shader.
func height(x: float, z: float) -> float:
	var y := 0.0
	var p := Vector2(x, z)
	for w in WAVES:
		var k: float = TAU / w[2]
		var c := sqrt(9.81 / k)
		var d: Vector2 = w[0].normalized()
		var f := k * (d.dot(p) - c * t)
		y += float(w[1]) * amp / k * sin(f)
	return y
