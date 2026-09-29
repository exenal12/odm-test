extends Node3D
## A repeatable, lightweight forest course for ODM traversal.

const WORLD_LAYER := 1
const GRAPPLE_LAYER := 2
const BASE_FOREST_HALF_SIZE := 95.0
const MAP_SCALE := 1.5
const FOREST_HALF_SIZE := BASE_FOREST_HALF_SIZE * MAP_SCALE
const VISUAL_FLOOR_MARGIN := 5.0
const TREE_SPACING := 20.0
const BASE_TREE_COUNT := 76
const SUPPLY_PLATFORM_COUNT := 6
## Deck height; titan swats reach roughly 20 m, so stay clear of them.
const SUPPLY_PLATFORM_HEIGHT := 24.0
const DECK_THICKNESS := 0.4
const GasSupplierScript := preload("res://scripts/world/gas_supplier.gd")

var _rng := RandomNumberGenerator.new()
var _bark_material: StandardMaterial3D
var _dark_bark_material: StandardMaterial3D
var _leaf_materials: Array[StandardMaterial3D] = []
var _ground_material: StandardMaterial3D
var _rock_material: StandardMaterial3D
var _wood_material: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 21974
	_bark_material = _material(Color(0.25, 0.17, 0.11))
	_dark_bark_material = _material(Color(0.16, 0.12, 0.09))
	_ground_material = _material(Color(0.18, 0.26, 0.15))
	_rock_material = _material(Color(0.27, 0.30, 0.27))
	_wood_material = _material(Color(0.52, 0.36, 0.2))
	_leaf_materials = [
		_material(Color(0.10, 0.23, 0.14)),
		_material(Color(0.15, 0.30, 0.17)),
		_material(Color(0.20, 0.34, 0.19)),
	]
	_build_ground()
	MapBounds.add_to(self, Vector2(FOREST_HALF_SIZE, FOREST_HALF_SIZE), WORLD_LAYER)
	_build_trees()
	_build_supply_platforms()
	_build_undergrowth()
	_build_navigation()


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
	# Keep visible ground beneath the player model when its collider reaches a wall.
	mesh.size = Vector3((FOREST_HALF_SIZE + VISUAL_FLOOR_MARGIN) * 2.0, 1.0,
		(FOREST_HALF_SIZE + VISUAL_FLOOR_MARGIN) * 2.0)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _ground_material
	body.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = Vector3(FOREST_HALF_SIZE * 2.0, 1.0, FOREST_HALF_SIZE * 2.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _build_trees() -> void:
	var grove := Node3D.new()
	grove.name = "GiantTrees"
	grove.add_to_group("nav_geometry")
	add_child(grove)
	var grid_radius := floori((FOREST_HALF_SIZE - 15.0) / TREE_SPACING)
	for gx in range(-grid_radius, grid_radius + 1):
		for gz in range(-grid_radius, grid_radius + 1):
			var x := float(gx) * TREE_SPACING + _rng.randf_range(-5.0, 5.0)
			var z := float(gz) * TREE_SPACING + _rng.randf_range(-5.0, 5.0)
			# Leave a clear landing zone and a loose northbound flying lane.
			if Vector2(x, z).length() < 12.0 or (absf(x) < 5.0 and z < -10.0):
				continue
			var tree := Node3D.new()
			tree.name = "GiantTree_%d_%d" % [gx + grid_radius, gz + grid_radius]
			tree.position = Vector3(x, 0.0, z)
			grove.add_child(tree)
			_build_tree(tree)
	_fill_outer_grove(grove, roundi(float(BASE_TREE_COUNT) * MAP_SCALE * MAP_SCALE), grid_radius)


## Fills gaps around the new perimeter so trees per square meter stay steady.
func _fill_outer_grove(grove: Node3D, target_count: int, grid_radius: int) -> void:
	var limit := FOREST_HALF_SIZE - 8.0
	var outer_band := float(grid_radius) * TREE_SPACING - 8.0
	var attempts := 0
	while grove.get_child_count() < target_count and attempts < 2000:
		attempts += 1
		var x := _rng.randf_range(-limit, limit)
		var z := _rng.randf_range(-limit, limit)
		if maxf(absf(x), absf(z)) < outer_band or (absf(x) < 5.0 and z < -10.0):
			continue
		var candidate := Vector2(x, z)
		var clear := true
		for existing in grove.get_children():
			var tree_pos := Vector2(existing.position.x, existing.position.z)
			if candidate.distance_squared_to(tree_pos) < 15.0 * 15.0:
				clear = false
				break
		if not clear:
			continue
		var tree := Node3D.new()
		tree.name = "GiantTree_Outer_%d" % grove.get_child_count()
		tree.position = Vector3(x, 0.0, z)
		grove.add_child(tree)
		_build_tree(tree)

func _build_tree(tree: Node3D) -> void:
	var height := _rng.randf_range(34.0, 52.0)
	var radius := _rng.randf_range(2.4, 3.8)
	tree.set_meta("height", height)
	tree.set_meta("radius", radius)
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


## Adds wooden platforms with kneeling gas suppliers to a few trees.
func _build_supply_platforms() -> void:
	var grove := get_node("GiantTrees")
	var picker := RandomNumberGenerator.new()
	picker.seed = 5150
	var candidates: Array[Node3D] = []
	for child in grove.get_children():
		var tree := child as Node3D
		if tree != null and tree.position.length() > 30.0 \
				and float(tree.get_meta("height")) >= SUPPLY_PLATFORM_HEIGHT + 14.0:
			candidates.append(tree)
	var chosen: Array[Node3D] = []
	var attempts := 0
	while chosen.size() < SUPPLY_PLATFORM_COUNT and attempts < 500 and not candidates.is_empty():
		attempts += 1
		var tree := candidates[picker.randi_range(0, candidates.size() - 1)]
		var spaced := true
		for other in chosen:
			if other.position.distance_to(tree.position) < 60.0:
				spaced = false
				break
		if spaced:
			chosen.append(tree)
	for tree in chosen:
		_build_supply_platform(tree)


func _build_supply_platform(tree: Node3D) -> void:
	var height: float = tree.get_meta("height")
	var base_radius: float = tree.get_meta("radius")
	var y := SUPPLY_PLATFORM_HEIGHT
	var trunk_radius := _trunk_radius_at(base_radius, height, y)
	var reach := trunk_radius + 3.5
	_clear_branches_near(tree, y, reach)
	var platform := Node3D.new()
	platform.name = "SupplyPlatform"
	platform.position = Vector3(0, y, 0)
	tree.add_child(platform)
	var deck := _cylinder_body(platform, "Deck", Vector3.ZERO, DECK_THICKNESS, reach,
		_wood_material, false)
	var deck_mesh := (deck.get_child(0) as MeshInstance3D).mesh as CylinderMesh
	deck_mesh.top_radius = reach
	deck_mesh.radial_segments = 24
	var deck_bottom := -DECK_THICKNESS * 0.5
	var strut_drop := 1.4
	# 0.9x the trunk radius sits inside even the flat faces of the 8-sided trunk mesh.
	var strut_root := _trunk_radius_at(base_radius, height, y - strut_drop) * 0.9
	for i in 4:
		var dir := Vector3(cos(TAU * float(i) / 4.0 + PI * 0.25), 0.0,
			sin(TAU * float(i) / 4.0 + PI * 0.25))
		_segment(platform, "Strut_%d" % i, dir * strut_root + Vector3.DOWN * strut_drop,
			dir * (trunk_radius + 1.8) + Vector3.UP * (deck_bottom + 0.1), 0.18,
			_wood_material, false)
	var angle := picker_angle(tree)
	var supplier := GasSupplierScript.new() as Node3D
	supplier.name = "GasSupplier"
	supplier.set("deck_radius", reach)
	supplier.set("trunk_radius", base_radius)
	supplier.position = Vector3(cos(angle), 0.0, sin(angle)) * (trunk_radius + 2.0) \
		+ Vector3.UP * DECK_THICKNESS * 0.5
	# Face outward toward approaching players.
	supplier.rotation.y = atan2(cos(angle), sin(angle))
	platform.add_child(supplier)


## Matches the trunk mesh, which tapers to 75% of its base radius at the top.
func _trunk_radius_at(base_radius: float, height: float, y: float) -> float:
	return base_radius * (1.0 - 0.25 * clampf(y / height, 0.0, 1.0))


## Removes branches and canopies that would pass through the platform or its headroom.
func _clear_branches_near(tree: Node3D, y: float, reach: float) -> void:
	var low := y - 2.5
	var high := y + 3.0
	for child in tree.get_children():
		var node := child as Node3D
		if node.name.begins_with("Branch_"):
			var length := ((node.get_child(0) as MeshInstance3D).mesh as CylinderMesh).height
			var axis := node.basis.y * length * 0.5
			for step in 11:
				var p := node.position - axis + axis * 2.0 * float(step) / 10.0
				if Vector2(p.x, p.z).length() <= reach + 1.5 and p.y > low - 1.0 and p.y < high + 1.0:
					node.free()
					break
		elif node.name.begins_with("Canopy"):
			var half := node.scale
			if Vector2(node.position.x, node.position.z).length() - half.x <= reach + 1.0 \
					and node.position.y - half.y < high and node.position.y + half.y > low:
				node.free()


func picker_angle(tree: Node3D) -> float:
	return fposmod(tree.position.x * 0.37 + tree.position.z * 0.53, TAU)


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
	var area_scale := MAP_SCALE * MAP_SCALE
	var fern_limit := FOREST_HALF_SIZE - 5.0
	for i in roundi(95.0 * area_scale):
		var pos := Vector3(_rng.randf_range(-fern_limit, fern_limit), 0.0,
			_rng.randf_range(-fern_limit, fern_limit))
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
	var rock_limit := FOREST_HALF_SIZE - 10.0
	for i in roundi(18.0 * area_scale):
		var rock := MeshInstance3D.new()
		rock.name = "MossyRock_%d" % i
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		rock.mesh = mesh
		rock.position = Vector3(_rng.randf_range(-rock_limit, rock_limit), 0.35,
			_rng.randf_range(-rock_limit, rock_limit))
		rock.scale = Vector3(1.3, 0.6, 1.0)
		rock.material_override = _rock_material
		details.add_child(rock)


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
