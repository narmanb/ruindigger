class_name Breaker
extends Crawler
## Breaker: a heavier burrower that goes for the ground instead of you. It
## moves and hunts like a crawler, but once it can see you under a roof it
## stops, braces and gnaws at that roof: dust rains above you for
## BREAKER_GNAW seconds, then the roof drops (after a last short warning).
## While it gnaws it is planted and takes BREAKER_GNAW_MULT damage. Bolted
## rock (anchor bolts) cannot be gnawed. Stun it and it loses its grip.

var gnawing := false
var gnaw_t := 0.0
var gnaw_cd := 2.5
var gnaw_cells: Array[Vector2i] = []
var gnaws := 0
var _dust_t := 0.0
static var _warned := false


func _ready() -> void:
	super._ready()
	hp = Balance.BREAKER_HP
	max_hp = hp
	spr.modulate = Color(1.0, 0.72, 0.5)
	spr.scale = Vector2(1.25, 1.25)


func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	gnaw_cd = maxf(0.0, gnaw_cd - delta)
	if gnawing:
		_gnaw_step(delta)
		return
	super._physics_process(delta)
	if state == S.CHASE and gnaw_cd <= 0.0 and _arrived() and not asleep:
		try_gnaw()


## Start gnawing the roof over the digger if one is in reach. Returns true
## if it started.
func try_gnaw() -> bool:
	var pl: Player = mine.player
	if pl == null or pl.dead or gnawing:
		return false
	var pc := grid.world_to_cell(pl.global_position)
	if absi(pc.x - cell.x) > Balance.BREAKER_RANGE or absi(pc.y - cell.y) > Balance.BREAKER_RANGE:
		return false
	if not _sees_player():
		return false
	# the roof over the digger: the first solid row above its head
	var roof := -1
	for y in range(pc.y - 2, pc.y - 8, -1):
		if grid.is_solid(pc.x, y):
			roof = y
			break
	if roof < 0:
		return false
	var cells: Array[Vector2i] = []
	for dx in range(-1, 2):
		var c := Vector2i(pc.x + dx, roof)
		if grid.is_solid(c.x, c.y) and mine.breakable_support(c):
			cells.append(c)
	if cells.size() < 2:
		return false
	gnawing = true
	gnaw_t = 0.0
	gnaw_cells = cells
	path.clear()
	windup = 0.0
	Audio.play_at("crawler_alert", global_position, 0.0, 0.1, 0.0)
	if not _warned:
		_warned = true
		mine.toast("A BREAKER IS GNAWING THE ROOF - move, bolt it, or hit it now!")
	return true


func _gnaw_step(delta: float) -> void:
	gnaw_t += delta
	anim_t += delta * 3.0
	flash = maxf(0.0, flash - delta * 5.0)
	_dust_t -= delta
	if _dust_t <= 0.0:
		_dust_t = 0.12
		for c in gnaw_cells:
			if randf() < 0.6:
				mine.fx.dust(grid.cell_center(c) + Vector2(randf_range(-6, 6), 8), Color(0.78, 0.68, 0.52), 3, Fx.ESSENTIAL)
		mine.fx.chips(global_position + Vector2(facing * 10, -4), Vector2(facing, -0.5), Color(0.6, 0.55, 0.5))
		if randf() < 0.3:
			Audio.play_at("hit_soft", global_position, -6.0, 0.2, 0.05)
	# the bolted roof cannot be gnawed: give up on cells that got anchored
	for c in gnaw_cells.duplicate():
		if not mine.breakable_support(c) or not grid.is_solid(c.x, c.y):
			gnaw_cells.erase(c)
	if gnaw_cells.is_empty():
		_stop()
		return
	if gnaw_t >= Balance.BREAKER_GNAW:
		_drop()
	_visual()
	queue_redraw()


func _drop() -> void:
	for c in gnaw_cells:
		if grid.is_solid(c.x, c.y) and mine.breakable_support(c):
			grid.set_mat(c.x, c.y, Cell.LOOSE)
			mine.collapse.pending[c] = Balance.BREAKER_DROP_WARN
	if not gnaw_cells.is_empty():
		var mid: Vector2i = gnaw_cells[gnaw_cells.size() / 2]
		mine.drop_unsupported(Vector2i(mid.x, mid.y - 1), Vector2i(2, 3), Balance.BREAKER_DROP_WARN + 0.3)
		Audio.play_at("rumble", grid.cell_center(mid), 0.0, 0.1, 0.2)
		mine.shake(0.3)
	gnaws += 1
	_stop()


func _stop() -> void:
	gnawing = false
	gnaw_cd = Balance.BREAKER_COOLDOWN
	gnaw_cells.clear()
	queue_redraw()


func hit(dmg: float, from: Vector2, knock: bool = true) -> void:
	if gnawing:
		dmg *= Balance.BREAKER_GNAW_MULT
	super.hit(dmg, from, knock)


func stun(t: float) -> void:
	if gnawing:
		_stop()
	super.stun(t)


func _draw() -> void:
	super._draw()
	# a stubby drill horn on its snout; it spins while it gnaws
	var f := float(facing)
	var base := Vector2(f * 9.0, -2.0)
	var tip := base + Vector2(f * 7.0, -3.0)
	draw_colored_polygon(PackedVector2Array([base + Vector2(0, -3), tip, base + Vector2(0, 3)]), Color("8d8f99"))
	if gnawing:
		var k := int(gnaw_t * 20.0) % 2
		draw_line(base + Vector2(f * 2.0, -2 + k * 2), tip, Color("d8dce6"), 1.0)
		var a := clampf(gnaw_t / Balance.BREAKER_GNAW, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 13.0, -PI * 0.5, -PI * 0.5 + TAU * a, 20, Color(1.0, 0.55, 0.25, 0.8), 1.5)
