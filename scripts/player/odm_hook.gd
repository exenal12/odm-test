class_name ODMHook
extends Node3D
## Single ODM hook: aim raycast, latch, cable length, and cable mesh.

enum State { IDLE, ATTACHED }

signal attached(anchor: Vector3)
signal detached

@export var is_left: bool = true
@export var cable_radius: float = 0.02
@export var cable_color: Color = Color(0.15, 0.15, 0.18)

var state: State = State.IDLE
var anchor_point: Vector3 = Vector3.ZERO
var cable_length: float = 0.0

var _cable_mesh: MeshInstance3D
var _tip_mesh: MeshInstance3D


func _ready() -> void:
	_cable_mesh = MeshInstance3D.new()
	_cable_mesh.name = "Cable"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = cable_radius
	cylinder.bottom_radius = cable_radius
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	_cable_mesh.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cable_color
	mat.roughness = 0.4
	_cable_mesh.material_override = mat
	_cable_mesh.visible = false
	add_child(_cable_mesh)

	_tip_mesh = MeshInstance3D.new()
	_tip_mesh.name = "Tip"
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	_tip_mesh.mesh = sphere
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.7, 0.15, 0.12)
	_tip_mesh.material_override = tip_mat
	_tip_mesh.visible = false
	add_child(_tip_mesh)


func is_attached() -> bool:
	return state == State.ATTACHED


func fire(
	origin: Vector3,
	direction: Vector3,
	max_range: float,
	space: PhysicsDirectSpaceState3D,
	collision_mask: int
) -> bool:
	detach()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * max_range)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false

	anchor_point = hit.position
	cable_length = origin.distance_to(anchor_point)
	state = State.ATTACHED
	_tip_mesh.visible = true
	_cable_mesh.visible = true
	attached.emit(anchor_point)
	return true


func detach() -> void:
	if state == State.IDLE:
		_cable_mesh.visible = false
		_tip_mesh.visible = false
		return
	state = State.IDLE
	_cable_mesh.visible = false
	_tip_mesh.visible = false
	detached.emit()


func shorten(amount: float, min_length: float = 1.5) -> void:
	if state != State.ATTACHED:
		return
	cable_length = maxf(min_length, cable_length - amount)


func update_visual(from_global: Vector3) -> void:
	if state != State.ATTACHED:
		_cable_mesh.visible = false
		_tip_mesh.visible = false
		return

	_tip_mesh.visible = true
	_tip_mesh.global_position = anchor_point

	var mid := (from_global + anchor_point) * 0.5
	var length := from_global.distance_to(anchor_point)
	if length < 0.01:
		_cable_mesh.visible = false
		return

	_cable_mesh.visible = true
	_cable_mesh.global_position = mid
	# CylinderMesh is Y-aligned; rotate to point from hip to anchor.
	var axis := (anchor_point - from_global).normalized()
	_cable_mesh.global_transform = Transform3D(_basis_from_y(axis), mid)
	var mesh := _cable_mesh.mesh as CylinderMesh
	if mesh:
		mesh.height = length


func _basis_from_y(y_axis: Vector3) -> Basis:
	var y := y_axis.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
