class_name RunRelic
extends Node2D
## A rare find that changes the current run (S7 of the fun pass). Taken with
## USE; its effect lasts until the run ends. Drawn in code.

var mine: Node
var id := 0
var group := 0          # relics sharing a group > 0 are a choice: take one, the rest crumble
var used := false
var _t := 0.0
var _glow: Sprite2D


func _ready() -> void:
	var col := Color(Balance.RUN_RELICS[id]["color"])
	_glow = Sprite2D.new()
	_glow.texture = load("res://assets/gen/glow.png")
	_glow.modulate = Color(col, 0.55)
	_glow.scale = Vector2(0.45, 0.45)
	add_child(_glow)
	var light := PointLight2D.new()
	light.texture = load("res://assets/gen/light.png")
	light.color = col
	light.energy = 0.7
	light.texture_scale = 0.3
	add_child(light)


func _process(delta: float) -> void:
	_t += delta
	_glow.modulate.a = 0.45 + 0.15 * sin(_t * 2.4)
	queue_redraw()


func _draw() -> void:
	var col := Color(Balance.RUN_RELICS[id]["color"])
	var bob := sin(_t * 2.0) * 1.5
	# a small plinth and a floating rune stone that turns slowly
	draw_rect(Rect2(-6, 5, 12, 3), Color("4a4252"))
	draw_rect(Rect2(-4, 3, 8, 2), Color("6e617b"))
	var c := Vector2(0, -3 + bob)
	var r := 5.0
	var pts := PackedVector2Array()
	for k in 6:
		pts.append(c + Vector2.RIGHT.rotated(_t * 0.8 + k * TAU / 6.0) * Vector2(r, r * 1.2))
	draw_colored_polygon(pts, col.darkened(0.25))
	draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.3), 1.0)
	draw_circle(c, 1.6, Color(1, 1, 1, 0.75 + 0.25 * sin(_t * 4.0)))


func take() -> void:
	if used or mine.ending:
		return
	used = true
	var info: Dictionary = Balance.RUN_RELICS[id]
	var relics: Array = Game.run["relics"]
	if not relics.has(info["id"]):
		relics.append(info["id"])
	if info["id"] == "spine" and mine.player:
		mine.player.max_hp += Balance.SPINE_HULL
		mine.player.hp = mine.player.max_hp
	Audio.play("lift_ding", -2.0)
	mine.hud.banner(String(info["name"]).to_upper())
	mine.toast("RUN RELIC: %s" % info["desc"])
	mine.run_relics.erase(self)
	if group > 0:
		for other in mine.run_relics.duplicate():
			if other.group == group and not other.used:
				other.crumble()
	hide()
	queue_free()


## The road not taken: it falls to dust.
func crumble() -> void:
	used = true
	mine.fx.dust(global_position, Color(Balance.RUN_RELICS[id]["color"]), 8)
	mine.fx.burst(global_position, Color(0.6, 0.55, 0.6), 8)
	mine.toast("The other relic crumbles to dust - %s is gone" % Balance.RUN_RELICS[id]["name"])
	mine.run_relics.erase(self)
	queue_free()
