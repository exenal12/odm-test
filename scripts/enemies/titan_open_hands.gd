extends SkeletonModifier3D
## Replaces the animation's finger pose with a relaxed open hand taken from another clip.
## Must sit before the grab arm modifier so the grab curl builds on the open hand.

## 0 = clip fingers, 1 = fully open.
var amount: float = 0.0

var _bones: Array[int] = []
var _open: Array[Quaternion] = []


## Samples the first frame of open_clip for every finger and thumb bone on both hands.
func setup(open_clip: Animation) -> void:
	var sk := get_skeleton()
	_bones.clear()
	_open.clear()
	for side in [".L", ".R"]:
		for finger in ["indexFinger", "middleFinger", "ringFinger", "pinky", "thumb"]:
			for i in 3:
				var bone_name := "B-%s0%d%s" % [finger, i + 1, side]
				var bone := sk.find_bone(bone_name)
				if bone < 0:
					continue
				var track := open_clip.find_track(NodePath("Skeleton3D:" + bone_name), Animation.TYPE_ROTATION_3D)
				_bones.append(bone)
				_open.append(open_clip.rotation_track_interpolate(track, 0.0) if track >= 0
						else sk.get_bone_rest(bone).basis.get_rotation_quaternion())


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or amount <= 0.001:
		return
	for i in _bones.size():
		sk.set_bone_pose_rotation(_bones[i], sk.get_bone_pose_rotation(_bones[i]).slerp(_open[i], amount))
