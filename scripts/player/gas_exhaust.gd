extends Node3D
## Thin contrail behind an ODM gas nozzle. It lingers in the air and fades out,
## and becomes wider, brighter, and longer-lived while boosting.

const SWING_WIDTH := 0.02
const BOOST_WIDTH := 0.055
const SWING_ALPHA := 0.4
const BOOST_ALPHA := 0.8
const SWING_LIFE := 1.2
const BOOST_LIFE := 2.0
const SWING_COLOR := Color(0.94, 0.96, 1.0)
const BOOST_COLOR := Color(0.8, 0.9, 1.0)
## Minimum distance between recorded trail points.
const MIN_STEP := 0.05
## How fast the boost look blends in and out (per second).
const BLEND_RATE := 6.0

var _mesh := ImmediateMesh.new()
var _points: Array[Dictionary] = []
var _active: bool = false
var _boosting: bool = false
var _new_segment: bool = true
var _level: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# World-space ribbon: keep it independent of the nozzle's movement.
	instance.top_level = true
	add_child(instance)


## Emits the contrail while gas is being spent (reeling or boosting); boost widens and brightens it.
func set_state(reeling: bool, boosting: bool) -> void:
	_active = reeling or boosting
	_boosting = boosting


func _process(delta: float) -> void:
	_clock += delta
	_level = move_toward(_level, 1.0 if _boosting else 0.0, BLEND_RATE * delta)
	if _active:
		_record_point()
	else:
		_new_segment = true
	while not _points.is_empty() and _clock - _points[0].time > _points[0].life:
		_points.pop_front()
	_rebuild_mesh()


func _record_point() -> void:
	var position := global_position
	if not _points.is_empty() and not _new_segment \
			and _points[-1].pos.distance_to(position) < MIN_STEP:
		return
	_points.append({
		"pos": position,
		"time": _clock,
		"life": lerpf(SWING_LIFE, BOOST_LIFE, _level),
		"width": lerpf(SWING_WIDTH, BOOST_WIDTH, _level),
		"alpha": lerpf(SWING_ALPHA, BOOST_ALPHA, _level),
		"color": SWING_COLOR.lerp(BOOST_COLOR, _level),
		"gap": _new_segment,
	})
	_new_segment = false


## Builds a camera-facing ribbon; each point fades and widens slightly with age.
func _rebuild_mesh() -> void:
	_mesh.clear_surfaces()
	var camera := get_viewport().get_camera_3d()
	if camera == null or _points.size() < 2:
		return
	var pts: Array[Dictionary] = _points.duplicate()
	if _active and not _new_segment:
		var head: Dictionary = pts[-1].duplicate()
		head.pos = global_position
		head.time = _clock
		head.gap = false
		pts.append(head)

	var count := pts.size()
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	var colors: Array[Color] = []
	var last_side := Vector3.ZERO
	for i in count:
		var p: Dictionary = pts[i]
		var prev: Vector3 = p.pos if (i == 0 or p.gap) else pts[i - 1].pos
		var next: Vector3 = p.pos if (i == count - 1 or pts[i + 1].gap) else pts[i + 1].pos
		var dir: Vector3 = next - prev
		var to_camera: Vector3 = camera.global_position - p.pos
		var side := dir.cross(to_camera)
		side = side.normalized() if side.length_squared() > 1e-8 else last_side
		last_side = side
		var age := clampf((_clock - p.time) / p.life, 0.0, 1.0)
		var half: float = p.width * (0.7 + 0.9 * age) * 0.5
		left.append(p.pos + side * half)
		right.append(p.pos - side * half)
		var c: Color = p.color
		colors.append(Color(c.r, c.g, c.b, p.alpha * pow(1.0 - age, 1.5)))

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, count):
		if pts[i].gap:
			continue
		var quad := [[i - 1, left], [i - 1, right], [i, right], [i - 1, left], [i, right], [i, left]]
		for corner in quad:
			var idx: int = corner[0]
			var edge: Array[Vector3] = corner[1]
			_mesh.surface_set_color(colors[idx])
			_mesh.surface_add_vertex(edge[idx])
	_mesh.surface_end()
