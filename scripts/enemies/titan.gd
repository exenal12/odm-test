class_name Titan
extends CharacterBody3D
## Titan enemy. Only hits on the nape kill it; body hits are ignored.

signal died(titan: Titan)

const NAPE_BONE := "B-neck"
## Nape offset from the neck bone in skeleton space (unscaled model units, -Z is the back).
const NAPE_OFFSET := Vector3(0.0, 0.05, -0.13)

## Hook and hit capsules: [from bone, to bone or skeleton-space offset, radius in model units].
const SEGMENTS := [
	["B-hips", "B-chest", 0.2], ["B-chest", "B-neck", 0.19],
	["B-neck", "B-head", 0.08], ["B-head", Vector3(0.0, 0.2, 0.0), 0.12],
	["B-upperArm.L", "B-forearm.L", 0.06], ["B-forearm.L", "B-hand.L", 0.05],
	["B-upperArm.R", "B-forearm.R", 0.06], ["B-forearm.R", "B-hand.R", 0.05],
	["B-thigh.L", "B-shin.L", 0.1], ["B-shin.L", "B-foot.L", 0.07], ["B-foot.L", "B-toe.L", 0.05],
	["B-thigh.R", "B-shin.R", 0.1], ["B-shin.R", "B-foot.R", 0.07], ["B-foot.R", "B-toe.R", 0.05],
]

@export var sink_duration: float = 1.5

@onready var nape: Area3D = $Nape
@onready var body_collider: CollisionShape3D = $CollisionShape3D
@onready var skeleton: Skeleton3D = $Model/Skeleton3D
@onready var animation_player: AnimationPlayer = $Model/AnimationPlayer
@onready var flash_mesh: MeshInstance3D = $Model/Skeleton3D/HumanM_BodyMesh

var alive: bool = true
var _neck_bone: int = -1
var _segments: Array[Dictionary] = []


func _ready() -> void:
	_neck_bone = skeleton.find_bone(NAPE_BONE)
	for def in SEGMENTS:
		_add_segment(def[0], def[1], def[2])


## Builds a kinematic capsule that follows the bones every physics frame.
## It is on the world and grappleable layers, so it blocks the player and takes hooks.
func _add_segment(from_bone: String, to: Variant, radius: float) -> void:
	var body := AnimatableBody3D.new()
	body.name = "Seg_" + from_bone
	body.collision_layer = 3
	body.collision_mask = 0
	body.add_to_group("grappleable")
	var shape := CapsuleShape3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	_segments.append({
		"body": body, "shape": shape, "from": skeleton.find_bone(from_bone),
		"to": skeleton.find_bone(to) if to is String else -1,
		"offset": to if to is Vector3 else Vector3.ZERO, "radius": radius,
	})


func _physics_process(_delta: float) -> void:
	var xform := skeleton.global_transform
	var scale_factor := xform.basis.get_scale().x
	for seg in _segments:
		var a: Vector3 = xform * skeleton.get_bone_global_pose(seg.from).origin
		var b: Vector3 = xform * (skeleton.get_bone_global_pose(seg.to).origin if seg.to >= 0
			else skeleton.get_bone_global_pose(seg.from).origin + seg.offset)
		var direction := b - a
		var length := direction.length()
		if length < 0.01:
			continue
		var radius: float = seg.radius * scale_factor
		var shape := seg.shape as CapsuleShape3D
		shape.radius = radius
		shape.height = length + radius * 2.0
		var body := seg.body as AnimatableBody3D
		body.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, direction / length)), (a + b) * 0.5)


func _process(_delta: float) -> void:
	if _neck_bone < 0:
		return
	var neck := skeleton.get_bone_global_pose(_neck_bone).origin
	nape.global_position = skeleton.global_transform * (neck + NAPE_OFFSET)


## Called by SwordCombat for any node the blade overlaps.
func on_sword_hit(target: Node3D, _damage: float) -> void:
	if not alive:
		return
	if target == nape:
		_die()
	else:
		_flash_deflect()


func _die() -> void:
	alive = false
	body_collider.set_deferred("disabled", true)
	for seg in _segments:
		(seg.body as AnimatableBody3D).collision_layer = 0
	nape.set_deferred("monitorable", false)
	animation_player.play(&"titan/Death")
	died.emit(self)
	await animation_player.animation_finished
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - 3.0, sink_duration)
	tween.tween_callback(queue_free)


func _flash_deflect() -> void:
	var material := flash_mesh.material_override as StandardMaterial3D
	if material == null:
		return
	var tween := create_tween()
	tween.tween_property(material, "emission_energy_multiplier", 1.5, 0.04)
	tween.tween_property(material, "emission_energy_multiplier", 0.0, 0.2)
