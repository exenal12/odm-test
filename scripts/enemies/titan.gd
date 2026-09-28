class_name Titan
extends CharacterBody3D
## Stationary titan. Only hits on the nape kill it; body hits are ignored.

signal died(titan: Titan)

@export var fall_duration: float = 1.6
@export var fade_duration: float = 1.2

@onready var nape: Area3D = $Nape
@onready var body_collider: CollisionShape3D = $CollisionShape3D
@onready var flash_mesh: MeshInstance3D = $Body

var alive: bool = true


func _ready() -> void:
	nape.set_meta(&"titan", self)


## Called by SwordCombat for any node the blade overlaps.
func on_sword_hit(target: Node3D, _damage: float) -> void:
	if not alive:
		return
	if target == nape:
		_die()
	else:
		_flash_deflect()


func _die() -> void:
	alive = false
	body_collider.set_deferred("disabled", true)
	nape.set_deferred("monitorable", false)
	var tween := create_tween()
	tween.tween_property(self, "rotation:x", -PI * 0.5, fall_duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position:y", position.y - 2.0, fade_duration)
	tween.tween_callback(queue_free)
	died.emit(self)


func _flash_deflect() -> void:
	var material := flash_mesh.material_override as StandardMaterial3D
	if material == null:
		return
	var tween := create_tween()
	tween.tween_property(material, "emission_energy_multiplier", 1.5, 0.04)
	tween.tween_property(material, "emission_energy_multiplier", 0.0, 0.2)
