extends Node3D
## Greybox traversal course: jump gaps, slide tunnels, ramps, towers, atrium, streets.
## Grappleable surfaces use physics layer 2 (bit value 2) in addition to world layer 1.

const LAYER_WORLD := 1
const LAYER_GRAPPLE := 2

## Width and depth of the generated ground plane.
@export var floor_size: Vector2 = Vector2(120, 80)


## Builds the complete greybox course once the scene enters the tree.
func _ready() -> void:
	_build()


## Clears any previous generated geometry and rebuilds every traversal zone.
func _build() -> void:
	_clear_generated()
	_add_zone_markers()
	_build_ground()
	MapBounds.add_to(_generated(), floor_size * 0.5, LAYER_WORLD)
	_build_jump_rooftops()
	_build_slide_tunnel()
	_build_ramps_and_ledges()
	_build_towers()
	_build_atrium()
	_build_narrow_street()
	_build_climb_stubs()
	_build_wallrun_panels()
	_build_gas_stations()


## Replaces the generated container so rebuilding never duplicates geometry.
func _clear_generated() -> void:
	var existing := get_node_or_null("Generated")
	if existing:
		existing.free()
	var gen := Node3D.new()
	gen.name = "Generated"
	add_child(gen)


## Returns the node that owns all procedurally generated playground content.
func _generated() -> Node3D:
	return $Generated as Node3D


## Creates named markers that identify the course's major testing areas.
func _add_zone_markers() -> void:
	var markers := {
		"Spawn": Vector3(0, 0.1, 0),
		"JumpRooftops": Vector3(18, 0.1, 0),
		"SlideTunnel": Vector3(-16, 0.1, 8),
		"Ramps": Vector3(0, 0.1, -18),
		"Towers": Vector3(35, 0.1, -10),
		"Atrium": Vector3(-5, 0.1, 30),
		"NarrowStreet": Vector3(25, 0.1, 25),
		"ClimbStubs": Vector3(-30, 0.1, -5),
		"WallrunPanels": Vector3(-30, 0.1, 20),
	}
	var root := Node3D.new()
	root.name = "Zones"
	_generated().add_child(root)
	for zone_name in markers:
		var marker := Marker3D.new()
		marker.name = zone_name
		marker.position = markers[zone_name]
		root.add_child(marker)


## Adds the large non-grappleable floor beneath the entire course.
func _build_ground() -> void:
	_box(
		Vector3(0, -0.5, 0),
		Vector3(floor_size.x, 1.0, floor_size.y),
		false,
		Color(0.35, 0.37, 0.4),
		"Ground"
	)


## Creates stepped rooftop platforms and a distant landing pad for jump tests.
func _build_jump_rooftops() -> void:
	var parent := _section("JumpRooftops")
	# Stepping platforms with gaps.
	var heights := [1.5, 3.0, 4.5, 3.5, 5.5]
	var x := 12.0
	for i in heights.size():
		var h: float = heights[i]
		_box(Vector3(x, h * 0.5, 0), Vector3(4.0, h, 4.0), true, Color(0.55, 0.45, 0.35), "Roof_%d" % i, parent)
		x += 6.5
	# Distant landing pad.
	_box(Vector3(x + 2.0, 2.0, 0), Vector3(6.0, 4.0, 6.0), true, Color(0.5, 0.4, 0.3), "LandingPad", parent)


## Builds a low-ceiling tunnel intended to showcase crouching and sliding.
func _build_slide_tunnel() -> void:
	var parent := _section("SlideTunnel")
	# Floor path
	_box(Vector3(-16, 0.15, 8), Vector3(10, 0.3, 3), false, Color(0.3, 0.3, 0.35), "TunnelFloor", parent)
	# Low ceiling — must crouch/slide (~1.0m clearance)
	_box(Vector3(-16, 1.35, 8), Vector3(10, 0.4, 3.2), true, Color(0.45, 0.45, 0.5), "TunnelCeiling", parent)
	_box(Vector3(-16, 0.7, 6.2), Vector3(10, 1.4, 0.4), true, Color(0.4, 0.4, 0.45), "TunnelWallL", parent)
	_box(Vector3(-16, 0.7, 9.8), Vector3(10, 1.4, 0.4), true, Color(0.4, 0.4, 0.45), "TunnelWallR", parent)


## Adds stepped ramps and elevated ledges for jump and movement testing.
func _build_ramps_and_ledges() -> void:
	var parent := _section("Ramps")
	_box(Vector3(-2, 1.0, -14), Vector3(4, 0.4, 8), false, Color(0.5, 0.48, 0.4), "RampBase", parent)
	# Stepped ramp approximation
	for i in 6:
		var z := -12.0 - i * 1.2
		var h := 0.4 + i * 0.55
		_box(Vector3(0, h * 0.5, z), Vector3(3.5, h, 1.2), false, Color(0.52, 0.5, 0.42), "RampStep_%d" % i, parent)
	_box(Vector3(0, 4.0, -22), Vector3(5, 0.5, 4), true, Color(0.55, 0.5, 0.4), "HighLedge", parent)
	_box(Vector3(6, 2.5, -20), Vector3(3, 5, 1), true, Color(0.45, 0.5, 0.55), "LedgeWall", parent)


## Creates tall grappleable towers and a midair platform for ODM swings.
func _build_towers() -> void:
	var parent := _section("Towers")
	_box(Vector3(32, 10, -8), Vector3(4, 20, 4), true, Color(0.4, 0.55, 0.65), "TowerA", parent)
	_box(Vector3(40, 14, -14), Vector3(3.5, 28, 3.5), true, Color(0.35, 0.5, 0.6), "TowerB", parent)
	_box(Vector3(38, 8, -4), Vector3(3, 16, 3), true, Color(0.42, 0.52, 0.58), "TowerC", parent)
	# Mid platforms between towers
	_box(Vector3(36, 8, -11), Vector3(3, 0.5, 3), true, Color(0.6, 0.55, 0.4), "TowerPad", parent)


## Builds the open atrium walls and pillars for long-distance hook tests.
func _build_atrium() -> void:
	var parent := _section("Atrium")
	# Open courtyard walls for long dual-hook swings
	_box(Vector3(-18, 12, 30), Vector3(2, 24, 24), true, Color(0.48, 0.42, 0.38), "AtriumWallW", parent)
	_box(Vector3(12, 12, 30), Vector3(2, 24, 24), true, Color(0.48, 0.42, 0.38), "AtriumWallE", parent)
	_box(Vector3(-3, 12, 42), Vector3(28, 24, 2), true, Color(0.46, 0.4, 0.36), "AtriumWallN", parent)
	# Corner pillars
	for px in [-14.0, 8.0]:
		for pz in [22.0, 38.0]:
			_box(Vector3(px, 10, pz), Vector3(2.5, 20, 2.5), true, Color(0.5, 0.45, 0.4), "AtriumPillar", parent)


## Creates a narrow street with tall walls and overhead obstacles.
func _build_narrow_street() -> void:
	var parent := _section("NarrowStreet")
	_box(Vector3(22, 6, 25), Vector3(1.5, 12, 20), true, Color(0.4, 0.4, 0.45), "StreetWallL", parent)
	_box(Vector3(28, 6, 25), Vector3(1.5, 12, 20), true, Color(0.4, 0.4, 0.45), "StreetWallR", parent)
	# Overhangs
	_box(Vector3(25, 5, 20), Vector3(5, 0.4, 3), true, Color(0.55, 0.5, 0.45), "StreetOverhang", parent)
	_box(Vector3(25, 8, 30), Vector3(5, 0.4, 3), true, Color(0.55, 0.5, 0.45), "StreetOverhang2", parent)


## Adds the ladder-like ledge strips used for traversal experiments.
func _build_climb_stubs() -> void:
	var parent := _section("ClimbStubs")
	# Ladder-like ledge strips (geometry only — climb logic later)
	for i in 8:
		var y := 0.6 + i * 0.85
		_box(Vector3(-30, y, -5), Vector3(1.2, 0.15, 0.4), true, Color(0.7, 0.55, 0.3), "ClimbLedge_%d" % i, parent)
	_box(Vector3(-30, 7.5, -5), Vector3(3, 0.4, 3), true, Color(0.6, 0.5, 0.35), "ClimbTop", parent)


## Adds tall flat panels for wall-run and grapple movement experiments.
func _build_wallrun_panels() -> void:
	var parent := _section("WallrunPanels")
	# Tall vertical panels (geometry only — wallrun later)
	_box(Vector3(-28, 3, 18), Vector3(0.4, 6, 12), true, Color(0.35, 0.55, 0.5), "WallrunA", parent)
	_box(Vector3(-34, 3.5, 22), Vector3(0.4, 7, 10), true, Color(0.32, 0.5, 0.48), "WallrunB", parent)


## Places gas refill stations near the spawn, towers, and atrium zones.
func _build_gas_stations() -> void:
	var parent := _section("GasStations")
	_make_gas_refill(Vector3(8, 0.5, 8), parent, "GasRefill_Spawn")
	_make_gas_refill(Vector3(36, 0.5, -6), parent, "GasRefill_Towers")
	_make_gas_refill(Vector3(-5, 0.5, 28), parent, "GasRefill_Atrium")


## Creates a refill Area3D with collision monitoring and a glowing visual orb.
func _make_gas_refill(pos: Vector3, parent: Node, station_name: String = "GasRefill") -> void:
	var script := load("res://scripts/world/gas_refill.gd") as GDScript
	var area: Area3D = script.new() as Area3D
	area.name = station_name
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	shape.shape = sphere
	area.add_child(shape)
	var mesh_inst := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.6
	sphere_mesh.height = 1.2
	mesh_inst.mesh = sphere_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.6, 0.2)
	mat.emission_energy_multiplier = 2.0
	mesh_inst.material_override = mat
	area.add_child(mesh_inst)
	parent.add_child(area)


## Creates and registers a named generated section for course geometry.
func _section(section_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = section_name
	_generated().add_child(node)
	return node


## Creates a box mesh and matching collision body, optionally marking it as
## grappleable on both the world and grapple physics layers.
func _box(
	pos: Vector3,
	size: Vector3,
	grappleable: bool,
	color: Color,
	box_name: String = "Box",
	parent: Node = null
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = pos
	body.collision_layer = LAYER_WORLD | (LAYER_GRAPPLE if grappleable else 0)
	body.collision_mask = 0
	if grappleable:
		body.add_to_group("grappleable")

	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if grappleable:
		mat.roughness = 0.7
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	if parent == null:
		parent = _generated()
	parent.add_child(body)
	return body
