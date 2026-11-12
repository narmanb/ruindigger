class_name ZoneKeepsake
extends Node2D
## A small glowing zone souvenir, recovered with the normal USE interaction.

var mine: Node
var id := 0
var used := false
var _time := 0.0
var _glow: Sprite2D


func _ready() -> void:
	var color := Color(Balance.KEEPSAKES[id]["color"])
	_glow = Sprite2D.new()
	_glow.texture = load("res://assets/gen/glow.png")
	_glow.modulate = Color(color, 0.5)
	_glow.scale = Vector2(0.35, 0.35)
	add_child(_glow)
	var light := PointLight2D.new()
	light.texture = load("res://assets/gen/light.png")
	light.color = color
	light.energy = 0.6
	light.texture_scale = 0.25
	add_child(light)


func _process(delta: float) -> void:
	_time += delta
	_glow.modulate.a = 0.45 + 0.1 * sin(_time * 3.0)


func _draw() -> void:
	var color := Color(Balance.KEEPSAKES[id]["color"])
	draw_line(Vector2(-7, 7), Vector2(7, 7), Color("6e617b"), 2)
	match id:
		0:
			draw_circle(Vector2.ZERO, 5, color)
			draw_line(Vector2(0, -3), Vector2(0, 3), Color("8a5a22"), 2)
		1:
			draw_rect(Rect2(-3, -4, 6, 9), color)
			draw_rect(Rect2(-2, -6, 4, 2), UIKit.TEXT)
			draw_line(Vector2(-1, -2), Vector2(-1, 2), Color.WHITE)
		2:
			for k in 8:
				var d := Vector2.RIGHT.rotated(k * TAU / 8)
				draw_line(d * 3, d * 6, color, 2)
			draw_circle(Vector2.ZERO, 4, color)
			draw_circle(Vector2.ZERO, 2, UIKit.PANEL)
		3:
			draw_rect(Rect2(-5, -5, 10, 10), color)
			draw_line(Vector2(-3, -2), Vector2(3, -2), UIKit.PANEL, 2)
			draw_line(Vector2(-3, 2), Vector2(3, 2), UIKit.PANEL, 2)
		4:
			for k in 3:
				var centre := Vector2((k - 1) * 4, -abs(k - 1) * 2)
				draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -6), centre + Vector2(3, 0), centre + Vector2(0, 5), centre + Vector2(-3, 0)]), color)
		5:
			# a bronze ring holding a warm lens
			draw_arc(Vector2(0, -1), 5.5, 0, TAU, 16, Color("b59a5e"), 2.0)
			draw_circle(Vector2(0, -1), 3.5, color)
			draw_circle(Vector2(-1, -2), 1.2, Color(1, 1, 1, 0.8))


func take() -> void:
	if used or mine.ending:
		return
	used = true
	var finds: Array = Game.run["finds"]
	if not finds.has(id):
		finds.append(id)
		Audio.play("pickup", -3.0)
		mine.toast("RECOVERED: %s - extract to bank %d CR" % [Balance.KEEPSAKES[id]["name"], Balance.KEEPSAKES[id]["value"]])
		mine.hud.pulse_cargo()
	mine.keepsakes.erase(self)
	hide()
	queue_free()
