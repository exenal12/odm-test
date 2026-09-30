extends SkeletonModifier3D
## Reaches a hand toward a world-space point with two-bone IK, then curls the fingers
## into a loose fist around it. Works from bone directions only, so it does not depend
## on the rig's local axes.

## 0 = animation only, 1 = fully IK-driven.
var weight: float = 0.0
## World-space point the palm should close around.
var target_world: Vector3
## World-space direction the elbow bends toward.
var pole_world: Vector3 = Vector3.DOWN
## Where the palm centre actually ended up (world space) after the last solve.
var palm_world: Vector3
## Orientation a gripped object should take, in world space.
var palm_basis: Basis = Basis()
## 0 = open hand (reaching), 1 = loose fist (holding).
var grip: float = 1.0
## 0..1 pulse that tightens the fist.
var squeeze: float = 0.0

## Curl in degrees per finger segment for a loose fist.
const FINGER_CURL := [55.0, 70.0, 45.0]
const THUMB_CURL := [25.0, 30.0, 25.0]
const SQUEEZE_EXTRA_DEG := 12.0
## How far into the palm (fraction of wrist-to-knuckle) the target sits.
const PALM_CENTER := 0.5

var _shoulder: int = -1
var _elbow: int = -1
var _hand: int = -1
var _middle_knuckle: int = -1
var _index_knuckle: int = -1
var _pinky_knuckle: int = -1
var _fingers: Array[Dictionary] = []


func setup(shoulder: String, elbow: String, hand: String, side: String) -> void:
	var sk := get_skeleton()
	_shoulder = sk.find_bone(shoulder)
	_elbow = sk.find_bone(elbow)
	_hand = sk.find_bone(hand)
	_middle_knuckle = sk.find_bone("B-middleFinger01" + side)
	_index_knuckle = sk.find_bone("B-indexFinger01" + side)
	_pinky_knuckle = sk.find_bone("B-pinky01" + side)
	_fingers.clear()
	for finger in ["indexFinger", "middleFinger", "ringFinger", "pinky", "thumb"]:
		var bones: Array[int] = []
		for i in 3:
			bones.append(sk.find_bone("B-%s0%d%s" % [finger, i + 1, side]))
		if bones.has(-1):
			continue
		_fingers.append({"bones": bones, "curl": THUMB_CURL if finger == "thumb" else FINGER_CURL})


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or weight <= 0.001 or _shoulder < 0 or _elbow < 0 or _hand < 0:
		return
	var inv := sk.global_transform.affine_inverse()
	var palm_target := inv * target_world
	var pole := (inv.basis * pole_world).normalized()

	var s := sk.get_bone_global_pose(_shoulder).origin
	var h := sk.get_bone_global_pose(_hand).origin
	var palm_length := 0.0
	if _middle_knuckle >= 0:
		palm_length = h.distance_to(sk.get_bone_global_pose(_middle_knuckle).origin)

	# The wrist stops short of the target so the palm centre lands on it.
	var goal := palm_target - (palm_target - s).normalized() * palm_length * PALM_CENTER
	if (goal - s).length_squared() < 0.0001:
		return
	_reach(goal, pole)
	# Second pass removes the error left by the wrist angle.
	goal += palm_target - _palm_point()
	_reach(goal, pole)
	_curl_fingers(palm_target)
	palm_world = sk.global_transform * _palm_point()
	_update_palm_basis()


## World-space orientation for a held object: Y runs along the knuckle line (like a bar
## gripped in a fist), Z points back toward the titan.
func _update_palm_basis() -> void:
	var sk := get_skeleton()
	if _index_knuckle < 0 or _pinky_knuckle < 0 or _middle_knuckle < 0:
		return
	var to_world := sk.global_transform.basis
	var across: Vector3 = to_world * (sk.get_bone_global_pose(_pinky_knuckle).origin \
			- sk.get_bone_global_pose(_index_knuckle).origin)
	var fingers: Vector3 = to_world * (sk.get_bone_global_pose(_middle_knuckle).origin \
			- sk.get_bone_global_pose(_hand).origin)
	var up := across.normalized()
	if up.dot(Vector3.UP) < 0.0:
		up = -up
	var back := -fingers
	back = (back - up * back.dot(up)).normalized()
	if back.length_squared() < 0.5:
		return
	palm_basis = Basis(up.cross(back), up, back)


## Skeleton-space centre of the palm, between the wrist and the middle knuckle.
func _palm_point() -> Vector3:
	var sk := get_skeleton()
	var wrist := sk.get_bone_global_pose(_hand).origin
	if _middle_knuckle < 0:
		return wrist
	return wrist.lerp(sk.get_bone_global_pose(_middle_knuckle).origin, PALM_CENTER)


## Two-bone IK: places the wrist at goal (skeleton space), bending the elbow toward pole.
func _reach(goal: Vector3, pole: Vector3) -> void:
	var sk := get_skeleton()
	var s := sk.get_bone_global_pose(_shoulder).origin
	var e := sk.get_bone_global_pose(_elbow).origin
	var h := sk.get_bone_global_pose(_hand).origin
	var upper := s.distance_to(e)
	var lower := e.distance_to(h)
	var to_goal := goal - s
	var dir := to_goal.normalized()
	var dist := clampf(to_goal.length(), absf(upper - lower) + 0.001, upper + lower - 0.001)
	var along := (upper * upper - lower * lower + dist * dist) / (2.0 * dist)
	var height := sqrt(maxf(upper * upper - along * along, 0.0))
	var bend := pole - dir * pole.dot(dir)
	bend = bend.normalized() if bend.length_squared() > 0.0001 else Vector3.UP

	_aim(_shoulder, _elbow, s + dir * along + bend * height)
	_aim(_elbow, _hand, s + dir * dist)


## Rotates a bone so the direction to its child points at the given skeleton-space position.
func _aim(bone: int, child: int, want_pos: Vector3) -> void:
	var sk := get_skeleton()
	var g := sk.get_bone_global_pose(bone)
	var current := sk.get_bone_global_pose(child).origin - g.origin
	var wanted := want_pos - g.origin
	if current.length_squared() < 0.000001 or wanted.length_squared() < 0.000001:
		return
	var rotated := Basis(Quaternion(current.normalized(), wanted.normalized())) * g.basis
	_set_global_basis(bone, rotated, weight)


## Bends every finger segment toward the point, forming a fist around it.
func _curl_fingers(point: Vector3) -> void:
	var sk := get_skeleton()
	for finger in _fingers:
		var bones: Array = finger.bones
		for i in bones.size():
			var g := sk.get_bone_global_pose(bones[i])
			var along: Vector3
			if i + 1 < bones.size():
				along = sk.get_bone_global_pose(bones[i + 1]).origin - g.origin
			else:
				along = g.origin - sk.get_bone_global_pose(bones[i - 1]).origin
			var axis := along.cross(point - g.origin)
			if axis.length_squared() < 0.00000001:
				continue
			var angle := deg_to_rad(finger.curl[i] + SQUEEZE_EXTRA_DEG * squeeze) * weight * grip
			_set_global_basis(bones[i], Basis(axis.normalized(), angle) * g.basis, 1.0)


## Sets a bone's skeleton-space rotation, blending from its current pose by amount.
func _set_global_basis(bone: int, global_basis: Basis, amount: float) -> void:
	var sk := get_skeleton()
	var parent := sk.get_bone_parent(bone)
	var parent_basis := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	var local := (parent_basis.inverse() * global_basis.orthonormalized()).get_rotation_quaternion()
	sk.set_bone_pose_rotation(bone, sk.get_bone_pose_rotation(bone).slerp(local, amount))
