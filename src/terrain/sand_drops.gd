class_name SandDrops
extends Node2D
## Flying dirt grains. Drilled sediment, fallen rubble and blasts throw a few
## grains that fly, bounce off walls, slow in water and land where they land;
## each one then adds its sand to the cell it came to rest in (SandSim), so
## piles grow from what actually fell. Bounded: beyond SAND_GRAINS_MAX, new
## sand is placed straight away instead.

var sim: SandSim
var grid: TerrainGrid
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var amt := PackedInt32Array()
var life := PackedFloat32Array()
var tint := PackedColorArray()
var lost := 0                    # px of sand that could not land anywhere
var landed := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 2
	rng.seed = 0x67726e73


func in_flight() -> int:
	var t := 0
	for a in amt:
		t += a
	return t


## Throw `total` px of sand from `origin` as `n` grains.
func spray(origin: Vector2, total: int, n: int, speed: float, up: float, color: Color) -> void:
	if total <= 0:
		return
	n = clampi(n, 1, total)
	if pos.size() + n > Balance.SAND_GRAINS_MAX:
		var c := grid.world_to_cell(origin)
		lost += total - sim.add(c, total)
		return
	var each := total / n
	var extra := total - each * n
	for k in n:
		pos.append(origin + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)))
		vel.append(Vector2(rng.randf_range(-1.0, 1.0) * speed, -rng.randf_range(0.2, 1.0) * speed * up))
		amt.append(each + (1 if k < extra else 0))
		life.append(0.0)
		tint.append(color.lightened(rng.randf_range(-0.12, 0.18)))


func _solid(p: Vector2) -> bool:
	var c := grid.world_to_cell(p)
	if not grid.in_bounds(c.x, c.y):
		return true
	if grid.is_solid(c.x, c.y):
		return true
	# the settled sand surface counts as ground too
	var h := grid.get_sand(c.x, c.y)
	return h > 0 and p.y >= (c.y + 1) * Balance.CELL - h


func _physics_process(delta: float) -> void:
	if pos.is_empty():
		return
	for i in range(pos.size() - 1, -1, -1):
		var p := pos[i]
		var v := vel[i]
		life[i] += delta
		var c := grid.world_to_cell(p)
		if grid.get_water(c.x, c.y) >= Balance.WATER_MAX / 2:
			v *= 0.86                       # water slows it to a drift
			v.y = minf(v.y + 120.0 * delta, 40.0)
		else:
			v.y = minf(v.y + 700.0 * delta, 360.0)
		var np := p + v * delta
		var land := false
		if _solid(np):
			if not _solid(Vector2(np.x, p.y)):
				land = true                 # hit ground or a pile: settle here
			else:
				v.x = -v.x * 0.35           # hit a wall: bounce back
				np = Vector2(p.x, np.y)
				if _solid(np):
					land = true
		if land or life[i] > 3.0:
			var lc := grid.world_to_cell(p)
			var put := sim.add(lc, amt[i])
			if put < amt[i]:
				put += sim.add(Vector2i(lc.x, lc.y - 1), amt[i] - put)
			lost += amt[i] - put
			landed += 1
			_remove(i)
			continue
		pos[i] = np
		vel[i] = v
	queue_redraw()


func _remove(i: int) -> void:
	pos.remove_at(i)
	vel.remove_at(i)
	amt.remove_at(i)
	life.remove_at(i)
	tint.remove_at(i)


func _draw() -> void:
	for i in pos.size():
		var p := pos[i].round()
		var s := 2.0 if amt[i] >= 3 else 1.0
		draw_rect(Rect2(p, Vector2(s, s)), tint[i])
		if s > 1.0:
			draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 1)), tint[i].darkened(0.3))
