extends Node
## Persistent meta-progression (credits, upgrades, stats) in user://progress.json.
## Every field is validated on load; anything malformed falls back to defaults.

signal changed

const PATH := "user://progress.json"
const VERSION := 2
const TRACKS := ["drill", "heat", "cargo", "hull", "scaffold"]

var credits: int = 0
var upgrades: Dictionary = {"drill": 0, "heat": 0, "cargo": 0, "hull": 0}
## Explosives bought and waiting for the next run, by type. A dive takes what
## its two slots use; the rest stays here.
var explosives: Dictionary = {}
var demo: Dictionary = {}          # Demolitions upgrade levels: capacity, power, radius
var slots: Array = Balance.EXPLOSIVE_DEFAULT.duplicate()   # [main, backup]; "" = empty
## Demo charges waiting for the next run (kept as a shortcut to explosives).
var charges: int:
	get:
		return int(explosives.get("charge", 0))
	set(v):
		explosives["charge"] = v
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
	explosives = {}
	demo = {}
	slots = Balance.EXPLOSIVE_DEFAULT.duplicate()
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


# --- explosives (Demolitions counter) ---------------------------------------
func demo_level(track: String) -> int:
	return int(demo.get(track, 0))


func demo_cost(track: String) -> int:
	var costs: Array = Balance.DEMO_UPGRADES[track]["costs"]
	var lv := demo_level(track)
	return int(costs[lv]) if lv < costs.size() else -1


func buy_demo(track: String) -> bool:
	var c := demo_cost(track)
	if c < 0 or credits < c:
		return false
	credits -= c
	demo[track] = demo_level(track) + 1
	save_progress()
	changed.emit()
	return true


## Most of a type you can hold.
func carry(kind: String) -> int:
	return Balance.explosive_carry(kind, demo_level("capacity"))


## Units of a type the next dive gets for free (the main slot only).
func free_units(kind: String) -> int:
	if kind == "" or slots[0] != kind:
		return 0
	return int(Balance.EXPLOSIVES[kind]["free"])


func stock(kind: String) -> int:
	return int(explosives.get(kind, 0))


## What a dive would start with for a type, if it is in a slot.
func packed(kind: String) -> int:
	return mini(carry(kind), stock(kind) + free_units(kind))


func can_buy_explosive(kind: String) -> bool:
	return Balance.EXPLOSIVES.has(kind) and credits >= int(Balance.EXPLOSIVES[kind]["price"]) and stock(kind) + free_units(kind) < carry(kind)


func buy_explosive(kind: String) -> bool:
	if not can_buy_explosive(kind):
		return false
	credits -= int(Balance.EXPLOSIVES[kind]["price"])
	explosives[kind] = stock(kind) + 1
	save_progress()
	changed.emit()
	return true


func buy_charge() -> bool:
	return buy_explosive("charge")


## Put a type in a slot (0 main, 1 backup; "" empties the backup). A type can
## only sit in one slot: picking the other slot's type swaps the two.
func set_slot(i: int, kind: String) -> bool:
	if i < 0 or i > 1 or (kind != "" and not Balance.EXPLOSIVES.has(kind)) or (i == 0 and kind == ""):
		return false
	var other := 1 - i
	if kind != "" and slots[other] == kind:
		slots[other] = slots[i]
	slots[i] = kind
	save_progress()
	changed.emit()
	return true


func charges_max() -> int:
	return carry("charge")


func add_credits(n: int) -> void:
	credits = maxi(0, credits + n)
	stats["lifetime_credits"] = int(stats.get("lifetime_credits", 0)) + maxi(n, 0)
	changed.emit()


func to_dict() -> Dictionary:
	return {"version": VERSION, "credits": credits, "upgrades": upgrades.duplicate(),
		"explosives": explosives.duplicate(), "demo": demo.duplicate(), "slots": slots.duplicate(),
		"stats": stats.duplicate(), "tutorial_done": tutorial_done}


func from_dict(d: Variant) -> void:
	reset()
	if typeof(d) != TYPE_DICTIONARY:
		return
	credits = _int(d.get("credits"), 0, 0, 9999999)
	tutorial_done = d.get("tutorial_done") == true
	var up: Variant = d.get("upgrades")
	if typeof(up) == TYPE_DICTIONARY:
		for t in TRACKS:
			var maxlv: int = Balance.UPGRADES[t]["costs"].size()
			upgrades[t] = _int(up.get(t), 0, 0, maxlv)
	var dm: Variant = d.get("demo")
	if typeof(dm) == TYPE_DICTIONARY:
		for t in Balance.DEMO_TRACKS:
			demo[t] = _int(dm.get(t), 0, 0, (Balance.DEMO_UPGRADES[t]["costs"] as Array).size())
	var sl: Variant = d.get("slots")
	if typeof(sl) == TYPE_ARRAY and sl.size() == 2 and typeof(sl[0]) == TYPE_STRING and typeof(sl[1]) == TYPE_STRING \
			and Balance.EXPLOSIVES.has(sl[0]) and (sl[1] == "" or Balance.EXPLOSIVES.has(sl[1])) and sl[0] != sl[1]:
		slots = [String(sl[0]), String(sl[1])]
	# saves from before the Demolitions counter (version 1): the Charge Rack
	# becomes BIGGER RACK, packed charges carry over, and the retired STICKY
	# CHARGES upgrade is paid back in credits
	if _int(d.get("version"), 1, 1, 99) < 2:
		if typeof(up) == TYPE_DICTIONARY:
			demo["capacity"] = _int(up.get("charge_rack"), 0, 0, (Balance.DEMO_UPGRADES["capacity"]["costs"] as Array).size())
			if _int(up.get("sticky"), 0, 0, 1) > 0:
				credits += Balance.STICKY_REFUND
		explosives["charge"] = _int(d.get("charges"), 0, 0, carry("charge"))
	var ex: Variant = d.get("explosives")
	if typeof(ex) == TYPE_DICTIONARY:
		for kind: String in Balance.EXPLOSIVES:
			if ex.has(kind):
				explosives[kind] = _int(ex.get(kind), 0, 0, carry(kind))
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
