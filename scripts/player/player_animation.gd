class_name PlayerAnimation
extends Node
## Native HumanF locomotion with per-arm attack and airborne hold layers.
## The animation tree uses Godot's bone filters so attacks preserve locomotion
## and a planted lower body while stationary. All clips target the unmodified
## HumanF_Model bind pose.

@export_range(0.01, 0.5, 0.01) var locomotion_blend: float = 0.18
@export_range(0.01, 0.5, 0.01) var attack_blend: float = 0.12
@export_range(0.01, 1.0, 0.01) var hold_blend: float = 0.22
@export_group("Death")
## Playback speed of the ground collapse; below 1 is slower.
@export_range(0.1, 3.0, 0.05) var death_speed: float = 1.0
@export_range(0.01, 1.0, 0.01) var death_blend: float = 0.15
## After an airborne body lands: seconds the limbs keep flopping, then seconds to fade to still.
@export var death_settle_time: float = 0.9
@export var death_fade_time: float = 0.6
## Yaw spin range (rad/s) of a body falling after an airborne death.
@export var death_spin: Vector2 = Vector2(0.8, 2.0)
## Peak pitch/roll (radians) of the tumble while falling dead.
@export var death_tilt: float = 0.45

@onready var model: Node3D = $"../Model"
@onready var animation_player: AnimationPlayer = $"../Model/AnimationPlayer"
@onready var skeleton: Skeleton3D = $"../Model/Skeleton3D"

var tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _base_clip: StringName = &""
var _hold_target: Array[float] = [0.0, 0.0]
var _hold_weight: Array[float] = [0.0, 0.0]
var _hold_time: Array[float] = [0.0, 0.0]
var _hold_active: Array[bool] = [false, false]
var _hold_entered: Array[bool] = [false, false]
var _head_stabilizer: HeadStabilizer
var _death_weight: float = 0.0
var _dying: bool = false
var _falling_dead: bool = false
var _air_death: bool = false
var _spin_speed: float = 0.0
var _yaw: float = 0.0
var _fall_time: float = 0.0
var _fall_speed: float = 0.0
var _tilt_weight: float = 0.0
var _tumble_phase: Vector2 = Vector2.ZERO
var _model_basis: Basis = Basis()
var _limp: LimpBody


func _ready() -> void:
	_build_tree()


func _build_tree() -> void:
	var library := animation_player.get_animation_library(&"humanf")
	if library == null:
		push_error("HumanF animation library is missing")
		return
	var state_machine := AnimationNodeStateMachine.new()
	var base_names: Array[StringName] = []
	for clip in library.get_animation_list():
		if String(clip).begins_with("Swing") or String(clip).begins_with("Hold") or String(clip).begins_with("Death"):
			continue
		var node := AnimationNodeAnimation.new()
		node.animation = StringName("humanf/%s" % clip)
		state_machine.add_node(clip, node)
		base_names.append(clip)
	for a in base_names:
		for b in base_names:
			if a == b:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = locomotion_blend
			transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			state_machine.add_transition(a, b, transition)
	var blend := AnimationNodeBlendTree.new()
	blend.add_node(&"Locomotion", state_machine)
	var base_speed := AnimationNodeTimeScale.new()
	blend.add_node(&"BaseSpeed", base_speed)
	blend.connect_node(&"BaseSpeed", 0, &"Locomotion")
	var previous: StringName = &"BaseSpeed"
	for side in ["Left", "Right"]:
		var attack_name := StringName("Swing" + side)
		var attack_node := AnimationNodeAnimation.new()
		attack_node.animation = StringName("humanf/%s" % attack_name)
		blend.add_node(attack_name, attack_node)
		var speed_name := StringName(side + "Speed")
		blend.add_node(speed_name, AnimationNodeTimeScale.new())
		blend.connect_node(speed_name, 0, attack_name)
		var swing_name := StringName(side + "Swing")
		var one_shot := AnimationNodeOneShot.new()
		one_shot.fadein_time = attack_blend
		one_shot.fadeout_time = attack_blend
		_mask_arm(one_shot, side == "Left", true)
		blend.add_node(swing_name, one_shot)
		blend.connect_node(swing_name, 0, previous)
		blend.connect_node(swing_name, 1, speed_name)
		previous = swing_name
	for side in ["Left", "Right"]:
		var enter_name := StringName("HoldEnter" + side)
		var pose_name := StringName("HoldPose" + side)
		var enter_node := AnimationNodeAnimation.new()
		enter_node.animation = StringName("humanf/%s" % enter_name)
		var pose_node := AnimationNodeAnimation.new()
		pose_node.animation = StringName("humanf/%s" % pose_name)
		blend.add_node(enter_name, enter_node)
		blend.add_node(pose_name, pose_node)
		var selector := AnimationNodeTransition.new()
		selector.add_input(&"Enter")
		selector.add_input(&"Pose")
		selector.xfade_time = 0.08
		var select_name := StringName(side + "HoldSelect")
		blend.add_node(select_name, selector)
		blend.connect_node(select_name, 0, enter_name)
		blend.connect_node(select_name, 1, pose_name)
		var layer_name := StringName(side + "Hold")
		var layer := AnimationNodeBlend2.new()
		_mask_arm(layer, side == "Left")
		blend.add_node(layer_name, layer)
		blend.connect_node(layer_name, 0, previous)
		blend.connect_node(layer_name, 1, select_name)
		previous = layer_name
	# Full-body death layer on top of everything: a collapse, or a held limp pose.
	var collapse := AnimationNodeAnimation.new()
	collapse.animation = &"humanf/Death"
	var limp := AnimationNodeAnimation.new()
	limp.animation = &"humanf/DeathLimp"
	blend.add_node(&"DeathCollapse", collapse)
	blend.add_node(&"DeathLimp", limp)
	var death_select := AnimationNodeTransition.new()
	death_select.add_input(&"Limp")
	death_select.add_input(&"Collapse")
	blend.add_node(&"DeathSelect", death_select)
	blend.connect_node(&"DeathSelect", 0, &"DeathLimp")
	blend.connect_node(&"DeathSelect", 1, &"DeathCollapse")
	blend.add_node(&"DeathSpeed", AnimationNodeTimeScale.new())
	blend.connect_node(&"DeathSpeed", 0, &"DeathSelect")
	blend.add_node(&"Death", AnimationNodeBlend2.new())
	blend.connect_node(&"Death", 0, previous)
	blend.connect_node(&"Death", 1, &"DeathSpeed")
	blend.connect_node(&"output", 0, &"Death")
	_head_stabilizer = HeadStabilizer.new()
	skeleton.add_child(_head_stabilizer)
	_limp = LimpBody.new()
	skeleton.add_child(_limp)
	skeleton.add_child(HandGrip.new())
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	add_child(tree)
	tree.anim_player = NodePath("../../Model/AnimationPlayer")
	tree.tree_root = blend
	tree.active = true
	_playback = tree.get(&"parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
	play_base(&"Idle")


func _mask_arm(node: AnimationNode, left: bool, include_torso: bool = false) -> void:
	node.set_filter_enabled(true)
	if include_torso:
		for bone in ["B-spine", "B-chest"]:
			node.set_filter_path(NodePath("Skeleton3D:%s" % bone), true)
	var suffix := ".L" if left else ".R"
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i)
		if bone.ends_with(suffix) and not (bone.begins_with("B-thigh") or bone.begins_with("B-shin") or bone.begins_with("B-foot") or bone.begins_with("B-toe")):
			var path := NodePath("Skeleton3D:%s" % bone)
			node.set_filter_path(path, true)


func has_clip(clip: StringName) -> bool:
	return animation_player.has_animation(StringName("humanf/%s" % clip))


func clip_length(clip: StringName) -> float:
	return animation_player.get_animation(StringName("humanf/%s" % clip)).length if has_clip(clip) else 0.0


func play_base(clip: StringName, speed: float = 1.0) -> void:
	if tree == null or _playback == null:
		return
	if not has_clip(clip):
		clip = &"Idle"
	if clip != _base_clip:
		_playback.travel(clip)
		_base_clip = clip
	tree.set(&"parameters/BaseSpeed/scale", speed)


func attack(left: bool, speed: float) -> void:
	if tree == null:
		return
	var side := "Left" if left else "Right"
	set_attack_speed(left, speed)
	tree.set("parameters/%sSwing/request" % side, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func set_attack_speed(left: bool, speed: float) -> void:
	if tree == null:
		return
	var side := "Left" if left else "Right"
	var clamped_speed := clampf(speed, 0.25, 4.0)
	tree.set("parameters/%sSpeed/scale" % side, clamped_speed)


func set_hold(left: bool, enabled: bool) -> void:
	var i := 0 if left else 1
	if enabled and not _hold_active[i]:
		_hold_time[i] = 0.0
		_hold_entered[i] = false
		tree.set("parameters/%sHoldSelect/transition_request" % ("Left" if left else "Right"), "Enter")
	_hold_active[i] = enabled
	_hold_target[i] = 1.0 if enabled else 0.0


## Grounded deaths play the collapse; airborne ones go limp and tumble until update_death sees the floor.
func play_death(airborne: bool) -> void:
	if tree == null or _dying:
		return
	_dying = true
	_falling_dead = airborne
	_air_death = airborne
	_spin_speed = randf_range(death_spin.x, death_spin.y) * (1.0 if randf() < 0.5 else -1.0)
	_tumble_phase = Vector2(randf() * TAU, randf() * TAU)
	_model_basis = model.basis
	set_hold(true, false)
	set_hold(false, false)
	if _head_stabilizer:
		_head_stabilizer.active = false
	if airborne and _limp:
		_limp.start(true)
	tree.set(&"parameters/DeathSelect/transition_request", "Limp" if airborne else "Collapse")


## Call every physics frame while dead. Returns true on the frame a falling body lands.
func update_death(delta: float, on_floor: bool, velocity: Vector3 = Vector3.ZERO) -> bool:
	if not _air_death:
		return false
	var landed := false
	if _falling_dead:
		if on_floor:
			_falling_dead = false
			landed = true
			if _limp:
				_limp.body_velocity = Vector3.ZERO
				_limp.land(_fall_speed, death_settle_time, death_fade_time)
			var rest_y := model.position.y
			var tween := create_tween()
			tween.tween_property(model, "position:y", rest_y - 0.07, 0.06)
			tween.tween_property(model, "position:y", rest_y, 0.2).set_trans(Tween.TRANS_SINE)
		else:
			_fall_time += delta
			_yaw += _spin_speed * delta
			_fall_speed = velocity.length()
			if _limp:
				_limp.body_velocity = velocity
	# Tumble: slow spin plus a wobbling tilt that levels out on landing.
	_tilt_weight = move_toward(_tilt_weight, 1.0 if _falling_dead else 0.0, delta / (0.5 if _falling_dead else 0.25))
	var pitch := death_tilt * sin(_fall_time * 1.4 + _tumble_phase.x) * _tilt_weight
	var roll := death_tilt * sin(_fall_time * 0.9 + _tumble_phase.y) * _tilt_weight
	model.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll) * _model_basis
	return landed


func _process(delta: float) -> void:
	if tree == null:
		return
	_death_weight = move_toward(_death_weight, 1.0 if _dying else 0.0, delta / death_blend)
	tree.set(&"parameters/Death/blend_amount", _death_weight)
	tree.set(&"parameters/DeathSpeed/scale", death_speed)
	for i in 2:
		var side := "Left" if i == 0 else "Right"
		if _hold_active[i]:
			_hold_time[i] += delta
			if not _hold_entered[i] and _hold_time[i] >= clip_length(StringName("HoldEnter" + side)):
				tree.set("parameters/%sHoldSelect/transition_request" % side, "Pose")
				_hold_entered[i] = true
		_hold_weight[i] = move_toward(_hold_weight[i], _hold_target[i], delta / maxf(hold_blend, 0.01))
		tree.set("parameters/%sHold/blend_amount" % side, _hold_weight[i])
