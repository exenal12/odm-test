extends Area3D
## Restores ODM gas while the player remains inside the volume.

## Gas restored per second while the player remains inside the area.
@export var refill_per_second: float = 40.0
## If enabled, refill the player's gas immediately upon entering.
@export var instant_fill_on_enter: bool = false

var _player_odm: ODMController


## Starts tracking player entry and exit so gas can refill only while occupied.
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Refills the tracked player's ODM gas every physics frame.
func _physics_process(delta: float) -> void:
	if _player_odm == null:
		return
	_player_odm.refill_gas(refill_per_second * delta)


## Stores the player's ODM controller when the player enters and optionally
## fills gas immediately.
func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var odm := body.get_node_or_null("ODMController") as ODMController
	if odm == null:
		return
	_player_odm = odm
	if instant_fill_on_enter:
		_player_odm.refill_gas()


## Stops refilling when the player leaves the station area.
func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_odm = null
