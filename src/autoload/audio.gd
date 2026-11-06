extends Node
## Pooled SFX playback with per-bus volume from settings. Sounds are the
## procedurally synthesised WAVs in assets/audio.

const SFX := {
	"dig_soft": "res://assets/audio/dig_soft.wav",
	"dig_rock": "res://assets/audio/dig_rock.wav",
	"dig_alloy": "res://assets/audio/dig_alloy.wav",
	"explosion": "res://assets/audio/explosion.wav",
	"gas_hiss": "res://assets/audio/gas_hiss.wav",
	"rattle": "res://assets/audio/rattle.wav",
	"ore_chime": "res://assets/audio/ore_chime.wav",
	"hurt": "res://assets/audio/hurt.wav",
	"jump": "res://assets/audio/jump.wav",
	"land": "res://assets/audio/land.wav",
	"alarm": "res://assets/audio/alarm.wav",
	"laser": "res://assets/audio/laser.wav",
	"enemy_death": "res://assets/audio/enemy_death.wav",
	"ui_click": "res://assets/audio/ui_click.wav",
	"purchase": "res://assets/audio/purchase.wav",
	"extract_win": "res://assets/audio/extract_win.wav",
}

const VOICES := 16

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _drill_player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in SFX:
		if ResourceLoader.exists(SFX[key]):
			_streams[key] = load(SFX[key])
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_drill_player = AudioStreamPlayer.new()
	_drill_player.bus = "Master"
	_drill_player.stream = _streams.get("drill_loop") if _streams.has("drill_loop") else null
	add_child(_drill_player)
	if _drill_player.stream:
		_drill_player.stream.loop = true
	apply_settings()

func apply_settings() -> void:
	var m := float(SaveManager.settings.get("master_volume", 0.8))
	var s := float(SaveManager.settings.get("sfx_volume", 0.9))
	var db := linear_to_db(max(0.0001, m * s))
	for p in _players:
		p.volume_db = db
	if _drill_player:
		_drill_player.volume_db = db - 4.0

func play(key: String, pitch_variation: float = 0.0, volume_db: float = 0.0) -> void:
	if not _streams.has(key):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[key]
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.volume_db = volume_db + linear_to_db(max(0.0001,
		float(SaveManager.settings.get("master_volume", 0.8)) *
		float(SaveManager.settings.get("sfx_volume", 0.9))))
	p.play()

func play_at(key: String, world_pos: Vector2, listener: Vector2, max_dist: float = 900.0,
		pitch_variation: float = 0.0) -> void:
	if not _streams.has(key):
		return
	var d := world_pos.distance_to(listener)
	if d > max_dist:
		return
	var atten := lerpf(0.0, -24.0, clampf(d / max_dist, 0.0, 1.0))
	play(key, pitch_variation, atten)

func drill(on: bool, material: int = 1) -> void:
	if _drill_player == null or _drill_player.stream == null:
		return
	if on and not _drill_player.playing:
		_drill_player.play()
	elif not on and _drill_player.playing:
		_drill_player.stop()
	if on:
		match material:
			Balance.Mat.BASALT:
				_drill_player.pitch_scale = 0.86
			Balance.Mat.ALLOY:
				_drill_player.pitch_scale = 0.72
			_:
				_drill_player.pitch_scale = 1.05

func dig_hit(material: int) -> void:
	match material:
		Balance.Mat.SOIL:
			play("dig_soft", 0.14)
		Balance.Mat.BASALT:
			play("dig_rock", 0.1)
		Balance.Mat.ALLOY:
			play("dig_alloy", 0.08)
		_:
			play("dig_rock", 0.1)
