extends Node3D
## Title screen: forest flyover behind a title, controls list and Play button.

const GAME_SCENE := "res://scenes/world/forest_world.tscn"
const ORBIT_RADIUS := 45.0
const ORBIT_HEIGHT := 14.0
const ORBIT_SPEED := 0.05
const HOW_TO_PLAY := """Swing through the forest with your ODM gear.

- Aim at a tree or surface and fire a hook (Q / E). Each hook anchors where it lands.
- Your reticle will change when you're aiming at a hookable surface.
- Hold Shift while airborne or hooked to burst gas and gain speed. Gas is limited, so watch the gauge.
- Toggle the reel with R to pull yourself toward your anchors.
- Land on supply platforms and press F near a supplier to refill gas.
- Attack with your blades by clicking. Titans are vulnerable at the back of their neck.
- Titans can attack you by swatting and grabbing, so keep moving.
- Your health regenerates slowly, so be careful."""
const CONTROLS := [
	["W A S D", "Move"],
	["Mouse", "Look"],
	["Space", "Jump"],
	["Left/Right Click", "Swing left/right sword"],
	["Shift", "Sprint / Gas boost (while hooked)"],
	["Ctrl", "Crouch / Slide"],
	["Q/E", "Fire left/right hook"],
	["E", "Fire right hook"],
	["R", "Toggle reel in"],
	["V", "Cycle camera"],
	["F", "Interact"],
	["Esc", "Pause"],
]

var _angle := 0.0
var _how_panel: Control
@onready var _camera: Camera3D = $Camera3D
@onready var _root: Control = %Root


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_update_camera()


func _process(delta: float) -> void:
	_angle += delta * ORBIT_SPEED
	_update_camera()


func _update_camera() -> void:
	var pos := Vector3(cos(_angle), 0.0, sin(_angle)) * ORBIT_RADIUS
	pos.y = ORBIT_HEIGHT
	_camera.position = pos
	_camera.look_at(Vector3(0.0, ORBIT_HEIGHT * 0.6, 0.0))


func _build_ui() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	_root.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 80)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 32)
	row.add_child(left)

	var title := Label.new()
	title.text = "ODM TEST"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	left.add_child(title)

	var play := Button.new()
	play.text = "Play"
	play.custom_minimum_size = Vector2(240, 64)
	play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	play.add_theme_font_size_override("font_size", 32)
	_style_button(play)
	play.pressed.connect(_on_play_pressed)
	left.add_child(play)
	play.grab_focus()

	var how := Button.new()
	how.text = "How to play"
	how.custom_minimum_size = Vector2(240, 56)
	how.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	how.add_theme_font_size_override("font_size", 26)
	_style_button(how)
	how.pressed.connect(func() -> void: _how_panel.visible = true)
	left.add_child(how)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(pad)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 8)
	pad.add_child(grid)

	var header := Label.new()
	header.text = "CONTROLS"
	header.add_theme_font_size_override("font_size", 28)
	grid.add_child(header)
	grid.add_child(Control.new())
	for entry in CONTROLS:
		var key := Label.new()
		key.text = entry[0]
		key.add_theme_color_override("font_color", Color(0.85, 0.95, 0.7))
		grid.add_child(key)
		var action := Label.new()
		action.text = entry[1]
		grid.add_child(action)
	_build_how_to_play()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _build_how_to_play() -> void:
	_how_panel = Control.new()
	_how_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_how_panel.visible = false
	_root.add_child(_how_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_how_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_how_panel.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 32)
	panel.add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	pad.add_child(box)

	var header := Label.new()
	header.text = "HOW TO PLAY"
	header.add_theme_font_size_override("font_size", 40)
	box.add_child(header)

	var body := Label.new()
	body.text = HOW_TO_PLAY
	body.custom_minimum_size.x = 640
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 20)
	box.add_child(body)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(200, 52)
	back.add_theme_font_size_override("font_size", 24)
	_style_button(back)
	back.pressed.connect(func() -> void: _how_panel.visible = false)
	box.add_child(back)


func _unhandled_input(event: InputEvent) -> void:
	if _how_panel.visible and event.is_action_pressed("ui_cancel"):
		_how_panel.visible = false
		get_viewport().set_input_as_handled()


func _style_button(b: Button) -> void:
	b.text = b.text.to_upper()
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	b.add_theme_constant_override("shadow_offset_x", 3)
	b.add_theme_constant_override("shadow_offset_y", 3)
