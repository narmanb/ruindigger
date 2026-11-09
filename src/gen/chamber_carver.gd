class_name ChamberCarver
extends RefCounted
## Shape language for generated spaces. Each archetype carves a recognisable
## silhouette into the grid and reports traversal anchors:
##   hall       wide cavern/sediment hall: uneven ceiling, wall shelves, floor steps
##   terraces   stepped shelves (slumped sediment / spore terraces), optional
##              perched basin on the top step
##   fissure    tall narrow crack with jagged walls, ledges, a rope ladder, a bridge
##   cathedral  monumental chamber: flat floor, sunken lake basin, stalactites,
##              stalagmites and high wall galleries
##   works      abandoned excavation: timbered tunnel, rail remains, a slumped
##              rubble section
##   ruin       angular alloy architecture in several arrangements (hall, twin
##              rooms with a broken gallery, stacked rooms) with geological
##              intrusions breaking the shell
## A chamber dictionary: {id, arch, variant, rect, stratum, entry, exit, backbone,
## basin: Array[Vector2i], sentries: Array}

var gen: MineGenerator
var g: TerrainGrid
var rng: RandomNumberGenerator


func _init(generator: MineGenerator, r: RandomNumberGenerator) -> void:
	gen = generator
	g = generator.g
	rng = r


# ---------------------------------------------------------------------------
# primitives
func air(x: int, y: int) -> void:
	if not gen.writable(x, y):
		return
	if g.get_mat(x, y) != Cell.LADDER and g.get_mat(x, y) != Cell.PLATFORM:
		g.put(x, y, Cell.AIR)


func solid(x: int, y: int, m: int, ore_id: int = 0) -> void:
	if not gen.writable(x, y) or gen.reserved.has(Vector2i(x, y)):
		return
	g.put(x, y, m, ore_id)


func rock_for(x: int, y: int) -> int:
	return Cell.HARD if g.get_stratum(x, y) == 2 else Cell.SOFT


## Organic tunnel: Catmull-Rom spline through jittered control points with a
## varying radius. Never touches reserved/supporting/protected cells.
func tunnel(a: Vector2, b: Vector2, r_min: float = 1.3, r_max: float = 2.0, wobble: float = 0.3) -> Array[Vector2i]:
	var carved: Array[Vector2i] = []
	var length := a.distance_to(b)
	if length < 1.0:
		return carved
	var perp := (b - a).orthogonal().normalized()
	var p1 := a.lerp(b, 0.33) + perp * rng.randf_range(-wobble, wobble) * length
	var p2 := a.lerp(b, 0.66) + perp * rng.randf_range(-wobble, wobble) * length
	var pts := [a + (a - p1) * 0.2, a, p1, p2, b, b + (b - p2) * 0.2]
	var phase := rng.randf() * TAU
	var steps := int(length * 2.5) + 4
	for seg in range(1, 4):
		for i in steps / 3 + 1:
			var t := float(i) / float(steps / 3)
			var p := _catmull(pts[seg - 1], pts[seg], pts[seg + 1], pts[seg + 2], t)
			var rr := lerpf(r_min, r_max, 0.5 + 0.5 * sin(phase + (seg + t) * 2.1))
			for yy in range(int(floor(p.y - rr * 1.15)), int(ceil(p.y + rr * 1.15)) + 1):
				for xx in range(int(floor(p.x - rr)), int(ceil(p.x + rr)) + 1):
					var dx := (xx + 0.5 - p.x) / rr
					var dy := (yy + 0.5 - p.y) / (rr * 1.15)
					if dx * dx + dy * dy <= 1.0 and gen.tunnel_ok(xx, yy):
						if g.is_solid(xx, yy):
							g.put(xx, yy, Cell.AIR)
							carved.append(Vector2i(xx, yy))
	return carved


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# ---------------------------------------------------------------------------
func carve(c: Dictionary) -> void:
	match c["arch"]:
		"hall":
			_hall(c)
		"terraces":
			_terraces(c)
		"fissure":
			_fissure(c)
		"cathedral":
			_cathedral(c)
		"works":
			_works(c)
		"ruin":
			_ruin(c)
	c["basin"] = c.get("basin", [])


func _floor_row(r: Rect2i, y: int, mat: int) -> void:
	for x in range(r.position.x - 1, r.end.x + 1):
		if not g.is_solid(x, y):
			solid(x, y, mat)


func _hall(c: Dictionary) -> void:
	var r: Rect2i = c["rect"]
	var fy := r.end.y - 1                 # feet row; floor at fy + 1
	var phase := rng.randf() * TAU
	var rough := 1.5 if c["stratum"] == 0 else 2.6
	for x in range(r.position.x, r.end.x):
		var u := float(x - r.position.x) / float(r.size.x - 1)
		var taper := int(round(3.0 * pow(absf(u - 0.5) * 2.0, 4.0)))
		var top := r.position.y + int(round(rough * (0.5 + 0.5 * sin(phase + x * 0.55) * cos(phase * 0.7 + x * 0.21)))) + taper
		top = mini(top, fy - 2)   # always at least 3 cells of headroom
		for y in range(top, fy + 1):
			air(x, y)
	_floor_row(r, fy + 1, Cell.HARD)
	# sediment banding in the walls of Dustworks halls
	if c["stratum"] == 0:
		for x in range(r.position.x - 2, r.end.x + 2):
			for y in [r.position.y - 1, r.position.y - 3]:
				if g.is_solid(x, y) and rng.randf() < 0.8:
					solid(x, y, Cell.HARD)
	# wall shelves (jumpable from the floor) and an occasional floor step
	for side in [0, 1]:
		if rng.randf() < 0.7:
			var sy := fy - 3
			var length := rng.randi_range(3, 5)
			for k in length:
				var sx: int = r.position.x + k if side == 0 else r.end.x - 1 - k
				solid(sx, sy, Cell.HARD)
	if r.size.x > 16 and rng.randf() < 0.6:
		var bx := r.position.x + rng.randi_range(5, r.size.x - 8)
		for k in rng.randi_range(2, 3):
			solid(bx + k, fy, rock_for(bx + k, fy))
	c["entry"] = Vector2i(r.position.x + 1, fy)
	c["exit"] = Vector2i(r.end.x - 2, fy)


func _terraces(c: Dictionary) -> void:
	var r: Rect2i = c["rect"]
	var n := clampi(r.size.x / 6, 3, 4)
	var step_w := r.size.x / n
	var ltr := rng.randf() < 0.5           # steps descend left -> right
	var bottom := r.end.y - 1              # feet row of the lowest step
	var phase := rng.randf() * TAU
	var floors: Array[int] = []
	for x in range(r.position.x, r.end.x):
		var i := mini((x - r.position.x) / step_w, n - 1)
		var level := i if ltr else n - 1 - i
		var fy := bottom - 2 * (n - 1 - level)
		floors.append(fy)
		var top := mini(r.position.y + int(round(1.5 + 1.5 * sin(phase + x * 0.4))), fy - 3)   # room to jump a step
		for y in range(top, fy + 1):
			air(x, y)
		for y in range(fy + 1, bottom + 2):
			solid(x, y, rock_for(x, y) if y > fy + 1 else Cell.HARD)
	var top_x := r.position.x + 1 if ltr else r.end.x - 2
	var low_x := r.end.x - 2 if ltr else r.position.x + 1
	c["entry"] = Vector2i(top_x, floors[top_x - r.position.x])
	c["exit"] = Vector2i(low_x, bottom)
	# perched basin on the top step, held by a sediment lip at the step edge
	c["basin"] = []
	if step_w >= 6 and rng.randf() < 0.55:
		var tf := floors[top_x - r.position.x]
		var edge_x := r.position.x + step_w - 1 if ltr else r.end.x - step_w
		var dirx := -1 if ltr else 1          # from the edge back toward the wall
		var basin: Array[Vector2i] = []
		for k in range(1, step_w - 2):
			var bx := edge_x + dirx * k
			for dy in [1, 2]:
				air(bx, tf + dy)
				basin.append(Vector2i(bx, tf + dy))
			solid(bx, tf + 3, Cell.HARD)
		for dy in [1, 2]:
			solid(edge_x, tf + dy, Cell.SOFT)
		c["basin"] = basin
		c["entry"] = Vector2i(top_x if absi(top_x - edge_x) >= step_w - 2 else top_x, tf)


func _fissure(c: Dictionary) -> void:
	var r: Rect2i = c["rect"]
	var phase := rng.randf() * TAU
	var ladder_left := rng.randf() < 0.5
	var mid := r.position.x + r.size.x / 2
	for y in range(r.position.y, r.end.y):
		var jl := int(round(0.8 + 0.8 * sin(phase + y * 0.7)))
		var jr := int(round(0.8 + 0.8 * cos(phase + y * 0.5)))
		for x in range(r.position.x + jl, r.end.x - jr):
			air(x, y)
	# guaranteed climbing line: a rope ladder down one side of the crack
	var lx := r.position.x + 1 if ladder_left else r.end.x - 2
	for y in range(r.position.y, r.end.y):
		air(lx, y)
		if not gen.reserved.has(Vector2i(lx, y)):
			g.put(lx, y, Cell.LADDER)
			g.set_flag(lx, y, Cell.F_NO_RUBBLE)
	# ledges on the other wall every 4 rows, and one plank bridge
	var ox := r.end.x - 1 if ladder_left else r.position.x
	for y in range(r.position.y + 4, r.end.y - 2, 4):
		solid(ox, y, Cell.HARD)
	var by := r.position.y + r.size.y / 2
	for x in range(r.position.x, r.end.x):
		if not g.is_solid(x, by) and g.get_mat(x, by) != Cell.LADDER:
			g.put(x, by, Cell.PLATFORM)
	_floor_row(Rect2i(r.position.x, r.position.y, r.size.x, r.size.y), r.end.y, Cell.HARD)
	# a short side mouth at the top so the crack opens onto its approach
	var mouth_dir := -1 if ladder_left else 1
	for k in range(0, 3):
		for dy in range(0, 3):
			air(mid + mouth_dir * (r.size.x / 2 + k), r.position.y + dy)
	c["entry"] = Vector2i(lx, r.position.y + 2)
	c["exit"] = Vector2i(lx, r.end.y - 1)


func _cathedral(c: Dictionary) -> void:
	var r: Rect2i = c["rect"]
	var cx := r.position.x + r.size.x / 2.0
	var cy := r.position.y + r.size.y * 0.42
	var rx := r.size.x / 2.0
	var ry := r.size.y * 0.55
	var fy := r.end.y - 2                  # feet row of the main floor
	var phase := rng.randf() * TAU
	for y in range(r.position.y, fy + 1):
		for x in range(r.position.x, r.end.x):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var wob := 0.08 * sin(phase + x * 0.5 + y * 0.3)
			if dx * dx + dy * dy <= 1.0 + wob or (y >= cy and absf(dx) <= 0.98):
				air(x, y)
	for x in range(r.position.x, r.end.x):
		for y in range(fy + 1, r.end.y + 1):
			solid(x, y, Cell.HARD)
	# sunken lake basin in the middle third of the floor
	var b0 := r.position.x + r.size.x / 4 + 1
	var b1 := r.end.x - r.size.x / 4 - 1
	var depth := 3
	var basin: Array[Vector2i] = []
	for x in range(b0, b1):
		var d := depth if (x > b0 and x < b1 - 1) else depth - 1
		for k in range(1, d + 1):
			air(x, fy + k)
			basin.append(Vector2i(x, fy + k))
		solid(x, fy + d + 1, Cell.HARD)
	c["basin"] = basin
	# stalactites (anchored in the ceiling) and stalagmites (jumpable)
	for k in rng.randi_range(3, 5):
		var sx := rng.randi_range(r.position.x + 3, r.end.x - 4)
		var top := r.position.y
		while top < fy and g.is_solid(sx, top):
			top += 1
		var length := rng.randi_range(2, 4)
		for y in range(top, mini(top + length, fy - 4)):
			solid(sx, y, Cell.HARD)
	for k in 2:
		# stalagmites stay clear of the entry/exit anchors
		var mx := rng.randi_range(r.position.x + 4, maxi(r.position.x + 4, b0 - 2)) if k == 0 else rng.randi_range(mini(b1 + 1, r.end.x - 6), r.end.x - 6)
		solid(mx, fy, Cell.HARD)
	# high galleries on both walls: elevated bypass ledges
	for side in [0, 1]:
		var gy := fy - 4
		for k in rng.randi_range(3, 5):
			var gx: int = r.position.x + 1 + k if side == 0 else r.end.x - 2 - k
			if not g.is_solid(gx, gy):
				solid(gx, gy, Cell.HARD)
	c["entry"] = Vector2i(r.position.x + 2, fy)
	c["exit"] = Vector2i(r.end.x - 3, fy)


func _works(c: Dictionary) -> void:
	var r: Rect2i = c["rect"]
	var fy := r.end.y - 1
	for x in range(r.position.x, r.end.x):
		for y in range(fy - 2, fy + 1):
			air(x, y)
		solid(x, fy + 1, Cell.HARD)
		if not gen.reserved.has(Vector2i(x, fy - 3)):
			solid(x, fy - 3, Cell.SOFT)
	for x in range(r.position.x + 2, r.end.x - 1, 6):
		gen.data["entities"].append({"type": "beam", "cell": Vector2i(x, fy - 1)})
	for x in range(r.position.x + 5, r.end.x - 1, 12):
		gen.data["entities"].append({"type": "lamp", "cell": Vector2i(x, fy - 2)})
	gen.data["entities"].append({"type": "crate", "cell": Vector2i(r.position.x + r.size.x / 3, fy)})
	# slumped section: a rubble pile resting on the floor (stable, diggable)
	if r.size.x >= 20:
		var sx := r.position.x + rng.randi_range(r.size.x / 2, r.size.x - 6)
		for x in range(sx, sx + 3):
			solid(x, fy, Cell.LOOSE)
			if x == sx + 1:
				solid(x, fy - 1, Cell.LOOSE)
	c["entry"] = Vector2i(r.position.x + 1, fy)
	c["exit"] = Vector2i(r.end.x - 2, fy)


func _ruin_room(r: Rect2i, door_l: bool, door_r: bool) -> int:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			solid(x, y, Cell.ALLOY)
	for y in range(r.position.y + 1, r.end.y - 1):
		for x in range(r.position.x + 1, r.end.x - 1):
			air(x, y)
	var fy := r.end.y - 2
	for dy in range(-2, 1):
		if door_l:
			air(r.position.x, fy + dy)
		if door_r:
			air(r.end.x - 1, fy + dy)
	return fy


func _ruin(c: Dictionary) -> void:
	var r: Rect2i = c["rect"]
	var variant: String = c.get("variant", "hall")
	c["sentries"] = []
	match variant:
		"twin":
			var w1 := r.size.x / 2 - 2
			var a := Rect2i(r.position.x, r.position.y, w1, r.size.y)
			var b := Rect2i(r.end.x - w1, r.position.y, w1, r.size.y)
			var fy := _ruin_room(a, true, true)
			_ruin_room(b, true, true)
			# broken gallery between the rooms: alloy corridor with a collapsed gap
			for x in range(a.end.x, b.position.x):
				solid(x, fy - 3, Cell.ALLOY)
				solid(x, fy + 1, Cell.ALLOY)
				for dy in range(-2, 1):
					air(x, fy + dy)
			var gap := a.end.x + (b.position.x - a.end.x) / 2
			solid(gap, fy - 3, Cell.SOFT)
			solid(gap, fy, Cell.LOOSE)
			c["sentries"].append({"cell": Vector2i(b.position.x + w1 / 2, fy), "module": Vector2i(b.end.x - 2, b.position.y + 1)})
			c["entry"] = Vector2i(a.position.x + 1, fy)
			c["exit"] = Vector2i(b.end.x - 2, fy)
		"stacked":
			var h1 := r.size.y / 2
			var top := Rect2i(r.position.x, r.position.y, r.size.x, h1 + 1)
			var bot := Rect2i(r.position.x, r.position.y + h1, r.size.x, r.size.y - h1)
			var left_first := rng.randf() < 0.5
			var fy1 := _ruin_room(top, left_first, not left_first)
			var fy2 := _ruin_room(bot, not left_first, left_first)
			# internal maintenance ladder joining the floors
			var lx := r.position.x + r.size.x / 2
			for y in range(fy1 - 1, fy2 + 1):
				air(lx, y)
				g.put(lx, y, Cell.LADDER)
				g.set_flag(lx, y, Cell.F_NO_RUBBLE)
			c["sentries"].append({"cell": Vector2i(r.position.x + (2 if left_first else r.size.x - 3), fy2), "module": Vector2i(r.position.x + (r.size.x - 2 if left_first else 1), bot.position.y + 1)})
			c["entry"] = Vector2i(r.position.x + 1 if left_first else r.end.x - 2, fy1)
			c["exit"] = Vector2i(r.end.x - 2 if left_first else r.position.x + 1, fy2)
		_:
			var fy3 := _ruin_room(r, true, true)
			if r.size.x >= 16:
				for y in range(r.position.y + 1, r.position.y + 3):
					solid(r.position.x + r.size.x / 2, y, Cell.ALLOY)
			var sx := r.position.x + rng.randi_range(3, r.size.x - 4)
			c["sentries"].append({"cell": Vector2i(sx, fy3), "module": Vector2i(r.position.x + 1 if sx > r.position.x + r.size.x / 2 else r.end.x - 2, r.position.y + 1)})
			c["entry"] = Vector2i(r.position.x + 1, fy3)
			c["exit"] = Vector2i(r.end.x - 2, fy3)
	# geological intrusion: a basalt wedge breaks through one upper corner of the shell
	if rng.randf() < 0.6:
		var right := rng.randf() < 0.5
		var cx := r.end.x - 1 if right else r.position.x
		for k in 4:
			for j in range(0, 4 - k):
				var x := cx + (-j if right else j)
				var y := r.position.y + k
				solid(x, y, Cell.HARD)
		c["intrusion"] = true
	# approach mouths outside the doors so the ruin opens into the rock
	for p in [c["entry"], c["exit"]]:
		var dirx := -1 if p.x < r.position.x + r.size.x / 2 else 1
		for k in range(1, 4):
			for dy in range(-2, 1):
				air((r.position.x - k) if dirx < 0 else (r.end.x - 1 + k), p.y + dy)
		for k in range(1, 4):
			var fx: int = (r.position.x - k) if dirx < 0 else (r.end.x - 1 + k)
			if not g.is_solid(fx, p.y + 1):
				solid(fx, p.y + 1, Cell.HARD)
