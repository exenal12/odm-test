extends Node3D

const DEBUG_MAP := "res://scenes/world/world.tscn"
const FOREST_MAP := "res://scenes/world/forest_world.tscn"


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_1:
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file.call_deferred(DEBUG_MAP)
	elif event.physical_keycode == KEY_2:
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file.call_deferred(FOREST_MAP)
