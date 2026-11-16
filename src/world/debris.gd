class_name Debris
extends Node2D
## Three tiers: Mine already owns pooled dust/chips; this node draws lightweight
## fragments in one batch and owns a bounded set of actual physical props.
## Fragments never become grid solids and never pay ore or spawn collapse rubble.

var mine: Node
var grid: TerrainGrid
var water: WaterSim
var fragments: Array = []
var props: Array[WaterProp] = []
var rng := RandomNumberGenerator.new()
var spawned_fragments := 0
var spawned_props := 0


func setup(g: TerrainGrid, sim: WaterSim, seed_value: int) -> void:
	grid = g
	water = sim
	rng.seed = seed_value ^ 0x57415445


func _prune() -> void:
	for i in range(props.size() - 1, -1, -1):
		if not is_instance_valid(props[i]) or props[i].is_queued_for_deletion():
			props.remove_at(i)


func _clear_position(pos: Vector2, half: Vector2) -> bool:
	for oy in [-half.y, half.y]:
		for ox in [-half.x, half.x]:
			if grid.solid_at(pos + Vector2(ox, oy)):
				return false
	if mine and mine.get("player") != null:
		var pl: Player = mine.player
		if Rect2(pl.global_position - Player.HALF, Player.HALF * 2.0).grow(half.length()).has_point(pos):
			return false
	if mine:
		for e in mine.enemies:
			if is_instance_valid(e) and e.hit_rect().grow(half.length()).has_point(pos):
				return false
	return true


func spawn_prop(kind: String, pos: Vector2) -> WaterProp:
	_prune()
	if props.size() >= Balance.DEBRIS_PROP_CAP:
		return null
	var spec: Dictionary = Balance.WATER_PROPS.get(kind, Balance.WATER_PROPS.stone)
	if not _clear_position(pos, spec.half):
		return null
	for other in props:
		if other.position.distance_to(pos) < other.half.length() + Vector2(spec.half).length():
			return null
	var prop := WaterProp.new()
	prop.grid = grid
	prop.water = water
	prop.mine = mine
	prop.configure(kind)
	prop.position = pos
	add_child(prop)
	props.append(prop)
	spawned_props += 1
	return prop


func on_broken(c: Vector2i, material: int, source: String) -> void:
	if source not in ["drill", "blast", "erosion"] or not Balance.DEBRIS_CHANCE.has(material):
		return
	var chance: float = Balance.DEBRIS_CHANCE[material]
	if rng.randf() >= chance:
		return
	var pos := grid.cell_center(c)
	if fragments.size() < Balance.DEBRIS_FRAGMENT_CAP and _clear_position(pos, Vector2(2, 2)):
		fragments.append({"p": pos, "v": Vector2(rng.randf_range(-Balance.DEBRIS_SCATTER, Balance.DEBRIS_SCATTER), -Balance.DEBRIS_HOP),
			"color": Cell.debris_color(material, grid.get_stratum(c.x, c.y)), "age": 0.0,
			"drag": Balance.DEBRIS_LIGHT_DRAG if material in [Cell.SOFT, Cell.LOOSE] else Balance.DEBRIS_STONE_DRAG,
			"size": rng.randf_range(1.5, 3.0)})
		spawned_fragments += 1
	if material in [Cell.HARD, Cell.CRACKED, Cell.ALLOY] and rng.randf() < Balance.DEBRIS_LARGE_CHANCE:
		var prop := spawn_prop("scrap" if material == Cell.ALLOY else "stone", pos)
		if prop:
			prop.linear_velocity = Vector2(rng.randf_range(-Balance.DEBRIS_SCATTER, Balance.DEBRIS_SCATTER), -Balance.DEBRIS_HOP)


func blast(pos: Vector2, radius: float) -> void:
	_prune()
	for prop in props:
		var offset := prop.global_position - pos
		if offset.length() < radius and grid.line_clear(pos, prop.global_position):
			var direction := offset.normalized() if offset.length() > 0.1 else Vector2.UP
			prop.sleeping = false
			# Velocity change is mass-dependent, unlike a cosmetic blast animation.
			prop.linear_velocity += direction * Balance.PROP_BLAST_IMPULSE * (1.0 - offset.length() / radius) / prop.mass
	for f in fragments:
		var offset: Vector2 = f.p - pos
		if offset.length() < radius and grid.line_clear(pos, f.p):
			f.v += offset.normalized() * Balance.PROP_BLAST_IMPULSE


func drill_rect(rect: Rect2, amount: float) -> void:
	_prune()
	for prop in props:
		if rect.intersects(Rect2(prop.position - prop.half, prop.half * 2.0)):
			prop.damage(amount)


func _physics_process(delta: float) -> void:
	if grid == null:
		return
	_prune()
	var had_fragments := not fragments.is_empty()
	for i in range(fragments.size() - 1, -1, -1):
		var f: Dictionary = fragments[i]
		f.age += delta
		if f.age > Balance.DEBRIS_LIFETIME:
			fragments.remove_at(i)
			continue
		var p: Vector2 = f.p
		var flow := water.sample_flow(p)
		var wet := water.immersion(p, Vector2(1, 1))
		var v: Vector2 = f.v
		v.y += Balance.GRAVITY * (Balance.DEBRIS_WET_GRAVITY if wet > 0 else 1.0) * delta
		v = v.move_toward(flow, float(f.drag) * maxf(wet, minf(1.0, flow.length() / Balance.WATER_FLOW_MAX)) * delta)
		v = v.limit_length(Balance.PROP_MAX_SPEED)
		var steps := maxi(1, ceili(v.length() * delta / Balance.WATER_DROP_SWEEP))
		for k in steps:
			var np := p + v * delta / steps
			if not grid.solid_at(Vector2(np.x, p.y)):
				p.x = np.x
			else:
				v.x *= -Balance.DEBRIS_BOUNCE
			if not grid.solid_at(Vector2(p.x, np.y + float(f.size))):
				p.y = np.y
			else:
				v.y = 0.0
				v.x = move_toward(v.x, 0.0, Balance.DEBRIS_FRICTION * delta / steps)
		f.p = p
		f.v = v
	if had_fragments:
		queue_redraw()


func _draw() -> void:
	for f in fragments:
		var color: Color = f.color
		color.a *= clampf((Balance.DEBRIS_LIFETIME - float(f.age)) / Balance.DEBRIS_FADE, 0.0, 1.0)
		var p: Vector2 = f.p
		var size: float = f.size
		draw_rect(Rect2(p - Vector2(size, size), Vector2(size * 2, size)), color)
