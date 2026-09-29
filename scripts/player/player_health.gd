class_name PlayerHealth
extends Node
## Player hit points with a short invulnerability window after each hit.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
signal died

@export var max_health: float = 100.0
@export var invulnerable_time: float = 1.0

var health: float
var dead: bool = false

var _invulnerable_left: float = 0.0


func _ready() -> void:
	health = max_health


func _process(delta: float) -> void:
	_invulnerable_left = maxf(0.0, _invulnerable_left - delta)


func take_damage(amount: float, source: Node = null) -> void:
	if dead or _invulnerable_left > 0.0 or amount <= 0.0:
		return
	_invulnerable_left = invulnerable_time
	health = maxf(0.0, health - amount)
	damaged.emit(amount, source)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		dead = true
		died.emit()


## Adds health up to the maximum; a negative amount restores to full.
func heal(amount: float = -1.0) -> void:
	if dead:
		return
	health = max_health if amount < 0.0 else minf(max_health, health + amount)
	health_changed.emit(health, max_health)
