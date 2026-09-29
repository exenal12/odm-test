class_name ODMController
extends Node
## Dual-hook ODM: latch, swing constraint, reel, gas boost.

## Emitted whenever current or maximum gas changes.
signal gas_changed(current: float, maximum: float)
## Emitted whenever either hook changes attachment state.
signal hooks_changed(left_attached: bool, right_attached: bool)
## Emitted immediately when a hook fire input is accepted.
signal hook_fired(is_left: bool)
## Emitted after a hook successfully finds an anchor.
signal hook_latched(is_left: bool)
## Emitted when an attached hook is released.
signal hook_detached(is_left: bool)
## Emitted once when a boost begins.
signal boosted
## Emitted when the reel mode is toggled.
signal reel_mode_changed(enabled: bool)

## Maximum distance a hook cable may extend.
@export var max_cable_length: float = 45.0
## Minimum cable distance allowed while reeling.
@export var min_cable_length: float = 1.5
## Strength of the cable pull toward an anchor.
@export var pull_strength: float = 28.0
## Additional pull multiplier applied when both hooks are attached.
@export var dual_pull_multiplier: float = 1.35
## Player travel speed and cable shortening rate while reel mode is on.
@export_range(0.0, 100.0, 0.5, "or_greater") var reel_speed: float = 14.0
## Extra reel speed when both hooks are attached (1.0 matches one hook).
@export_range(0.0, 5.0, 0.05, "or_greater") var dual_reel_speed_multiplier: float = 1.35
## How quickly extra speed (boost or carried momentum) fades while reeling.
@export_range(0.0, 20.0, 0.1, "or_greater") var reel_boost_decay: float = 1.0
## Hard upper limit on speed while reeling; speed above reel speed is kept up to this.
@export_range(0.0, 200.0, 0.5, "or_greater") var max_grapple_speed: float = 45.0
## Maximum portion of reel speed that a single hook may carry sideways.
@export_range(0.0, 0.8, 0.05) var single_hook_arc_ratio: float = 0.35
## Rate at which sideways momentum settles during a single-hook reel.
@export_range(0.0, 10.0, 0.1) var single_hook_arc_damping: float = 1.5
## Horizontal velocity damping applied during swings.
@export var swing_damping: float = 0.15
## Acceleration added in the boost direction.
@export var boost_impulse: float = 16.0
## Maximum total velocity allowed during a boost.
@export var boost_max_speed: float = 28.0
## Camera-relative steering strength while airborne or hooked.
@export var air_control: float = 8.0
## Maximum gas capacity.
@export var gas_max: float = 100.0
## Gas consumed per second while boosting.
@export var gas_boost_drain: float = 28.0 ## per second while boosting
## Gas consumed per second while reeling.
@export var gas_reel_drain: float = 4.0 ## per second while reeling
## Height above the player used when aiming without a camera.
@export var look_aim_height: float = 1.2
## Physics layer bit for grappleable surfaces (layer 2).
@export var grapple_collision_mask: int = 2

## When true, hooks/boost/steering come from the ai_* API instead of Input.
@export var ai_controlled: bool = false

var gas: float = 100.0
## AI intent: world-space steering direction and boost hold.
var ai_steer: Vector3 = Vector3.ZERO
var ai_boost: bool = false

var _ai_fire: Array[bool] = [false, false]
var _ai_release: Array[bool] = [false, false]
var _aim_origin_override: Vector3 = Vector3.ZERO
var _aim_dir_override: Vector3 = Vector3.ZERO

var _player: CharacterBody3D
var _camera: Camera3D
var _left_hook: ODMHook
var _right_hook: ODMHook
var _left_socket: Marker3D
var _right_socket: Marker3D
var _boosting: bool = false
var _reel_boost_bonus: float = 0.0
var reel_enabled: bool = true


## Binds the controller to the player, camera, and ODM gear, creating missing
## sockets or hook nodes before announcing the initial empty state.
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
	reel_mode_changed.emit(reel_enabled)


## Updates the camera used to aim newly fired hooks and boost direction.
func set_camera(camera: Camera3D) -> void:
	_camera = camera


## Reports whether any hook is attached or the gas boost is currently active.
func is_active() -> bool:
	return _left_hook.is_attached() or _right_hook.is_attached() or _boosting


## Reports whether at least one hook is currently attached.
func is_hooked() -> bool:
	return _left_hook.is_attached() or _right_hook.is_attached()


## Returns the current gas amount for HUD and gameplay consumers.
func get_gas() -> float:
	return gas


## Returns the configured maximum gas capacity.
func get_gas_max() -> float:
	return gas_max


func is_reel_enabled() -> bool:
	return reel_enabled


func set_reel_enabled(enabled: bool) -> void:
	if reel_enabled == enabled:
		return
	reel_enabled = enabled
	reel_mode_changed.emit(reel_enabled)


## AI: queues a hook fire toward the aim set by set_aim, consumed next tick.
func request_fire(is_left: bool) -> void:
	_ai_fire[0 if is_left else 1] = true


## AI: queues a hook release, consumed next tick.
func request_release(is_left: bool) -> void:
	_ai_release[0 if is_left else 1] = true


## AI: sets where the next fired hooks originate and point.
func set_aim(origin: Vector3, direction: Vector3) -> void:
	_aim_origin_override = origin
	_aim_dir_override = direction.normalized()


## AI: returns the point a hook is attached to (left preferred), or ZERO.
func get_anchor() -> Vector3:
	if left_attached():
		return _left_hook.anchor_point
	if right_attached():
		return _right_hook.anchor_point
	return Vector3.ZERO


func _input(event: InputEvent) -> void:
	if ai_controlled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("odm_reel_toggle"):
		set_reel_enabled(not reel_enabled)
		get_viewport().set_input_as_handled()


## Refills gas completely when amount is negative, otherwise adds a capped
## amount and broadcasts the new value.
func refill_gas(amount: float = -1.0) -> void:
	if amount < 0.0:
		gas = gas_max
	else:
		gas = minf(gas_max, gas + amount)
	gas_changed.emit(gas, gas_max)


## Detaches both hooks and hides the cables.
func release_hooks() -> void:
	for pair in [[_left_hook, true], [_right_hook, false]]:
		var hook: ODMHook = pair[0]
		if hook != null and hook.is_attached():
			hook.detach()
			hook_detached.emit(pair[1])
	hooks_changed.emit(false, false)
	_update_cable_visuals()


## Reports whether the left hook is attached.
func left_attached() -> bool:
	return _left_hook != null and _left_hook.is_attached()


## Reports whether the right hook is attached.
func right_attached() -> bool:
	return _right_hook != null and _right_hook.is_attached()


## Keeps hook controls on Q/E and reserves mouse buttons for swords.
func ensure_input_actions() -> void:
	_remove_mouse_bindings("odm_hook_left")
	_remove_mouse_bindings("odm_hook_right")
	_add_key_action("odm_hook_left", KEY_Q)
	_add_key_action("odm_hook_right", KEY_E)
	_add_key_action("odm_boost", KEY_SHIFT)
	_add_key_action("odm_reel_toggle", KEY_R)


## Advances all ODM systems for one physics frame in a stable order:
## input, reeling, cable constraints, steering, boost, then visuals.
func physics_tick(delta: float) -> void:
	if _player == null:
		return
	if _camera == null and not ai_controlled:
		_camera = _player.get_viewport().get_camera_3d()

	_handle_hook_input()
	if not reel_enabled or not is_hooked():
		_reel_boost_bonus = 0.0
	_player.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING if reel_enabled and is_hooked() else CharacterBody3D.MOTION_MODE_GROUNDED
	_apply_reel(delta)
	_apply_cable_constraints(delta)
	_apply_air_steer(delta)
	_apply_boost(delta)
	_update_cable_visuals()


## Routes each hook's input action into its fire or detach behavior.
func _handle_hook_input() -> void:
	_update_single_hook(_left_hook, "odm_hook_left", true)
	_update_single_hook(_right_hook, "odm_hook_right", false)
	_ai_fire = [false, false]
	_ai_release = [false, false]


## Fires or detaches one hook and emits the corresponding public signals.
func _update_single_hook(hook: ODMHook, action: StringName, is_left: bool) -> void:
	var side := 0 if is_left else 1
	var pressed: bool = _ai_fire[side] if ai_controlled else Input.is_action_just_pressed(action)
	var released: bool = _ai_release[side] if ai_controlled else Input.is_action_just_released(action)
	if pressed:
		hook_fired.emit(is_left)
		if _try_fire(hook):
			hook_latched.emit(is_left)
			hooks_changed.emit(left_attached(), right_attached())
	elif released:
		if hook.is_attached():
			hook.detach()
			hook_detached.emit(is_left)
			hooks_changed.emit(left_attached(), right_attached())


## Performs the raycast from the current aim direction and rejects hits that
## exceed the configured cable length.
func _try_fire(hook: ODMHook) -> bool:
	var origin := _aim_origin()
	var direction := _aim_direction()
	var space := _player.get_world_3d().direct_space_state
	var ok := hook.fire(origin, direction, max_cable_length, space, grapple_collision_mask)
	if ok and hook.cable_length > max_cable_length:
		hook.detach()
		return false
	return ok


## Returns true when a hook fired now would hit something within cable length.
func can_hook_target() -> bool:
	if _player == null:
		return false
	var origin := _aim_origin()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + _aim_direction().normalized() * max_cable_length)
	query.collision_mask = grapple_collision_mask
	query.collide_with_areas = false
	return not _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Chooses the camera position as the hook origin, falling back to the player
## body when no camera is available.
func _aim_origin() -> Vector3:
	if ai_controlled:
		return _aim_origin_override
	if _camera:
		return _camera.global_position
	return _player.global_position + Vector3.UP * look_aim_height


## Chooses the camera's forward direction as the aim vector, falling back to
## the player's forward direction.
func _aim_direction() -> Vector3:
	if ai_controlled:
		return _aim_dir_override if _aim_dir_override != Vector3.ZERO else -_player.global_transform.basis.z
	if _camera:
		return -_camera.global_transform.basis.z
	return -_player.global_transform.basis.z


## Returns the world-space position of the selected gear socket.
func _socket_global(is_left: bool) -> Vector3:
	var socket := _left_socket if is_left else _right_socket
	if socket:
		return socket.global_position
	return _player.global_position + Vector3((-0.25 if is_left else 0.25), 0.9, 0.0)


## Shortens all attached cables while reel mode is enabled.
func _apply_reel(delta: float) -> void:
	if not reel_enabled:
		return
	var shortening := _effective_reel_speed() * delta
	var reeling := false
	if _left_hook.is_attached():
		_left_hook.shorten(shortening, min_cable_length)
		reeling = true
	if _right_hook.is_attached():
		_right_hook.shorten(shortening, min_cable_length)
		reeling = true
	if reeling and gas_reel_drain > 0.0:
		_spend_gas(gas_reel_drain * delta)


## Reel mode follows the cable directly with two hooks. A single hook retains
## limited sideways momentum for a shallow arc. Reel off allows a full swing.
func _apply_cable_constraints(delta: float) -> void:
	if reel_enabled and is_hooked():
		var to_target := _reel_target() - (_player.global_position + Vector3.UP * 0.9)
		var distance := to_target.length()
		if distance <= 0.001:
			_player.velocity = Vector3.ZERO
			return
		var direction := to_target / distance
		var base_speed := _effective_reel_speed()
		var carried := _player.velocity.length() - base_speed
		_reel_boost_bonus = maxf(_reel_boost_bonus, carried)
		_reel_boost_bonus = clampf(_reel_boost_bonus, 0.0, maxf(0.0, max_grapple_speed - base_speed))
		_reel_boost_bonus = move_toward(_reel_boost_bonus, 0.0, reel_boost_decay * delta)
		var speed := minf(base_speed + _reel_boost_bonus,
			maxf(0.0, distance - min_cable_length) * 7.0)
		if left_attached() and right_attached():
			_player.velocity = direction * speed
		else:
			# Keep a little tangential momentum (including gravity) so one cable arcs.
			var tangent := _player.velocity - direction * _player.velocity.dot(direction)
			tangent *= exp(-single_hook_arc_damping * delta)
			tangent = tangent.limit_length(speed * single_hook_arc_ratio)
			var radial_speed := sqrt(maxf(0.0, speed * speed - tangent.length_squared()))
			_player.velocity = direction * radial_speed + tangent
		return

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

	var player_pos := _player.global_position + Vector3.UP * 0.9
	var pull_scale := dual_pull_multiplier if anchors.size() > 1 else 1.0
	for i in anchors.size():
		var to_anchor: Vector3 = anchors[i] - player_pos
		var dist := to_anchor.length()
		var max_len: float = lengths[i]
		if dist <= max_len or dist <= 0.001:
			continue
		var dir := to_anchor / dist
		var excess := dist - max_len
		_player.velocity += dir * excess * pull_strength * pull_scale * delta
		var outward_speed := _player.velocity.dot(-dir)
		if outward_speed > 0.0:
			_player.velocity += dir * outward_speed
		_player.global_position += dir * excess * minf(1.0, 12.0 * delta)

	var horizontal := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	horizontal = horizontal.lerp(Vector3.ZERO, swing_damping * delta)
	_player.velocity.x = horizontal.x
	_player.velocity.z = horizontal.z


## Applies camera-relative air steering while hooked, boosting, or airborne.
func _apply_air_steer(delta: float) -> void:
	if reel_enabled and is_hooked():
		return
	if not is_hooked() and _player.is_on_floor():
		return
	if not is_active():
		return
	if ai_controlled:
		_player.velocity += ai_steer.normalized() * air_control * delta
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


## Applies directional boost while gas and the airborne/hooked requirements
## are satisfied, clamping total speed and emitting the boost event once.
func _apply_boost(delta: float) -> void:
	var was_boosting := _boosting
	_boosting = false
	var wants_boost: bool = ai_boost if ai_controlled else Input.is_action_pressed("odm_boost")
	var can_boost := wants_boost and (is_hooked() or not _player.is_on_floor()) and gas > 0.0
	if not can_boost:
		return

	_boosting = true
	var reel_boosting := reel_enabled and is_hooked()
	var boost_dir := _aim_direction()
	if reel_enabled and is_hooked():
		var target := _reel_target()
		var toward_target := target - (_player.global_position + Vector3.UP * 0.9)
		if toward_target.length_squared() > 0.001:
			boost_dir = toward_target.normalized()
	# Bias slightly along current velocity for continuity outside reel mode.
	if (not reel_enabled or not is_hooked()) and _player.velocity.length() > 1.0:
		boost_dir = (boost_dir + _player.velocity.normalized() * 0.35).normalized()
	_player.velocity += boost_dir * boost_impulse * delta
	var speed_cap := boost_max_speed
	if reel_boosting:
		# Boost must have room to add speed even above a high base reel speed.
		speed_cap = maxf(speed_cap, maxf(_effective_reel_speed() + 4.0, max_grapple_speed))
	if _player.velocity.length() > speed_cap:
		_player.velocity = _player.velocity.normalized() * speed_cap
	if reel_boosting:
		_reel_boost_bonus = maxf(0.0, _player.velocity.length() - _effective_reel_speed())
	_spend_gas(gas_boost_drain * delta)
	if not was_boosting:
		boosted.emit()


## Returns the reel speed used by movement and cable shortening.
func _effective_reel_speed() -> float:
	var multiplier := dual_reel_speed_multiplier if left_attached() and right_attached() else 1.0
	return maxf(reel_speed, 0.0) * maxf(multiplier, 0.0)


## Returns the current single anchor or midpoint between two anchors.
func _reel_target() -> Vector3:
	if _left_hook.is_attached() and _right_hook.is_attached():
		return (_left_hook.anchor_point + _right_hook.anchor_point) * 0.5
	if _left_hook.is_attached():
		return _left_hook.anchor_point
	return _right_hook.anchor_point


## Spends gas safely, clamps it at zero, and emits the updated gas amount.
func _spend_gas(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if gas <= 0.0:
		gas = 0.0
		return false
	gas = maxf(0.0, gas - amount)
	gas_changed.emit(gas, gas_max)
	return true


## Updates both hook cable meshes from their gear socket positions.
func _update_cable_visuals() -> void:
	if _left_hook:
		_left_hook.update_visual(_socket_global(true))
	if _right_hook:
		_right_hook.update_visual(_socket_global(false))


## Adds a physical keyboard binding to an action if it is not already present.
func _add_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == keycode:
			return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


## Removes old runtime or saved mouse bindings from a hook action.
func _remove_mouse_bindings(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton:
			InputMap.action_erase_event(action, event)
