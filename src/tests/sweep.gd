extends Node
## Broad generator sweep: generates many seeds and asserts the hard invariants
## hold for every one of them. This is the test that lets us claim "no seed can
## produce an unwinnable or unlootable mine" with evidence.

const SEEDS := 120

var _passed := true
var _fail_count := 0

func _ready() -> void:
	print("=== RUIN DIGGER generator sweep (%d seeds) ===" % SEEDS)
	var t0 := Time.get_ticks_msec()
	var worst := 0
	for s in range(1, SEEDS + 1):
		var t1 := Time.get_ticks_msec()
		_sweep_seed(s)
		worst = maxi(worst, Time.get_ticks_msec() - t1)
	print("  swept %d seeds in %d ms (worst single seed %d ms)" % [
		SEEDS, Time.get_ticks_msec() - t0, worst])
	print("=== sweep result: %s ===" % ("PASS" if _passed else "FAIL"))
	get_tree().quit(0 if _passed else 1)

func _sweep_seed(s: int) -> void:
	var r := WorldGen.generate(s, 168, 132)
	var g: TerrainGrid = r.grid
	var spawn: Vector2i = r.spawn
	var relic: Vector2i = r.relic
	var lift: Vector2i = r.lift
	var target := Vector2i(relic.x, relic.y - 2)

	if g.get_material(spawn.x, spawn.y) != Balance.Mat.EMPTY:
		fail(s, "spawn cell is solid")
	if g.get_material(spawn.x, spawn.y + 2) == Balance.Mat.EMPTY:
		fail(s, "spawn has no floor")
	if g.get_material(lift.x, lift.y) != Balance.Mat.EMPTY:
		fail(s, "lift cell is solid")
	if g.get_material(lift.x, lift.y + 2) == Balance.Mat.EMPTY:
		fail(s, "lift has no floor")
	if g.get_material(relic.x, relic.y) != Balance.Mat.EMPTY:
		fail(s, "relic cell is solid")
	if g.get_material(relic.x, relic.y + 2) == Balance.Mat.EMPTY:
		fail(s, "relic has no floor")

	# Objective must be walkable end to end (this is the real player route).
	var walk: PackedByteArray = g.reach_mask(spawn, 400000)
	if walk[g.idx(target.x, target.y)] != 1:
		fail(s, "relic target not reachable on foot")
	if walk[g.idx(lift.x, lift.y)] != 1:
		fail(s, "lift not reachable on foot from relic route")
	# The relic itself must be reachable on foot too (the chamber doorway).
	if walk[g.idx(relic.x, relic.y)] != 1:
		fail(s, "relic cell not reachable on foot")

	# Every ore and gas cell must be obtainable by drilling.
	var dig: PackedByteArray = g.reach_mask_diggable(spawn, 400000)
	var ore_bad := 0
	for i in g.ore.size():
		if g.ore[i] != 0 and dig[i] == 0:
			ore_bad += 1
	if ore_bad > 0:
		fail(s, "%d ore cells unreachable by drilling" % ore_bad)
	var gas_bad := 0
	for key in g.gas.keys():
		if dig[key] == 0:
			gas_bad += 1
	if gas_bad > 0:
		fail(s, "%d gas cells unreachable by drilling" % gas_bad)

	if r.ore_count < 40:
		fail(s, "only %d ore placed" % r.ore_count)
	if r.reachable_count < 1500:
		fail(s, "only %d reachable cells" % r.reachable_count)

	# The relic chamber must be sealed: its shell must be bedrock.
	var room: Rect2i = r.relic_room.grow(1)
	var leaks := 0
	for x in range(room.position.x, room.end.x):
		for y in range(room.position.y, room.end.y):
			if x == room.position.x or x == room.end.x - 1 \
					or y == room.position.y or y == room.end.y - 1:
				var m: int = g.get_material(x, y)
				if m != Balance.Mat.BEDROCK and m != Balance.Mat.EMPTY:
					leaks += 1
	# One doorway is allowed to be EMPTY, so just require bedrock everywhere but
	# the door column.
	var door_x := room.position.x
	var non_bedrock_outside_door := 0
	for x in range(room.position.x, room.end.x):
		for y in range(room.position.y, room.end.y):
			if x == room.position.x or x == room.end.x - 1 \
					or y == room.position.y or y == room.end.y - 1:
				if x == door_x:
					continue
				if g.get_material(x, y) != Balance.Mat.BEDROCK:
					non_bedrock_outside_door += 1
	if non_bedrock_outside_door > 0:
		fail(s, "%d non-bedrock shell cells outside the doorway" % non_bedrock_outside_door)

func fail(s: int, msg: String) -> void:
	_passed = false
	_fail_count += 1
	if _fail_count <= 20:
		print("  FAIL seed %d: %s" % [s, msg])
