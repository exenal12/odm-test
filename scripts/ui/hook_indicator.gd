@tool
extends Control
## Slanted blade-shaped hook indicator that pops when the hook latches.

const ON_FILL := Color(0.85, 0.8, 0.65, 1.0)
const OFF_FILL := Color(0.14, 0.14, 0.16, 0.8)
const ON_EDGE := Color(0.72, 0.16, 0.1, 1.0)
const OFF_EDGE := Color(0.35, 0.33, 0.3, 1.0)
const SLANT := 8.0

@export var mirrored: bool = false:
	set(v):
		mirrored = v
		queue_redraw()

var active: bool = false:
	set(v):
		if v == active:
			return
		active = v
		if active and is_inside_tree():
			_pop = 1.3
			create_tween().tween_property(self, "_pop", 1.0, 0.15)
		queue_redraw()
var _pop: float = 1.0:
	set(v):
		_pop = v
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var pts := PackedVector2Array([Vector2(SLANT, 0), Vector2(w, 0), Vector2(w - SLANT, h), Vector2(0, h)])
	if mirrored:
		pts = PackedVector2Array([Vector2(0, 0), Vector2(w - SLANT, 0), Vector2(w, h), Vector2(SLANT, h)])
	var center := size * 0.5
	draw_set_transform(center * (1.0 - _pop), 0.0, Vector2.ONE * _pop)
	draw_colored_polygon(pts, ON_FILL if active else OFF_FILL)
	var closed := pts + PackedVector2Array([pts[0]])
	draw_polyline(closed, ON_EDGE if active else OFF_EDGE, 1.5, true)
