extends CanvasLayer
## ESC pause overlay with Continue and Back to menu.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const THEME := preload("res://scenes/ui/hud_theme.tres")

var _panel: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	visible = false
	_build_ui()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_set_paused(not get_tree().paused)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func _on_back_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _build_ui() -> void:
	var root := Control.new()
	root.theme = THEME
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var cont := _button("Continue")
	cont.pressed.connect(func() -> void: _set_paused(false))
	box.add_child(cont)
	var back := _button("Back to menu")
	back.pressed.connect(_on_back_pressed)
	box.add_child(back)
	visibility_changed.connect(func() -> void:
		if visible:
			cont.grab_focus())


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	b.add_theme_constant_override("shadow_offset_x", 3)
	b.add_theme_constant_override("shadow_offset_y", 3)
	b.custom_minimum_size = Vector2(280, 56)
	b.add_theme_font_size_override("font_size", 28)
	return b
