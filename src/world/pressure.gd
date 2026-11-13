class_name Pressure
extends Node
## The mine wakes up (S3 of the fun pass). A 0..100 meter that rises with time
## spent in deeper zones and with the noise you make, and eases off while you
## retreat to shallower ground. Each tier sets off telegraphed events near the
## player: tremors that bring a ceiling down, gas venting from the rock, and
## crawler swarms that come for the noise. Every event warns first.

var mine: Node
var value := 0.0
var tier := 0
var event_t := 0.0
var events := 0
var spawned: Array = []           # crawlers this system brought in
var rng := RandomNumberGenerator.new()
var _deepest_rank := 0


func _ready() -> void:
	rng.seed = int(Game.run.get("seed", 1)) ^ 0x70726573
	value = float(Game.run.get("pressure", 0.0))
	tier = _tier_of(value)
	event_t = Balance.PRESSURE_FIRST_EVENT


func _mult() -> float:
	return float(Game.run.get("contract", {}).get("pressure", 1.0))


func _tier_of(v: float) -> int:
	var t := 0
	for k in Balance.PRESSURE_TIERS.size():
		if v >= Balance.PRESSURE_TIERS[k]:
			t = k + 1
	return t


func zone() -> int:
	var pl: Player = mine.player
	if pl == null:
		return 0
	var c: Vector2i = mine.grid.world_to_cell(pl.global_position)
	return maxi(0, mine.grid.get_stratum(c.x, c.y))


## Drilling and blasts make the mine restless.
func on_noise(radius_cells: float) -> void:
	var k: float = Balance.PRESSURE_NOISE_MULT[zone()] * _mult()
	value += (Balance.PRESSURE_BLAST if radius_cells >= 14.0 else Balance.PRESSURE_DRILL) * k


func _physics_process(delta: float) -> void:
	var pl: Player = mine.player
	if pl == null or pl.dead or mine.ending:
		return
	var z := zone()
	var rank: int = Balance.PRESSURE_ZONE_RANK[z]
	_deepest_rank = maxi(_deepest_rank, rank)
	if rank < _deepest_rank:
		value -= Balance.PRESSURE_RETREAT * delta
	else:
		value += Balance.PRESSURE_RATE[z] * _mult() * delta
	value = clampf(value, 0.0, 100.0)
	Game.run["pressure"] = value
	var t := _tier_of(value)
	if t != tier:
		if t > tier and mine.hud:
			mine.hud.banner(Balance.PRESSURE_NAMES[t])
			mine.toast(Balance.PRESSURE_WARN[t])
			Audio.play("rumble", -2.0)
			mine.shake(0.25 + 0.1 * t)
			event_t = minf(event_t, Balance.PRESSURE_FIRST_EVENT)
		tier = t
	if tier == 0:
		return
	event_t -= delta
	if event_t <= 0.0:
		var base: float = Balance.PRESSURE_INTERVAL[tier - 1]
		event_t = base * rng.randf_range(0.75, 1.3)
		trigger_event()


## Pick and start one event. Returns its name ("" if nothing fit here).
func trigger_event(kind: String = "") -> String:
	var options: Array = ["tremor", "gas", "swarm"] if kind == "" else [kind]
	# shuffle on this system's own stream and take the first that fits
	for k in range(options.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp: String = options[k]
		options[k] = options[j]
		options[j] = tmp
	for o: String in options:
		var ok := false
		match o:
			"tremor": ok = _tremor()
			"gas": ok = _gas()
			"swarm": ok = _swarm()
		if ok:
			events += 1
			return o
	return ""


func _player_cell() -> Vector2i:
	return mine.grid.world_to_cell(mine.player.global_position)


## A ceiling near you loosens and comes down after a warning.
func _tremor() -> bool:
	var g: TerrainGrid = mine.grid
	var pc := _player_cell()
	var cells: Array[Vector2i] = []
	var want: int = Balance.PRESSURE_TREMOR_CELLS[tier - 1]
	var r := Balance.PRESSURE_EVENT_RADIUS
	for attempt in 220:
		if cells.size() >= want:
			break
		var c := pc + Vector2i(rng.randi_range(-r, r), rng.randi_range(-r, 2))
		if absi(c.x - pc.x) <= Balance.PRESSURE_TREMOR_SAFE and tier < 3:
			continue        # below the top tier, never straight overhead
		if not g.in_bounds(c.x, c.y) or g.get_mat(c.x, c.y) != Cell.SOFT or g.get_ore(c.x, c.y) != 0:
			continue
		if g.has_flag(c.x, c.y, Cell.F_PROTECTED) or g.is_solid(c.x, c.y + 1) or cells.has(c):
			continue
		if mine.collapse.pending.has(c):
			continue
		cells.append(c)
		# a short run of the same ceiling comes with it
		for dx in [-1, 1]:
			var n := Vector2i(c.x + dx, c.y)
			if cells.size() < want and g.get_mat(n.x, n.y) == Cell.SOFT and g.get_ore(n.x, n.y) == 0 and not g.is_solid(n.x, n.y + 1) \
					and not g.has_flag(n.x, n.y, Cell.F_PROTECTED) and not cells.has(n):
				cells.append(n)
	if cells.is_empty():
		return false
	for c in cells:
		g.set_mat(c.x, c.y, Cell.LOOSE)
		mine.collapse.pending[c] = Balance.PRESSURE_TREMOR_WARN * rng.randf_range(0.9, 1.3)
	Audio.play("rumble", 0.0)
	mine.shake(0.5)
	mine.toast("TREMOR - the ceiling is coming down!")
	return true


## Gas bleeds out of the rock somewhere near you.
func _gas() -> bool:
	var g: TerrainGrid = mine.grid
	var pc := _player_cell()
	for attempt in 120:
		var c := pc + Vector2i(rng.randi_range(-9, 9), rng.randi_range(-5, 3))
		var d := absi(c.x - pc.x) + absi(c.y - pc.y)
		if d < 4 or not g.in_bounds(c.x, c.y) or g.is_solid(c.x, c.y) or g.get_water(c.x, c.y) > 0:
			continue
		# it seeps from a wall or floor
		if not (g.is_solid(c.x, c.y + 1) or g.is_solid(c.x - 1, c.y) or g.is_solid(c.x + 1, c.y)):
			continue
		mine.gas.vent_at(g.cell_center(c), 2 + tier)
		return true
	return false


## Crawlers come for the noise, from outside the screen.
func _swarm() -> bool:
	var alive := 0
	for e in spawned:
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			alive += 1
	if alive >= Balance.PRESSURE_SWARM_MAX:
		return false
	var g: TerrainGrid = mine.grid
	var pc := _player_cell()
	var want: int = mini(Balance.PRESSURE_SWARM_SIZE[tier - 1], Balance.PRESSURE_SWARM_MAX - alive)
	var made := 0
	for attempt in 400:
		if made >= want:
			break
		var c := pc + Vector2i(rng.randi_range(-24, 24), rng.randi_range(-12, 12))
		if Vector2(c - pc).length() < 14.0 or not g.in_bounds(c.x, c.y) or g.is_solid(c.x, c.y) or not g.is_solid(c.x, c.y + 1):
			continue
		if g.get_water(c.x, c.y) > 0 or g.get_lava(c.x, c.y) > 0 or g.get_stratum(c.x, c.y) < 0:
			continue
		var cr: Node = mine.spawn_crawler(c)
		cr.hear(mine.player.global_position, 60.0)
		spawned.append(cr)
		made += 1
	if made == 0:
		return false
	Audio.play("crawler_hit", -4.0)
	mine.toast("SKITTERING IN THE WALLS - something heard you")
	return true
