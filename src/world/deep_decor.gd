class_name DeepDecor
extends Node2D
## Background architecture of THE FIRST CIVILIZATION, drawn in code. Each piece
## sits behind rock, water and lava (z -8), never collides, and animates only
## while it is on screen. The origin is the bottom-left corner at floor level;
## `w` and `h` are in cells. Glowing parts add soft sprites to the glow layer.

var kind := "colossus"
var w := 4
var h := 4
var flip := false
var variant := 0
var mine: Node
var t := 0.0
var _glows: Array[Sprite2D] = []
var _glow_base: Array[Color] = []
var _glow_pos: Array[Vector2] = []
var _spark := 0.0
var _spark_next := 1.0
var _rng := RandomNumberGenerator.new()

const C := 16.0
const BRONZE := Color("7a673f")
const BRONZE_D := Color("4f422e")
const BRONZE_L := Color("b49a62")
const DARK := Color("2f271d")
const STONE := Color("6a645a")
const STONE_D := Color("46423b")
const STONE_L := Color("88806f")
const PATINA := Color("587060")
const CYAN := Color(0.43, 0.95, 0.82)
const EMBER := Color(1.0, 0.55, 0.2)
const RED := Color(1.0, 0.3, 0.22)
const ANIMATED := ["furnace", "conduit", "lift_wreck", "signal", "shelves", "pylon", "cables", "husk", "junction", "colossus"]
const GLOW_TEX := preload("res://assets/gen/glow.png")


func _ready() -> void:
	z_index = -8
	_rng.seed = hash("%s:%d:%d" % [kind, int(position.x), int(position.y)])
	t = _rng.randf() * 10.0
	set_process(kind in ANIMATED)
	_setup_glows()


func _exit_tree() -> void:
	for g in _glows:
		if is_instance_valid(g):
			g.queue_free()


func _px(x: float) -> float:
	return w * C - x if flip else x


func _add_glow(p: Vector2, col: Color, s: float) -> void:
	if mine == null or mine.get("glow_root") == null:
		return
	var g := Sprite2D.new()
	g.texture = GLOW_TEX
	g.scale = Vector2(s, s)
	g.modulate = col
	mine.glow_root.add_child(g)
	var lp := Vector2(_px(p.x), -p.y)
	g.global_position = global_position + lp
	_glows.append(g)
	_glow_base.append(col)
	_glow_pos.append(lp)


func _setup_glows() -> void:
	var W := w * C
	var H := h * C
	match kind:
		"colossus":
			if variant != 1:
				_add_glow(Vector2(W * 0.5, H * 0.52), Color(CYAN, 0.45), 0.5)
		"furnace":
			_add_glow(Vector2(W * 0.5, 14), Color(EMBER, 0.7), 0.7)
		"conduit":
			for k in 3:
				_add_glow(Vector2(0, 8), Color(CYAN, 0.5), 0.3)
		"husk":
			_add_glow(Vector2(W * 0.78, H * 0.62), Color(RED, 0.0), 0.18)
		"signal":
			_add_glow(Vector2(8, H - 8), Color(RED if variant == 0 else CYAN, 0.6), 0.3)
		"shelves":
			_add_glow(Vector2(W * 0.5, H * 0.5), Color(CYAN, 0.22), 0.6)
		"pylon":
			_add_glow(Vector2(W * 0.5, H - 10), Color(CYAN, 0.6), 0.55)
		"lift_wreck":
			_add_glow(Vector2(W * 0.82, H * 0.95), Color(1.0, 0.85, 0.5, 0.0), 0.35)
		"junction":
			_add_glow(Vector2(W * 0.5, H * 0.7), Color(CYAN, 0.35), 0.25)
		"railcar":
			_add_glow(Vector2(W * 0.5, 34), Color(CYAN, 0.3), 0.35)


func _on_screen() -> bool:
	var xf := get_canvas_transform()
	var sc := xf.get_scale()
	var vis := Rect2(-xf.origin / sc, get_viewport_rect().size / sc).grow(48)
	return vis.intersects(Rect2(global_position + Vector2(0, -h * C), Vector2(w * C, h * C)))


func _process(delta: float) -> void:
	t += delta
	if not _on_screen():
		return
	match kind:
		"furnace":
			var f := 0.75 + 0.18 * sin(t * 2.1) + 0.07 * sin(t * 7.3)
			_glows_alpha(0, 0.7 * f)
		"conduit":
			for k in _glows.size():
				var x := fmod(t * 70.0 + k * (w * C / 3.0), w * C)
				_glows[k].global_position = global_position + Vector2(_px(x), -8)
		"husk":
			var blink := maxf(0.0, sin(t * 0.9)) ** 12
			_glows_alpha(0, 0.55 * blink)
		"signal":
			_glows_alpha(0, 0.65 if fmod(t, 1.6) < 0.8 else 0.08)
		"pylon":
			var on: bool = mine != null and mine.get("gate") != null and is_instance_valid(mine.gate) and mine.gate.get("powered") == true
			_glows_alpha(0, (0.75 if on else 0.35) + 0.15 * sin(t * (5.0 if on else 1.5)))
		"lift_wreck":
			_spark -= delta
			_spark_next -= delta
			if _spark_next <= 0.0:
				_spark = 0.16
				_spark_next = _rng.randf_range(0.6, 2.4)
			_glows_alpha(0, 0.8 if _spark > 0.0 else 0.0)
		"shelves":
			_glows_alpha(0, 0.2 + 0.05 * sin(t * 1.3))
		"junction":
			_glows_alpha(0, 0.3 + 0.2 * step_wave(t * 1.7))
		"colossus":
			if not _glows.is_empty():
				_glows_alpha(0, 0.35 + 0.15 * sin(t * 0.8))
	queue_redraw()


func step_wave(x: float) -> float:
	return 1.0 if fmod(x, 2.0) < 1.0 else 0.0


func _glows_alpha(i: int, a: float) -> void:
	if i < _glows.size():
		var c := _glow_base[i]
		c.a = a
		_glows[i].modulate = c


# --- drawing helpers (y measured up from the floor) -----------------------------
func _r(x: float, y: float, ww: float, hh: float, col: Color) -> void:
	draw_rect(Rect2(x, -y - hh, ww, hh), col)


func _poly(pts: Array, col: Color) -> void:
	var p := PackedVector2Array()
	for v: Vector2 in pts:
		p.append(Vector2(v.x, -v.y))
	draw_colored_polygon(p, col)


func _line(a: Vector2, b: Vector2, col: Color, width: float = 1.0) -> void:
	draw_line(Vector2(a.x, -a.y), Vector2(b.x, -b.y), col, width)


func _circ(c: Vector2, r: float, col: Color) -> void:
	draw_circle(Vector2(c.x, -c.y), r, col)


var _base := Transform2D.IDENTITY


func _draw() -> void:
	_base = Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(w * C, 0)) if flip else Transform2D.IDENTITY
	draw_set_transform_matrix(_base)
	var W := w * C
	var H := h * C
	match kind:
		"colossus": _draw_colossus(W, H)
		"fallen_head": _draw_fallen_head(W, H)
		"furnace": _draw_furnace(W, H)
		"pipes": _draw_pipes(W)
		"conduit": _draw_conduit(W)
		"junction": _draw_junction(W, H)
		"husk": _draw_husk(W, H)
		"rail": _draw_rail(W)
		"railcar": _draw_railcar(W, H)
		"signal": _draw_signal(H)
		"shelves": _draw_shelves(W, H)
		"lift_wreck": _draw_lift_wreck(W, H)
		"cables": _draw_cables(W, H)
		"pylon": _draw_pylon(W, H)


# --- FIRST HALL: seated giants on plinths ----------------------------------------
func _draw_colossus(W: float, H: float) -> void:
	_r(0, 0, W, 12, STONE_D)
	_r(0, 10, W, 2, STONE_L)
	_r(4, 3, W - 8, 1, STONE)
	var knee_h := H * 0.2
	_r(W * 0.1, 12, W * 0.8, knee_h, STONE)
	_r(W * 0.1, 12 + knee_h - 3, W * 0.8, 3, STONE_L)
	# shins and feet
	_r(W * 0.14, 12, W * 0.18, knee_h - 3, STONE_D)
	_r(W * 0.68, 12, W * 0.18, knee_h - 3, STONE_D)
	var ty0 := 12 + knee_h
	var ty1 := H * 0.8
	_poly([Vector2(W * 0.24, ty0), Vector2(W * 0.76, ty0), Vector2(W * 0.88, ty1), Vector2(W * 0.12, ty1)], STONE)
	_poly([Vector2(W * 0.24, ty0), Vector2(W * 0.36, ty0), Vector2(W * 0.3, ty1), Vector2(W * 0.12, ty1)], STONE_L)
	# arms resting on the knees
	_r(W * 0.02, ty0 - 2, W * 0.13, ty1 - ty0 - 4, STONE_D)
	_r(W * 0.85, ty0 - 2, W * 0.13, ty1 - ty0 - 4, STONE_D)
	_r(W * 0.0, ty0 - 4, W * 0.2, 6, STONE)
	_r(W * 0.8, ty0 - 4, W * 0.2, 6, STONE)
	# carved bands on the chest
	for k in 3:
		_r(W * 0.3, ty0 + 8 + k * 7, W * 0.4, 1, STONE_D)
	if variant == 1:
		# broken: the head lies somewhere in the hall, a jagged neck remains
		_poly([Vector2(W * 0.36, ty1), Vector2(W * 0.64, ty1), Vector2(W * 0.6, ty1 + 6), Vector2(W * 0.52, ty1 + 3), Vector2(W * 0.44, ty1 + 7), Vector2(W * 0.38, ty1 + 4)], STONE_D)
	else:
		var hy := ty1
		var hh := H * 0.17
		_r(W * 0.32, hy, W * 0.36, hh, STONE)
		_r(W * 0.32, hy + hh - 3, W * 0.36, 3, STONE_L)
		_poly([Vector2(W * 0.28, hy + hh), Vector2(W * 0.72, hy + hh), Vector2(W * 0.5, hy + hh + 8)], STONE_D)
		var eye := 0.5 + 0.2 * sin(t * 0.8)
		_r(W * 0.38, hy + hh * 0.45, W * 0.24, 2, Color(CYAN, eye))
	var core := 0.55 + 0.2 * sin(t * 0.8)
	_circ(Vector2(W * 0.5, H * 0.52), W * 0.07, Color(0.12, 0.2, 0.2))
	if variant != 1:
		_circ(Vector2(W * 0.5, H * 0.52), W * 0.05, Color(CYAN, core))
	# weathering cracks
	_rng.seed = int(W * 7 + H)
	for k in 4:
		var a := Vector2(_rng.randf_range(W * 0.15, W * 0.85), _rng.randf_range(14, H * 0.75))
		_line(a, a + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-10, -4)), DARK, 1.0)


func _draw_fallen_head(W: float, H: float) -> void:
	_poly([Vector2(2, 0), Vector2(W - 4, 0), Vector2(W - 1, H * 0.7), Vector2(W * 0.4, H), Vector2(0, H * 0.6)], STONE)
	_poly([Vector2(W * 0.4, H), Vector2(W - 1, H * 0.7), Vector2(W - 6, H * 0.55), Vector2(W * 0.42, H * 0.82)], STONE_L)
	_r(W * 0.25, H * 0.35, W * 0.35, 2, Color(0.12, 0.2, 0.2))
	_line(Vector2(W * 0.7, 2), Vector2(W * 0.62, H * 0.5), DARK)
	_r(-6, 0, 5, 3, STONE_D)
	_r(W + 2, 0, 4, 2, STONE_D)


# --- HEAT WORKS: furnaces, chimneys and hot pipes -----------------------------------
func _draw_furnace(W: float, H: float) -> void:
	var bh := minf(H, 4.0 * C)
	# chimney up to the ceiling
	var cx := W * 0.62
	_r(cx, bh - 4, 10, H - bh + 4, BRONZE_D)
	_r(cx + 2, bh - 4, 2, H - bh + 4, BRONZE)
	var y := bh + 10.0
	while y < H - 4:
		_r(cx - 1, y, 12, 3, BRONZE)
		y += 26.0
	# body
	_r(0, 0, W, bh - 8, BRONZE_D)
	_poly([Vector2(0, bh - 8), Vector2(W, bh - 8), Vector2(W - 6, bh), Vector2(6, bh)], BRONZE)
	_r(0, bh - 10, W, 2, BRONZE_L)
	_r(0, 0, W, 4, DARK)
	for rx in range(4, int(W) - 2, 10):
		_circ(Vector2(rx, bh - 14), 1.2, BRONZE_L)
	# the glowing mouth with a grille
	var f := 0.75 + 0.18 * sin(t * 2.1) + 0.07 * sin(t * 7.3)
	var mw := W * 0.5
	var mx := (W - mw) * 0.5
	_r(mx - 2, 4, mw + 4, 22, DARK)
	_r(mx, 4, mw, 18, Color(EMBER.r * f, EMBER.g * f, EMBER.b * f))
	_r(mx + 2, 4, mw - 4, 8, Color(1.0, 0.85 * f, 0.4 * f))
	_circ(Vector2(W * 0.5, 22), mw * 0.5, Color(EMBER.r * f, EMBER.g * f * 0.9, EMBER.b * f))
	for gx in range(int(mx) + 4, int(mx + mw), 6):
		_line(Vector2(gx, 4), Vector2(gx, 26), DARK, 2.0)
	# a pressure gauge
	_circ(Vector2(W * 0.2, bh - 22), 5, BRONZE_L)
	_circ(Vector2(W * 0.2, bh - 22), 3.5, DARK)
	_line(Vector2(W * 0.2, bh - 22), Vector2(W * 0.2 + 3 * cos(t), bh - 22 + 3 * sin(t)), RED)


func _draw_pipes(W: float) -> void:
	_r(0, 2, W, 6, BRONZE_D)
	_r(0, 6, W, 1, BRONZE_L)
	_r(0, 10, W, 4, BRONZE_D)
	_r(0, 13, W, 1, BRONZE)
	var x := 12.0
	var k := 0
	while x < W - 8:
		_r(x, 0, 4, 16, DARK)
		_r(x - 1, 14, 6, 2, BRONZE)
		if k % 4 == 2:
			_circ(Vector2(x + 18, 5), 5, BRONZE)
			_circ(Vector2(x + 18, 5), 2, DARK)
		if variant == 1 and k % 3 == 1:
			_r(x + 8, 3, 14, 3, Color(EMBER, 0.55))
		x += 48.0
		k += 1


# --- CONDUIT: power lines with pulses ----------------------------------------------
func _draw_conduit(W: float) -> void:
	_r(0, 2, W, 12, BRONZE_D)
	_r(0, 12, W, 2, BRONZE)
	_r(0, 6, W, 4, Color(0.08, 0.16, 0.16))
	_r(0, 7, W, 2, Color(CYAN, 0.25))
	var x := 20.0
	while x < W - 10:
		_r(x, 0, 8, 16, BRONZE)
		_r(x + 2, 1, 4, 14, BRONZE_D)
		x += 64.0
	for k in 3:
		var px := fmod(t * 70.0 + k * (W / 3.0), W)
		for j in 5:
			var a := 0.9 - j * 0.18
			_r(px - j * 5.0, 6, 5, 4, Color(CYAN, a))


func _draw_junction(W: float, H: float) -> void:
	_r(2, 0, W - 4, H - 6, BRONZE_D)
	_r(0, H - 8, W, 4, BRONZE)
	_r(4, H - 4, 6, 4, BRONZE_D)
	_r(W - 10, H - 4, 6, 4, BRONZE_D)
	_r(6, H * 0.35, W - 12, H * 0.3, DARK)
	for k in 3:
		var on := step_wave(t * 1.7 + k * 0.6) > 0.5
		_r(9 + k * 6, H * 0.45, 3, 3, Color(CYAN, 0.9) if on else Color(0.1, 0.2, 0.2))
	_circ(Vector2(W * 0.5, H * 0.18), 4, BRONZE_L)
	_line(Vector2(W * 0.5, H * 0.18), Vector2(W * 0.5 + 3, H * 0.18 + 2), DARK)


# --- STILL HALL: kneeling machine husks ---------------------------------------------
func _draw_husk(W: float, H: float) -> void:
	# a machine knelt on one knee, head bowed, one hand on the floor. W 64, H 80.
	var sx := W / 64.0
	var sy := H / 80.0
	var M := Color("57524a")
	var MD := Color("39362f")
	var ML := Color("7f786a")
	var P := func(x: float, y: float) -> Vector2: return Vector2(x * sx, y * sy)
	_r(0, 0, W, 2, STONE_D.darkened(0.3))
	# rear leg: shin flat on the floor, thigh up to the hip
	_line(P.call(6, 4), P.call(30, 4), MD, 8.0 * sx)
	_line(P.call(30, 5), P.call(24, 30), MD, 9.0 * sx)
	_circ(P.call(30, 6), 5.0 * sx, M)
	# front leg: foot, upright shin, thigh back to the hip
	_r(38 * sx, 0, 18 * sx, 5 * sy, MD)
	_line(P.call(46, 4), P.call(46, 26), M, 8.0 * sx)
	_line(P.call(46, 26), P.call(26, 32), M, 9.0 * sx)
	_circ(P.call(46, 26), 5.5 * sx, ML)
	# pelvis and a slumped torso
	_r(16 * sx, 26 * sy, 18 * sx, 10 * sy, MD)
	_poly([P.call(14, 34), P.call(36, 34), P.call(50, 58), P.call(28, 70), P.call(16, 56)], M)
	_poly([P.call(28, 70), P.call(50, 58), P.call(47, 54), P.call(27, 64)], ML)
	for k in 3:
		_line(P.call(20 + k * 5, 40 + k * 2), P.call(30 + k * 5, 56 + k * 2), MD, 1.5)
	# spine vents glow faintly cyan, long dead
	_r(17 * sx, 44 * sy, 3 * sx, 10 * sy, Color(0.15, 0.25, 0.24))
	# bowed head with a visor
	_poly([P.call(46, 46), P.call(60, 48), P.call(60, 60), P.call(48, 62)], MD)
	_poly([P.call(48, 62), P.call(60, 60), P.call(58, 64), P.call(50, 65)], M)
	var blink := maxf(0.0, sin(t * 0.9)) ** 12
	_r(51 * sx, 52 * sy, 8 * sx, 2.5 * sy, Color(RED.r, RED.g, RED.b, 0.2 + 0.8 * blink))
	# shoulder plate and an arm reaching down to the floor
	_line(P.call(42, 60), P.call(52, 32), MD, 7.0 * sx)
	_line(P.call(52, 32), P.call(58, 6), MD, 6.0 * sx)
	_circ(P.call(52, 32), 4.0 * sx, M)
	_r(53 * sx, 0, 10 * sx, 6 * sy, M)
	_poly([P.call(30, 66), P.call(44, 70), P.call(52, 62), P.call(46, 56), P.call(34, 58)], ML.darkened(0.15))
	# patina streaks where water once ran over it
	_line(P.call(33, 66), P.call(31, 44), PATINA.darkened(0.2), 1.5)
	_line(P.call(40, 62), P.call(38, 48), PATINA.darkened(0.2), 1.0)


# --- DEEP ROAD / transit: rails, cars, signals ---------------------------------------
func _draw_rail(W: float) -> void:
	var x := 0.0
	while x < W:
		_r(x + 1, 0, 6, 3, DARK)
		x += 9.0
	_r(0, 3, W, 2, BRONZE_L)
	_r(0, 2, W, 1, BRONZE_D)


func _draw_railcar(W: float, H: float) -> void:
	var tilt := 0.0 if variant == 0 else -0.18
	draw_set_transform_matrix(_base * Transform2D(tilt, Vector2(W * 0.15, 0)))
	_draw_car_body(W, H, -W * 0.15)
	draw_set_transform_matrix(_base)


func _draw_car_body(W: float, H: float, ox: float) -> void:
	_circ(Vector2(ox + W * 0.22, 6), 6, DARK)
	_circ(Vector2(ox + W * 0.78, 6), 6, DARK)
	_circ(Vector2(ox + W * 0.22, 6), 2, BRONZE_L)
	_circ(Vector2(ox + W * 0.78, 6), 2, BRONZE_L)
	_r(ox + 4, 8, W - 8, 4, BRONZE_D)
	_poly([Vector2(ox + 2, 12), Vector2(ox + W - 2, 12), Vector2(ox + W + 2, H - 10), Vector2(ox - 2, H - 10)], BRONZE)
	_r(ox - 3, H - 12, W + 6, 3, BRONZE_L)
	for k in range(1, 4):
		_line(Vector2(ox + W * k / 4.0, 13), Vector2(ox + W * k / 4.0, H - 13), BRONZE_D, 1.0)
	# cargo of pale crystal
	_poly([Vector2(ox + W * 0.2, H - 9), Vector2(ox + W * 0.32, H + 2), Vector2(ox + W * 0.42, H - 9)], Color(0.55, 0.85, 0.8))
	_poly([Vector2(ox + W * 0.4, H - 9), Vector2(ox + W * 0.55, H + 7), Vector2(ox + W * 0.66, H - 9)], Color(0.7, 0.95, 0.9))
	_poly([Vector2(ox + W * 0.62, H - 9), Vector2(ox + W * 0.72, H - 1), Vector2(ox + W * 0.8, H - 9)], Color(0.5, 0.78, 0.75))


func _draw_signal(H: float) -> void:
	_r(5, 0, 6, 3, DARK)
	_r(7, 0, 2, H - 12, BRONZE_D)
	_r(2, H - 16, 12, 14, BRONZE)
	_r(4, H - 14, 8, 10, DARK)
	var on := fmod(t, 1.6) < 0.8
	var col := RED if variant == 0 else CYAN
	_circ(Vector2(8, H - 9), 3, col if on else col.darkened(0.8))
	_r(1, H - 2, 14, 2, BRONZE_L)


# --- ARCHIVE: racks of record slates -------------------------------------------------
func _draw_shelves(W: float, H: float) -> void:
	_r(0, 0, 3, H, BRONZE_D)
	_r(W - 3, 0, 3, H, BRONZE_D)
	_r(0, H - 3, W, 3, BRONZE)
	_rng.seed = int(global_position.x * 3 + global_position.y)
	var sy := 4.0
	var row := 0
	while sy < H - 14:
		_r(2, sy, W - 4, 2, BRONZE)
		var x := 5.0
		while x < W - 8:
			var roll := _rng.randf()
			if roll < 0.72:
				var lit := _rng.randf() < 0.35
				var tall := _rng.randf_range(10, 15)
				var col := Color(0.15, 0.28, 0.28)
				if lit:
					col = Color(CYAN, 0.5 + 0.4 * sin(t * _rng.randf_range(0.6, 1.8) + x + row))
				_r(x, sy + 2, 3, tall, col)
				_r(x, sy + 1 + tall, 3, 1, BRONZE_L.darkened(0.3))
			elif roll < 0.8:
				# a slate fallen over on the shelf
				_r(x - 2, sy + 2, 12, 3, Color(0.2, 0.3, 0.3))
				x += 6.0
			x += 5.0
		sy += 22.0
		row += 1
	_r(-4, 0, 8, 2, Color(0.2, 0.3, 0.3))


# --- arrival: the wrecked lift cage and its snapped cables -----------------------------
func _draw_lift_wreck(W: float, H: float) -> void:
	var tilt := -0.13
	draw_set_transform_matrix(_base * Transform2D(tilt, Vector2(4, 0)))
	var cw := W - 14
	var ch := H - 10
	# floor plate, posts, crossbars and a crumpled roof
	_r(0, 0, cw, 5, BRONZE_D)
	_r(0, 4, cw, 1, BRONZE_L)
	for px in [0.0, cw * 0.5 - 1.5, cw - 3.0]:
		_r(px, 5, 3, ch - 5, BRONZE)
	_line(Vector2(3, 6), Vector2(cw * 0.5 - 2, ch - 2), BRONZE_D, 2.0)
	_line(Vector2(cw * 0.5 + 2, 6), Vector2(cw - 3, ch - 8), BRONZE_D, 2.0)
	_line(Vector2(cw * 0.5 + 2, ch - 8), Vector2(cw - 4, ch * 0.45), BRONZE_D, 2.0)
	_poly([Vector2(-3, ch - 2), Vector2(cw * 0.45, ch + 4), Vector2(cw * 0.6, ch - 3), Vector2(cw + 4, ch + 2), Vector2(cw + 3, ch - 6), Vector2(-2, ch - 7)], BRONZE)
	_r(0, ch * 0.5, cw * 0.5, 2, BRONZE_D)
	# the door hangs from one hinge
	_line(Vector2(cw - 1, ch * 0.7), Vector2(cw + 10, 3), BRONZE, 2.0)
	_line(Vector2(cw + 2, ch * 0.72), Vector2(cw + 13, 6), BRONZE_D, 1.0)
	# snapped hoist cables curl up from the roof
	var sway := 2.0 * sin(t * 0.7)
	draw_polyline(PackedVector2Array([Vector2(cw * 0.3, -ch - 3), Vector2(cw * 0.28, -ch - 12), Vector2(cw * 0.36 + sway, -ch - 20), Vector2(cw * 0.42 + sway, -ch - 16)]), DARK, 2.0)
	draw_polyline(PackedVector2Array([Vector2(cw * 0.7, -ch - 2), Vector2(cw * 0.74, -ch - 14), Vector2(cw * 0.66 - sway, -ch - 22)]), DARK, 2.0)
	if _spark > 0.0:
		var sp := Vector2(cw * 0.82, -ch - 2)
		for k in 6:
			var d := Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(3, 9)
			draw_line(sp, sp + d, Color(1.0, 0.9, 0.55), 1.0)
	draw_set_transform_matrix(_base)
	# scattered debris on the floor
	_r(W - 10, 0, 7, 3, BRONZE_D)
	_r(-8, 0, 5, 2, BRONZE_D)
	_line(Vector2(-14, 1), Vector2(-4, 4), BRONZE, 2.0)


func _draw_cables(W: float, H: float) -> void:
	for k in 2:
		var x0 := W * (0.3 + 0.4 * k)
		var pts := PackedVector2Array()
		var n := int(H / 8.0) + 1
		for j in n + 1:
			var y := -H + j * (H / n)
			var depth := float(j) / n
			pts.append(Vector2(x0 + depth * depth * 4.0 * sin(t * 0.6 + k * 1.7), y))
		draw_polyline(pts, DARK, 2.0)
		var end := pts[pts.size() - 1]
		draw_line(end, end + Vector2(-3, 4), DARK, 1.0)
		draw_line(end, end + Vector2(2, 5), DARK, 1.0)


# --- transit gate pylons --------------------------------------------------------------
func _draw_pylon(W: float, H: float) -> void:
	_r(0, 0, W, 6, BRONZE_D)
	_r(2, 6, W - 4, 3, BRONZE)
	_r(W * 0.5 - 4, 9, 8, H - 26, BRONZE_D)
	_r(W * 0.5 - 2, 9, 2, H - 26, BRONZE)
	var on: bool = mine != null and mine.get("gate") != null and is_instance_valid(mine.gate) and mine.gate.get("powered") == true
	var y := 16.0
	var k := 0
	while y < H - 22:
		var a := 0.25 + (0.6 if on else 0.15) * (0.5 + 0.5 * sin(t * (5.0 if on else 1.5) - k))
		_r(W * 0.5 - 8, y, 16, 3, BRONZE)
		_r(W * 0.5 - 6, y + 1, 12, 1, Color(CYAN, a))
		y += 14.0
		k += 1
	_poly([Vector2(W * 0.5, H), Vector2(W * 0.5 + 7, H - 10), Vector2(W * 0.5, H - 20), Vector2(W * 0.5 - 7, H - 10)], Color(CYAN, 0.55 if on else 0.3))
	_poly([Vector2(W * 0.5, H - 4), Vector2(W * 0.5 + 3, H - 10), Vector2(W * 0.5, H - 16), Vector2(W * 0.5 - 3, H - 10)], Color(0.85, 1.0, 0.95, 0.8 if on else 0.35))
