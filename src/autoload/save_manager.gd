extends Node
## Persistent on-device progression and settings. Written to user:// with
## validation and safe defaults, so a corrupt or hand-edited file can never
## break the game.

const SAVE_PATH := "user://ruindigger_save.json"
const SAVE_VERSION := 1

var credits: int = 0
var upgrades: Dictionary = {"drill": 0, "suit": 0, "cargo": 0, "charges": 0}
var best_depth: int = 0
var runs_completed: int = 0
var last_seed: int = 0

var settings: Dictionary = {
	"master_volume": 0.8,
	"sfx_volume": 0.9,
	"music_volume": 0.6,
	"screen_shake": 1.0,
	"reduced_flash": false,
	"low_effects": false,
	"button_scale": 1.0,
	"button_opacity": 0.55,
	"left_handed": false,
	"show_fps": false,
	"touch_controls": true,
}

func _ready() -> void:
	load_save()

func default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"credits": 0,
		"upgrades": {"drill": 0, "suit": 0, "cargo": 0, "charges": 0},
		"best_depth": 0,
		"runs_completed": 0,
		"last_seed": 0,
		"settings": settings.duplicate(true),
	}

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("SaveManager: could not open save file; using defaults.")
		return
	var text := f.get_as_text()
	f.close()
	# JSON.parse_string() logs an engine error for malformed input, which is
	# exactly what we expect from a corrupt save. The instance API returns an
	# error code instead, so a damaged save degrades quietly to defaults.
	var json := JSON.new()
	var parsed = json.parse(text)
	if parsed != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("SaveManager: save file was not valid JSON; using defaults.")
		return
	_apply(json.data)

func _apply(d: Dictionary) -> void:
	if int(d.get("version", 0)) != SAVE_VERSION:
		push_warning("SaveManager: save version mismatch; keeping what is readable.")
	credits = max(0, int(d.get("credits", 0)))
	var up = d.get("upgrades", {})
	if typeof(up) == TYPE_DICTIONARY:
		for k in upgrades.keys():
			upgrades[k] = clampi(int(up.get(k, 0)), 0, Balance.UPGRADES[k]["max_level"])
	best_depth = max(0, int(d.get("best_depth", 0)))
	runs_completed = max(0, int(d.get("runs_completed", 0)))
	last_seed = int(d.get("last_seed", 0))
	var st = d.get("settings", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in settings.keys():
			if st.has(k):
				settings[k] = st[k]
	_sanitise_settings()

func _sanitise_settings() -> void:
	for k in ["master_volume", "sfx_volume", "music_volume"]:
		settings[k] = clampf(float(settings[k]), 0.0, 1.0)
	settings["screen_shake"] = clampf(float(settings["screen_shake"]), 0.0, 2.0)
	settings["button_scale"] = clampf(float(settings["button_scale"]), 0.7, 1.6)
	settings["button_opacity"] = clampf(float(settings["button_opacity"]), 0.2, 1.0)

func save() -> void:
	var d := {
		"version": SAVE_VERSION,
		"credits": credits,
		"upgrades": upgrades,
		"best_depth": best_depth,
		"runs_completed": runs_completed,
		"last_seed": last_seed,
		"settings": settings,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: could not write save file.")
		return
	f.store_string(JSON.stringify(d, "\t"))
	f.close()

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))

func can_afford(id: String) -> bool:
	var lv := upgrade_level(id)
	var costs: Array = Balance.UPGRADES[id]["costs"]
	return lv < costs.size() and credits >= int(costs[lv])

func buy(id: String) -> bool:
	if not Balance.UPGRADES.has(id) or not can_afford(id):
		return false
	var lv := upgrade_level(id)
	credits -= int(Balance.UPGRADES[id]["costs"][lv])
	upgrades[id] = lv + 1
	save()
	return true

func add_credits(amount: int) -> void:
	credits = max(0, credits + amount)
	save()

func reset_progress() -> void:
	var s := settings.duplicate(true)
	var d := default_data()
	credits = 0
	upgrades = d["upgrades"]
	best_depth = 0
	runs_completed = 0
	last_seed = 0
	settings = s
	save()
