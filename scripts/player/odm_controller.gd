class_name ODMController
extends Node
## Dual-hook ODM: latch, swing constraint, reel, gas boost.

signal gas_changed(current: float, maximum: float)
signal hooks_changed(left_attached: bool, right_attached: bool)
signal hook_fired(is_left: bool)
signal hook_latched(is_left: bool)
signal hook_detached(is_left: bool)
signal boosted

@export var max_cable_length: float = 45.0
@export var min_cable_length: float = 1.5
@export var pull_strength: float = 28.0
@export var dual_pull_multiplier: float = 1.35
@export var reel_speed: float = 14.0
@export var swing_damping: float = 0.15
@export var boost_impulse: float = 16.0
@export var boost_max_speed: float = 28.0
@export var air_control: float = 8.0
@export var gas_max: float = 100.0
@export var gas_boost_drain: float = 28.0 ## per second while boosting
@export var gas_reel_drain: float = 4.0 ## per second while reeling
@export var look_aim_height: float = 1.2
## Physics layer bit for grappleable surfaces (layer 2).
@export var grapple_collision_mask: int = 2

var gas: float = 100.0

var _player: CharacterBody3D
var _camera: Camera3D
var _left_hook: ODMHook
var _right_hook: ODMHook
var _left_socket: Marker3D
var _right_socket: Marker3D
var _boosting: bool = false


func setup(player: CharacterBody3D, camera: Camera3D, gear_root: Node3D) -> void:
	_player = player
	_camera = camera
	gas = gas_max

	_left_socket = gear_root.get_node_or_null("LeftSocket") as Marker3D
	_right_socket = gear_root.get_node_or_null("RightSocket") as Marker3D
	if _left_socket == null:
		_left_socket = Marker3D.new()
		_left_socket.name = "LeftSocket"
		_left_socket.position = Vector3(-0.25, 0.9, 0.05)
		gear_root.add_child(_left_socket)
	if _right_socket == null:
		_right_socket = Marker3D.new()
		_right_socket.name = "RightSocket"
		_right_socket.position = Vector3(0.25, 0.9, 0.05)
		gear_root.add_child(_right_socket)

	_left_hook = gear_root.get_node_or_null("LeftHook") as ODMHook
	_right_hook = gear_root.get_node_or_null("RightHook") as ODMHook
	if _left_hook == null:
		_left_hook = ODMHook.new()
		_left_hook.name = "LeftHook"
		_left_hook.is_left = true
		gear_root.add_child(_left_hook)
	if _right_hook == null:
		_right_hook = ODMHook.new()
		_right_hook.name = "RightHook"
		_right_hook.is_left = false
		_right_hook.cable_color = Color(0.2, 0.18, 0.16)
		gear_root.add_child(_right_hook)

	gas_changed.emit(gas, gas_max)
	hooks_changed.emit(false, false)


func set_camera(camera: Camera3D) -> void:
	_camera = camera


func is_active() -> bool:
	return _left_hook.is_attached() or _right_hook.is_attached() or _boosting


func is_hooked() -> bool:
	return _left_hook.is_attached() or _right_hook.is_attached()


func get_gas() -> float:
	return gas


func get_gas_max() -> float:
	return gas_max


func refill_gas(amount: float = -1.0) -> void:
	if amount < 0.0:
		gas = gas_max
	else:
		gas = minf(gas_max, gas + amount)
	gas_changed.emit(gas, gas_max)


func left_attached() -> bool:
	return _left_hook != null and _left_hook.is_attached()


func right_attached() -> bool:
	return _right_hook != null and _right_hook.is_attached()


func ensure_input_actions() -> void:
	_add_mouse_action("odm_hook_left", MOUSE_BUTTON_LEFT)
	_add_mouse_action("odm_hook_right", MOUSE_BUTTON_RIGHT)
	_add_key_action("odm_hook_left", KEY_Q)
	_add_key_action("odm_hook_right", KEY_E)
	_add_key_action("odm_boost", KEY_SHIFT)


func physics_tick(delta: float) -> void:
	if _player == null:
		return
	if _camera == null:
		_camera = _player.get_viewport().get_camera_3d()

	_handle_hook_input()
	_apply_reel(delta)
	_apply_cable_constraints(delta)
	_apply_air_steer(delta)
	_apply_boost(delta)
	_update_cable_visuals()


func _handle_hook_input() -> void:
	_update_single_hook(_left_hook, "odm_hook_left", true)
	_update_single_hook(_right_hook, "odm_hook_right", false)


func _update_single_hook(hook: ODMHook, action: StringName, is_left: bool) -> void:
	if Input.is_action_just_pressed(action):
		hook_fired.emit(is_left)
		if _try_fire(hook):
			hook_latched.emit(is_left)
			hooks_changed.emit(left_attached(), right_attached())
	elif Input.is_action_just_released(action):
		if hook.is_attached():
			hook.detach()
			hook_detached.emit(is_left)
			hooks_changed.emit(left_attached(), right_attached())


func _try_fire(hook: ODMHook) -> bool:
	var origin := _aim_origin()
	var direction := _aim_direction()
	var space := _player.get_world_3d().direct_space_state
	var ok := hook.fire(origin, direction, max_cable_length, space, grapple_collision_mask)
	if ok and hook.cable_length > max_cable_length:
		hook.detach()
		return false
	return ok


func _aim_origin() -> Vector3:
	if _camera:
		return _camera.global_position
	return _player.global_position + Vector3.UP * look_aim_height


func _aim_direction() -> Vector3:
	if _camera:
		return -_camera.global_transform.basis.z
	return -_player.global_transform.basis.z


func _socket_global(is_left: bool) -> Vector3:
	var socket := _left_socket if is_left else _right_socket
	if socket:
		return socket.global_position
	return _player.global_position + Vector3((-0.25 if is_left else 0.25), 0.9, 0.0)


func _apply_reel(delta: float) -> void:
	var reeling := false
	if _left_hook.is_attached() and Input.is_action_pressed("odm_hook_left"):
		_left_hook.shorten(reel_speed * delta, min_cable_length)
		reeling = true
	if _right_hook.is_attached() and Input.is_action_pressed("odm_hook_right"):
		_right_hook.shorten(reel_speed * delta, min_cable_length)
		reeling = true
	if reeling and gas_reel_drain > 0.0:
		_spend_gas(gas_reel_drain * delta)


func _apply_cable_constraints(delta: float) -> void:
	var anchors: Array[Vector3] = []
	var lengths: Array[float] = []
	if _left_hook.is_attached():
		anchors.append(_left_hook.anchor_point)
		lengths.append(_left_hook.cable_length)
	if _right_hook.is_attached():
		anchors.append(_right_hook.anchor_point)
		lengths.append(_right_hook.cable_length)
	if anchors.is_empty():
		return

	var pull_scale := dual_pull_multiplier if anchors.size() > 1 else 1.0
	var player_pos := _player.global_position + Vector3.UP * 0.9

	for i in anchors.size():
		var to_anchor: Vector3 = anchors[i] - player_pos
		var dist := to_anchor.length()
		var max_len: float = lengths[i]
		if dist <= 0.001:
			continue
		var dir := to_anchor / dist

		# Soft pull toward slack removal + hard clamp beyond cable length.
		if dist > max_len:
			var excess := dist - max_len
			_player.velocity += dir * excess * pull_strength * pull_scale * delta
			# Kill outward radial velocity so swing stays on the sphere.
			var radial_speed := _player.velocity.dot(-dir)
			if radial_speed > 0.0:
				_player.velocity += dir * radial_speed
			# Nudge position back inside the cable sphere.
			var correction := dir * excess
			_player.global_position += correction * minf(1.0, 12.0 * delta)
		else:
			# Mild attract while holding for classic ODM "pull in" feel.
			var slack_factor := 1.0 - (dist / maxf(max_len, 0.01))
			_player.velocity += dir * pull_strength * 0.35 * pull_scale * (0.35 + slack_factor) * delta

	# Light damping so swings don't explode.
	var horizontal := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	horizontal = horizontal.lerp(Vector3.ZERO, swing_damping * delta)
	_player.velocity.x = horizontal.x
	_player.velocity.z = horizontal.z


func _apply_air_steer(delta: float) -> void:
	if not is_hooked() and _player.is_on_floor():
		return
	if not is_active():
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir == Vector2.ZERO or _camera == null:
		return
	var basis := _camera.global_transform.basis
	var forward := -basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	var wish := (forward * -input_dir.y + right * input_dir.x).normalized()
	_player.velocity += wish * air_control * delta


func _apply_boost(delta: float) -> void:
	var was_boosting := _boosting
	_boosting = false
	var wants_boost := Input.is_action_pressed("odm_boost")
	var can_boost := wants_boost and (is_hooked() or not _player.is_on_floor()) and gas > 0.0
	if not can_boost:
		return

	_boosting = true
	var boost_dir := _aim_direction()
	# Bias slightly along current velocity for continuity.
	if _player.velocity.length() > 1.0:
		boost_dir = (boost_dir + _player.velocity.normalized() * 0.35).normalized()
	_player.velocity += boost_dir * boost_impulse * delta
	if _player.velocity.length() > boost_max_speed:
		_player.velocity = _player.velocity.normalized() * boost_max_speed
	_spend_gas(gas_boost_drain * delta)
	if not was_boosting:
		boosted.emit()


func _spend_gas(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if gas <= 0.0:
		gas = 0.0
		return false
	gas = maxf(0.0, gas - amount)
	gas_changed.emit(gas, gas_max)
	return true


func _update_cable_visuals() -> void:
	if _left_hook:
		_left_hook.update_visual(_socket_global(true))
	if _right_hook:
		_right_hook.update_visual(_socket_global(false))


func _add_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == keycode:
			return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _add_mouse_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventMouseButton and existing.button_index == button:
			return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
