extends Node
## Registers keyboard, gamepad and (via project settings) touch actions so the
## game works the same everywhere. Touch input is handled by the on-screen
## controls, which feed the same action names.

const KEY_ACTIONS := {
	"move_left":  [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up":    [KEY_W, KEY_UP],
	"move_down":  [KEY_S, KEY_DOWN],
	"jump":       [KEY_SPACE, KEY_K],
	"drill":      [KEY_J, KEY_L],
	"charge":     [KEY_B, KEY_I],
	"interact":   [KEY_E, KEY_ENTER],
	"pause":      [KEY_ESCAPE, KEY_P],
	"map":        [KEY_TAB],
	"debug_toggle": [KEY_F3],
	"restart":    [KEY_R],
}

const JOY_BUTTON_ACTIONS := {
	"move_left":  [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"move_up":    [JOY_BUTTON_DPAD_UP],
	"move_down":  [JOY_BUTTON_DPAD_DOWN],
	"jump":       [JOY_BUTTON_A],
	"drill":      [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER],
	"charge":     [JOY_BUTTON_B, JOY_BUTTON_LEFT_SHOULDER],
	"interact":   [JOY_BUTTON_Y],
	"pause":      [JOY_BUTTON_START],
	"map":        [JOY_BUTTON_BACK],
}

const JOY_AXIS_ACTIONS := {
	"move_left":  [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up":    [JOY_AXIS_LEFT_Y, -1.0],
	"move_down":  [JOY_AXIS_LEFT_Y, 1.0],
}

func _ready() -> void:
	for action_name in KEY_ACTIONS.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
	for action_name in KEY_ACTIONS:
		for key in KEY_ACTIONS[action_name]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action_name, ev)
	for action_name in JOY_BUTTON_ACTIONS:
		for button in JOY_BUTTON_ACTIONS[action_name]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action_name, ev)
	for action_name in JOY_AXIS_ACTIONS:
		var spec = JOY_AXIS_ACTIONS[action_name]
		var ev := InputEventJoypadMotion.new()
		ev.axis = spec[0]
		ev.axis_value = spec[1]
		InputMap.action_add_event(action_name, ev)
