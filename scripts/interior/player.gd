extends CharacterBody3D
## First-person walking inside the boat. The camera rolls and pitches with
## the hull and jolts when depth charges go off.

const SPEED := 2.6
const RUN := 4.2
const SENS := 0.0022

var head: Node3D
var cam: Camera3D
var yaw := 0.0
var pitch := 0.0
var enabled := true
var roll := 0.0
var hull_pitch := 0.0
var shake := 0.0
var bob := 0.0


func _init() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	head = Node3D.new()
	head.position.y = 1.62
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 0.05
	cam.far = 200.0
	cam.cull_mask = 2
	head.add_child(cam)
	floor_max_angle = deg_to_rad(50)


func look(rel: Vector2) -> void:
	if not enabled:
		return
	yaw -= rel.x * SENS
	pitch = clampf(pitch - rel.y * SENS, -1.45, 1.45)


func face(y: float, p := 0.0) -> void:
	yaw = y
	pitch = p


func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if enabled:
		if Input.is_key_pressed(KEY_W):
			dir.z -= 1
		if Input.is_key_pressed(KEY_S):
			dir.z += 1
		if Input.is_key_pressed(KEY_A):
			dir.x -= 1
		if Input.is_key_pressed(KEY_D):
			dir.x += 1
	dir = dir.normalized().rotated(Vector3.UP, yaw)
	var spd := RUN if Input.is_key_pressed(KEY_SHIFT) else SPEED
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	if dir.length() > 0.1:
		bob += delta * spd * 2.4
	head.rotation = Vector3(pitch, yaw, 0)
	var jolt := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.05
	cam.position = Vector3(0, sin(bob) * 0.025, 0) + jolt
	cam.rotation = Vector3(hull_pitch, 0, roll + jolt.x * 0.5)
