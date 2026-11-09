extends SceneTree
## Fires torpedoes into every target at random spots, one every two minutes,
## until she sinks, and prints the average hits it took against the
## hits-to-sink figure in scripts/data.gd. For tuning scripts/sim/damage.gd.
## godot --headless --path . -s tools/damage_calibration.gd

const Damage := preload("res://scripts/sim/damage.gd")
const GameData := preload("res://scripts/data.gd")
func trial(layout: String, type: String, nat: String, L: float, B: float, D: float, hp: float, gap: float) -> Array:
	var h := Damage.new()
	h.setup(layout, type, nat, L, B, D, hp)
	h.mag_risk = 0.0
	var hits := 0
	var tsink := 0.0
	var max_list := 0.0
	while hits < 20:
		h.torpedo(randf_range(0.08, 0.92), -1 if randf() < 0.5 else 1, 1.0)
		hits += 1
		var t := 0.0
		while t < gap:
			h.step(0.25)
			h.events.clear()
			max_list = maxf(max_list, absf(h.list))
			t += 0.25
			if not h.afloat():
				return [hits, h.mode, t, max_list]
	return [hits, "afloat", 0.0, max_list]
func _init():
	seed(7)
	var nations := GameData.nations()
	var rows := []
	for nid in GameData.NATION_ORDER:
		for t in nations[nid]["targets"]:
			var sum := 0.0
			var caps := 0
			var ts := 0.0
			var ml := 0.0
			var N := 40
			for k in N:
				var r := trial(t["layout"], t["type"], t["nation"], t["length"], t["beam"], t["draft"], float(t["hp"]), 120.0)
				sum += r[0]
				if r[1] == "capsize": caps += 1
				ts += r[2]
				ml += r[3]
			print("%-12s hp=%d type=%s nat=%s  mean hits=%.2f capsize=%d%% after-last=%.0fs maxlist=%.1f" % [t["id"], t["hp"], t["type"], t["nation"], sum / N, caps * 100 / N, ts / N, ml / N])
	for e in [["dd_us","dd","us",1.0],["pc","pc","jp",0.45]]:
		var sum := 0.0
		for k in 60:
			sum += trial(e[0], e[1], e[2], 115.0, 11.0, 3.6, e[3], 120.0)[0]
		print("%s mean hits %.2f" % [e[0], sum / 60.0])
	quit()
