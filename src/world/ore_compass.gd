class_name OreCompass
extends Node2D
## Greedy Lamp: small arrows in a ring around the digger, each pointing at
## ore that is not on screen. Lives in the glow layer so it reads in the dark.
## Only ore embedded in rock counts; the generator only places ore on rock
## that borders reachable space, so every arrow points at ore you can mine.

var mine: Node
var targets: Array = []        # [{dir: Vector2, color: Color, dist: float}]
var _scan_t := 0.0
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	var on: bool = Game.has_relic("greedy") and mine.player != null and not mine.player.dead
	visible = on
	if not on:
		targets.clear()
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = Balance.GREEDY_TICK
		scan()
	global_position = mine.player.global_position + Vector2(0, -8)
	queue_redraw()


## The world rect the camera shows right now.
func view_rect() -> Rect2:
	var cam: Camera2D = mine.camera
	var half: Vector2 = get_viewport_rect().size / cam.zoom * 0.5
	return Rect2(cam.get_screen_center_position() - half, half * 2.0)


## Find the nearest off-screen ore, at most GREEDY_ARROWS directions.
func scan() -> void:
	targets.clear()
	var g: TerrainGrid = mine.grid
	var pl_pos: Vector2 = mine.player.global_position
	var pc := g.world_to_cell(pl_pos)
	var seen := view_rect()
	var r := Balance.GREEDY_RADIUS
	var found: Array = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var c := pc + Vector2i(dx, dy)
			if not g.in_bounds(c.x, c.y):
				continue
			var o := g.get_ore(c.x, c.y)
			if o == 0 or not Cell.is_solid(g.get_mat(c.x, c.y)):
				continue
			var p := g.cell_center(c)
			if seen.has_point(p):
				continue
			found.append([pl_pos.distance_squared_to(p), p, o])
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var sep := deg_to_rad(Balance.GREEDY_SEP_DEG)
	for f: Array in found:
		if targets.size() >= Balance.GREEDY_ARROWS:
			break
		var dir: Vector2 = (f[1] - pl_pos).normalized()
		var close := false
		for t: Dictionary in targets:
			if absf((t["dir"] as Vector2).angle_to(dir)) < sep:
				close = true
				break
		if close:
			continue
		var value: float = float(Balance.ORE[int(f[2])]["value"]) if Balance.ORE.has(int(f[2])) else 6.0
		var col := Balance.ore_color(int(f[2]))
		col = col.lightened(clampf(value / 120.0, 0.0, 0.3))   # better ore glows brighter
		col.a = 0.95
		targets.append({"dir": dir, "color": col, "dist": sqrt(float(f[0])) / Balance.CELL, "pos": f[1]})


func _draw() -> void:
	var pulse := 0.85 + 0.15 * sin(_t * 4.0)
	for t: Dictionary in targets:
		var d: Vector2 = t["dir"]
		var col: Color = t["color"]
		col.a *= pulse
		var n := d.orthogonal()
		var base := d * Balance.GREEDY_RING
		var tip := base + d * 11.0
		var notch := base + d * 3.0
		# chevron: dark outline, ore-coloured fill, bright rim
		var outer := PackedVector2Array([tip + d * 1.5, base + n * 7.5 - d * 1.0, notch - d * 1.0, base - n * 7.5 - d * 1.0])
		var inner := PackedVector2Array([tip, base + n * 6.0, notch, base - n * 6.0])
		draw_colored_polygon(outer, Color(0, 0, 0, 0.75 * col.a))
		draw_colored_polygon(inner, col)
		draw_polyline(inner + PackedVector2Array([inner[0]]), col.lightened(0.55), 1.0)
