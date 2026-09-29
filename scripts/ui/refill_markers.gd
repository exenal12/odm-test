extends Control
## Screen-space markers for nearby refill points. They are drawn on the HUD, so they
## show through trees and walls; off-screen ones cling to the screen edge with an arrow.

const COLOR := Color(0.3, 0.85, 0.35)
const OUTLINE := Color(0, 0, 0, 0.8)

## Markers appear within this distance (meters) of the player.
@export var show_distance: float = 90.0
## Markers fade in over this stretch just inside show_distance.
@export var fade_distance: float = 20.0
## Keeps edge-clamped markers this far from the screen border.
@export var edge_margin: float = 56.0
## Height above the refill point's origin that the marker points at.
@export var marker_height: float = 1.2


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	if player == null or cam == null:
		return
	var font := get_theme_default_font()
	for node in get_tree().get_nodes_in_group("gas_supplier") \
			+ get_tree().get_nodes_in_group("gas_station"):
		var point := (node as Node3D).global_position + Vector3.UP * marker_height
		var dist := player.global_position.distance_to(point)
		if dist > show_distance:
			continue
		var alpha := clampf((show_distance - dist) / maxf(fade_distance, 0.01), 0.0, 1.0)
		_draw_marker(cam, point, dist, alpha, font)


func _draw_marker(cam: Camera3D, point: Vector3, dist: float, alpha: float, font: Font) -> void:
	var center := size * 0.5
	var screen := cam.unproject_position(point)
	var behind := cam.is_position_behind(point)
	if behind:
		# Projections of points behind the camera come out mirrored through the center.
		screen = center * 2.0 - screen
	var inner := Rect2(Vector2.ONE * edge_margin, size - Vector2.ONE * edge_margin * 2.0)
	var col := Color(COLOR, alpha)
	var pos := screen
	if behind or not inner.has_point(screen):
		var dir := screen - center
		dir = dir.normalized() if dir.length_squared() > 1.0 else Vector2.DOWN
		var half := inner.size * 0.5
		# Scale the direction until it touches the inner rectangle's border.
		pos = center + dir * minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
		var side := Vector2(-dir.y, dir.x)
		var arrow := PackedVector2Array([pos + dir * 24.0, pos + dir * 14.0 + side * 7.0,
			pos + dir * 14.0 - side * 7.0])
		draw_colored_polygon(arrow, col)
	_draw_diamond(pos, 11.0, Color(OUTLINE, 0.8 * alpha))
	_draw_diamond(pos, 8.0, col)
	var label := "GAS  %d m" % roundi(dist)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var text_pos := pos + Vector2(-width * 0.5, 28.0)
	draw_string_outline(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4,
		Color(OUTLINE, 0.8 * alpha))
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _draw_diamond(pos: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(r, 0),
		pos + Vector2(0, r), pos + Vector2(-r, 0)]), col)
