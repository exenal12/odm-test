@tool
extends Control
## Small cable spool indicator. A colored cable means reel-in is enabled.

@export var reel_enabled: bool = true:
	set(value):
		reel_enabled = value
		queue_redraw()


func _draw() -> void:
	var color := Color(0.85, 0.8, 0.65) if reel_enabled else Color(0.5, 0.48, 0.45)
	var center := Vector2(9, 15)
	draw_arc(center, 5.5, 0.0, TAU, 24, color, 2.0, true)
	draw_circle(center, 1.5, color)
	draw_line(Vector2(13, 12), Vector2(23, 5), color, 2.0, true)
	draw_circle(Vector2(23, 5), 2.5, color)
	if reel_enabled:
		draw_colored_polygon(PackedVector2Array([Vector2(17, 6), Vector2(23, 8), Vector2(19, 12)]), color)
	else:
		draw_line(Vector2(3, 4), Vector2(25, 25), Color(0.95, 0.36, 0.32), 2.5, true)
