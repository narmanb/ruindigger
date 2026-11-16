extends Node
## Boot node: hands control to the Game screen flow.

func _ready() -> void:
	Game.goto.call_deferred("title", true)
