extends SceneTree

# Builds the titan animation library from the male clips. Bind poses are
# checked against the male model before tracks are copied.
const MODEL := "res://assets/Human Melee Animations/Models/HumanM_Model.fbx"
const OUT := "res://scenes/enemies/animations/humanm_titan.tres"
const MALE := "res://assets/Human Melee Animations/Animations/Male/"
const CLIPS := {
	"Idle": [MALE + "Idles/HumanM@Idle01.fbx", true],
	"Walk": [MALE + "Movement/Run/HumanM@Run01_Forward.fbx", true],
	"Damage": [MALE + "Combat/HumanM@CombatDamage01.fbx", false],
	"Attack": [MALE + "Combat/2H/HumanM@Attack2H01.fbx", false],
	"Death": [MALE + "Combat/HumanM@Death01.fbx", false],
}


func _initialize() -> void:
	var model := (load(MODEL) as PackedScene).instantiate()
	var target := model.get_node("Skeleton3D") as Skeleton3D
	var library := AnimationLibrary.new()
	for clip_name in CLIPS:
		var source := (load(CLIPS[clip_name][0]) as PackedScene).instantiate()
		var skeleton := source.get_node("Skeleton3D") as Skeleton3D
		var source_player := source.get_node("AnimationPlayer") as AnimationPlayer
		for i in target.get_bone_count():
			var j := skeleton.find_bone(target.get_bone_name(i))
			if j < 0 or target.get_bone_rest(i).origin.distance_to(skeleton.get_bone_rest(j).origin) > 0.0001:
				push_error("Bind pose mismatch: %s / %s" % [clip_name, target.get_bone_name(i)])
				quit(1)
				return
		var animation := source_player.get_animation(source_player.get_animation_list()[0]).duplicate(true) as Animation
		for t in range(animation.get_track_count() - 1, -1, -1):
			var path := animation.track_get_path(t)
			if path.get_subname_count() > 0 and target.find_bone(path.get_subname(0)) < 0:
				animation.remove_track(t)
		animation.loop_mode = Animation.LOOP_LINEAR if CLIPS[clip_name][1] else Animation.LOOP_NONE
		library.add_animation(clip_name, animation)
		print("OK ", clip_name, " ", animation.length, "s")
		source.free()
	model.free()
	print("save: ", ResourceSaver.save(library, OUT))
	quit()
