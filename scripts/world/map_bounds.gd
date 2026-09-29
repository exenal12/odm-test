class_name MapBounds
extends RefCounted
## Builds collision-only walls around a rectangular map floor.

const WALL_HEIGHT := 240.0
const WALL_THICKNESS := 2.0
const WALL_BOTTOM := -5.0


static func add_to(parent: Node3D, half_extents: Vector2, world_layer: int) -> Node3D:
	var bounds := Node3D.new()
	bounds.name = "BoundaryWalls"
	parent.add_child(bounds)

	var center_y := WALL_BOTTOM + WALL_HEIGHT * 0.5
	var x_side_length := half_extents.y * 2.0 + WALL_THICKNESS * 2.0
	var z_side_length := half_extents.x * 2.0 + WALL_THICKNESS * 2.0
	for side in [-1.0, 1.0]:
		_add_wall(bounds, "East" if side > 0.0 else "West",
			Vector3(side * (half_extents.x + WALL_THICKNESS * 0.5), center_y, 0.0),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, x_side_length), world_layer)
		_add_wall(bounds, "South" if side > 0.0 else "North",
			Vector3(0.0, center_y, side * (half_extents.y + WALL_THICKNESS * 0.5)),
			Vector3(z_side_length, WALL_HEIGHT, WALL_THICKNESS), world_layer)
	return bounds


static func _add_wall(parent: Node3D, wall_name: String, position: Vector3,
		size: Vector3, world_layer: int) -> void:
	var wall := StaticBody3D.new()
	wall.name = wall_name
	wall.position = position
	wall.collision_layer = world_layer
	wall.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	wall.add_child(collider)
	parent.add_child(wall)
