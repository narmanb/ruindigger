extends Node
## Screen flow (title -> outpost -> mine -> results) and current-run state.

signal run_changed

const SCREENS := {
	"title": "res://src/ui/title_screen.gd",
	"outpost": "res://src/world/outpost.gd",
	"mine": "res://src/world/mine.gd",
	"results": "res://src/ui/results_screen.gd",
}

var current: Node = null
var current_name := ""
var contract: Dictionary = {}
var contract_offers: Array = []
var modifiers: Array = []          # ids chosen on the contract board for the next dive
var loadout: Dictionary = Balance.GADGET_DEFAULT.duplicate()   # gadgets packed at the supply locker
var run: Dictionary = {}
var last_result: Dictionary = {}
var _fade: ColorRect
var _fade_layer: CanvasLayer
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.02, 0.05, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade)
	roll_contracts()


func roll_contracts() -> void:
	contract_offers.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool: Array = Balance.CONTRACTS.duplicate()
	# Standard survey is always offered so new players have a baseline.
	var first: Dictionary = pool.pop_front()
	pool.shuffle()
	for c in [first, pool[0], pool[1]]:
		var d: Dictionary = c.duplicate()
		d["seed"] = rng.randi_range(1000, 999999)
		d["reward"] = int(Balance.RELIC_BONUS * float(d["bonus"]))
		contract_offers.append(d)
	contract = contract_offers[0]


func toggle_modifier(id: String) -> bool:
	if modifiers.has(id):
		modifiers.erase(id)
		run_changed.emit()
		return true
	if modifiers.size() >= Balance.MODIFIER_MAX or Balance.modifier(id).is_empty():
		return false
	modifiers.append(id)
	run_changed.emit()
	return true


## The contract with the chosen modifiers folded in, and their total bonus.
func modded_contract(base: Dictionary, mods: Array) -> Dictionary:
	var c := base.duplicate()
	var bonus := 0.0
	var dark := 1.0
	for id in mods:
		var m := Balance.modifier(String(id))
		for k in Balance.MODIFIER_KEYS:
			if m.has(k):
				c[k] = float(c.get(k, 1.0)) * float(m[k])
		dark = minf(dark, float(m.get("dark", 1.0)))
		bonus += float(m.get("bonus", 0.0))
	c["dark"] = dark
	c["mod_bonus"] = bonus
	return c


## Extra pay on ore credits from this run's modifiers.
func modifier_pay(cargo: Dictionary) -> int:
	var b := float(run.get("contract", {}).get("mod_bonus", 0.0))
	return int(round(cargo_value(cargo) * b))


func choose_contract(i: int) -> void:
	if i >= 0 and i < contract_offers.size():
		contract = contract_offers[i]
		run_changed.emit()


func goto(screen: String, instant: bool = false) -> void:
	if _busy:
		return
	_busy = true
	get_tree().paused = false
	if not instant and current != null:
		var tw := create_tween()
		tw.tween_property(_fade, "color:a", 1.0, 0.25)
		await tw.finished
	if current != null:
		current.queue_free()
		await get_tree().process_frame
	var script: GDScript = load(SCREENS[screen])
	current = script.new()
	current.name = screen.capitalize().replace(" ", "")
	current_name = screen
	get_tree().root.add_child(current)
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.35)
	_busy = false


func start_run(go: bool = true) -> void:
	# the two explosive slots: what was bought (plus the main slot's free
	# units) goes down with you; stock of other types waits at the outpost
	var slots: Array = Progress.slots.duplicate()
	var ammo: Array = [0, 0]
	for i in 2:
		var kind: String = slots[i]
		if kind != "":
			ammo[i] = Progress.packed(kind)
			Progress.explosives[kind] = 0
	Progress.stats["runs"] = int(Progress.stats.get("runs", 0)) + 1
	Progress.save_progress()
	run = {
		"seed": int(contract.get("seed", 1234)),
		"contract": modded_contract(contract, modifiers),
		"modifiers": modifiers.duplicate(),
		"slots": slots,           # explosive type per slot: [main, backup]
		"charges": ammo[0],       # units left in the main slot
		"charges2": ammo[1],      # units left in the backup slot
		"lures": Balance.LURES_PER_RUN,
		"shears": Balance.SHEARS_PER_RUN,
		"bolts": Balance.BOLTS_PER_RUN,
		"relics": [],
		"loadout": loadout.duplicate(),
		"gadget_cd": 0.0,
		"cargo": {},
		"finds": [],
		"banked": {},
		"relic": false,
		"max_depth": 0,
		"kills": 0,
		"time": 0.0,
		"ore_mined": 0,
		"scaffold": Balance.scaffold_capacity(Progress.level("scaffold")),
		"ladders_built": 0,
		"stage": "mine",          # "mine" (five zones) or "deep" (The First Civilization)
		"depth_offset": 0,        # cells already descended in earlier stages
		"deep_exit": false,
	}
	if go:
		goto("mine")


## Start a mission from the outpost's MISSIONS terminal: a fixed map with its
## own goal. It is a dive like any other (explosives, gadgets, hull, cargo),
## but it has no contract, no orders besides its goal, and no relic.
func start_mission(id: String) -> bool:
	var m := Balance.mission(id)
	if m.is_empty() or not Progress.mission_open(id):
		return false
	start_run(false)
	run["stage"] = "mission"
	run["mission"] = id
	run["seed"] = int(m["seed"])
	run["contract"] = {"id": "mission", "name": m["name"]}
	run["modifiers"] = []
	run["no_pressure"] = not bool(m.get("pressure", true))
	run["mission_fill"] = 0
	run["orders"] = [{"kind": "mission", "goal": m["goal"], "text": m["goal"], "need": int(round(float(m["target"]) * 100.0)),
		"have": 0, "done": false, "reward": int(m["reward"]) / (2 if Progress.mission_done(id) else 1)}]
	goto("mine")
	return true


func in_mission() -> bool:
	return run.get("stage", "mine") == "mission"


## Has this run's mission goal been met?
func mission_goal_met() -> bool:
	for o: Dictionary in run.get("orders", []):
		if String(o["kind"]) == "mission":
			return bool(o["done"])
	return false


## One-way descent into The First Civilization. The SAME run continues: cargo,
## relic, finds, charges, scaffold, hull and the contract all carry over.
func descend(hull_now: float, from_depth_cells: int) -> void:
	if run.get("stage", "mine") == "deep":
		return
	run["stage"] = "deep"
	run["hp"] = hull_now
	run["pressure"] = float(run.get("pressure", 0.0)) * Balance.PRESSURE_DESCENT_KEEP
	run["depth_offset"] = from_depth_cells
	run["max_depth"] = maxi(int(run.get("max_depth", 0)), from_depth_cells)
	goto("mine")


## Explosive type in a slot of this run (0 main, 1 backup); "" when empty.
func slot_kind(i: int) -> String:
	var s: Array = run.get("slots", Balance.EXPLOSIVE_DEFAULT)
	return String(s[i]) if i >= 0 and i < s.size() else ""


func slot_key(i: int) -> String:
	return "charges" if i == 0 else "charges2"


func slot_ammo(i: int) -> int:
	return int(run.get(slot_key(i), 0))


func has_explosive(kind: String) -> bool:
	return slot_kind(0) == kind or slot_kind(1) == kind


func has_relic(id: String) -> bool:
	return (run.get("relics", []) as Array).has(id)


## A relic id this run does not hold yet: `preferred` if it is free, else the
## next free one in the list. -1 when the run already holds every relic.
## Relics marked "deep" are only offered when `deep_ok` (The First Civilization).
func unowned_relic_id(preferred: int, deep_ok: bool = true) -> int:
	var n: int = Balance.RUN_RELICS.size()
	for k in n:
		var id := (preferred + k) % n
		var info: Dictionary = Balance.RUN_RELICS[id]
		if bool(info.get("deep", false)) and not deep_ok:
			continue
		if not has_relic(String(info["id"])):
			return id
	return -1


func in_deep() -> bool:
	return run.get("stage", "mine") == "deep"


func cargo_count() -> int:
	var n := 0
	for k in run.get("cargo", {}).keys():
		n += int(run["cargo"][k])
	return n


func cargo_value(cargo: Dictionary) -> int:
	var v := 0
	for k in cargo.keys():
		v += Balance.ore_value(int(k)) * int(cargo[k])
	return v


## Cheapest key in the rack, or -1 when empty.
func cheapest_cargo() -> int:
	var best := -1
	var bv := 1 << 30
	for k in run.get("cargo", {}).keys():
		if int(run["cargo"][k]) <= 0:
			continue
		var v := Balance.ore_value(int(k))
		if v < bv:
			bv = v
			best = int(k)
	return best


## Can this ore key go into a rack of `cap`? Yes if there is room, or if it is
## worth more than the cheapest thing carried (it will be swapped in).
func can_take(key: int, cap: int) -> bool:
	if cargo_count() < cap:
		return true
	var c := cheapest_cargo()
	return c >= 0 and Balance.ore_value(key) > Balance.ore_value(c)


func finds_value(finds: Array) -> int:
	var value := 0
	var seen: Dictionary = {}
	for id in finds:
		if typeof(id) == TYPE_INT and id >= 0 and id < Balance.KEEPSAKES.size() and not seen.has(id):
			seen[id] = true
			value += int(Balance.KEEPSAKES[id]["value"])
	return value


## Blood Bargain: extra pay on ore credits, scaled by the hull you were
## missing when you extracted.
func bargain_pay_for(ore_credits: int) -> int:
	if not has_relic("bargain"):
		return 0
	var missing := clampf(1.0 - float(run.get("hull_frac", 1.0)), 0.0, 1.0)
	return int(round(float(ore_credits) * missing * Balance.BARGAIN_MAX))


func end_run(extracted: bool, cause: String = "") -> void:
	var cargo: Dictionary = run.get("cargo", {}).duplicate()
	var credits := 0
	var relic_bonus := 0
	var finds: Array = run.get("finds", []).duplicate()
	var finds_bonus := finds_value(finds) if extracted else 0
	var deep: bool = run.get("stage", "mine") == "deep"
	var deep_bonus := Balance.DEEP_EXIT_BONUS if (extracted and deep and run.get("deep_exit", false)) else 0
	var orders: Array = []
	var orders_bonus := 0
	for o: Dictionary in run.get("orders", []):
		var met := Orders.satisfied(o, run)
		orders.append({"text": o.get("text", ""), "met": met, "reward": int(o.get("reward", 0))})
	var mod_pay := 0
	var bargain_pay := 0
	if extracted:
		orders_bonus = Orders.payout(run)
		credits = cargo_value(cargo)
		mod_pay = modifier_pay(cargo)
		bargain_pay = bargain_pay_for(credits)
		if run.get("relic", false):
			relic_bonus = int(contract.get("reward", Balance.RELIC_BONUS))
		Progress.stats["extractions"] = int(Progress.stats.get("extractions", 0)) + 1
		if run.get("relic", false):
			Progress.stats["relics"] = int(Progress.stats.get("relics", 0)) + 1
	else:
		Progress.stats["deaths"] = int(Progress.stats.get("deaths", 0)) + 1
	var depth_m := int(run.get("max_depth", 0) * Balance.METERS_PER_CELL)
	var mission_id := String(run.get("mission", ""))
	var mission_won := mission_id != "" and extracted and mission_goal_met()
	if mission_id == "":
		# a mission's map has its own depths: they do not count as how deep
		# you have been in the mine
		Progress.stats["best_depth"] = maxi(int(Progress.stats.get("best_depth", 0)), depth_m)
	var mission_first := Progress.complete_mission(mission_id) if mission_won else false
	Progress.add_credits(credits + relic_bonus + finds_bonus + deep_bonus + orders_bonus + mod_pay + bargain_pay)
	Progress.tutorial_done = true
	Progress.save_progress()
	last_result = {
		"extracted": extracted, "cause": cause, "cargo": cargo, "credits": credits,
		"relic": run.get("relic", false), "relic_bonus": relic_bonus, "depth": depth_m,
		"finds": finds, "finds_bonus": finds_bonus, "orders": orders, "orders_bonus": orders_bonus,
		"modifiers": run.get("modifiers", []).duplicate(), "mod_pay": mod_pay,
		"bargain": has_relic("bargain") and extracted, "bargain_pay": bargain_pay,
		"deep": deep, "deep_exit": extracted and deep and run.get("deep_exit", false), "deep_bonus": deep_bonus,
		"kills": run.get("kills", 0), "time": run.get("time", 0.0), "seed": run.get("seed", 0),
		"contract": String(run.get("contract", {}).get("name", contract.get("name", ""))) if mission_id != "" else contract.get("name", ""),
		"mission": mission_id, "mission_won": mission_won, "mission_first": mission_first,
	}
	roll_contracts()
	goto("results")
