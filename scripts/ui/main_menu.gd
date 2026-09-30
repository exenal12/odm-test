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
- Titans can attack you by swatting, stomping, and grabbing, so keep moving.
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
var _settings_panel: Control
var _settings_scroll: ScrollContainer
var _settings_controls: Dictionary = {}
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
	left.add_theme_constant_override("separation", 24)
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

	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.custom_minimum_size = Vector2(240, 56)
	settings_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	settings_btn.add_theme_font_size_override("font_size", 26)
	_style_button(settings_btn)
	settings_btn.pressed.connect(func() -> void:
		_refresh_settings_ui()
		_settings_panel.visible = true)
	left.add_child(settings_btn)

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
	_build_settings()


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


func _build_settings() -> void:
	_settings_panel = Control.new()
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.visible = false
	_root.add_child(_settings_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.add_child(dim)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 40)
	_settings_panel.add_child(outer)

	var align := HBoxContainer.new()
	align.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(align)

	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	align.add_child(spacer_l)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	align.add_child(panel)

	var spacer_r := Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	align.add_child(spacer_r)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(box)

	var header := Label.new()
	header.text = "SETTINGS"
	header.add_theme_font_size_override("font_size", 36)
	box.add_child(header)

	var note := Label.new()
	note.text = "Changes apply for this session only and reset when the game closes."
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.75, 0.8, 0.7))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_settings_scroll = scroll

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	_add_section(list, "GAMEPLAY")
	_settings_controls["player_max_health"] = _add_slider(
		list, "Player health", 50.0, 300.0, 5.0, "%.0f",
		func(v: float) -> void: GameSettings.player_max_health = v)
	_settings_controls["odm_speed_scale"] = _add_slider(
		list, "ODM speed", 0.5, 2.0, 0.05, "%.2fx",
		func(v: float) -> void: GameSettings.odm_speed_scale = v)
	_settings_controls["gas_max"] = _add_slider(
		list, "Gas amount", 25.0, 200.0, 5.0, "%.0f",
		func(v: float) -> void: GameSettings.gas_max = v)
	_settings_controls["gas_boost_drain"] = _add_slider(
		list, "Gas boost usage /s", 1.0, 50.0, 1.0, "%.0f",
		func(v: float) -> void: GameSettings.gas_boost_drain = v)
	_settings_controls["gas_reel_drain"] = _add_slider(
		list, "Gas reel usage /s", 0.0, 20.0, 0.5, "%.1f",
		func(v: float) -> void: GameSettings.gas_reel_drain = v)
	_settings_controls["titan_spawn_rate"] = _add_slider(
		list, "Titan spawn rate", 0.25, 3.0, 0.05, "%.2fx",
		func(v: float) -> void: GameSettings.titan_spawn_rate = v)
	_settings_controls["soldier_spawn_rate"] = _add_slider(
		list, "Soldier spawn rate", 0.25, 3.0, 0.05, "%.2fx",
		func(v: float) -> void: GameSettings.soldier_spawn_rate = v)

	_add_section(list, "DEBUG")
	_settings_controls["debug_sword_hitboxes"] = _add_checkbox(
		list, "Show sword hitboxes",
		func(on: bool) -> void: GameSettings.debug_sword_hitboxes = on)
	_settings_controls["debug_titan_hitboxes"] = _add_checkbox(
		list, "Show titan attack hitboxes",
		func(on: bool) -> void: GameSettings.debug_titan_hitboxes = on)
	_settings_controls["debug_titan_ai"] = _add_checkbox(
		list, "Show titan AI status",
		func(on: bool) -> void: GameSettings.debug_titan_ai = on)
	_settings_controls["debug_soldier_ai"] = _add_checkbox(
		list, "Show soldier AI status",
		func(on: bool) -> void: GameSettings.debug_soldier_ai = on)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)

	var reset := Button.new()
	reset.text = "Reset to default"
	reset.custom_minimum_size = Vector2(240, 48)
	reset.add_theme_font_size_override("font_size", 22)
	_style_button(reset)
	reset.pressed.connect(_on_reset_settings)
	buttons.add_child(reset)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 48)
	back.add_theme_font_size_override("font_size", 22)
	_style_button(back)
	back.pressed.connect(func() -> void:
		GameSettings.notify_changed()
		_settings_panel.visible = false)
	buttons.add_child(back)

	_refresh_settings_ui()


func _add_section(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.7))
	parent.add_child(label)


func _add_slider(
	parent: Control,
	title: String,
	min_v: float,
	max_v: float,
	step: float,
	format: String,
	on_change: Callable,
) -> Dictionary:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var top := HBoxContainer.new()
	row.add_child(top)
	var name := Label.new()
	name.text = title
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_font_size_override("font_size", 18)
	top.add_child(name)
	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.7))
	top.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 28)
	slider.gui_input.connect(_on_settings_slider_gui_input.bind(slider))
	row.add_child(slider)

	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = format % v
		on_change.call(v))

	return {"slider": slider, "label": value_label, "format": format}


## Wheel over a slider should scroll the settings list, not nudge the value.
func _on_settings_slider_gui_input(event: InputEvent, slider: Control) -> void:
	if event is not InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	slider.accept_event()
	if _settings_scroll == null:
		return
	var delta := int(round(event.factor * 40.0))
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_settings_scroll.scroll_vertical -= delta
	else:
		_settings_scroll.scroll_vertical += delta


func _add_checkbox(parent: Control, title: String, on_change: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = title
	box.add_theme_font_size_override("font_size", 18)
	# HUD Button styles inherit onto CheckBox; clear them so checked/hover
	# don't draw the menu button frame over the checkbox icon.
	var empty := StyleBoxEmpty.new()
	for style in ["normal", "pressed", "hover", "hover_pressed", "disabled", "focus"]:
		box.add_theme_stylebox_override(style, empty)
	box.add_theme_constant_override("h_separation", 12)
	box.add_theme_color_override("font_color", Color(0.88, 0.84, 0.74))
	box.add_theme_color_override("font_pressed_color", Color(0.88, 0.84, 0.74))
	box.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.82))
	box.add_theme_color_override("font_hover_pressed_color", Color(1.0, 0.92, 0.82))
	box.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	box.add_theme_constant_override("outline_size", 3)
	box.toggled.connect(on_change)
	parent.add_child(box)
	return box


func _refresh_settings_ui() -> void:
	var snap := GameSettings.snapshot()
	for key in ["player_max_health", "odm_speed_scale", "gas_max", "gas_boost_drain",
			"gas_reel_drain", "titan_spawn_rate", "soldier_spawn_rate"]:
		var ctrl: Dictionary = _settings_controls[key]
		var slider: HSlider = ctrl["slider"]
		slider.set_value_no_signal(float(snap[key]))
		(ctrl["label"] as Label).text = (ctrl["format"] as String) % float(snap[key])
	for key in ["debug_sword_hitboxes", "debug_titan_hitboxes", "debug_titan_ai", "debug_soldier_ai"]:
		(_settings_controls[key] as CheckBox).set_pressed_no_signal(bool(snap[key]))


func _on_reset_settings() -> void:
	GameSettings.reset_to_defaults()
	_refresh_settings_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _settings_panel.visible:
			GameSettings.notify_changed()
			_settings_panel.visible = false
			get_viewport().set_input_as_handled()
		elif _how_panel.visible:
			_how_panel.visible = false
			get_viewport().set_input_as_handled()


func _style_button(b: Button) -> void:
	b.text = b.text.to_upper()
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	b.add_theme_constant_override("shadow_offset_x", 3)
	b.add_theme_constant_override("shadow_offset_y", 3)
