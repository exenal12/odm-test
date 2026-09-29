class_name SoldierDirector
extends Node3D
## Scene-level difficulty and spawning for soldiers. Place one in a world scene and
## tweak the exports; settings are applied to every soldier and titan on start.

@export_group("Spawning")
@export var soldier_scene: PackedScene = preload("res://scenes/npc/soldier.tscn")
@export_range(0, 50) var soldier_count: int = 1
## Soldiers spawn on a ring of this radius around the director.
@export var spawn_radius: float = 8.0
## Seconds before a dead soldier is replaced. Negative disables respawning.
@export var respawn_delay: float = -1.0

@export_group("Soldier Difficulty")
@export var soldier_health: float = 20.0
## Chance a nape strike attempt lands when the soldier is in position.
@export_range(0.0, 1.0) var strike_chance: float = 0.7
@export var strike_cooldown: float = 1.5
@export var hook_range: float = 38.0
@export var run_speed: float = 6.0
## How far behind the titan a soldier must be (degrees from its back) to hook.
@export_range(10.0, 180.0) var rear_angle_deg: float = 70.0
## Soldiers hook onto scenery to travel, like the player.
@export var use_traversal: bool = true
## Soldiers head for a gas station at or below this fraction of full gas.
@export_range(0.0, 1.0) var low_gas_fraction: float = 0.25
## Seconds a soldier waits in position before the first hook.
@export var reaction_time: float = 1.5
## Soldiers only strike while the titan is focused on something else.
@export var require_distraction: bool = true
## Seconds a soldier stays hooked onto a titan without striking before giving up.
@export var max_hook_time: float = 5.0
## Most soldiers hooked onto one titan at once. 0 means unlimited.
@export var max_attackers: int = 1

@export_group("Titan Difficulty")
## A soldier this close is noticed regardless of facing or line of sight.
@export var titan_notice_range: float = 12.0
## Below 1.0 titans stay locked on their current target more stubbornly.
@export_range(0.1, 1.0) var titan_retarget_bias: float = 0.6
## The nape only counts when the attacker is within this angle of the titan's back.
@export_range(10.0, 180.0) var nape_rear_angle_deg: float = 100.0
@export var titan_attack_damage: float = 25.0


func _ready() -> void:
	_setup.call_deferred()


func _setup() -> void:
	for i in soldier_count:
		_spawn(TAU * i / maxf(soldier_count, 1.0))
	apply_all()


## Re-applies the current settings to every soldier and titan in the scene.
func apply_all() -> void:
	for node in get_tree().get_nodes_in_group("soldier"):
		if node is Soldier:
			_apply_soldier(node)
	for node in get_tree().get_nodes_in_group("titan"):
		if node is Titan:
			_apply_titan(node)


func _apply_soldier(soldier: Soldier) -> void:
	soldier.max_health = soldier_health
	soldier.health = minf(soldier.health, soldier_health) if soldier.health > 0.0 else soldier_health
	soldier.strike_chance = strike_chance
	soldier.strike_cooldown = strike_cooldown
	soldier.hook_range = hook_range
	soldier.run_speed = run_speed
	soldier.rear_angle_deg = rear_angle_deg
	soldier.use_traversal = use_traversal
	soldier.low_gas_fraction = low_gas_fraction
	soldier.reaction_time = reaction_time
	soldier.require_distraction = require_distraction
	soldier.max_attackers = max_attackers
	soldier.max_hook_time = max_hook_time


func _apply_titan(titan: Titan) -> void:
	titan.soldier_notice_range = titan_notice_range
	titan.retarget_bias = titan_retarget_bias
	titan.nape_rear_angle_deg = nape_rear_angle_deg
	titan.attack_damage = titan_attack_damage


func _spawn(angle: float) -> void:
	if soldier_scene == null:
		return
	var soldier := soldier_scene.instantiate() as Soldier
	_apply_soldier(soldier)
	add_child(soldier)
	soldier.global_position = global_position + Vector3(cos(angle), 0.0, sin(angle)) * spawn_radius
	soldier.died.connect(_on_soldier_died.bind(angle))


func _on_soldier_died(_soldier: Soldier, angle: float) -> void:
	if respawn_delay < 0.0:
		return
	await get_tree().create_timer(respawn_delay).timeout
	_spawn(angle)
	apply_all()
