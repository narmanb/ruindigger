class_name HudSkin
extends RefCounted
## The in-game HUD's shared look: chamfered metal frames with orange corner
## highlights and a hazard strip, octagonal touch buttons, and small pixel-art
## icons. Everything is drawn with primitives on whole pixels, so every panel
## and button stays one consistent interface and scales with the HUD.

const OUTLINE := Color("09080d")
const METAL_HI := Color("a19eb0")
const METAL := Color("5f5c6e")
const METAL_LO := Color("2c2936")
const INTERIOR := Color(0.06, 0.055, 0.09, 0.9)
const INTERIOR_HI := Color(0.11, 0.1, 0.15, 0.92)
const ORANGE := Color("ff9a2e")
const ORANGE_DK := Color("9a4f12")
const YELLOW := Color("ffd23f")
const CYAN := Color("5ff2e6")
const TEAL := Color("3fe0b0")
const RED := Color("ff4a3d")
const GREEN := Color("3fe08a")
const TEXT := Color("e9e3f2")
const MUTED := Color("8c869c")


static func chamfer(r: Rect2, cut: float) -> PackedVector2Array:
	var a := r.position
	var b := r.end
	return PackedVector2Array([
		Vector2(a.x + cut, a.y), Vector2(b.x - cut, a.y), Vector2(b.x, a.y + cut), Vector2(b.x, b.y - cut),
		Vector2(b.x - cut, b.y), Vector2(a.x + cut, b.y), Vector2(a.x, b.y - cut), Vector2(a.x, a.y + cut)])


static func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	q.append(p[0])
	return q


## A HUD panel: outline, bevelled metal rim, dark interior, orange corner
## brackets and (optionally) a hazard strip on the bottom edge.
static func frame(ci: CanvasItem, r: Rect2, accent: Color = ORANGE, hazard: bool = true, cut: float = 6.0) -> void:
	r = Rect2(r.position.round(), r.size.round())
	ci.draw_colored_polygon(chamfer(r, cut), OUTLINE)
	var m := r.grow(-1.0)
	ci.draw_colored_polygon(chamfer(m, cut - 0.5), METAL)
	# bevel: light top-left, dark bottom-right
	var pm := chamfer(m, cut - 0.5)
	ci.draw_polyline(PackedVector2Array([pm[6], pm[7], pm[0], pm[1]]), METAL_HI, 1.0)
	ci.draw_polyline(PackedVector2Array([pm[2], pm[3], pm[4], pm[5]]), METAL_LO, 1.0)
	var inner := r.grow(-3.0)
	ci.draw_colored_polygon(chamfer(inner, cut - 2.0), INTERIOR)
	ci.draw_polyline(_closed(chamfer(inner, cut - 2.0)), Color(0, 0, 0, 0.6), 1.0)
	# orange brackets across the four cut corners
	var pc := chamfer(r.grow(-1.0), cut - 0.5)
	var dim := accent.darkened(0.35)
	for k in [[7, 0], [1, 2], [3, 4], [5, 6]]:
		ci.draw_line(pc[k[0]], pc[k[1]], accent, 2.0)
	ci.draw_line(pc[0], pc[0] + Vector2(6, 0), dim, 1.0)
	ci.draw_line(pc[1], pc[1] - Vector2(6, 0), dim, 1.0)
	ci.draw_line(pc[4], pc[4] - Vector2(6, 0), dim, 1.0)
	ci.draw_line(pc[5], pc[5] + Vector2(6, 0), dim, 1.0)
	if hazard and r.size.x > 40.0:
		var hw := clampf(r.size.x * 0.22, 14.0, 44.0)
		hazard_strip(ci, Rect2(r.position.x + 10.0, r.end.y - 3.0, hw, 3.0), accent)


static func hazard_strip(ci: CanvasItem, r: Rect2, accent: Color = ORANGE) -> void:
	r = Rect2(r.position.round(), r.size.round())
	ci.draw_rect(r, Color(0.08, 0.06, 0.04))
	var x := r.position.x
	var k := 0
	while x < r.end.x:
		var w := minf(3.0, r.end.x - x)
		if k % 2 == 0:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x, r.end.y), Vector2(x + 1.0, r.position.y), Vector2(x + w + 1.0, r.position.y), Vector2(x + w, r.end.y)]), accent)
		x += 3.0
		k += 1


## Octagonal touch button: metal rim, coloured inner ring, dark face.
static func button(ci: CanvasItem, c: Vector2, hw: float, hh: float, accent: Color, pressed: bool, dim: float = 1.0, op: float = 1.0) -> void:
	var r := Rect2((c - Vector2(hw, hh)).round(), (Vector2(hw, hh) * 2.0).round())
	var cut := roundf(minf(hw, hh) * 0.42)
	var a := op
	ci.draw_colored_polygon(chamfer(r, cut), Color(OUTLINE, 0.95 * a))
	var m := r.grow(-1.0)
	var pm := chamfer(m, cut - 0.5)
	ci.draw_colored_polygon(pm, Color(METAL, a))
	ci.draw_polyline(PackedVector2Array([pm[6], pm[7], pm[0], pm[1], pm[2]]), Color(METAL_HI, a), 1.0)
	ci.draw_polyline(PackedVector2Array([pm[2], pm[3], pm[4], pm[5], pm[6]]), Color(METAL_LO, a), 1.0)
	var ring := r.grow(-3.0)
	var acc := accent.lightened(0.25) if pressed else accent
	acc = Color(acc.r * dim + 0.25 * (1.0 - dim), acc.g * dim + 0.25 * (1.0 - dim), acc.b * dim + 0.25 * (1.0 - dim), a)
	var face := r.grow(-4.0)
	var fc := Color("1c1a26") if pressed else Color("100e17")
	ci.draw_colored_polygon(chamfer(face, cut - 2.5), Color(fc, a))
	ci.draw_polyline(_closed(chamfer(ring.grow(-0.5), cut - 2.0)), acc, 2.0)
	# a soft top sheen on the face
	var top := chamfer(face, cut - 3.0)
	ci.draw_line(top[0] + Vector2(0, 1), top[1] + Vector2(0, 1), Color(1, 1, 1, 0.08 * a), 1.0)
	if hw > 18.0:
		hazard_strip(ci, Rect2(c.x - hw * 0.45, r.end.y - 3.0, hw * 0.9, 2.0), Color(acc, a))


static func label(ci: CanvasItem, pos: Vector2, text: String, size: int, col: Color, center: bool = false) -> void:
	var f := UIKit.font_head()
	var p := pos
	if center:
		p.x -= f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	ci.draw_string(f, (p + Vector2(1, 1)).round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, col.a * 0.8))
	ci.draw_string(f, p.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Segmented meter like the references: dark trough, bright blocks.
static func meter(ci: CanvasItem, r: Rect2, frac: float, col: Color, segs: int = 12, blink: bool = false) -> void:
	r = Rect2(r.position.round(), r.size.round())
	ci.draw_rect(r, Color(0.03, 0.025, 0.05, 0.9))
	var filled := int(round(clampf(frac, 0.0, 1.0) * segs))
	var sw := (r.size.x - 1.0) / segs
	for i in segs:
		var sr := Rect2(roundf(r.position.x + 1.0 + i * sw), r.position.y + 1.0, maxf(1.0, roundf(sw) - 1.0), r.size.y - 2.0)
		if i < filled:
			var c := col.lightened(0.45) if blink else col
			ci.draw_rect(sr, c)
			ci.draw_rect(Rect2(sr.position, Vector2(sr.size.x, 1)), c.lightened(0.35))
		else:
			ci.draw_rect(sr, Color(0.17, 0.15, 0.22))


# --- icons (centred on c, about `s` px tall) ----------------------------------
static func icon(ci: CanvasItem, kind: String, c: Vector2, s: float, a: float = 1.0) -> void:
	c = c.round()
	match kind:
		"drill": _drill(ci, c, s, a)
		"jump": _jump(ci, c, s, a)
		"charge": _bomb(ci, c, s, a)
		"ladder": _ladder(ci, c, s, a)
		"sonar": _sonar(ci, c, s, a)
		"cryo": _cryo(ci, c, s, a)
		"lure": _lure(ci, c, s, a)
		"crate": _crate(ci, c, s, a)
		"pause": _pause(ci, c, s, a)
		"use": _use(ci, c, s, a)


static func _drill(ci: CanvasItem, c: Vector2, s: float, a: float) -> void:
	# a drill bit pointing up-right with spiral flutes
	var dir := Vector2(1, -1).normalized()
	var perp := Vector2(dir.y, -dir.x)
	var base := c - dir * s * 0.42
	var tip := c + dir * s * 0.5
	var w := s * 0.3
	ci.draw_colored_polygon(PackedVector2Array([base + perp * w, tip, base - perp * w]), Color(ORANGE, a))
	ci.draw_colored_polygon(PackedVector2Array([base + perp * w, base + perp * w * 0.4 + dir * s * 0.35, tip, base + dir * s * 0.1]), Color(YELLOW, a))
	for k in 3:
		var t := 0.18 + k * 0.22
		var p := base.lerp(tip, t)
		var ww := w * (1.0 - t)
		ci.draw_line(p + perp * ww, p - perp * ww + dir * 2.0, Color(ORANGE_DK, a), 1.0)
	ci.draw_rect(Rect2(base - dir * s * 0.1 - Vector2(2, 2), Vector2(4, 4)), Color(METAL_HI, a))


static func _jump(ci: CanvasItem, c: Vector2, s: float, a: float) -> void:
	var w := s * 0.45
	for k in 2:
		var y := c.y - s * 0.12 + k * s * 0.36
		ci.draw_polyline(PackedVector2Array([Vector2(c.x - w, y + w * 0.6), Vector2(c.x, y - w * 0.15), Vector2(c.x + w, y + w * 0.6)]), Color(CYAN, a), 3.0)


static func _bomb(ci: CanvasItem, c: Vector2, s: float, a: float) -> void:
	var r := s * 0.34
	var bc := c + Vector2(-s * 0.06, s * 0.1)
	ci.draw_circle(bc, r + 1.0, Color(OUTLINE, a))
	ci.draw_circle(bc, r, Color(ORANGE, a))
	ci.draw_circle(bc + Vector2(-r * 0.35, -r * 0.35), r * 0.35, Color(YELLOW, a))
	var neck := bc + Vector2(r * 0.6, -r * 0.6)
	ci.draw_rect(Rect2(neck - Vector2(2, 2), Vector2(4, 4)), Color(METAL_HI, a))
	var spark := neck + Vector2(s * 0.18, -s * 0.18)
	ci.draw_line(neck, spark, Color(TEXT, a), 1.0)
	for k in 6:
		var d := Vector2.RIGHT.rotated(k * TAU / 6.0)
		ci.draw_line(spark + d * 1.5, spark + d * s * 0.14, Color(YELLOW, a), 1.0)


static func _ladder(ci: CanvasItem, c: Vector2, s: float, a: float) -> void:
	var h := s * 0.5
	var w := s * 0.26
	var col := Color(YELLOW.lerp(ORANGE, 0.35), a)
	ci.draw_rect(Rect2(c.x - w - 1.0, c.y - h, 2, h * 2.0), col)
	ci.draw_rect(Rect2(c.x + w - 1.0, c.y - h, 2, h * 2.0), col)
	for k in 4:
		var y := c.y - h + 2.0 + k * (h * 2.0 - 4.0) / 3.0
		ci.draw_rect(Rect2(c.x - w, roundf(y), w * 2.0, 2), col)


static func _sonar(ci: CanvasItem, c: Vector2, s: float, a: float) -> void:
	var o := c + Vector2(0, s * 0.3)
	for k in 3:
		var r := s * (0.2 + k * 0.17)
		ci.draw_arc(o, r, PI * 1.05, PI * 1.95, 10, Color(CYAN, a * (1.0 - k * 0.2)), 2.0)
	ci.draw_line(o, o + Vector2(s * 0.25, -s * 0.38), Color(CYAN, a), 1.0)
	ci.draw_circle(o, 2.0, Color(CYAN, a))


static func _cryo(ci: CanvasItem, c: Vector2, s: float, a: float) -> void:
	for k in 3:
		var d := Vector2.RIGHT.rotated(k * PI / 3.0 + PI / 2.0) * s * 0.45
		ci.draw_line(c - d, c + d, Color(CYAN, a), 2.0)
		var e := d * 0.6
		var side := Vector2(-d.y, d.x).normalized() * s * 0.12
		ci.draw_line(c + e, c + e + side + d * 0.25, Color(CYAN, a), 1.0)
		ci.draw_line(c + e, c + e - side + d * 0.25, Color(CYAN, a), 1.0)


static func _lure(ci: CanvasItem, c: Vector2, s: float, a: float) -> void:
	var foot := c + Vector2(0, s * 0.42)
	ci.draw_rect(Rect2(foot.x - s * 0.22, foot.y - 2.0, s * 0.44, 2), Color(CYAN, a))
	ci.draw_rect(Rect2(c.x - 1.0, c.y - s * 0.1, 2, s * 0.5), Color(CYAN, a))
	ci.draw_circle(c + Vector2(0, -s * 0.16), 2.5, Color(CYAN, a))
	for k in 2:
		var r := s * (0.22 + k * 0.14)
		ci.draw_arc(c + Vector2(0, -s * 0.16), r, -PI * 0.85, -PI * 0.15, 8, Color(CYAN, a * (0.9 - k * 0.3)), 1.0)


static func _crate(ci: CanvasItem, c: Vector2, s: float, a: float) -> void:
	var r := Rect2(c - Vector2(s * 0.42, s * 0.38), Vector2(s * 0.84, s * 0.76))
	r = Rect2(r.position.round(), r.size.round())
	ci.draw_rect(r, Color(ORANGE_DK, a))
	ci.draw_rect(r.grow(-1.0), Color(ORANGE, a))
	ci.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.3, r.size.x, 1), Color(ORANGE_DK, a))
	ci.draw_line(r.position + Vector2(2, 2), r.end - Vector2(2, 2), Color(YELLOW, a), 1.0)
	ci.draw_line(Vector2(r.end.x - 2, r.position.y + 2), Vector2(r.position.x + 2, r.end.y - 2), Color(YELLOW, a), 1.0)


static func _pause(ci: CanvasItem, c: Vector2, s: float, a: float) -> void:
	var h := s * 0.5
	ci.draw_rect(Rect2(roundf(c.x - s * 0.25), roundf(c.y - h), 3, roundf(h * 2.0)), Color(TEXT, a))
	ci.draw_rect(Rect2(roundf(c.x + s * 0.25 - 3.0), roundf(c.y - h), 3, roundf(h * 2.0)), Color(TEXT, a))


static func _use(ci: CanvasItem, c: Vector2, s: float, a: float) -> void:
	var r := s * 0.32
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), Color(TEAL, a))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.45), c + Vector2(r * 0.45, 0), c + Vector2(0, r * 0.45), c + Vector2(-r * 0.45, 0)]), Color(INTERIOR, a))


## A small arrow (for the toolbar tab): dir -1 points left, +1 right.
static func arrow(ci: CanvasItem, c: Vector2, s: float, dir: int, col: Color) -> void:
	c = c.round()
	var w := s * 0.35
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(dir * w, 0), c + Vector2(-dir * w, -s * 0.5), c + Vector2(-dir * w, s * 0.5)]), col)
