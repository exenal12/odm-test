extends SceneTree

# Assemble clips authored for the supplied HumanF_Model.fbx. This checks the
# bind pose before copying tracks; no retarget or rest-pose rewrite is used.
const MODEL := "res://assets/Human Melee Animations/Models/HumanF_Model.fbx"
const OUT := "res://scenes/player/animations/humanf_native.tres"
const FEMALE := "res://assets/Human Melee Animations/Animations/Female/"
const CLIPS := {
	"Idle": FEMALE + "Combat/HumanF@CombatIdle01.fbx",
	"IdleRelaxed": FEMALE + "Idles/HumanF@Idle01.fbx",
	"RunForward": FEMALE + "Movement/Run/HumanF@Run01_Forward.fbx",
	"RunBackward": FEMALE + "Movement/Run/HumanF@Run01_Backward.fbx",
	"StrafeLeft": FEMALE + "Movement/Run/HumanF@Run01_Left.fbx",
	"StrafeRight": FEMALE + "Movement/Run/HumanF@Run01_Right.fbx",
	"StrafeForwardLeft": FEMALE + "Movement/Run/HumanF@Run01_ForwardLeft.fbx",
	"StrafeForwardRight": FEMALE + "Movement/Run/HumanF@Run01_ForwardRight.fbx",
	"StrafeBackwardLeft": FEMALE + "Movement/Run/HumanF@Run01_BackwardLeft.fbx",
	"StrafeBackwardRight": FEMALE + "Movement/Run/HumanF@Run01_BackwardRight.fbx",
	"AttackLeft": FEMALE + "Combat/1H/HumanF@Attack1H01_L.fbx",
	"AttackRight": FEMALE + "Combat/1H/HumanF@Attack1H01_R.fbx",
}

func _initialize() -> void:
	var model_scene := load(MODEL) as PackedScene
	if model_scene == null:
		push_error("Could not load HumanF model")
		quit(1)
		return
	var model := model_scene.instantiate()
	var target := model.get_node("Skeleton3D") as Skeleton3D
	var library := AnimationLibrary.new()
	for clip_name in CLIPS:
		var source_scene := load(CLIPS[clip_name]) as PackedScene
		if source_scene == null:
			push_error("Missing source clip: " + CLIPS[clip_name])
			quit(1)
			return
		var source := source_scene.instantiate()
		var skeleton := source.get_node("Skeleton3D") as Skeleton3D
		var source_player := source.get_node("AnimationPlayer") as AnimationPlayer
		if skeleton == null or source_player == null:
			push_error("Invalid female clip scene: " + clip_name)
			quit(1)
			return
		for i in target.get_bone_count():
			var name := target.get_bone_name(i)
			var j := skeleton.find_bone(name)
			if j < 0 or target.get_bone_parent(i) >= 0 and skeleton.get_bone_name(skeleton.get_bone_parent(j)) != target.get_bone_name(target.get_bone_parent(i)):
				push_error("Skeleton mismatch for " + clip_name + " / " + name)
				quit(1)
				return
			var a := target.get_bone_rest(i)
			var b := skeleton.get_bone_rest(j)
			if a.origin.distance_to(b.origin) > 0.0001 or not a.basis.is_equal_approx(b.basis):
				push_error("Bind pose mismatch for " + clip_name + " / " + name)
				quit(1)
				return
		var source_name := source_player.get_animation_list()[0]
		var animation := source_player.get_animation(source_name).duplicate(true) as Animation
		var dropped := 0
		for t in range(animation.get_track_count() - 1, -1, -1):
			var path := animation.track_get_path(t)
			if path.get_subname_count() > 0 and target.find_bone(path.get_subname(0)) < 0:
				animation.remove_track(t)
				dropped += 1
		animation.loop_mode = Animation.LOOP_LINEAR if clip_name.begins_with("Run") or clip_name.begins_with("Strafe") or clip_name.begins_with("Idle") else Animation.LOOP_NONE
		library.add_animation(clip_name, animation)
		print("VERIFIED ", clip_name, " ", animation.length, "s ", animation.get_track_count(), " tracks, dropped ", dropped, " helper tracks")
		source.free()
	_add_verified_ual_clips(target, library)
	_add_verified_sword_swings(target, library)
	for side in ["Left", "Right"]:
		var source_name := StringName("Attack" + side)
		var source_attack := library.get_animation(source_name)
		library.add_animation(StringName("HoldEnter" + side), _make_hold_clip(source_attack, side, false))
		library.add_animation(StringName("HoldPose" + side), _make_hold_clip(source_attack, side, true))
		library.remove_animation(source_name)
	model.free()
	var err := ResourceSaver.save(library, OUT)
	if err != OK:
		push_error("Could not save animation library: " + str(err))
		quit(1)
		return
	print("SAVED ", OUT)
	quit()


func _make_hold_clip(source: Animation, side: String, static_pose: bool) -> Animation:
	var clip := Animation.new()
	clip.length = 0.1 if static_pose else 0.32
	clip.loop_mode = Animation.LOOP_LINEAR if static_pose else Animation.LOOP_NONE
	var suffix := ".L" if side == "Left" else ".R"
	for t in source.get_track_count():
		var kind := source.track_get_type(t)
		if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var path := source.track_get_path(t)
		if not String(path.get_subname(0)).ends_with(suffix):
			continue
		var index := clip.add_track(kind)
		clip.track_set_path(index, path)
		for time in ([0.0] if static_pose else [0.0, 0.14, 0.32]):
			var sample: float = 0.32 if static_pose else time
			var value: Variant
			match kind:
				Animation.TYPE_POSITION_3D: value = source.position_track_interpolate(t, sample)
				Animation.TYPE_ROTATION_3D: value = source.rotation_track_interpolate(t, sample)
				Animation.TYPE_SCALE_3D: value = source.scale_track_interpolate(t, sample)
			clip.track_insert_key(index, time, value)
	return clip


func _add_verified_ual_clips(target: Skeleton3D, library: AnimationLibrary) -> void:
	var scene := load("res://scenes/player/animations/HumanF_UAL_Retarget.glb") as PackedScene
	if scene == null:
		push_error("Retargeted UAL glTF is missing")
		return
	var root := scene.instantiate()
	var source := root.get_node("Armature/Skeleton3D") as Skeleton3D
	var player := root.get_node("AnimationPlayer") as AnimationPlayer
	for i in target.get_bone_count():
		var j := source.find_bone(target.get_bone_name(i))
		assert(j >= 0, "UAL export is missing a HumanF bone")
		var a := target.get_bone_rest(i)
		var b := source.get_bone_rest(j)
		assert(a.origin.distance_to(b.origin) < 0.0001 and (a.basis.inverse() * b.basis).get_rotation_quaternion().get_angle() < 0.0001, "UAL export changed HumanF bind pose: %s" % target.get_bone_name(i))
	for name in player.get_animation_list():
		var animation := player.get_animation(name).duplicate(true) as Animation
		for t in animation.get_track_count():
			var path := animation.track_get_path(t)
			var bone := path.get_subname(0)
			assert(target.find_bone(bone) >= 0, "UAL track targets an unknown bone")
			animation.track_set_path(t, NodePath("Skeleton3D:%s" % bone))
		animation.loop_mode = Animation.LOOP_LINEAR if name in ["Walk", "Crouch_Idle", "Crouch_Fwd", "Jump", "Slide"] else Animation.LOOP_NONE
		library.add_animation(name, animation)
		print("VERIFIED_UAL ", name, " ", animation.length, "s ", animation.get_track_count(), " tracks")
	root.free()


func _add_verified_sword_swings(target: Skeleton3D, library: AnimationLibrary) -> void:
	var scene := load("res://scenes/player/animations/HumanF_SwordSwings.glb") as PackedScene
	assert(scene != null, "Mirrored sword swings are missing")
	var root := scene.instantiate()
	var source := root.get_node("Armature/Skeleton3D") as Skeleton3D
	var player := root.get_node("AnimationPlayer") as AnimationPlayer
	for i in target.get_bone_count():
		var j := source.find_bone(target.get_bone_name(i))
		assert(j >= 0, "Swing export is missing a HumanF bone")
		var a := target.get_bone_rest(i)
		var b := source.get_bone_rest(j)
		assert(a.origin.distance_to(b.origin) < 0.0001 and (a.basis.inverse() * b.basis).get_rotation_quaternion().get_angle() < 0.0001, "Swing export changed HumanF bind pose")
	for name in player.get_animation_list():
		var animation := player.get_animation(name).duplicate(true) as Animation
		for t in animation.get_track_count():
			var path := animation.track_get_path(t)
			var bone := path.get_subname(0)
			assert(target.find_bone(bone) >= 0, "Swing track targets unknown bone")
			animation.track_set_path(t, NodePath("Skeleton3D:%s" % bone))
		animation.loop_mode = Animation.LOOP_NONE
		_stabilize_swing_head(target, animation)
		library.add_animation(name, animation)
		print("VERIFIED_SWING ", name, " ", animation.length, "s ", animation.get_track_count(), " tracks")
	root.free()


# Keep the head facing the character's forward direction while the chest turns.
# Split the correction between neck and head so the neck does not absorb it all.
func _stabilize_swing_head(skeleton: Skeleton3D, animation: Animation) -> void:
	var tracks: Dictionary = {}
	for t in animation.get_track_count():
		if animation.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			tracks[String(animation.track_get_path(t).get_subname(0))] = t
	assert(tracks.has("B-neck") and tracks.has("B-head") and tracks.has("B-chest"))
	var neck := skeleton.find_bone("B-neck")
	var head := skeleton.find_bone("B-head")
	var chest := skeleton.get_bone_parent(neck)
	assert(chest == skeleton.find_bone("B-chest"))
	var rest_neck := skeleton.get_bone_global_rest(neck).basis.get_rotation_quaternion()
	var rest_head := skeleton.get_bone_global_rest(head).basis.get_rotation_quaternion()
	var neck_rest_local := skeleton.get_bone_rest(neck).basis.get_rotation_quaternion()
	var head_rest_local := skeleton.get_bone_rest(head).basis.get_rotation_quaternion()
	var samples: Array = []
	var sample_count := int(ceilf(animation.length * 30.0)) + 1
	for i in sample_count:
		var time := minf(float(i) / 30.0, animation.length)
		var chest_global := _sample_swing_global_rotation(skeleton, animation, tracks, chest, time)
		var source_neck_global := _sample_swing_global_rotation(skeleton, animation, tracks, neck, time)
		var desired_neck_global := source_neck_global.slerp(rest_neck, 0.5)
		var neck_local := (chest_global * neck_rest_local).inverse() * desired_neck_global
		var head_local := (desired_neck_global * head_rest_local).inverse() * rest_head
		samples.append([time, neck_local.normalized(), head_local.normalized()])
	var neck_track: int = tracks["B-neck"]
	var head_track: int = tracks["B-head"]
	animation.remove_track(maxi(neck_track, head_track))
	animation.remove_track(mini(neck_track, head_track))
	neck_track = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(neck_track, NodePath("Skeleton3D:B-neck"))
	head_track = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(head_track, NodePath("Skeleton3D:B-head"))
	for sample in samples:
		animation.track_insert_key(neck_track, sample[0], sample[1])
		animation.track_insert_key(head_track, sample[0], sample[2])


func _sample_swing_global_rotation(skeleton: Skeleton3D, animation: Animation, tracks: Dictionary, bone: int, time: float) -> Quaternion:
	var parent := skeleton.get_bone_parent(bone)
	var parent_rotation := _sample_swing_global_rotation(skeleton, animation, tracks, parent, time) if parent >= 0 else Quaternion.IDENTITY
	var rest_rotation := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	var name := String(skeleton.get_bone_name(bone))
	var pose_rotation := animation.rotation_track_interpolate(tracks[name], time) if tracks.has(name) else Quaternion.IDENTITY
	return (parent_rotation * rest_rotation * pose_rotation).normalized()
