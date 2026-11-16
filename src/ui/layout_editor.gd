class_name LayoutEditor
extends CanvasLayer
## Drag-to-arrange editor for the touch controls. Shows the controls at their
## real size and position; every drag is saved straight to Settings.

var controls: TouchControls


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.03, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	controls = TouchControls.new()
	controls.edit_mode = true
	root.add_child(controls)
	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -150
	top.offset_right = 150
	top.offset_top = 10
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(top)
	var title := UIKit.label("DRAG ANY CONTROL TO MOVE IT", 12, UIKit.AMBER, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	top.add_child(row)
	row.add_child(UIKit.button("RESET LAYOUT", Settings.reset_layout, 120.0))
	var done := UIKit.button("DONE", queue_free, 90.0)
	row.add_child(done)
	done.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		queue_free()
