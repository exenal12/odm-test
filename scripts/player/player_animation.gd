class_name PlayerAnimation
extends Node
## Native HumanF locomotion with per-arm attack and airborne hold layers.
## The animation tree uses Godot's bone filters so attacks preserve locomotion
## and a planted lower body while stationary. All clips target the unmodified
## HumanF_Model bind pose.

@export_range(0.01, 0.5, 0.01) var locomotion_blend: float = 0.18
@export_range(0.01, 0.5, 0.01) var attack_blend: float = 0.12
@export_range(0.01, 1.0, 0.01) var hold_blend: float = 0.22

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
		if String(clip).begins_with("Swing") or String(clip).begins_with("Hold"):
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
	blend.connect_node(&"output", 0, previous)
	skeleton.add_child(HeadStabilizer.new())
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


func _process(delta: float) -> void:
	if tree == null:
		return
	for i in 2:
		var side := "Left" if i == 0 else "Right"
		if _hold_active[i]:
			_hold_time[i] += delta
			if not _hold_entered[i] and _hold_time[i] >= clip_length(StringName("HoldEnter" + side)):
				tree.set("parameters/%sHoldSelect/transition_request" % side, "Pose")
				_hold_entered[i] = true
		_hold_weight[i] = move_toward(_hold_weight[i], _hold_target[i], delta / maxf(hold_blend, 0.01))
		tree.set("parameters/%sHold/blend_amount" % side, _hold_weight[i])
