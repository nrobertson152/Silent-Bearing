class_name Sfx
extends Node
## Every sound is synthesised at startup, so the game ships no audio files.
## Distant sounds can be delayed by their travel time through the air.

const RATE := 22050

var streams := {}
var pool: Array = []
var loops := {}
var delayed: Array = []
var on := true
var t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_build()
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	for name in ["motor", "diesel", "sea", "flow"]:
		var p := AudioStreamPlayer.new()
		p.stream = streams[name]
		p.volume_db = -80.0
		add_child(p)
		p.play()
		loops[name] = p


func play(name: String, vol := 1.0, delay := 0.0) -> void:
	if not on or not streams.has(name) or vol <= 0.01:
		return
	if delay > 0.05:
		delayed.append([t + delay, name, vol])
		return
	for p in pool:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = linear_to_db(clampf(vol, 0.0, 1.5))
			p.pitch_scale = _rng.randf_range(0.94, 1.06)
			p.play()
			return


func set_loop(name: String, vol: float, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = loops.get(name)
	if p == null:
		return
	var target := linear_to_db(maxf(vol, 0.0001)) if on else -80.0
	p.volume_db = lerpf(p.volume_db, target, 0.1)
	p.pitch_scale = pitch


func _process(delta: float) -> void:
	t += delta
	if delayed.is_empty():
		return
	var keep := []
	for d in delayed:
		if t >= d[0]:
			play(d[1], d[2])
		else:
			keep.append(d)
	delayed = keep


func toggle() -> bool:
	on = not on
	if not on:
		for p in pool:
			p.stop()
		for k in loops:
			loops[k].volume_db = -80.0
	return on


# ------------------------------------------------------------- synthesis
func _n() -> float:
	return _rng.randf() * 2.0 - 1.0


static func _alpha(fc: float) -> float:
	return 1.0 - exp(-TAU * fc / RATE)


func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	var g := 0.9 / peak
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i] * g, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


func _buf(secs: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * secs))
	return b


func _boom(secs: float, fc: float, decay: float, crack: float, thump := 0.8) -> PackedFloat32Array:
	var b := _buf(secs)
	var a := _alpha(fc)
	var y := 0.0
	var y2 := 0.0
	var ph := 0.0
	for i in b.size():
		var tt := float(i) / RATE
		var x := _n()
		y += a * (x - y)
		y2 += a * (y - y2)
		ph += TAU * (36.0 + 30.0 * exp(-tt * 6.0)) / RATE
		b[i] = y2 * 6.0 * exp(-tt * decay) + sin(ph) * exp(-tt * 3.5) * thump + x * exp(-tt * 30.0) * crack
	return b


func _build() -> void:
	# Sonar ping with its echo.
	var b := _buf(2.4)
	for i in b.size():
		var tt := float(i) / RATE
		var v := sin(TAU * 1250.0 * tt) * minf(1.0, tt * 80.0) * exp(-tt * 2.4)
		b[i] = v
	var d := int(0.42 * RATE)
	for i in range(b.size() - 1, d, -1):
		b[i] += b[i - d] * 0.3
	streams["ping"] = _wav(b)
	streams["torp_hit"] = _wav(_boom(4.0, 140.0, 1.1, 0.12, 1.0))
	streams["boom"] = streams["torp_hit"]
	streams["breakup"] = _wav(_breakup())
	var dc := _boom(3.0, 90.0, 1.8, 0.6, 1.0)
	for i in dc.size():
		var tt := float(i) / RATE
		dc[i] += (sin(TAU * 183.0 * tt) + 0.6 * sin(TAU * 291.0 * tt)) * exp(-tt * 2.2) * 0.35
	streams["dc"] = _wav(dc)
	streams["hit_far"] = _wav(_boom(1.8, 220.0, 2.4, 0.3, 0.5))
	streams["gun_far"] = _wav(_boom(2.4, 120.0, 2.0, 0.05, 0.7))
	# Deck gun: a hard crack and a short boom.
	var g := _boom(1.4, 400.0, 4.0, 1.4, 1.0)
	streams["deckgun"] = _wav(g)
	# AA: a short pop.
	b = _buf(0.22)
	for i in b.size():
		var tt := float(i) / RATE
		b[i] = _n() * exp(-tt * 45.0) + sin(TAU * 140.0 * tt) * exp(-tt * 25.0)
	streams["aa"] = _wav(b)
	# Machine-gun burst from an aircraft.
	b = _buf(0.7)
	for i in b.size():
		var tt := float(i) / RATE
		var ph := fmod(tt * 14.0, 1.0)
		b[i] = _n() * exp(-ph * 18.0) * (1.0 - tt / 0.7)
	streams["mg"] = _wav(b)
	# Torpedo launch: a thump and rushing air.
	b = _buf(1.0)
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var tt := float(i) / RATE
		var x := _n()
		y1 += _alpha(1400.0) * (x - y1)
		y2 += _alpha(180.0) * (x - y2)
		b[i] = (y1 - y2) * 2.2 * exp(-tt * 3.2) * minf(1.0, tt * 20.0) + sin(TAU * 68.0 * tt) * exp(-tt * 8.0)
	streams["launch"] = _wav(b)
	b = _buf(0.5)
	for i in b.size():
		var tt := float(i) / RATE
		b[i] = sin(TAU * 85.0 * tt) * exp(-tt * 10.0)
	streams["thud"] = _wav(b)
	# Hull groaning under pressure.
	b = _buf(2.2)
	var ph := 0.0
	var ly := 0.0
	for i in b.size():
		var tt := float(i) / RATE
		ph += TAU * (115.0 - 30.0 * tt) / RATE
		ly += _alpha(300.0) * (_n() - ly)
		b[i] = (sin(ph) * (0.6 + 0.4 * sin(TAU * 7.0 * tt)) + ly * 0.8) * minf(1.0, tt * 4.0) * exp(-tt * 1.1)
	streams["creak"] = _wav(b)
	# Diving alarm.
	b = _buf(1.8)
	ph = 0.0
	ly = 0.0
	for i in b.size():
		var tt := float(i) / RATE
		var cyc := fmod(tt, 0.9)
		var f := 230.0 + 260.0 * clampf(cyc / 0.55, 0.0, 1.0)
		ph += f / RATE
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		ly += _alpha(1800.0) * (saw - ly)
		b[i] = ly * (1.0 if cyc < 0.62 else 0.0)
	streams["klaxon"] = _wav(b)
	# General alarm bell.
	b = _buf(1.6)
	for i in b.size():
		var tt := float(i) / RATE
		b[i] = (sin(TAU * 880.0 * tt) + 0.5 * sin(TAU * 2310.0 * tt)) * (0.5 + 0.5 * sign(sin(TAU * 18.0 * tt))) * minf(1.0, (1.6 - tt) * 4.0)
	streams["alarm"] = _wav(b)
	# Engine order telegraph bell.
	b = _buf(1.2)
	for i in b.size():
		var tt := float(i) / RATE
		b[i] = (sin(TAU * 1480.0 * tt) + 0.4 * sin(TAU * 3940.0 * tt)) * exp(-tt * 3.5)
	streams["telegraph"] = _wav(b)
	streams["cheer"] = streams["telegraph"]
	# Periscope hoist motor.
	b = _buf(1.3)
	ph = 0.0
	for i in b.size():
		var tt := float(i) / RATE
		ph += TAU * (260.0 + 160.0 * tt) / RATE
		b[i] = (sin(ph) + 0.3 * sin(ph * 2.0)) * minf(1.0, tt * 8.0) * minf(1.0, (1.3 - tt) * 6.0) * 0.6
	streams["scope"] = _wav(b)
	# Blowing ballast: a long roar of air.
	b = _buf(3.2)
	ly = 0.0
	for i in b.size():
		var tt := float(i) / RATE
		var x := _n()
		ly += _alpha(2500.0) * (x - ly)
		b[i] = (x - ly) * minf(1.0, tt * 3.0) * minf(1.0, (3.2 - tt) * 1.5)
	streams["blow"] = _wav(b)
	# Shell splashes and hits.
	for name in ["splash", "splash_near"]:
		var secs := 1.3 if name == "splash" else 1.9
		b = _buf(secs)
		ly = 0.0
		for i in b.size():
			var tt := float(i) / RATE
			ly += _alpha(900.0 if name == "splash" else 1600.0) * (_n() - ly)
			b[i] = ly * minf(1.0, tt * 30.0) * exp(-tt * (3.0 if name == "splash" else 1.8))
		streams[name] = _wav(b)
	b = _buf(1.6)
	for i in b.size():
		var tt := float(i) / RATE
		var v := 0.0
		for f in [310.0, 523.0, 788.0, 1210.0, 1660.0]:
			v += sin(TAU * f * tt) * exp(-tt * (3.0 + f / 600.0))
		b[i] = v * 0.4 + _n() * exp(-tt * 25.0)
	streams["hull_hit"] = _wav(b)
	# Loops: electric motors, diesels, the sea outside, water past the hull.
	b = _buf(2.0)
	for i in b.size():
		var tt := float(i) / RATE
		b[i] = sin(TAU * 60.0 * tt) * 0.5 + sin(TAU * 120.0 * tt) * 0.35 + sin(TAU * 420.0 * tt) * 0.12 + sin(TAU * 840.0 * tt) * 0.05 + _n() * 0.03
	streams["motor"] = _wav(b, true)
	b = _buf(2.0)
	ly = 0.0
	for i in b.size():
		var tt := float(i) / RATE
		ly += _alpha(250.0) * (_n() - ly)
		var ph2 := fmod(tt * 9.0, 1.0)
		b[i] = ly * 4.0 * (0.4 + exp(-ph2 * 9.0)) + sin(TAU * 36.0 * tt) * 0.4
	streams["diesel"] = _wav(b, true)
	b = _buf(4.0)
	ly = 0.0
	var ly2 := 0.0
	for i in b.size():
		var tt := float(i) / RATE
		ly += _alpha(500.0) * (_n() - ly)
		ly2 += _alpha(120.0) * (_n() - ly2)
		b[i] = ly * (0.6 + 0.4 * sin(TAU * 0.25 * tt)) + ly2 * 2.0
	streams["sea"] = _wav(b, true)
	b = _buf(3.0)
	ly = 0.0
	for i in b.size():
		var tt := float(i) / RATE
		ly += _alpha(350.0) * (_n() - ly)
		b[i] = ly * (0.8 + 0.2 * sin(TAU * tt / 3.0 * 2.0))
	streams["flow"] = _wav(b, true)


func _breakup() -> PackedFloat32Array:
	var b := _buf(6.0)
	var ly := 0.0
	var ph := 0.0
	for i in b.size():
		var tt := float(i) / RATE
		ly += _alpha(70.0) * (_n() - ly)
		ph += TAU * (80.0 - 6.0 * tt + 20.0 * sin(tt * 1.3)) / RATE
		var crack := 0.0
		if _rng.randf() < 0.0004:
			crack = _n() * 4.0
		b[i] = ly * 8.0 * minf(1.0, tt * 2.0) * exp(-tt * 0.35) + sin(ph) * 0.35 * exp(-tt * 0.4) + crack
	return b
