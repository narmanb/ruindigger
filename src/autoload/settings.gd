extends Node
## Player-facing options, persisted to user://settings.cfg with validation.

signal changed

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"master_volume": 0.9,
	"sfx_volume": 0.9,
	"music_volume": 0.6,
	"screen_shake": 0.8,
	"reduced_flashing": false,
	"low_effects": false,
	"fps_30": false,
	"touch_mode": 0,        # 0 auto, 1 always, 2 never
	"touch_scale": 1.0,
	"touch_opacity": 0.65,
	"show_fps": false,
}

const RANGES := {
	"master_volume": [0.0, 1.0],
	"sfx_volume": [0.0, 1.0],
	"music_volume": [0.0, 1.0],
	"screen_shake": [0.0, 1.0],
	"touch_mode": [0, 2],
	"touch_scale": [0.7, 1.5],
	"touch_opacity": [0.25, 1.0],
}

var values: Dictionary = DEFAULTS.duplicate()
var path: String = PATH


func _ready() -> void:
	load_settings()
	apply()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, v: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	values[key] = _sanitize(key, v)
	apply()
	save_settings()
	changed.emit()


func _sanitize(key: String, v: Variant) -> Variant:
	var def: Variant = DEFAULTS[key]
	if typeof(def) == TYPE_BOOL:
		return bool(v) if (typeof(v) == TYPE_BOOL or typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) else def
	if typeof(def) == TYPE_INT:
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return def
		var r: Array = RANGES.get(key, [-999999, 999999])
		return clampi(int(v), int(r[0]), int(r[1]))
	if typeof(def) == TYPE_FLOAT:
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return def
		var fv: float = float(v)
		if is_nan(fv) or is_inf(fv):
			return def
		var r2: Array = RANGES.get(key, [-1e9, 1e9])
		return clampf(fv, float(r2[0]), float(r2[1]))
	return def


func load_settings() -> void:
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key in DEFAULTS.keys():
		if cfg.has_section_key("options", key):
			values[key] = _sanitize(key, cfg.get_value("options", key))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in values.keys():
		cfg.set_value("options", key, values[key])
	cfg.save(path)


func apply() -> void:
	Engine.max_fps = 30 if values["fps_30"] else 0
	for bus in [["Master", "master_volume"], ["SFX", "sfx_volume"], ["Music", "music_volume"]]:
		var idx := AudioServer.get_bus_index(bus[0])
		if idx >= 0:
			var lin: float = values[bus[1]]
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(lin, 0.0001)))
			AudioServer.set_bus_mute(idx, lin <= 0.001)


func shake_scale() -> float:
	return values["screen_shake"]


func reduced_flashing() -> bool:
	return values["reduced_flashing"]


func low_effects() -> bool:
	return values["low_effects"]
