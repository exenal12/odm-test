extends Node3D
## A repeatable, lightweight forest course for ODM traversal.

const WORLD_LAYER := 1
const GRAPPLE_LAYER := 2
const FOREST_HALF_SIZE := 95.0

var _rng := RandomNumberGenerator.new()
var _bark_material: StandardMaterial3D
var _dark_bark_material: StandardMaterial3D
var _leaf_materials: Array[StandardMaterial3D] = []
var _ground_material: StandardMaterial3D
var _rock_material: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 21974
	_bark_material = _material(Color(0.25, 0.17, 0.11))
	_dark_bark_material = _material(Color(0.16, 0.12, 0.09))
	_ground_material = _material(Color(0.18, 0.26, 0.15))
	_rock_material = _material(Color(0.27, 0.30, 0.27))
	_leaf_materials = [
		_material(Color(0.10, 0.23, 0.14)),
		_material(Color(0.15, 0.30, 0.17)),
		_material(Color(0.20, 0.34, 0.19)),
	]
	_build_ground()
	MapBounds.add_to(self, Vector2(FOREST_HALF_SIZE, FOREST_HALF_SIZE), WORLD_LAYER)
	_build_trees()
	_build_undergrowth()
	_build_refills()


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "ForestFloor"
	body.add_to_group("nav_geometry")
	body.position.y = -0.5
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(FOREST_HALF_SIZE * 2.0, 1.0, FOREST_HALF_SIZE * 2.0)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _ground_material
	body.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _build_trees() -> void:
	var grove := Node3D.new()
	grove.name = "GiantTrees"
	grove.add_to_group("nav_geometry")
	add_child(grove)
	for gx in range(-4, 5):
		for gz in range(-4, 5):
			var x := float(gx) * 20.0 + _rng.randf_range(-5.0, 5.0)
			var z := float(gz) * 20.0 + _rng.randf_range(-5.0, 5.0)
			# Leave a clear landing zone and a loose northbound flying lane.
			if Vector2(x, z).length() < 12.0 or (absf(x) < 5.0 and z < -10.0):
				continue
			var tree := Node3D.new()
			tree.name = "GiantTree_%d_%d" % [gx + 4, gz + 4]
			tree.position = Vector3(x, 0.0, z)
			grove.add_child(tree)
			_build_tree(tree)


func _build_tree(tree: Node3D) -> void:
	var height := _rng.randf_range(34.0, 52.0)
	var radius := _rng.randf_range(2.4, 3.8)
	_cylinder_body(tree, "Trunk", Vector3(0, height * 0.5, 0), height, radius,
		_bark_material, true)
	# Dark buttress roots broaden the base and make the trunks read as ancient trees.
	for i in 4:
		var angle := TAU * float(i) / 4.0 + _rng.randf_range(-0.2, 0.2)
		var root_end := Vector3(cos(angle) * (radius + 4.0), 0.35,
			sin(angle) * (radius + 4.0))
		_segment(tree, "Root_%d" % i, Vector3(0, 2.0, 0), root_end,
			_rng.randf_range(0.8, 1.3), _dark_bark_material, true)
	# Long radial branches create intermediate hook targets below the crown.
	for tier in 3:
		var branch_y := height * (0.43 + float(tier) * 0.17)
		for arm in 3:
			var angle := TAU * float(arm) / 3.0 + float(tier) * 0.7 + _rng.randf_range(-0.2, 0.2)
			var reach := _rng.randf_range(7.0, 11.0)
			var endpoint := Vector3(cos(angle) * reach, branch_y + _rng.randf_range(1.0, 3.0),
				sin(angle) * reach)
			_segment(tree, "Branch_%d_%d" % [tier, arm],
				Vector3(0, branch_y - 0.8, 0), endpoint,
				1.0 - float(tier) * 0.12, _bark_material, true)
			if tier > 0:
				_foliage(tree, endpoint + Vector3.UP * 1.2,
					Vector3(4.0, 2.8, 4.0), tier + arm)
	_foliage(tree, Vector3(0, height - 1.0, 0), Vector3(7.0, 5.0, 7.0), 0)
	_foliage(tree, Vector3(0, height + 3.0, 0), Vector3(4.5, 4.0, 4.5), 1)


func _cylinder_body(parent: Node3D, name: String, pos: Vector3, height: float,
		radius: float, material: Material, grappleable: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	body.collision_layer = WORLD_LAYER | (GRAPPLE_LAYER if grappleable else 0)
	body.collision_mask = 0
	if grappleable:
		body.add_to_group("grappleable")
	var mesh := CylinderMesh.new()
	mesh.height = height
	mesh.top_radius = radius * 0.75
	mesh.bottom_radius = radius
	mesh.radial_segments = 8
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	var shape := CylinderShape3D.new()
	shape.height = height
	shape.radius = radius
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	return body


func _segment(parent: Node3D, name: String, from: Vector3, to: Vector3,
		radius: float, material: Material, grappleable: bool) -> void:
	var direction := to - from
	var body := _cylinder_body(parent, name, (from + to) * 0.5,
		direction.length(), radius, material, grappleable)
	body.quaternion = Quaternion(Vector3.UP, direction.normalized())


func _foliage(parent: Node3D, pos: Vector3, size: Vector3, palette_index: int) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var visual := MeshInstance3D.new()
	visual.name = "Canopy"
	visual.mesh = mesh
	visual.position = pos
	visual.scale = size
	visual.material_override = _leaf_materials[palette_index % _leaf_materials.size()]
	parent.add_child(visual)


func _build_undergrowth() -> void:
	var details := Node3D.new()
	details.name = "Undergrowth"
	add_child(details)
	for i in 95:
		var pos := Vector3(_rng.randf_range(-90.0, 90.0), 0.0,
			_rng.randf_range(-90.0, 90.0))
		if pos.length() < 9.0:
			continue
		var bush := MeshInstance3D.new()
		bush.name = "Fern_%d" % i
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		bush.mesh = mesh
		bush.position = pos + Vector3.UP * 0.55
		bush.scale = Vector3(_rng.randf_range(0.8, 1.8), 0.5,
			_rng.randf_range(0.8, 1.8))
		bush.material_override = _leaf_materials[i % _leaf_materials.size()]
		details.add_child(bush)
	for i in 18:
		var rock := MeshInstance3D.new()
		rock.name = "MossyRock_%d" % i
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		rock.mesh = mesh
		rock.position = Vector3(_rng.randf_range(-85.0, 85.0), 0.35,
			_rng.randf_range(-85.0, 85.0))
		rock.scale = Vector3(1.3, 0.6, 1.0)
		rock.material_override = _rock_material
		details.add_child(rock)


func _build_refills() -> void:
	for pos in [Vector3(7, 0.6, 7), Vector3(1, 0.6, -45),
			Vector3(-46, 0.6, 26), Vector3(43, 0.6, 45)]:
		var station := (load("res://scripts/world/gas_refill.gd") as GDScript).new() as Area3D
		station.name = "GasRefill"
		station.position = pos
		station.collision_layer = 0
		station.collision_mask = WORLD_LAYER
		var shape := SphereShape3D.new()
		shape.radius = 2.0
		var collider := CollisionShape3D.new()
		collider.shape = shape
		station.add_child(collider)
		var glow := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.6
		mesh.height = 1.2
		glow.mesh = mesh
		var material := _material(Color(0.35, 0.9, 0.35))
		material.emission_enabled = true
		material.emission = Color(0.1, 0.7, 0.15)
		material.emission_energy_multiplier = 2.0
		glow.material_override = material
		station.add_child(glow)
		add_child(station)


## Bakes a titan-sized navmesh from the floor and trunk colliders (in a thread).
func _build_navigation() -> void:
	var navmesh := NavigationMesh.new()
	navmesh.cell_size = 0.5
	navmesh.cell_height = 0.25
	navmesh.agent_radius = 2.5
	navmesh.agent_height = 12.0
	navmesh.agent_max_climb = 0.5
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = WORLD_LAYER
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navmesh.geometry_source_group_name = &"nav_geometry"
	var region := NavigationRegion3D.new()
	region.name = "TitanNavRegion"
	region.navigation_mesh = navmesh
	add_child(region)
	region.bake_navigation_mesh(true)
