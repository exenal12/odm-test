class_name SoldierDirector
extends Node3D
## Scene-level spawn director: places the player on a gas platform, then maintains
## titans and soldiers with time-scaled rates, counts, and speeds.

@export var player_path: NodePath = ^"../Player"
@export var titan_scene: PackedScene = preload("res://scenes/enemies/titan.tscn")
@export var soldier_scene: PackedScene = preload("res://scenes/npc/soldier.tscn")
## Matches GiantForest FOREST_HALF_SIZE (95 * 1.5).
@export var map_half_size: float = 142.5

@export_group("Player Spawn")
## How far from the supplier the player stands on the deck.
@export var player_deck_offset: float = 1.6

@export_group("Titan Spawning")
@export_range(1, 20) var titan_min_start: int = 1
## Extra minimum living titans gained each minute survived.
@export var titan_min_gain_per_minute: float = 0.35
@export_range(1, 30) var titan_cap: int = 6
## Seconds between spawn attempts at the start of a run.
@export var titan_spawn_interval_start: float = 40.0
## Floor for the spawn interval as the run goes on.
@export var titan_spawn_interval_min: float = 12.0
## Minutes until the spawn interval reaches its floor.
@export var titan_spawn_rate_ramp_minutes: float = 8.0
## How far inward from the boundary wall titans appear.
@export var titan_edge_margin: float = 22.0
## Lateral jitter along the far edge, as a fraction of map half-size.
@export_range(0.0, 1.0) var titan_edge_jitter: float = 0.55
## Height checked for camera visibility when spawning.
@export var titan_visibility_height: float = 8.0

@export_group("Titan Speed")
@export var titan_base_wander_speed: float = 4.0
@export var titan_base_chase_speed: float = 10.0
## Added to wander/chase each minute survived (before the max multiplier).
@export var titan_speed_gain_per_minute: float = 0.2
@export var titan_speed_max_multiplier: float = 1.6

@export_group("Soldier Spawning")
@export_range(0, 20) var starting_soldiers: int = 3
## Spacing between starting soldiers on the player's platform.
@export var starting_soldier_spacing: float = 1.4
## Seconds between spawn attempts at the start of a run.
@export var soldier_spawn_interval_start: float = 55.0
## Ceiling for the interval as soldier spawns become rarer.
@export var soldier_spawn_interval_max: float = 140.0
## Minutes until the soldier interval reaches its ceiling.
@export var soldier_spawn_rate_ramp_minutes: float = 10.0
## Max living soldiers = floor(living_titans * soldier_ratio_num / soldier_ratio_den).
@export_range(1, 10) var soldier_ratio_num: int = 2
@export_range(1, 10) var soldier_ratio_den: int = 3

@export_group("Soldier Difficulty")
@export var soldier_health: float = 20.0
@export_range(0.0, 1.0) var strike_chance: float = 0.7
@export var strike_cooldown: float = 1.5
@export var hook_range: float = 38.0
@export var run_speed: float = 6.0
@export_range(10.0, 180.0) var rear_angle_deg: float = 70.0
@export var use_traversal: bool = true
@export_range(0.0, 1.0) var low_gas_fraction: float = 0.25
@export var reaction_time: float = 1.5
@export var require_distraction: bool = true
@export var max_hook_time: float = 5.0
@export var max_attackers: int = 1

@export_group("Titan Difficulty")
@export var titan_notice_range: float = 12.0
@export_range(0.1, 1.0) var titan_retarget_bias: float = 0.6
@export_range(10.0, 180.0) var nape_rear_angle_deg: float = 100.0
@export var titan_attack_damage: float = 25.0

var _player: CharacterBody3D
var _elapsed: float = 0.0
var _titan_timer: float = 0.0
var _soldier_timer: float = 0.0
var _start_supplier: GasSupplier
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	GameSettings.settings_changed.connect(_on_settings_changed)
	_setup.call_deferred()


func _on_settings_changed() -> void:
	# Force the next spawn attempt soon so rate changes are felt quickly.
	_titan_timer = minf(_titan_timer, 0.5)
	_soldier_timer = minf(_soldier_timer, 0.5)


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_elapsed += delta
	_apply_titan_speeds()
	_titan_timer -= delta
	_soldier_timer -= delta
	var below_min := _alive_titans() < _target_titan_count()
	if below_min or _titan_timer <= 0.0:
		if _try_spawn_titan(below_min and _alive_titans() == 0):
			_titan_timer = _titan_spawn_interval()
		elif _titan_timer <= 0.0:
			_titan_timer = 1.5
	if _soldier_timer <= 0.0:
		if _try_spawn_soldier():
			_soldier_timer = _soldier_spawn_interval()
		else:
			_soldier_timer = 2.5


func _setup() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	var suppliers := _gas_suppliers()
	if suppliers.is_empty():
		push_warning("SoldierDirector: no gas platforms found; leaving default spawns.")
		_ensure_min_titans(true)
		return
	_start_supplier = suppliers[_rng.randi_range(0, suppliers.size() - 1)]
	_place_player(_start_supplier)
	_spawn_starting_soldiers(_start_supplier)
	_ensure_min_titans(true)
	_titan_timer = _titan_spawn_interval()
	_soldier_timer = _soldier_spawn_interval() * 0.5
	apply_all()


## Re-applies difficulty settings to every soldier and titan in the scene.
func apply_all() -> void:
	for node in get_tree().get_nodes_in_group("soldier"):
		if node is Soldier:
			_apply_soldier(node)
	for node in get_tree().get_nodes_in_group("titan"):
		if node is Titan:
			_apply_titan(node)
			_apply_titan_speed(node)


func _place_player(supplier: GasSupplier) -> void:
	if _player == null:
		return
	var facing := -supplier.outward()
	if facing.length_squared() < 0.01:
		facing = Vector3.FORWARD
	var deck := supplier.landing_point()
	var right := Vector3(-facing.z, 0.0, facing.x).normalized()
	_player.global_position = deck + right * player_deck_offset + Vector3.UP * 0.05
	_player.look_at(_player.global_position + facing, Vector3.UP)
	_player.velocity = Vector3.ZERO


func _spawn_starting_soldiers(supplier: GasSupplier) -> void:
	if soldier_scene == null or starting_soldiers <= 0:
		return
	var facing := -supplier.outward()
	if facing.length_squared() < 0.01:
		facing = Vector3.FORWARD
	var right := Vector3(-facing.z, 0.0, facing.x).normalized()
	var base := supplier.landing_point()
	var half := float(starting_soldiers - 1) * 0.5
	for i in starting_soldiers:
		var offset := (float(i) - half) * starting_soldier_spacing
		var pos := base + right * offset + facing * 0.4 + Vector3.UP * 0.05
		_spawn_soldier_at(pos, facing)


func _ensure_min_titans(force_visible: bool) -> void:
	while _alive_titans() < _target_titan_count():
		if not _try_spawn_titan(force_visible):
			break


func _try_spawn_titan(force_visible: bool = false) -> bool:
	if titan_scene == null or _alive_titans() >= titan_cap:
		return false
	var pos := _pick_titan_spawn(force_visible)
	if pos == Vector3.INF:
		return false
	var titan := titan_scene.instantiate() as Titan
	if titan == null:
		return false
	_apply_titan(titan)
	_apply_titan_speed(titan)
	get_parent().add_child(titan)
	titan.global_position = pos
	if _player != null:
		var toward := _player.global_position - titan.global_position
		toward.y = 0.0
		if toward.length_squared() > 0.01:
			titan.look_at(titan.global_position + toward.normalized(), Vector3.UP)
	return true


func _try_spawn_soldier() -> bool:
	if soldier_scene == null:
		return false
	if _alive_soldiers() >= _max_soldiers_for_titans():
		return false
	var suppliers := _unseen_suppliers()
	if suppliers.is_empty():
		return false
	var supplier: GasSupplier = suppliers[_rng.randi_range(0, suppliers.size() - 1)]
	var facing := -supplier.outward()
	if facing.length_squared() < 0.01:
		facing = Vector3.FORWARD
	var right := Vector3(-facing.z, 0.0, facing.x).normalized()
	var pos := supplier.landing_point() \
		+ right * _rng.randf_range(-1.2, 1.2) \
		+ facing * _rng.randf_range(0.0, 0.8) \
		+ Vector3.UP * 0.05
	_spawn_soldier_at(pos, facing)
	return true


func _spawn_soldier_at(pos: Vector3, facing: Vector3) -> Soldier:
	var soldier := soldier_scene.instantiate() as Soldier
	_apply_soldier(soldier)
	get_parent().add_child(soldier)
	soldier.global_position = pos
	if facing.length_squared() > 0.01:
		soldier.look_at(soldier.global_position + facing.normalized(), Vector3.UP)
	return soldier


func _pick_titan_spawn(force_visible: bool) -> Vector3:
	if _player == null:
		return Vector3.INF
	var flat := Vector2(_player.global_position.x, _player.global_position.z)
	var away := -flat
	if away.length_squared() < 1.0:
		var angle := _rng.randf() * TAU
		away = Vector2(cos(angle), sin(angle))
	else:
		away = away.normalized()
	var radius := map_half_size - titan_edge_margin
	var along := Vector2(-away.y, away.x)
	var fallback := Vector3(away.x * radius, 0.0, away.y * radius)
	for _attempt in 12:
		var lateral := along * (_rng.randf_range(-1.0, 1.0) * radius * titan_edge_jitter)
		var spot := away * radius + lateral
		spot.x = clampf(spot.x, -radius, radius)
		spot.y = clampf(spot.y, -radius, radius)
		var world := Vector3(spot.x, 0.0, spot.y)
		if not _point_visible(world + Vector3.UP * titan_visibility_height):
			return world
		fallback = world
	return fallback if force_visible else Vector3.INF


func _point_visible(world_pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	if not cam.is_position_in_frustum(world_pos):
		return false
	# Treat anything clearly behind the camera as unseen even if frustum math is generous.
	var to := world_pos - cam.global_position
	if to.dot(-cam.global_transform.basis.z) <= 0.0:
		return false
	return true


func _unseen_suppliers() -> Array[GasSupplier]:
	var out: Array[GasSupplier] = []
	for supplier in _gas_suppliers():
		if _start_supplier != null and supplier == _start_supplier and _elapsed < 8.0:
			continue
		if not _point_visible(supplier.deck_center() + Vector3.UP * 1.5):
			out.append(supplier)
	return out


func _gas_suppliers() -> Array[GasSupplier]:
	var out: Array[GasSupplier] = []
	for node in get_tree().get_nodes_in_group("gas_supplier"):
		var supplier := node as GasSupplier
		if supplier != null:
			out.append(supplier)
	return out


func _alive_titans() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("titan"):
		var titan := node as Titan
		if titan != null and titan.alive:
			count += 1
	return count


func _alive_soldiers() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("soldier"):
		var soldier := node as Soldier
		if soldier != null and soldier.alive:
			count += 1
	return count


func _target_titan_count() -> int:
	var gained := int(floor(_elapsed / 60.0 * titan_min_gain_per_minute))
	return clampi(titan_min_start + gained, titan_min_start, titan_cap)


func _max_soldiers_for_titans() -> int:
	return int(floor(float(_alive_titans()) * float(soldier_ratio_num) / float(soldier_ratio_den)))


func _titan_spawn_interval() -> float:
	var t := 0.0 if titan_spawn_rate_ramp_minutes <= 0.0 \
		else clampf(_elapsed / (titan_spawn_rate_ramp_minutes * 60.0), 0.0, 1.0)
	var base := lerpf(titan_spawn_interval_start, titan_spawn_interval_min, t)
	return base / maxf(0.05, GameSettings.titan_spawn_rate)


func _soldier_spawn_interval() -> float:
	var t := 0.0 if soldier_spawn_rate_ramp_minutes <= 0.0 \
		else clampf(_elapsed / (soldier_spawn_rate_ramp_minutes * 60.0), 0.0, 1.0)
	var base := lerpf(soldier_spawn_interval_start, soldier_spawn_interval_max, t)
	return base / maxf(0.05, GameSettings.soldier_spawn_rate)


func _apply_titan_speeds() -> void:
	for node in get_tree().get_nodes_in_group("titan"):
		if node is Titan and node.alive:
			_apply_titan_speed(node)


func _apply_titan_speed(titan: Titan) -> void:
	var added := (_elapsed / 60.0) * titan_speed_gain_per_minute
	titan.wander_speed = minf(titan_base_wander_speed + added,
		titan_base_wander_speed * titan_speed_max_multiplier)
	titan.chase_speed = minf(titan_base_chase_speed + added,
		titan_base_chase_speed * titan_speed_max_multiplier)


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
