extends Area3D
## Restores ODM gas while the player remains inside the volume.

@export var refill_per_second: float = 40.0
@export var instant_fill_on_enter: bool = false

var _player_odm: ODMController


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if _player_odm == null:
		return
	_player_odm.refill_gas(refill_per_second * delta)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var odm := body.get_node_or_null("ODMController") as ODMController
	if odm == null:
		return
	_player_odm = odm
	if instant_fill_on_enter:
		_player_odm.refill_gas()


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_odm = null
