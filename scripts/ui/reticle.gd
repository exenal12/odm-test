@tool
extends Control
## Diagonal-tick reticle. Turns red and tightens when a hook target is in range.

const IDLE := Color(0.88, 0.84, 0.74, 0.8)
const LOCKED := Color(0.9, 0.25, 0.15, 1.0)
const GAP_IDLE := 9.0
const GAP_LOCKED := 6.0

var locked: bool = false
var _gap: float = GAP_IDLE:
	set(v):
		_gap = v
		queue_redraw()
var _tint: Color = IDLE:
	set(v):
		_tint = v
		queue_redraw()
var _hit: float = 0.0:
	set(v):
		_hit = v
		queue_redraw()
var _tween: Tween


func set_locked(value: bool) -> void:
	if value == locked:
		return
	locked = value
	_kill_tween()
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "_gap", GAP_LOCKED if locked else GAP_IDLE, 0.1)
	_tween.tween_property(self, "_tint", LOCKED if locked else IDLE, 0.1)


## Quick squeeze when a hook is fired.
func pulse() -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "_gap", 2.5, 0.04)
	_tween.tween_property(self, "_gap", GAP_LOCKED if locked else GAP_IDLE, 0.15)


## Flashes an X marker when a sword strike connects.
func hit_marker() -> void:
	_hit = 1.0
	create_tween().tween_property(self, "_hit", 0.0, 0.3)


func _kill_tween() -> void:
	if _tween:
		_tween.kill()


func _draw() -> void:
	var c := size * 0.5
	for i in 4:
		var dir := Vector2.from_angle(PI * 0.25 + i * PI * 0.5)
		draw_line(c + dir * _gap, c + dir * (_gap + 8.0), Color(0, 0, 0, 0.7), 4.0, true)
		draw_line(c + dir * _gap, c + dir * (_gap + 8.0), _tint, 2.0, true)
	draw_circle(c, 2.5, Color(0, 0, 0, 0.7))
	draw_circle(c, 1.5, _tint)
	if _hit > 0.0:
		var col := Color(0.95, 0.2, 0.12, _hit)
		for i in 4:
			var dir := Vector2.from_angle(i * PI * 0.5)
			draw_line(c + dir * 5.0, c + dir * (11.0 + 6.0 * (1.0 - _hit)), col, 3.0, true)
