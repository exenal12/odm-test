extends Control
## Circular heading-up radar: red titans, white soldiers, green gas stations.

const BG := Color(0.055, 0.055, 0.06, 0.8)
const RING := Color(0.72, 0.16, 0.1, 1.0)
const BONE := Color(0.88, 0.84, 0.74, 1.0)
const TITAN := Color(0.9, 0.15, 0.1)
const SOLDIER := Color(1, 1, 1)
const STATION := Color(0.3, 0.85, 0.35)

## World distance (meters) mapped to the edge of the map.
@export var world_range: float = 150.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 3.0
	draw_circle(c, radius, BG)
	draw_arc(c, radius, 0.0, TAU, 64, RING, 2.0, true)

	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	if player == null or cam == null:
		return
	var f3 := -cam.global_transform.basis.z
	var fwd := Vector2(f3.x, f3.z)
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var origin := Vector2(player.global_position.x, player.global_position.z)

	var north := Vector2(0, -1)
	var n_pos := c + Vector2(north.dot(right), -north.dot(fwd)) * (radius - 9.0)
	var font := get_theme_default_font()
	draw_string(font, n_pos + Vector2(-4, 5), "N", HORIZONTAL_ALIGNMENT_CENTER, 8, 12, Color(BONE, 0.6))

	for node in get_tree().get_nodes_in_group("gas_station"):
		_draw_blip(node, origin, c, radius, right, fwd, STATION, 3.5, true)
	for node in get_tree().get_nodes_in_group("soldier"):
		if node.get("alive") != false:
			_draw_blip(node, origin, c, radius, right, fwd, SOLDIER, 2.5, false)
	for node in get_tree().get_nodes_in_group("titan"):
		if node.get("alive") != false:
			_draw_blip(node, origin, c, radius, right, fwd, TITAN, 4.0, false)

	var tri := PackedVector2Array([c + Vector2(0, -6), c + Vector2(4.5, 5), c + Vector2(-4.5, 5)])
	draw_colored_polygon(tri, BONE)
	draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0, 0, 0, 0.8), 1.0, true)


func _draw_blip(node: Node, origin: Vector2, c: Vector2, radius: float, right: Vector2, fwd: Vector2, color: Color, r: float, diamond: bool) -> void:
	var n3 := node as Node3D
	if n3 == null:
		return
	var d := Vector2(n3.global_position.x, n3.global_position.z) - origin
	var p := Vector2(d.dot(right), -d.dot(fwd)) * (radius / world_range)
	var max_len := radius - r - 2.0
	var faded := p.length() > max_len
	if faded:
		p = p.normalized() * max_len
	var col := Color(color, 0.55) if faded else color
	var pos := c + p
	if diamond:
		var pts := PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(r, 0), pos + Vector2(0, r), pos + Vector2(-r, 0)])
		draw_colored_polygon(pts, col)
	else:
		draw_circle(pos, r + 1.0, Color(0, 0, 0, 0.7))
		draw_circle(pos, r, col)
