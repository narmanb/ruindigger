extends Node
## Builds the input map in code so keyboard, gamepad and touch share actions.

signal device_changed(kind: String)

var last_device := "keyboard"  # keyboard | gamepad | touch

const KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"aim_up": [KEY_W, KEY_UP],
	"aim_down": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE, KEY_Z],
	"drill": [KEY_J, KEY_X, KEY_SHIFT],
	"charge": [KEY_K, KEY_C],
	"interact": [KEY_E, KEY_F],
	"pause": [KEY_ESCAPE, KEY_P],
	"map": [KEY_M, KEY_TAB],
}

const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"interact": [JOY_BUTTON_Y, JOY_BUTTON_X],
	"charge": [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_B],
	"drill": [JOY_BUTTON_RIGHT_SHOULDER],
	"pause": [JOY_BUTTON_START],
	"map": [JOY_BUTTON_BACK],
	"move_left": [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"aim_up": [JOY_BUTTON_DPAD_UP],
	"aim_down": [JOY_BUTTON_DPAD_DOWN],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for action in KEYS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.35)
		for k in KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for action in PAD_BUTTONS.keys():
		for b in PAD_BUTTONS[action]:
			var e := InputEventJoypadButton.new()
			e.button_index = b
			e.device = -1
			InputMap.action_add_event(action, e)
	_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("aim_up", JOY_AXIS_LEFT_Y, -1.0)
	_axis("aim_down", JOY_AXIS_LEFT_Y, 1.0)
	_axis("drill", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_axis("charge", JOY_AXIS_TRIGGER_LEFT, 1.0)
	# UI navigation with the gamepad works through ui_* defaults; add shoulder tabs
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var e := InputEventJoypadButton.new()
		e.button_index = pair[1]
		InputMap.action_add_event(pair[0], e)


func _axis(action: String, axis: int, dir: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = dir
	e.device = -1
	InputMap.action_add_event(action, e)


func _input(event: InputEvent) -> void:
	var kind := last_device
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		kind = "touch"
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		kind = "gamepad"
	elif event is InputEventKey:
		kind = "keyboard"
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		kind = "keyboard"
	if kind != last_device:
		last_device = kind
		device_changed.emit(kind)
