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
const BARK_SHADER := preload("res://scenes/world/shaders/bark.gdshader")
const LEAF_SHADER := preload("res://scenes/world/shaders/leaves.gdshader")
const GROUND_SHADER := preload("res://scenes/world/shaders/ground.gdshader")
const GRASS_SHADER := preload("res://scenes/world/shaders/grass.gdshader")
const FERN_SHADER := preload("res://scenes/world/shaders/fern.gdshader")
const ROCK_SHADER := preload("res://scenes/world/shaders/rock.gdshader")
const PLANK_SHADER := preload("res://scenes/world/shaders/planks.gdshader")
const EMBLEM_TEXTURE := preload("res://assets/textures/survey_corps_emblem.png")
## Undergrowth is scattered in square chunks so distant ones can be culled.
const DETAIL_CHUNK_SIZE := 24.0
const GRASS_PER_CHUNK := 260
const FERNS_PER_CHUNK := 14
const GRASS_VISIBLE_RANGE := 55.0
const FERN_VISIBLE_RANGE := 110.0

var _rng := RandomNumberGenerator.new()
## Separate stream for purely visual variation, so the layout stays the same.
var _look_rng := RandomNumberGenerator.new()
var _bark_material: Material
var _dark_bark_material: Material
var _leaf_materials: Array[Material] = []
var _ground_material: Material
var _rock_material: Material
var _wood_material: Material
var _deck_material: Material
var _canopy_mesh: SphereMesh


func _ready() -> void:
	_rng.seed = 21974
	_look_rng.seed = 7741
	_bark_material = _shader_material(BARK_SHADER, {})
	_dark_bark_material = _shader_material(BARK_SHADER, {
		"bark_color": Color(0.2, 0.15, 0.1), "moss_amount": 0.75, "ridges": 10.0})
	_ground_material = _shader_material(GROUND_SHADER, {})
	_rock_material = _shader_material(ROCK_SHADER, {})
	_wood_material = _material(Color(0.42, 0.29, 0.17))
	_deck_material = _shader_material(PLANK_SHADER, {})
	_leaf_materials = [
		_shader_material(LEAF_SHADER, {"leaf_dark": Color(0.05, 0.13, 0.06), "leaf_light": Color(0.24, 0.4, 0.13)}),
		_shader_material(LEAF_SHADER, {"leaf_dark": Color(0.07, 0.16, 0.06), "leaf_light": Color(0.33, 0.47, 0.15)}),
		_shader_material(LEAF_SHADER, {"leaf_dark": Color(0.09, 0.17, 0.05), "leaf_light": Color(0.42, 0.5, 0.17)}),
	]
	_canopy_mesh = SphereMesh.new()
	_canopy_mesh.radius = 1.0
	_canopy_mesh.height = 2.0
	_canopy_mesh.radial_segments = 20
	_canopy_mesh.rings = 12
	_build_ground()
	MapBounds.add_to(self, Vector2(FOREST_HALF_SIZE, FOREST_HALF_SIZE), WORLD_LAYER)
	_build_trees()
	_build_supply_platforms()
	_build_undergrowth()
	_build_backdrop()
	_build_navigation()


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _shader_material(shader: Shader, params: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	for key in params:
		material.set_shader_parameter(key, params[key])
	return material


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "ForestFloor"
	body.add_to_group("nav_geometry")
	body.add_to_group("surface_grass")
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
		_bark_material, true, 18)
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
	for i in chosen.size():
		_build_supply_platform(chosen[i], i)


func _build_supply_platform(tree: Node3D, index: int) -> void:
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
		_deck_material, false, 32)
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
	supplier.set("look_index", index)
	supplier.position = Vector3(cos(angle), 0.0, sin(angle)) * (trunk_radius + 2.0) \
		+ Vector3.UP * DECK_THICKNESS * 0.5
	# Face outward toward approaching players.
	supplier.rotation.y = atan2(cos(angle), sin(angle))
	platform.add_child(supplier)
	_dress_platform(platform, reach, trunk_radius, angle, DECK_THICKNESS * 0.5)


## Visual-only railing, lantern and banner so stations read as landmarks from a distance.
## Nothing here collides, so landing and refuelling are unaffected.
func _dress_platform(platform: Node3D, reach: float, trunk_radius: float, supplier_angle: float,
		deck_top: float) -> void:
	var dressing := Node3D.new()
	dressing.name = "Dressing"
	platform.add_child(dressing)
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.06
	post_mesh.bottom_radius = 0.07
	post_mesh.height = 1.1
	post_mesh.radial_segments = 6
	var rope_material := _material(Color(0.55, 0.45, 0.3))
	var post_radius := reach - 0.2
	var posts := 14
	# Leave the railing open in front of the supplier.
	var gap := deg_to_rad(40.0)
	var tops: Array[Vector3] = []
	for i in posts + 1:
		var a := supplier_angle + gap + (TAU - gap * 2.0) * float(i) / posts
		var base := Vector3(cos(a), 0.0, sin(a)) * post_radius + Vector3.UP * deck_top
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.material_override = _wood_material
		post.position = base + Vector3.UP * 0.55
		dressing.add_child(post)
		tops.append(base + Vector3.UP * 1.0)
	for i in tops.size() - 1:
		for drop in [0.0, 0.45]:
			var from: Vector3 = tops[i] + Vector3.DOWN * drop
			var to: Vector3 = tops[i + 1] + Vector3.DOWN * drop
			_visual_segment(dressing, from, to, 0.022, rope_material)

	var lantern_angle := supplier_angle + gap + 0.15
	var lantern_pos := Vector3(cos(lantern_angle), 0.0, sin(lantern_angle)) * post_radius \
		+ Vector3.UP * (deck_top + 1.35)
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(0.22, 0.3, 0.22)
	frame.mesh = frame_mesh
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.75, 0.4)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.62, 0.25)
	glass.emission_energy_multiplier = 3.0
	frame.material_override = glass
	frame.position = lantern_pos
	dressing.add_child(frame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.4)
	light.light_energy = 1.6
	light.omni_range = 9.0
	light.light_volumetric_fog_energy = 2.0
	light.position = lantern_pos
	dressing.add_child(light)

	# Banner hangs from a short spar on the trunk, a quarter turn from the supplier.
	var banner_angle := supplier_angle + PI * 0.5
	var out := Vector3(cos(banner_angle), 0.0, sin(banner_angle))
	var spar_start := out * (trunk_radius - 0.3) + Vector3.UP * 5.5
	var spar_end := out * (trunk_radius + 2.2) + Vector3.UP * 5.5
	_visual_segment(dressing, spar_start, spar_end, 0.07, _wood_material)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.13, 0.3, 0.2)
	cloth.roughness = 0.9
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var banner := MeshInstance3D.new()
	var banner_mesh := QuadMesh.new()
	banner_mesh.size = Vector2(1.5, 2.4)
	banner.mesh = banner_mesh
	banner.material_override = cloth
	var facing := Basis.looking_at(out.cross(Vector3.UP), Vector3.UP)
	banner.basis = facing
	banner.position = out * (trunk_radius + 1.3) + Vector3.UP * 4.25
	dressing.add_child(banner)
	var emblem_material := StandardMaterial3D.new()
	emblem_material.albedo_texture = EMBLEM_TEXTURE
	emblem_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	emblem_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	emblem_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for side in [1.0, -1.0]:
		var emblem := MeshInstance3D.new()
		var emblem_mesh := QuadMesh.new()
		emblem_mesh.size = Vector2(1.0, 1.0 * 149.0 / 111.0)
		emblem.mesh = emblem_mesh
		emblem.material_override = emblem_material
		emblem.basis = facing if side > 0.0 else facing * Basis(Vector3.UP, PI)
		emblem.position = banner.position + facing.z * 0.01 * side + Vector3.UP * 0.2
		dressing.add_child(emblem)


func _visual_segment(parent: Node3D, from: Vector3, to: Vector3, radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 6
	mesh.rings = 1
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = (from + to) * 0.5
	visual.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	parent.add_child(visual)


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
			# Leaf lumps reach about 35% past the canopy's scale.
			var half := node.scale * 1.35
			if Vector2(node.position.x, node.position.z).length() - half.x <= reach + 1.0 \
					and node.position.y - half.y < high and node.position.y + half.y > low:
				node.free()


func picker_angle(tree: Node3D) -> float:
	return fposmod(tree.position.x * 0.37 + tree.position.z * 0.53, TAU)


func _cylinder_body(parent: Node3D, name: String, pos: Vector3, height: float,
		radius: float, material: Material, grappleable: bool, segments: int = 10) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	body.collision_layer = WORLD_LAYER | (GRAPPLE_LAYER if grappleable else 0)
	body.collision_mask = 0
	if grappleable:
		body.add_to_group("grappleable")
	body.add_to_group("surface_wood")
	var mesh := CylinderMesh.new()
	mesh.height = height
	mesh.top_radius = radius * 0.75
	mesh.bottom_radius = radius
	mesh.radial_segments = segments
	mesh.rings = 1
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
	var visual := MeshInstance3D.new()
	visual.name = "Canopy"
	visual.mesh = _canopy_mesh
	visual.position = pos
	visual.scale = size * _look_rng.randf_range(0.9, 1.25)
	visual.rotation.y = _look_rng.randf() * TAU
	visual.material_override = _leaf_materials[palette_index % _leaf_materials.size()]
	visual.set_instance_shader_parameter(&"seed", _look_rng.randf() * 100.0)
	# The shader pushes lumps out past the unit sphere.
	visual.extra_cull_margin = 2.0
	parent.add_child(visual)


func _build_undergrowth() -> void:
	var details := Node3D.new()
	details.name = "Undergrowth"
	add_child(details)
	var grass_mesh := _grass_clump_mesh()
	var fern_mesh := _fern_mesh()
	var grass_material := _shader_material(GRASS_SHADER, {})
	var fern_material := _shader_material(FERN_SHADER, {})
	var limit := FOREST_HALF_SIZE - 3.0
	var chunks := ceili(limit * 2.0 / DETAIL_CHUNK_SIZE)
	for cx in chunks:
		for cz in chunks:
			var origin := Vector3(-limit + (cx + 0.5) * DETAIL_CHUNK_SIZE, 0.0,
				-limit + (cz + 0.5) * DETAIL_CHUNK_SIZE)
			_scatter_chunk(details, "Grass_%d_%d" % [cx, cz], origin, grass_mesh, grass_material,
				GRASS_PER_CHUNK, Vector2(0.6, 1.1), GRASS_VISIBLE_RANGE)
			_scatter_chunk(details, "Ferns_%d_%d" % [cx, cz], origin, fern_mesh, fern_material,
				FERNS_PER_CHUNK, Vector2(0.8, 1.6), FERN_VISIBLE_RANGE)
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 16
	rock_mesh.rings = 8
	var rock_limit := FOREST_HALF_SIZE - 10.0
	for i in roundi(18.0 * MAP_SCALE * MAP_SCALE):
		var rock := MeshInstance3D.new()
		rock.name = "MossyRock_%d" % i
		rock.mesh = rock_mesh
		var size := _look_rng.randf_range(0.7, 1.8)
		rock.position = Vector3(_look_rng.randf_range(-rock_limit, rock_limit), size * 0.25,
			_look_rng.randf_range(-rock_limit, rock_limit))
		rock.scale = Vector3(1.3, 0.65, 1.0) * size
		rock.rotation.y = _look_rng.randf() * TAU
		rock.material_override = _rock_material
		rock.set_instance_shader_parameter(&"seed", _look_rng.randf() * 100.0)
		details.add_child(rock)


## Non-colliding trees and ground beyond the boundary walls, so the forest fades
## into the fog instead of ending at a visible edge.
func _build_backdrop() -> void:
	var backdrop := Node3D.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	var inner := FOREST_HALF_SIZE + 4.0
	var outer := FOREST_HALF_SIZE + 110.0
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(outer * 2.0, outer * 2.0)
	var floor_visual := MeshInstance3D.new()
	floor_visual.name = "OuterFloor"
	floor_visual.mesh = floor_mesh
	floor_visual.material_override = _ground_material
	floor_visual.position.y = -0.02
	backdrop.add_child(floor_visual)

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.75
	trunk_mesh.bottom_radius = 1.0
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 10
	trunk_mesh.rings = 1
	var trunks := MultiMesh.new()
	trunks.transform_format = MultiMesh.TRANSFORM_3D
	trunks.mesh = trunk_mesh
	var crowns := MultiMesh.new()
	crowns.transform_format = MultiMesh.TRANSFORM_3D
	crowns.mesh = _canopy_mesh
	var trunk_xforms: Array[Transform3D] = []
	var crown_xforms: Array[Transform3D] = []
	var attempts := 0
	while trunk_xforms.size() < 260 and attempts < 5000:
		attempts += 1
		var pos := Vector3(_look_rng.randf_range(-outer, outer), 0.0, _look_rng.randf_range(-outer, outer))
		if maxf(absf(pos.x), absf(pos.z)) < inner:
			continue
		var height := _look_rng.randf_range(34.0, 52.0)
		var radius := _look_rng.randf_range(2.4, 3.8)
		trunk_xforms.append(Transform3D(Basis.from_scale(Vector3(radius, height, radius)),
			pos + Vector3.UP * height * 0.5))
		for tier in 3:
			var spread := Vector3(_look_rng.randf_range(-4, 4), 0.0, _look_rng.randf_range(-4, 4)) * float(tier)
			var size := Vector3(7.0, 5.0, 7.0) * _look_rng.randf_range(0.8, 1.2) * (1.0 - tier * 0.2)
			var crown_basis := Basis(Vector3.UP, _look_rng.randf() * TAU).scaled(size)
			crown_xforms.append(Transform3D(crown_basis,
				pos + spread + Vector3.UP * (height - tier * 6.0)))
	trunks.instance_count = trunk_xforms.size()
	for i in trunk_xforms.size():
		trunks.set_instance_transform(i, trunk_xforms[i])
	crowns.instance_count = crown_xforms.size()
	for i in crown_xforms.size():
		crowns.set_instance_transform(i, crown_xforms[i])
	for pair in [[trunks, _bark_material, "BackdropTrunks"], [crowns, _leaf_materials[1], "BackdropCrowns"]]:
		var instance := MultiMeshInstance3D.new()
		instance.name = pair[2]
		instance.multimesh = pair[0]
		instance.material_override = pair[1]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		backdrop.add_child(instance)


## One MultiMesh of randomly placed, rotated and tinted copies within a chunk.
func _scatter_chunk(parent: Node3D, name: String, origin: Vector3, mesh: Mesh,
		material: Material, count: int, scale_range: Vector2, visible_range: float) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	var half := DETAIL_CHUNK_SIZE * 0.5
	for i in count:
		var pos := Vector3(_look_rng.randf_range(-half, half), 0.0, _look_rng.randf_range(-half, half))
		var basis := Basis(Vector3.UP, _look_rng.randf() * TAU).scaled(
			Vector3.ONE * _look_rng.randf_range(scale_range.x, scale_range.y))
		multimesh.set_instance_transform(i, Transform3D(basis, pos))
		var shade := _look_rng.randf_range(0.75, 1.15)
		multimesh.set_instance_color(i, Color(shade, shade * _look_rng.randf_range(0.95, 1.08), shade * 0.9))
	var instance := MultiMeshInstance3D.new()
	instance.name = name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.position = origin
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = visible_range
	instance.visibility_range_end_margin = 8.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(instance)


## A tuft of curved blades; UV.y runs from root (0) to tip (1).
func _grass_clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for blade in 9:
		var angle := rng.randf() * TAU
		var root := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.0, 0.25)
		var lean := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.1, 0.3)
		var side := Vector3(-sin(angle), 0.0, cos(angle)) * 0.035
		var height := rng.randf_range(0.35, 0.7)
		var mid := root + lean * 0.4 + Vector3.UP * height * 0.55
		var tip := root + lean + Vector3.UP * height
		for tri in [[root - side, root + side, mid + side * 0.6, 0.0, 0.0, 0.55],
				[root - side, mid + side * 0.6, mid - side * 0.6, 0.0, 0.55, 0.55],
				[mid - side * 0.6, mid + side * 0.6, tip, 0.55, 0.55, 1.0]]:
			for k in 3:
				st.set_uv(Vector2(0.5, tri[3 + k]))
				st.set_normal(Vector3.UP)
				st.add_vertex(tri[k])
	return st.commit()


## Arching fronds; UV.x spans the frond width (0.5 on the stem), UV.y base to tip.
func _fern_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var fronds := 7
	var steps := 6
	for f in fronds:
		var angle := TAU * float(f) / fronds + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x)
		var length := rng.randf_range(0.9, 1.3)
		var rise := rng.randf_range(0.5, 0.8)
		var width := 0.24
		var points: Array[Vector3] = []
		for i in steps + 1:
			var t := float(i) / steps
			points.append(out * length * t + Vector3.UP * (rise * sin(t * PI * 0.8) - 0.1 * t))
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var a := points[i]
			var b := points[i + 1]
			var quad := [[a - side * width, 0.0, t0], [a + side * width, 1.0, t0],
				[b + side * width, 1.0, t1], [b - side * width, 0.0, t1]]
			for index in [0, 1, 2, 0, 2, 3]:
				st.set_uv(Vector2(quad[index][1], quad[index][2]))
				st.set_normal(Vector3.UP)
				st.add_vertex(quad[index][0])
	return st.commit()


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
