extends Node3D
## The wake map: a top-down orthographic render of foam around the camera that
## the ocean shader reads. Ships, the boat and torpedoes leave soft blobs on a
## render layer only this camera sees: churned water astern (red), the spreading
## V of a Kelvin wake (green), the bow wave and hull wash, and short-lived
## patches where shells, bombs and depth charges went off. Because the ocean
## draws the foam itself, wakes follow the waves instead of floating on them.

const Gfx := preload("res://scripts/view/gfx.gd")

const LAYER := 20
const MASK := 1 << (LAYER - 1)
## Half-angle of a Kelvin wake: the arms spread at tan(19.47 deg) of the ship's speed.
const KELVIN := 0.3536

var vp: SubViewport
var cam: Camera3D
var size := 1024.0
var res := 1024
var center := Vector2.ZERO
var m_foam: ShaderMaterial
var m_lines: ShaderMaterial
var m_ring: ShaderMaterial
var blob: QuadMesh


func _init() -> void:
	res = 2048 if Gfx.quality >= 2 else 1024
	vp = SubViewport.new()
	vp.size = Vector2i(res, res)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0
	vp.audio_listener_enable_3d = false
	add_child(vp)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.near = 1.0
	cam.far = 1200.0
	cam.cull_mask = MASK
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	vp.add_child(cam)
	cam.current = true
	var shader: Shader = load("res://shaders/wake_mark.gdshader")
	m_foam = ShaderMaterial.new()
	m_foam.shader = shader
	m_lines = ShaderMaterial.new()
	m_lines.shader = shader
	m_lines.set_shader_parameter("channel", Vector3(0.0, 1.0, 0.0))
	m_ring = ShaderMaterial.new()
	m_ring.shader = shader
	m_ring.set_shader_parameter("channel", Vector3(0.8, 0.6, 0.0))
	m_ring.set_shader_parameter("ring", 1.0)
	blob = QuadMesh.new()
	blob.orientation = PlaneMesh.FACE_Y
	blob.size = Vector2(1, 1)


## Stop rendering the map while the outside world is hidden (inside the boat).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED


func texture() -> Texture2D:
	return vp.get_texture()


## Keep the map over the patch of sea the camera is looking at, snapped to
## whole texels so the foam doesn't crawl.
func follow(cam_xform: Transform3D) -> void:
	var f := -cam_xform.basis.z
	var fwd := Vector2(f.x, f.z)
	fwd = fwd.normalized() if fwd.length() > 0.05 else Vector2.ZERO
	var c := Vector2(cam_xform.origin.x, cam_xform.origin.z) + fwd * size * 0.3
	var texel := size / res
	center = Vector2(snappedf(c.x, texel), snappedf(c.y, texel))
	cam.global_transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)),
		Vector3(center.x, 600.0, center.y))


func _emitter(mat: Material, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = blob
	p.material_override = mat
	p.layers = MASK
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.gravity = Vector3.ZERO
	p.spread = 0.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	add_child(p)
	return p


static func _curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(a, b) + 0.01
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	return c


static func _fade(peak: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(peak, 0, 0, 1))
	g.add_point(0.15, Color(peak * 0.8, 0, 0, 1))
	g.set_color(g.get_point_count() - 1, Color(0, 0, 0, 1))
	return g


## Churned water left astern: starts the width of the hull and spreads out.
func trail(width: float, life: float, amount: int, peak := 1.0) -> CPUParticles3D:
	var p := _emitter(m_foam, amount, life)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(width * 0.25, 0.0, 1.0)
	p.direction = Vector3(0, 0, 1)
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.4
	p.scale_amount_min = width * 0.75
	p.scale_amount_max = width * 1.0
	p.scale_amount_curve = _curve(1.0, 2.3)
	p.color_ramp = _fade(peak)
	return p


## One arm of the Kelvin wake. Blobs leave the bow sideways at KELVIN times the
## ship's speed, which lays them out along the classic 19.5-degree line.
func arm(side: float, width: float, life: float, amount: int) -> CPUParticles3D:
	var p := _emitter(m_lines, amount, life)
	p.direction = Vector3(side, 0, 0.15)
	p.spread = 2.0
	p.flatness = 1.0
	p.scale_amount_min = width * 0.5
	p.scale_amount_max = width * 0.7
	p.scale_amount_curve = _curve(1.0, 2.6)
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0, 0, 1))
	g.add_point(0.08, Color(0.9, 0, 0, 1))
	g.set_color(g.get_point_count() - 1, Color(0, 0, 0, 1))
	p.color_ramp = g
	return p


## The bow wave and hull wash quad that rides under a ship.
func hull(parent: Node3D, beam: float, length: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(beam * 2.6, length * 1.3)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/wake_hull.gdshader")
	m.set_shader_parameter("beam", beam)
	m.set_shader_parameter("hull_len", length)
	mi.material_override = m
	mi.layers = MASK
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	parent.add_child(mi)
	return mi


## Points a ship's wake emitters and sets their strength for this frame.
## `xf` is the ship's transform, `half_len` half its length, `kn` its speed.
func steer(rec: Dictionary, xf: Transform3D, half_len: float, kn: float, on: bool) -> void:
	var flat := Basis(Vector3.UP, xf.basis.get_euler(EULER_ORDER_YXZ).y)
	var v := kn * 0.514444
	var s := clampf(kn / 25.0, 0.0, 1.3)
	var stern := xf * Vector3(0, 0, half_len * 0.92)
	var bow := xf * Vector3(0, 0, -half_len * 0.9)
	var tr: CPUParticles3D = rec["trail"]
	tr.global_transform = Transform3D(flat, Vector3(stern.x, 0.0, stern.z))
	tr.emitting = on and kn > 1.0
	tr.color = Color(clampf(0.35 + s, 0.0, 1.0), 1, 1, 1)
	for a in rec["arms"]:
		var e: CPUParticles3D = a
		e.global_transform = Transform3D(flat, Vector3(bow.x, 0.0, bow.z))
		e.emitting = on and kn > 3.0
		e.initial_velocity_min = v * KELVIN * 0.95
		e.initial_velocity_max = v * KELVIN * 1.05
		e.color = Color(clampf(0.25 + s, 0.0, 1.0), 1, 1, 1)
	var h: MeshInstance3D = rec["hull"]
	h.visible = on
	(h.material_override as ShaderMaterial).set_shader_parameter("speed", s)


## A full wake for something `beam` wide and `length` long.
func ship(parent: Node3D, beam: float, length: float, life := 45.0) -> Dictionary:
	var n := int(clampf(life * 2.0, 30.0, 120.0))
	# Blobs overlap more on a wide hull, so each one is fainter.
	return {
		"trail": trail(beam, life, n, clampf(2.6 / beam, 0.08, 0.45)),
		"arms": [arm(1.0, maxf(beam * 0.45, 3.0), life * 0.6, n), arm(-1.0, maxf(beam * 0.45, 3.0), life * 0.6, n)],
		"hull": hull(parent, beam, length),
	}


func free_ship(rec: Dictionary) -> void:
	for k in ["trail"]:
		rec[k].emitting = false
	for a in rec["arms"]:
		a.emitting = false
	rec["hull"].visible = false


## A patch of white water that fades over `life` seconds (splashes, hits,
## depth charges). With `ring`, an expanding shock ring instead of a disc.
func patch(pos: Vector3, radius: float, life: float, peak := 1.0, ring := false) -> void:
	var p := _emitter(m_ring if ring else m_foam, 1, life)
	p.one_shot = true
	p.explosiveness = 1.0
	p.scale_amount_min = radius * (0.4 if ring else 1.6)
	p.scale_amount_max = p.scale_amount_min
	p.scale_amount_curve = _curve(1.0, 5.0 if ring else 1.6)
	p.color_ramp = _fade(peak)
	p.global_position = Vector3(pos.x, 0.0, pos.z)
	p.emitting = true
	p.finished.connect(p.queue_free)
