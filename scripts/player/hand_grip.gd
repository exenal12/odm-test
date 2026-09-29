class_name HandGrip
extends SkeletonModifier3D
## Wraps each hand's fingers around the handle held on its B-handProp bone.
## The handle is a "GripAxis" node (local Y along the handle) inside the prop's
## BoneAttachment3D. Each finger segment is rotated about the handle axis until its
## far end lands on a circle around the handle, so the fist closes on the grip.

## Distance from the handle axis to the finger bones' centerline.
@export var finger_radius: float = 0.027
## The thumb closes over the fingers, so it wraps slightly wider.
@export var thumb_radius: float = 0.036
## Largest bend applied to a single segment.
@export var max_bend_degrees: float = 115.0

const FINGERS := ["indexFinger", "middleFinger", "ringFinger", "pinky"]
## The last segment has no child bone; its length is this fraction of the one before.
const TIP_FRACTION := 0.8

var _hands: Array[Dictionary] = []
var _resolved := false


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not _resolved:
		_resolve(sk)
	for hand in _hands:
		var grip_node := hand.grip as Node3D
		if not is_instance_valid(grip_node) or not grip_node.is_visible_in_tree():
			continue
		var grip: Transform3D = sk.get_bone_global_pose(hand.prop) * hand.offset
		var axis := grip.basis.y.normalized()
		for chain in hand.fingers:
			_reset(sk, chain.bones)
		for chain in hand.fingers:
			for i in chain.bones.size():
				_wrap(sk, chain.bones[i], chain.along[i], grip.origin, axis, chain.radius, chain.sense)


## Finds every prop attachment that holds a GripAxis and caches its finger chains.
func _resolve(sk: Skeleton3D) -> void:
	_resolved = true
	for child in sk.get_children():
		var attachment := child as BoneAttachment3D
		if attachment == null or not String(attachment.bone_name).begins_with("B-handProp"):
			continue
		var grip := attachment.find_child("GripAxis", true, false) as Node3D
		if grip == null:
			continue
		var side := String(attachment.bone_name).trim_prefix("B-handProp")
		var prop := sk.find_bone(attachment.bone_name)
		var offset := Transform3D.IDENTITY
		var node: Node = grip
		while node != attachment:
			offset = (node as Node3D).transform * offset
			node = node.get_parent()
		var hand := {"prop": prop, "offset": offset, "grip": grip, "fingers": []}
		var finger_sense := 0.0
		for finger in FINGERS + ["thumb"]:
			var bones: Array[int] = []
			for i in 3:
				bones.append(sk.find_bone("B-%s0%d%s" % [finger, i + 1, side]))
			if bones.has(-1):
				continue
			var chain := {"bones": bones, "along": _segments(sk, bones),
				"radius": thumb_radius if finger == "thumb" else finger_radius}
			if finger == "middleFinger":
				finger_sense = _curl_sense(sk, bones[0], chain.along[0], prop, offset)
			hand.fingers.append(chain)
		# Fingers and thumb wrap the handle from opposite sides.
		for chain in hand.fingers:
			chain.sense = -finger_sense if chain.radius == thumb_radius else finger_sense
		_hands.append(hand)


## Each segment's vector from its joint to the next, in the bone's own rest frame.
func _segments(sk: Skeleton3D, bones: Array[int]) -> Array[Vector3]:
	var along: Array[Vector3] = []
	for i in bones.size():
		if i + 1 < bones.size():
			along.append(sk.get_bone_rest(bones[i + 1]).origin)
		else:
			var rest := sk.get_bone_rest(bones[i])
			along.append(rest.basis.inverse() * rest.origin * TIP_FRACTION)
	return along


## Rotation direction about the handle axis (+1 or -1) that brings the middle
## finger's first segment in toward the handle, measured in the rest pose.
func _curl_sense(sk: Skeleton3D, bone: int, along: Vector3, prop: int, offset: Transform3D) -> float:
	var grip := sk.get_bone_global_rest(prop) * offset
	var axis := grip.basis.y.normalized()
	var g := sk.get_bone_global_rest(bone)
	var p := g.origin - grip.origin
	p -= axis * p.dot(axis)
	var s := g.basis * along
	s -= axis * s.dot(axis)
	return -1.0 if p.dot(axis.cross(s)) > 0.0 else 1.0


func _reset(sk: Skeleton3D, bones: Array[int]) -> void:
	for bone in bones:
		sk.set_bone_pose_rotation(bone, sk.get_bone_rest(bone).basis.get_rotation_quaternion())


## Rotates one segment about the handle axis so its far end sits on the wrap circle.
func _wrap(sk: Skeleton3D, bone: int, along: Vector3, center: Vector3, axis: Vector3,
		radius: float, sense: float) -> void:
	var g := sk.get_bone_global_pose(bone)
	var p := g.origin - center
	p -= axis * p.dot(axis)
	var s := g.basis * along
	s -= axis * s.dot(axis)
	var length := s.length()
	if length < 0.00001:
		return
	var u := s / length
	var w := axis.cross(u)
	# The far end traces p + length * (cos t * u + sin t * w) as the segment turns by t,
	# so hitting the circle means alpha * cos t + beta * sin t = k.
	var alpha := p.dot(u)
	var beta := p.dot(w)
	var rho := sqrt(alpha * alpha + beta * beta)
	if rho < 0.00001:
		return
	var k := (radius * radius - p.length_squared() - length * length) / (2.0 * length)
	var phi := atan2(beta, alpha)
	var angle := 0.0
	if k / rho <= -1.0:
		angle = wrapf(phi + PI, -PI, PI)
	elif k / rho < 1.0:
		var spread := acos(k / rho)
		var best := INF
		for candidate in [wrapf(phi + spread, -PI, PI), wrapf(phi - spread, -PI, PI)]:
			if candidate * sense >= 0.0 and absf(candidate) < best:
				best = absf(candidate)
				angle = candidate
	if angle * sense <= 0.0:
		return
	angle = sense * minf(absf(angle), deg_to_rad(max_bend_degrees))
	var turned := Basis(axis, angle) * g.basis
	var parent := sk.get_bone_parent(bone)
	var parent_basis := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	sk.set_bone_pose_rotation(bone, (parent_basis.inverse() * turned).get_rotation_quaternion())
