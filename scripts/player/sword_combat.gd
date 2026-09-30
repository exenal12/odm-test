class_name SwordCombat
extends Node
## One attack per click, with an independent aerial press-and-hold pose.
## The hit signal is the integration point for future damage/impact logic.

signal sword_hit(is_left: bool, target: Node3D, damage: float)

@export_group("Sword Attack")
@export_range(0.0, 1000.0, 1.0, "or_greater") var damage: float = 20.0
## Playback multiplier for both swords. 1 = authored speed; 2 = twice as fast.
## Can be adjusted during an attack without restarting it or desynchronizing hitboxes.
@export_range(0.25, 4.0, 0.05) var swing_speed: float = 2.0:
	set(value):
		swing_speed = clampf(value, 0.25, 4.0)
		if is_node_ready() and animation_controller != null:
			animation_controller.set_attack_speed(true, swing_speed)
			animation_controller.set_attack_speed(false, swing_speed)
@export_range(0.0, 1.0, 0.01) var attack_cooldown: float = 0.18
@export_range(0.05, 0.5, 0.01) var air_hold_threshold: float = 0.18
@export_range(0.0, 1.0, 0.01) var hit_start_fraction: float = 0.20
@export_range(0.0, 1.0, 0.01) var hit_end_fraction: float = 0.72

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var animation_controller: PlayerAnimation = $"../PlayerAnimation"
@onready var left_hitbox: Area3D = $"../Model/Skeleton3D/LeftHandAttachment/LeftSword/Hitbox"
@onready var right_hitbox: Area3D = $"../Model/Skeleton3D/RightHandAttachment/RightSword/Hitbox"

var _cooldown_left: float = 0.0
var _cooldown_right: float = 0.0
var _attack_elapsed: Array[float] = [-1.0, -1.0]
var _pending: Array[bool] = [false, false]
var _pending_elapsed: Array[float] = [0.0, 0.0]
var _holding: Array[bool] = [false, false]
var _hit_targets: Array[Dictionary] = [{}, {}]
var _grab_struck: Array[bool] = [false, false]
var _debug_meshes: Array[MeshInstance3D] = []
var _gs: Node


func _ready() -> void:
	_ensure_mouse_action(&"sword_left", MOUSE_BUTTON_LEFT)
	_ensure_mouse_action(&"sword_right", MOUSE_BUTTON_RIGHT)
	left_hitbox.body_entered.connect(_on_overlap.bind(0))
	left_hitbox.area_entered.connect(_on_overlap.bind(0))
	right_hitbox.body_entered.connect(_on_overlap.bind(1))
	right_hitbox.area_entered.connect(_on_overlap.bind(1))
	left_hitbox.monitoring = false
	right_hitbox.monitoring = false
	_setup_debug_meshes()
	_gs = get_node("/root/GameSettings")
	_gs.settings_changed.connect(_sync_debug_meshes)
	_sync_debug_meshes()


func _process(delta: float) -> void:
	if animation_controller == null:
		return
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_cooldown_right = maxf(0.0, _cooldown_right - delta)
	for side in 2:
		var action: StringName = &"sword_left" if side == 0 else &"sword_right"
		var grounded: bool = player.is_on_floor() or player.get(&"grabbed") == true
		if Input.is_action_just_pressed(action):
			if grounded:
				_start_attack(side)
			else:
				_pending[side] = true
				_pending_elapsed[side] = 0.0
		if _pending[side]:
			_pending_elapsed[side] += delta
			if not Input.is_action_pressed(action):
				_pending[side] = false
				if not grounded:
					_start_attack(side)
			elif not grounded and _pending_elapsed[side] >= air_hold_threshold:
				_pending[side] = false
				_holding[side] = true
				animation_controller.set_hold(side == 0, true)
		if _holding[side] and (grounded or not Input.is_action_pressed(action)):
			_holding[side] = false
			animation_controller.set_hold(side == 0, false)
		if _attack_elapsed[side] >= 0.0:
			_attack_elapsed[side] += delta * swing_speed
			var duration := animation_controller.clip_length(&"SwingLeft" if side == 0 else &"SwingRight")
			var active := _attack_elapsed[side] >= duration * hit_start_fraction and _attack_elapsed[side] <= duration * hit_end_fraction
			_hitbox(side).monitoring = active
			if active and not _grab_struck[side]:
				_grab_struck[side] = true
				if player.get(&"grabbed") == true:
					player.strike_grabber(damage)
			if _attack_elapsed[side] >= duration:
				_attack_elapsed[side] = -1.0
				_hitbox(side).monitoring = false
				if side == 0:
					_cooldown_left = attack_cooldown
				else:
					_cooldown_right = attack_cooldown
	_update_debug_mesh_colors()


func _setup_debug_meshes() -> void:
	for hb in [left_hitbox, right_hitbox]:
		var shape_node := hb.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			_debug_meshes.append(null)
			continue
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		if shape_node.shape is BoxShape3D:
			box.size = (shape_node.shape as BoxShape3D).size
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.35, 0.15, 0.22)
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shape_node.add_child(mi)
		_debug_meshes.append(mi)


func _sync_debug_meshes() -> void:
	var on: bool = bool(_gs.get("debug_sword_hitboxes"))
	for mesh in _debug_meshes:
		if mesh != null:
			mesh.visible = on
	_update_debug_mesh_colors()


func _update_debug_mesh_colors() -> void:
	if not bool(_gs.get("debug_sword_hitboxes")):
		return
	for side in 2:
		var mesh := _debug_meshes[side] if side < _debug_meshes.size() else null
		if mesh == null:
			continue
		var mat := mesh.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.albedo_color = Color(1.0, 0.12, 0.08, 0.55) if _hitbox(side).monitoring \
			else Color(1.0, 0.4, 0.2, 0.2)


func _start_attack(side: int) -> void:
	if (_cooldown_left if side == 0 else _cooldown_right) > 0.0 or _attack_elapsed[side] >= 0.0:
		return
	if not animation_controller.has_clip(&"SwingLeft" if side == 0 else &"SwingRight"):
		return
	_attack_elapsed[side] = 0.0
	_grab_struck[side] = false
	_hit_targets[side].clear()
	_hitbox(side).monitoring = false
	animation_controller.attack(side == 0, swing_speed)


func _hitbox(side: int) -> Area3D:
	return left_hitbox if side == 0 else right_hitbox


func _on_overlap(target: Node3D, side: int) -> void:
	if _attack_elapsed[side] < 0.0 or target == player or player.is_ancestor_of(target) or target.is_ancestor_of(player):
		return
	if target in _hit_targets[side]:
		return
	_hit_targets[side][target] = true
	sword_hit.emit(side == 0, target, damage)
	var receiver: Node = target if target.has_method(&"on_sword_hit") else target.get_parent()
	if receiver != null and receiver.has_method(&"on_sword_hit"):
		receiver.on_sword_hit(target, damage, player.global_position)


func _ensure_mouse_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button:
			return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
