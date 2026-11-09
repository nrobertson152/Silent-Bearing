extends SceneTree
## Fires one effect in open water and saves frames as it develops.
## xvfb-run godot --path . --fixed-fps 20 --resolution 960x540 -s tools/fx_preview.gd -- <out_dir> <effect> [tod]
## Effects: torpedo, shell, splash, dc, muzzle, fire, smoke

const GameData := preload("res://scripts/data.gd")
const U := preload("res://scripts/util.gd")
const World := preload("res://scripts/sim/world.gd")
const WorldView := preload("res://scripts/view/world_view.gd")

var frame := 0
var view: WorldView
var w: World
var cam: Camera3D
var out_dir := "."
var effect := "torpedo"
var snaps := {4: "a", 12: "b", 30: "c", 70: "d", 140: "e"}
var fire_rec := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "."
	effect = args[1] if args.size() > 1 else "torpedo"
	var nat: Dictionary = GameData.nations()["us"]
	var spec: Dictionary = nat["targets"][3].duplicate()
	if args.size() > 2:
		spec["tod"] = args[2]
	w = World.new(nat, spec)
	w.sub.pos = Vector2(0, -3000)
	w.sub.depth = 30.0
	for e in w.ships:
		e.pos = Vector2(5000 + e.id * 300, 5000)
	view = WorldView.new()
	root.add_child(view)
	view.setup(w)
	cam = Camera3D.new()
	cam.far = 60000.0
	root.add_child(cam)
	cam.current = true
	cam.fov = 50.0
	cam.look_at_from_position(Vector3(-260, 25, 160), Vector3(0, 25, 0))


func _process(dt: float) -> bool:
	frame += 1
	w.t += dt
	if frame == 2:
		match effect:
			"torpedo":
				view.fx.explosion(Vector3.ZERO, 12.0, "torpedo")
			"shell":
				view.fx.explosion(Vector3(0, 8, 0), 2.5, "shell_hit")
			"splash":
				view.fx.splash(Vector3.ZERO, 9.0)
			"dc":
				view.fx.depth_charge(Vector3.ZERO, 30.0)
			"muzzle":
				view.fx.muzzle(Vector3(0, 10, 0), 152.0, Vector3(0, 0.2, 1).normalized())
			"fire", "smoke":
				var holder := Node3D.new()
				root.add_child(holder)
				if effect == "fire":
					fire_rec = view.fx.ship_fire(holder, Vector3(0, 6, 0), 6.0)
					view.fx.set_fire(fire_rec, 0.9, true)
				else:
					var p := view.fx.funnel_smoke(holder, Vector3(0, 20, 0), view.m_smoke, 3.2)
					p.emitting = true
	view.sync(dt, cam.global_position)
	if snaps.has(frame):
		root.get_viewport().get_texture().get_image().save_png("%s/fx_%s_%s.png" % [out_dir, effect, snaps[frame]])
	return frame >= 140
