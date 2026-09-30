extends Node
## Testing helper: pressing K kills the parent player.
## Remove by deleting the DebugKill node from player.tscn.


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_K:
		get_parent().take_damage(INF, null, true)
