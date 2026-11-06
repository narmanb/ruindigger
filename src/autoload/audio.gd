extends Node
## Sound manager: pooled one-shots (flat + positional), named loops and music.

const SFX_DIR := "res://assets/sfx/"
const LOOPS := ["drill_soft", "drill_hard", "drill_metal", "drill_idle", "gas_hiss", "lift_hum",
	"amb_dust", "amb_spore", "amb_engine", "amb_outpost"]

var _streams: Dictionary = {}
var _flat: Array[AudioStreamPlayer] = []
var _pos: Array[AudioStreamPlayer2D] = []
var _flat_i := 0
var _pos_i := 0
var _loops: Dictionary = {}       # name -> AudioStreamPlayer
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_name := ""
var _last_play: Dictionary = {}   # rate limit identical sounds


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_flat.append(p)
	for i in 18:
		var q := AudioStreamPlayer2D.new()
		q.bus = "SFX"
		q.max_distance = 520.0
		q.attenuation = 1.6
		add_child(q)
		_pos.append(q)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for m in [_music_a, _music_b]:
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)


func _setup_buses() -> void:
	for b in ["SFX", "Music"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.55
		rv.damping = 0.6
		rv.wet = 0.12
		rv.dry = 1.0
		AudioServer.add_bus_effect(sfx, rv)
	if Engine.has_singleton("Settings") or get_node_or_null("/root/Settings"):
		get_node("/root/Settings").apply()


func stream(sfx_name: String) -> AudioStream:
	if _streams.has(sfx_name):
		return _streams[sfx_name]
	var path := SFX_DIR + sfx_name + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
		if s is AudioStreamWAV and sfx_name in LOOPS:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
	_streams[sfx_name] = s
	return s


func _rate_ok(sfx_name: String, min_gap: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(sfx_name, -10.0)) < min_gap:
		return false
	_last_play[sfx_name] = now
	return true


func play(sfx_name: String, volume_db: float = 0.0, pitch_var: float = 0.06, min_gap: float = 0.03) -> void:
	var s := stream(sfx_name)
	if s == null or not _rate_ok(sfx_name, min_gap):
		return
	var p := _flat[_flat_i]
	_flat_i = (_flat_i + 1) % _flat.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func play_at(sfx_name: String, pos: Vector2, volume_db: float = 0.0, pitch_var: float = 0.08, min_gap: float = 0.03) -> void:
	var s := stream(sfx_name)
	if s == null or not _rate_ok(sfx_name + str(int(pos.x / 64)) + str(int(pos.y / 64)), min_gap):
		return
	var p := _pos[_pos_i]
	_pos_i = (_pos_i + 1) % _pos.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func loop(loop_name: String, on: bool, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _loops.get(loop_name)
	if on:
		if p == null:
			p = AudioStreamPlayer.new()
			p.bus = "SFX"
			p.stream = stream(loop_name)
			add_child(p)
			_loops[loop_name] = p
		p.volume_db = volume_db
		p.pitch_scale = pitch
		if not p.playing:
			p.play()
	elif p and p.playing:
		p.stop()


func stop_all_loops() -> void:
	for k in _loops.keys():
		_loops[k].stop()


func music(track: String, fade: float = 1.5) -> void:
	if track == _music_name:
		return
	_music_name = track
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_music_b, "volume_db", -80.0, fade)
	if track != "":
		_music_a.stream = stream(track)
		_music_a.volume_db = -40.0
		_music_a.play()
		tw.tween_property(_music_a, "volume_db", -4.0, fade)
	tw.chain().tween_callback(_music_b.stop)
