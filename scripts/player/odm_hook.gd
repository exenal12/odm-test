class_name ODMHook
extends Node3D
## Single ODM hook: aim raycast, latch, cable length, and cable visuals.
## Gameplay latches instantly; the visuals show the anchor flying out, the cable
## settling taut, and the anchor reeling back in on release or a miss.

enum State { IDLE, ATTACHED }
enum Visual { HIDDEN, OUT, LATCHED, RETRACT }

## Emitted when the hook latches to a world anchor.
signal attached(anchor: Vector3)
## Emitted when the hook returns to the idle state.
signal detached

## Selects the default side of the ODM gear used by this hook.
@export var is_left: bool = true
## Radius of the visible cable.
@export var cable_radius: float = 0.01
## Material color applied to the cable mesh.
@export var cable_color: Color = Color(0.3, 0.31, 0.33)
## Visual speed of the anchor flying out and reeling back, in m/s.
@export var fly_speed: float = 220.0
@export var retract_speed: float = 90.0
## Extra cable length paid out at latch, as a fraction of the span; it decays so the cable snaps taut.
@export var latch_slack: float = 0.05
@export var slack_decay: float = 7.0

const SEGMENTS := 20
const SIDES := 6
const SOLVER_ITERATIONS := 12
const DAMPING := 0.96
## How quickly a tensioned cable is pulled onto the straight line (per second, at full tension).
## The length constraint alone converges too slowly on long spans to ever look taut.
const TENSION_RATE := 30.0
## How deep the anchor spike sinks into the surface.
const EMBED_DEPTH := 0.1
## Anchor model extents along its local Z (spike points toward -Z).
const ANCHOR_TIP_Z := -0.17
const ANCHOR_REAR_Z := 0.09

var state: State = State.IDLE
## World-space anchor. Follows the hit body when it moves.
var anchor_point: Vector3:
	get:
		if is_instance_valid(_anchor_body):
			_anchor_world = _anchor_body.global_transform * _anchor_local
		return _anchor_world
	set(value):
		_anchor_world = value
var cable_length: float = 0.0

var _anchor_world: Vector3 = Vector3.ZERO
var _anchor_body: Node3D
var _anchor_local: Vector3 = Vector3.ZERO
var _anchor_dir_local: Vector3 = Vector3.FORWARD
var _hook_dir: Vector3 = Vector3.FORWARD

var _visual: Visual = Visual.HIDDEN
var _target: Vector3
var _flown: float = 0.0
var _tip: Vector3
var _slack: float = 0.0
var _last_start: Vector3
var _last_end: Vector3
var _points := PackedVector3Array()
var _previous := PackedVector3Array()

var _cable_mesh: MeshInstance3D
var _cable_material: StandardMaterial3D
var _anchor_model: Node3D


func _ready() -> void:
	_cable_material = StandardMaterial3D.new()
	_cable_material.albedo_color = cable_color
	_cable_material.metallic = 0.8
	_cable_material.roughness = 0.35
	_cable_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cable_mesh = MeshInstance3D.new()
	_cable_mesh.name = "Cable"
	_cable_mesh.mesh = ImmediateMesh.new()
	# Vertices are written in world space.
	_cable_mesh.top_level = true
	_cable_mesh.visible = false
	add_child(_cable_mesh)
	_anchor_model = _build_anchor()
	_anchor_model.visible = false
	add_child(_anchor_model)


## Reports whether the hook currently has a latched anchor.
func is_attached() -> bool:
	return state == State.ATTACHED


## The body the hook is stuck in, or null for static scenery.
func get_anchored_body() -> Node3D:
	return _anchor_body if is_attached() and is_instance_valid(_anchor_body) else null


## Raycasts along the supplied aim direction and latches on a hit. A miss still
## throws the anchor out visually before reeling it back.
func fire(
	origin: Vector3,
	direction: Vector3,
	max_range: float,
	space: PhysicsDirectSpaceState3D,
	collision_mask: int
) -> bool:
	detach()
	var dir := direction.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_launch(origin + dir * max_range)
		return false

	anchor_point = hit.position
	_anchor_body = null
	_hook_dir = dir
	var collider := hit.collider as Node3D
	if collider is CharacterBody3D or collider is AnimatableBody3D:
		_anchor_body = collider
		_anchor_local = collider.global_transform.affine_inverse() * hit.position
		_anchor_dir_local = collider.global_basis.inverse() * dir
	cable_length = origin.distance_to(anchor_point)
	state = State.ATTACHED
	_launch(hit.position)
	attached.emit(anchor_point)
	return true


## Returns the hook to its idle state. By default the anchor reels back in;
## pass instant to hide the cable and hook immediately. Emits detach only when
## it was previously attached.
func detach(instant: bool = false) -> void:
	var was_attached := state == State.ATTACHED
	if not was_attached and not instant:
		return
	state = State.IDLE
	_anchor_body = null
	if instant:
		_hide_visuals()
	elif _visual == Visual.OUT or _visual == Visual.LATCHED:
		_visual = Visual.RETRACT
	if was_attached:
		detached.emit()


func _hide_visuals() -> void:
	_visual = Visual.HIDDEN
	_points.clear()
	if is_instance_valid(_cable_mesh):
		_cable_mesh.visible = false
	if is_instance_valid(_anchor_model):
		_anchor_model.visible = false


## Decreases cable length while preserving the configured minimum length.
func shorten(amount: float, min_length: float = 1.5) -> void:
	if state != State.ATTACHED:
		return
	cable_length = maxf(min_length, cable_length - amount)


## Advances the anchor flight and cable simulation from the gear socket, then
## rebuilds the cable mesh. Call once per physics frame.
func update_visual(from_global: Vector3) -> void:
	var delta := get_physics_process_delta_time()
	match _visual:
		Visual.HIDDEN:
			_cable_mesh.visible = false
			_anchor_model.visible = false
			return
		Visual.OUT:
			if state == State.ATTACHED:
				_target = anchor_point
			_flown += fly_speed * delta
			var span := from_global.distance_to(_target)
			_tip = from_global.move_toward(_target, _flown)
			if _flown >= span:
				if state == State.ATTACHED:
					_visual = Visual.LATCHED
					_slack = latch_slack
				else:
					_visual = Visual.RETRACT
		Visual.LATCHED:
			_tip = anchor_point
			_slack *= exp(-slack_decay * delta)
		Visual.RETRACT:
			_tip = _tip.move_toward(from_global, retract_speed * delta)
			if _tip.distance_to(from_global) < 0.3:
				_visual = Visual.HIDDEN
				_cable_mesh.visible = false
				_anchor_model.visible = false
				return

	_place_anchor(from_global)
	var cable_end := _anchor_model.global_transform * Vector3(0, 0, ANCHOR_REAR_Z)
	var span := from_global.distance_to(cable_end)
	var rest := span * (1.0 + _slack)
	var tension := 1.0 - _slack / maxf(latch_slack, 0.0001)
	if _visual == Visual.OUT:
		rest = span * 1.04
		tension = 0.15
	elif _visual == Visual.RETRACT:
		rest = span * 1.1
		tension = 0.0
	_simulate(from_global, cable_end, rest, delta)
	if tension > 0.0:
		_tighten(from_global, cable_end, 1.0 - exp(-TENSION_RATE * tension * delta))
	_build_tube()
	_cable_mesh.visible = true
	_anchor_model.visible = true


func _launch(target: Vector3) -> void:
	_target = target
	_flown = 0.0
	_slack = 0.0
	_visual = Visual.OUT
	_points.clear()


## Points the anchor along its flight; once latched it sits embedded in the surface.
func _place_anchor(from_global: Vector3) -> void:
	var forward := _tip - from_global
	if _visual == Visual.LATCHED:
		forward = _hook_dir
		if is_instance_valid(_anchor_body):
			forward = _anchor_body.global_basis * _anchor_dir_local
	if forward.length_squared() < 0.0001:
		forward = _hook_dir
	forward = forward.normalized()
	var up := Vector3.UP if absf(forward.y) < 0.95 else Vector3.RIGHT
	var origin := _tip
	if _visual == Visual.LATCHED:
		origin = _tip + forward * (EMBED_DEPTH + ANCHOR_TIP_Z)
	_anchor_model.global_transform = Transform3D(Basis.looking_at(forward, up), origin)


## Verlet rope pinned at both ends. Interior points first move with the ends so
## fast travel doesn't stretch the cable; gravity and slack add the sag and sway.
func _simulate(start: Vector3, end: Vector3, rest_length: float, delta: float) -> void:
	if _points.size() != SEGMENTS + 1:
		_points.resize(SEGMENTS + 1)
		_previous.resize(SEGMENTS + 1)
		for i in SEGMENTS + 1:
			_points[i] = start.lerp(end, float(i) / SEGMENTS)
			_previous[i] = _points[i]
		_last_start = start
		_last_end = end
	var start_move := start - _last_start
	var end_move := end - _last_end
	_last_start = start
	_last_end = end
	var gravity := Vector3.DOWN * 9.8 * delta * delta
	for i in range(1, SEGMENTS):
		var carry := start_move.lerp(end_move, float(i) / SEGMENTS)
		var velocity := (_points[i] - _previous[i]) * DAMPING
		_previous[i] = _points[i] + carry
		_points[i] += carry + velocity + gravity
	_points[0] = start
	_points[SEGMENTS] = end
	var segment := rest_length / SEGMENTS
	for _iteration in SOLVER_ITERATIONS:
		for i in SEGMENTS:
			var offset := _points[i + 1] - _points[i]
			var length := offset.length()
			if length <= segment or length < 0.00001:
				continue
			var correction := offset * ((length - segment) / length)
			if i == 0:
				_points[i + 1] -= correction
			elif i + 1 == SEGMENTS:
				_points[i] += correction
			else:
				_points[i] += correction * 0.5
				_points[i + 1] -= correction * 0.5


## Pulls interior points toward the straight span; previous positions move too,
## so tightening doesn't inject velocity.
func _tighten(start: Vector3, end: Vector3, amount: float) -> void:
	for i in range(1, SEGMENTS):
		var goal := start.lerp(end, float(i) / SEGMENTS)
		var shift := (goal - _points[i]) * amount
		_points[i] += shift
		_previous[i] += shift


## Rebuilds the cable as a thin tube along the simulated points, using
## parallel-transported rings so the tube doesn't twist.
func _build_tube() -> void:
	var mesh := _cable_mesh.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var count := _points.size()
	if count < 2:
		return
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var side := Vector3.ZERO
	for i in count:
		var tangent := (_points[mini(i + 1, count - 1)] - _points[maxi(i - 1, 0)]).normalized()
		if side == Vector3.ZERO:
			side = tangent.cross(Vector3.UP)
			if side.length_squared() < 0.001:
				side = tangent.cross(Vector3.RIGHT)
		side = (side - tangent * side.dot(tangent)).normalized()
		var other := tangent.cross(side)
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for k in SIDES:
			var angle := TAU * k / SIDES
			var n := side * cos(angle) + other * sin(angle)
			ring.append(_points[i] + n * cable_radius)
			ring_normals.append(n)
		rings.append(ring)
		normals.append(ring_normals)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _cable_material)
	for i in count - 1:
		for k in SIDES:
			var k2 := (k + 1) % SIDES
			_vertex(mesh, rings[i][k], normals[i][k])
			_vertex(mesh, rings[i + 1][k], normals[i + 1][k])
			_vertex(mesh, rings[i + 1][k2], normals[i + 1][k2])
			_vertex(mesh, rings[i][k], normals[i][k])
			_vertex(mesh, rings[i + 1][k2], normals[i + 1][k2])
			_vertex(mesh, rings[i][k2], normals[i][k2])
	mesh.surface_end()


func _vertex(mesh: ImmediateMesh, point: Vector3, normal: Vector3) -> void:
	mesh.surface_set_normal(normal)
	mesh.surface_add_vertex(point)


## Barbed harpoon head: spike toward local -Z, three swept-back flukes, and a
## rear eyelet where the cable ties on.
func _build_anchor() -> Node3D:
	var root := Node3D.new()
	root.name = "Anchor"
	root.top_level = true
	var steel := _material(Color(0.72, 0.74, 0.77), 0.85, 0.25)
	var gunmetal := _material(Color(0.16, 0.17, 0.19), 0.7, 0.4)
	var brass := _material(Color(0.74, 0.56, 0.26), 0.9, 0.35)
	var along_z := Basis(Vector3.RIGHT, -PI * 0.5)

	_part(root, _cylinder(0.0, 0.028, 0.12), steel, Transform3D(along_z, Vector3(0, 0, -0.11)))
	_part(root, _cylinder(0.028, 0.028, 0.1), gunmetal, Transform3D(along_z, Vector3.ZERO))
	_part(root, _cylinder(0.032, 0.032, 0.014), brass, Transform3D(along_z, Vector3(0, 0, 0.05)))
	_part(root, _cylinder(0.026, 0.012, 0.03), gunmetal, Transform3D(along_z, Vector3(0, 0, 0.072)))
	var eyelet := TorusMesh.new()
	eyelet.inner_radius = 0.006
	eyelet.outer_radius = 0.011
	_part(root, eyelet, steel, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0, ANCHOR_REAR_Z)))

	var barb := BoxMesh.new()
	barb.size = Vector3(0.01, 0.006, 0.075)
	for i in 3:
		var angle := TAU * i / 3.0
		var out := Vector3(cos(angle), sin(angle), 0.0)
		var dir := (out * 0.42 + Vector3.BACK * 0.8).normalized()
		var base := out * 0.026 + Vector3(0, 0, -0.045)
		_part(root, barb, steel, Transform3D(Basis.looking_at(-dir, out), base + dir * 0.0375))
	return root


func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	return mesh


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _part(parent: Node3D, mesh: Mesh, material: Material, xform: Transform3D) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.transform = xform
	parent.add_child(part)
