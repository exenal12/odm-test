extends SkeletonModifier3D
## Two-bone leg IK that places an ankle at a world-space point, bending the knee toward
## pole_world. The foot keeps its animated orientation so the sole stays level.

## 0 = animation only, 1 = fully IK-driven.
var weight: float = 0.0
var target_world: Vector3
var pole_world: Vector3 = Vector3.FORWARD

var _hip: int = -1
var _knee: int = -1
var _ankle: int = -1


func setup(thigh: String, shin: String, foot: String) -> void:
	var sk := get_skeleton()
	_hip = sk.find_bone(thigh)
	_knee = sk.find_bone(shin)
	_ankle = sk.find_bone(foot)


## Thigh plus shin length in world units.
func leg_length() -> float:
	var sk := get_skeleton()
	var h := sk.get_bone_global_pose(_hip).origin
	var k := sk.get_bone_global_pose(_knee).origin
	var a := sk.get_bone_global_pose(_ankle).origin
	return (h.distance_to(k) + k.distance_to(a)) * sk.global_transform.basis.get_scale().x


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or weight <= 0.001 or _hip < 0 or _knee < 0 or _ankle < 0:
		return
	var foot_basis := sk.get_bone_global_pose(_ankle).basis
	var inv := sk.global_transform.affine_inverse()
	var goal := inv * target_world
	var pole := (inv.basis * pole_world).normalized()
	var h := sk.get_bone_global_pose(_hip).origin
	var upper := h.distance_to(sk.get_bone_global_pose(_knee).origin)
	var lower := sk.get_bone_global_pose(_knee).origin.distance_to(sk.get_bone_global_pose(_ankle).origin)
	var to_goal := goal - h
	if to_goal.length_squared() < 0.0001:
		return
	var dir := to_goal.normalized()
	var dist := clampf(to_goal.length(), absf(upper - lower) + 0.001, upper + lower - 0.001)
	var along := (upper * upper - lower * lower + dist * dist) / (2.0 * dist)
	var height := sqrt(maxf(upper * upper - along * along, 0.0))
	var bend := pole - dir * pole.dot(dir)
	bend = bend.normalized() if bend.length_squared() > 0.0001 else Vector3.FORWARD
	_aim(_hip, _knee, h + dir * along + bend * height)
	_aim(_knee, _ankle, h + dir * dist)
	_set_global_basis(_ankle, foot_basis, weight)


func _aim(bone: int, child: int, want_pos: Vector3) -> void:
	var sk := get_skeleton()
	var g := sk.get_bone_global_pose(bone)
	var current := sk.get_bone_global_pose(child).origin - g.origin
	var wanted := want_pos - g.origin
	if current.length_squared() < 0.000001 or wanted.length_squared() < 0.000001:
		return
	_set_global_basis(bone, Basis(Quaternion(current.normalized(), wanted.normalized())) * g.basis, weight)


func _set_global_basis(bone: int, global_basis: Basis, amount: float) -> void:
	var sk := get_skeleton()
	var parent := sk.get_bone_parent(bone)
	var parent_basis := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	var local := (parent_basis.inverse() * global_basis.orthonormalized()).get_rotation_quaternion()
	sk.set_bone_pose_rotation(bone, sk.get_bone_pose_rotation(bone).slerp(local, amount))
