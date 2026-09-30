class_name TitanFeatures
extends SkeletonModifier3D
## Gives a HumanM-rigged titan its proportions: an oversized head and hands.
## The face is left plain, like the soldiers'.

const HEAD_SCALE := 1.25
const HAND_SCALE := 1.15

var _head := -1
var _hands: Array[int] = []


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_head = skeleton.find_bone("B-head")
	_hands.assign([skeleton.find_bone("B-hand.L"), skeleton.find_bone("B-hand.R")])


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _head < 0:
		return
	skeleton.set_bone_pose_scale(_head, Vector3.ONE * HEAD_SCALE)
	for hand in _hands:
		if hand >= 0:
			skeleton.set_bone_pose_scale(hand, Vector3.ONE * HAND_SCALE)
