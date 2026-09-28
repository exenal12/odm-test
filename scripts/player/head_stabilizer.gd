class_name HeadStabilizer
extends SkeletonModifier3D
## Keeps the head at its rest orientation so torso twist from attacks
## doesn't swing it.

@export var head_bone: StringName = &"B-head"

var _head := -1


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _head < 0:
		_head = skeleton.find_bone(head_bone)
		if _head < 0:
			return
	var parent := skeleton.get_bone_parent(_head)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis
	var target := skeleton.get_bone_global_rest(_head).basis
	skeleton.set_bone_pose_rotation(_head, (parent_basis.inverse() * target).get_rotation_quaternion())
