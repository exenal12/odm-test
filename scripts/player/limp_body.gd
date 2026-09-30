class_name LimpBody
extends SkeletonModifier3D
## Procedural looseness for a dead body: each listed bone is a damped spring
## that trails against the air while falling and flops when the body lands.
## Offsets are layered on top of whatever pose the animation produced.

## [bone, drag weight, stiffness]. Loose limbs have low stiffness and more drag.
const BONES := [
	["B-spine", 0.25, 70.0], ["B-chest", 0.25, 70.0],
	["B-neck", 0.35, 45.0], ["B-head", 0.45, 35.0],
	["B-upperArm.L", 1.0, 22.0], ["B-forearm.L", 0.7, 18.0], ["B-hand.L", 0.4, 18.0],
	["B-upperArm.R", 1.0, 22.0], ["B-forearm.R", 0.7, 18.0], ["B-hand.R", 0.4, 18.0],
	["B-thigh.L", 0.55, 30.0], ["B-shin.L", 0.6, 24.0],
	["B-thigh.R", 0.55, 30.0], ["B-shin.R", 0.6, 24.0],
]

## World-space velocity of the body; drives the airflow the limbs trail against.
var body_velocity: Vector3 = Vector3.ZERO
## Fall speed (m/s) at which limbs reach full drag.
@export var full_drag_speed: float = 14.0
@export_range(0.0, 90.0) var max_angle_deg: float = 65.0
## Fraction of critical damping; below 1 so limbs overshoot and wobble.
@export_range(0.05, 1.0) var damping_ratio: float = 0.3
@export var flutter: float = 0.25

var _bones: Array[int] = []
var _offset: Array[Vector3] = []
var _spin: Array[Vector3] = []
var _time: float = 0.0
var _airborne: bool = true


func _ready() -> void:
	active = false


## Starts from the current pose with a random jolt, as if the body was just struck.
func start(airborne: bool) -> void:
	var skeleton := get_skeleton()
	_bones.clear()
	_offset.clear()
	_spin.clear()
	for entry in BONES:
		_bones.append(skeleton.find_bone(entry[0]))
		_offset.append(Vector3.ZERO)
		_spin.append(_random_vector() * 6.0 * entry[1])
	_airborne = airborne
	influence = 1.0
	active = true


## Kicks every limb on impact, then eases the effect out once they have settled.
func land(impact_speed: float, settle_time: float = 0.9, fade_time: float = 0.6) -> void:
	_airborne = false
	var kick := clampf(impact_speed / full_drag_speed, 0.3, 1.5)
	for i in _spin.size():
		_spin[i] += (_random_vector() * 0.5 + Vector3.RIGHT * 0.8) * 9.0 * kick * BONES[i][1]
	var tween := create_tween()
	tween.tween_interval(settle_time)
	tween.tween_property(self, "influence", 0.0, maxf(fade_time, 0.01))
	tween.tween_callback(func() -> void: active = false)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _bones.is_empty():
		return
	var delta := get_process_delta_time()
	_time += delta
	var air := -(skeleton.global_basis.inverse() * body_velocity)
	var drag := clampf(air.length() / full_drag_speed, 0.0, 1.0) if _airborne else 0.0
	var max_angle := deg_to_rad(max_angle_deg)
	for i in _bones.size():
		var bone := _bones[i]
		if bone < 0:
			continue
		var weight: float = BONES[i][1]
		var stiffness: float = BONES[i][2]
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
		var local_rotation := skeleton.get_bone_pose_rotation(bone)
		var target := Vector3.ZERO
		if drag > 0.0:
			# Rotate the bone toward the direction the air pushes it.
			var direction := local_rotation * Vector3.UP
			var push := (parent_basis.inverse() * air).normalized()
			var axis := direction.cross(push)
			if axis.length() > 0.001:
				target = axis.normalized() * minf(direction.angle_to(push), max_angle) * weight * drag
			target += Vector3(sin(_time * 7.3 + i), sin(_time * 5.1 + i * 2.0), sin(_time * 6.2 + i * 3.0)) * flutter * weight * drag
		var damping := 2.0 * sqrt(stiffness) * damping_ratio
		_spin[i] += ((target - _offset[i]) * stiffness - _spin[i] * damping) * delta
		_offset[i] += _spin[i] * delta
		_offset[i] = _offset[i].limit_length(max_angle)
		var angle := _offset[i].length()
		if angle > 0.0001:
			var extra := Quaternion(_offset[i] / angle, angle)
			skeleton.set_bone_pose_rotation(bone, (extra * local_rotation).normalized())


static func _random_vector() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
