extends Node
## Persistent meta-progression (credits, upgrades, stats) in user://progress.json.
## Every field is validated on load; anything malformed falls back to defaults.

signal changed

const PATH := "user://progress.json"
const VERSION := 1
const TRACKS := ["drill", "heat", "cargo", "hull"]

var credits: int = 0
var upgrades: Dictionary = {"drill": 0, "heat": 0, "cargo": 0, "hull": 0}
var charges: int = 0          # purchased charges waiting for the next run
var stats: Dictionary = {}
var tutorial_done: bool = false
var path: String = PATH


func _ready() -> void:
	load_progress()


func default_stats() -> Dictionary:
	return {"runs": 0, "extractions": 0, "deaths": 0, "relics": 0, "best_depth": 0, "lifetime_credits": 0}


func reset() -> void:
	credits = 0
	upgrades = {"drill": 0, "heat": 0, "cargo": 0, "hull": 0}
	charges = 0
	stats = default_stats()
	tutorial_done = false


func level(track: String) -> int:
	return int(upgrades.get(track, 0))


func next_cost(track: String) -> int:
	var lv := level(track)
	var costs: Array = Balance.UPGRADES[track]["costs"]
	if lv >= costs.size():
		return -1
	return int(costs[lv])


func can_buy(track: String) -> bool:
	var c := next_cost(track)
	return c >= 0 and credits >= c


func buy(track: String) -> bool:
	if not can_buy(track):
		return false
	credits -= next_cost(track)
	upgrades[track] = level(track) + 1
	save_progress()
	changed.emit()
	return true


func buy_charge() -> bool:
	if credits < Balance.CHARGE_PRICE or charges + Balance.CHARGES_FREE >= Balance.CHARGES_MAX:
		return false
	credits -= Balance.CHARGE_PRICE
	charges += 1
	save_progress()
	changed.emit()
	return true


func add_credits(n: int) -> void:
	credits = maxi(0, credits + n)
	stats["lifetime_credits"] = int(stats.get("lifetime_credits", 0)) + maxi(n, 0)
	changed.emit()


func to_dict() -> Dictionary:
	return {"version": VERSION, "credits": credits, "upgrades": upgrades.duplicate(),
		"charges": charges, "stats": stats.duplicate(), "tutorial_done": tutorial_done}


func from_dict(d: Variant) -> void:
	reset()
	if typeof(d) != TYPE_DICTIONARY:
		return
	credits = _int(d.get("credits"), 0, 0, 9999999)
	charges = _int(d.get("charges"), 0, 0, Balance.CHARGES_MAX)
	tutorial_done = d.get("tutorial_done") == true
	var up: Variant = d.get("upgrades")
	if typeof(up) == TYPE_DICTIONARY:
		for t in TRACKS:
			var maxlv: int = Balance.UPGRADES[t]["costs"].size()
			upgrades[t] = _int(up.get(t), 0, 0, maxlv)
	var st: Variant = d.get("stats")
	if typeof(st) == TYPE_DICTIONARY:
		for k in stats.keys():
			stats[k] = _int(st.get(k), 0, 0, 999999999)


func _int(v: Variant, def: int, lo: int, hi: int) -> int:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var f := float(v)
		if is_nan(f) or is_inf(f):
			return def
		return clampi(int(f), lo, hi)
	return def


func save_progress() -> void:
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		push_warning("Progress: cannot write save")
		return
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	# atomic-ish replace so a crash mid-write never corrupts the real file
	var dir := DirAccess.open("user://")
	if dir:
		if FileAccess.file_exists(path):
			dir.remove(path.get_file())
		dir.rename((path + ".tmp").get_file(), path.get_file())


func load_progress() -> void:
	reset()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		push_warning("Progress: save file unreadable, using defaults")
		return
	from_dict(j.data)
