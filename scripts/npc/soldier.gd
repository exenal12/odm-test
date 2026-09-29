class_name Soldier
extends CharacterBody3D
## NPC that walks to the nearest titan, hooks toward its nape with ODM gear, and strikes it.

signal titan_killed(titan: Titan)
signal died(soldier: Soldier)

@export_group("Health")
@export var max_health: float = 20.0

@export_group("Movement")
@export var run_speed: float = 6.0
@export var turn_speed: float = 8.0
@export var ground_accel: float = 30.0
## Stop walking once this close to the titan on the ground plane.
@export var min_ground_distance: float = 10.0

@export_group("ODM")
## Maximum distance at which a hook is fired at the titan.
@export var hook_range: float = 38.0
## Seconds between hook attempts.
@export var hook_retry: float = 0.5
## Within this distance the soldier re-hooks straight at the nape.
@export var reattach_range: float = 12.0
## Hooks are only fired while within this angle of the titan's back.
@export_range(10.0, 180.0) var rear_angle_deg: float = 70.0
## Minimum distance kept from the titan while circling around to its back.
@export var flank_radius: float = 30.0

@export_group("Attack")
@export var strike_range: float = 5.0
@export_range(0.0, 1.0) var strike_chance: float = 0.7
@export var strike_damage: float = 20.0
@export var strike_cooldown: float = 1.5
## Delay from swing start to the hit landing.
@export var strike_hit_delay: float = 0.25

## Aim offsets from the nape tried in turn when a hook misses or latches poorly.
const AIM_OFFSETS: Array[Vector3] = [
	Vector3.ZERO, Vector3(0.0, -2.5, 0.0), Vector3(0.0, -5.0, 0.0), Vector3(0.0, 1.5, 0.0),
]
const EYE_HEIGHT := 1.4

@onready var odm: ODMController = $ODMController
@onready var odm_gear: Node3D = $ODMGear
@onready var animation: PlayerAnimation = $PlayerAnimation

var target: Titan
var health: float = 0.0
var alive: bool = true

var _agent: NavigationAgent3D
var _hook_timer: float = 0.0
var _strike_timer: float = 0.0
var _retarget_timer: float = 0.0
var _hit_timer: float = -1.0
var _aim_attempt: int = 0
var _check_pending: bool = false


func _ready() -> void:
	add_to_group("soldier")
	health = max_health
	odm.ai_controlled = true
	odm.setup(self, null, odm_gear)
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.5
	_agent.height = 1.8
	_agent.path_desired_distance = 1.5
	_agent.target_desired_distance = 2.0
	add_child(_agent)
	_hook_timer = randf() * hook_retry


## Titans call this (same signature as the player's).
func take_damage(amount: float, _source: Node = null, _ignore_invulnerable: bool = false) -> void:
	if not alive or amount <= 0.0:
		return
	health -= amount
	if health <= 0.0:
		_die()


func _die() -> void:
	alive = false
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	odm.release_hooks()
	odm.ai_steer = Vector3.ZERO
	died.emit(self)
	get_tree().create_timer(2.0).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	if not alive:
		velocity.x = move_toward(velocity.x, 0.0, ground_accel * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_accel * delta)
		velocity += get_gravity() * delta
		move_and_slide()
		animation.play_base(&"Idle")
		return
	_hook_timer = maxf(0.0, _hook_timer - delta)
	_strike_timer = maxf(0.0, _strike_timer - delta)
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or not _target_valid():
		_retarget_timer = 0.5
		_pick_target()

	if not is_on_floor():
		velocity += get_gravity() * delta

	var walk_dir := Vector3.ZERO
	if _target_valid():
		var nape := target.nape.global_position
		_think(nape)
		walk_dir = _ground_direction()
	else:
		odm.ai_steer = Vector3.ZERO
		if odm.is_hooked():
			odm.release_hooks()
	_update_strike(delta)

	if odm.is_active():
		odm.physics_tick(delta)
		_face(Vector3(velocity.x, 0.0, velocity.z), delta)
	else:
		_ground_move(walk_dir, delta)
		odm.physics_tick(delta)
	move_and_slide()
	_update_animation()


func _target_valid() -> bool:
	return target != null and is_instance_valid(target) and target.alive


func _pick_target() -> void:
	var best: Titan
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("titan"):
		var titan := node as Titan
		if titan == null or not titan.alive:
			continue
		var d := global_position.distance_squared_to(titan.global_position)
		if d < best_dist:
			best_dist = d
			best = titan
	if best != target:
		_aim_attempt = 0
	target = best


func _eye() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT


## Decides hook actions and strikes for this frame.
func _think(nape: Vector3) -> void:
	var dist := _eye().distance_to(nape)
	var hooked := odm.is_hooked()

	if _check_pending:
		_check_pending = false
		if hooked:
			var anchor_gap := odm.get_anchor().distance_to(nape)
			if anchor_gap > dist - 5.0 and anchor_gap > strike_range + 2.0:
				odm.request_release(true)
				odm.request_release(false)
				_aim_attempt += 1
				_hook_timer = hook_retry
				hooked = false
		else:
			_aim_attempt += 1

	var flat := nape - global_position
	flat.y = 0.0
	odm.ai_steer = flat

	var behind := _behind_titan()
	if hooked:
		if dist <= strike_range:
			_begin_strike()
		elif behind and dist <= reattach_range and _hook_timer <= 0.0 \
				and odm.get_anchor().distance_to(nape) > strike_range + 2.0:
			_fire_at(nape, 0)
	elif behind and dist <= hook_range and _hook_timer <= 0.0:
		_fire_at(nape, _aim_attempt)


## True when the soldier is inside the rear cone of the titan.
func _behind_titan() -> bool:
	var back := Vector3(-target.global_basis.z.x, 0.0, -target.global_basis.z.z).normalized()
	var to_me := global_position - target.global_position
	to_me.y = 0.0
	if to_me.length_squared() < 0.01:
		return true
	return back.dot(to_me.normalized()) >= cos(deg_to_rad(rear_angle_deg))


func _fire_at(nape: Vector3, attempt: int) -> void:
	var aim_point := nape + AIM_OFFSETS[attempt % AIM_OFFSETS.size()]
	var origin := _eye()
	odm.set_aim(origin, aim_point - origin)
	odm.request_fire(true)
	odm.request_fire(false)
	_hook_timer = hook_retry
	_check_pending = true


func _begin_strike() -> void:
	if _strike_timer > 0.0 or _hit_timer >= 0.0:
		return
	_strike_timer = strike_cooldown
	_hit_timer = strike_hit_delay
	var left := randf() < 0.5
	if animation.has_clip(&"SwingLeft" if left else &"SwingRight"):
		animation.attack(left, 2.0)


func _update_strike(delta: float) -> void:
	if _hit_timer < 0.0:
		return
	_hit_timer -= delta
	if _hit_timer >= 0.0:
		return
	_hit_timer = -1.0
	if not _target_valid():
		return
	var nape := target.nape.global_position
	if _eye().distance_to(nape) > strike_range * 1.5 or randf() > strike_chance:
		return
	var victim := target
	victim.on_sword_hit(victim.nape, strike_damage, global_position)
	if victim.alive:
		return
	odm.release_hooks()
	titan_killed.emit(victim)


## Horizontal direction toward the titan, following the navmesh when it exists.
func _ground_direction() -> Vector3:
	var goal := target.global_position
	if not _behind_titan():
		goal = _flank_point()
	var to_goal := goal - global_position
	to_goal.y = 0.0
	if _behind_titan() and to_goal.length() < min_ground_distance:
		return Vector3.ZERO
	if to_goal.length() < 2.0:
		return Vector3.ZERO
	var dir := to_goal
	if _nav_ready():
		_agent.target_position = goal
		dir = _agent.get_next_path_position() - global_position
		dir.y = 0.0
		if dir.length_squared() < 0.01:
			dir = to_goal
	return dir.normalized()


## A point on a circle around the titan, a bit further toward its back than we are.
func _flank_point() -> Vector3:
	var center := target.global_position
	var offset := global_position - center
	offset.y = 0.0
	var radius := maxf(offset.length(), flank_radius)
	var dir := offset.normalized() if offset.length_squared() > 0.01 else Vector3.FORWARD
	var back := Vector3(-target.global_basis.z.x, 0.0, -target.global_basis.z.z).normalized()
	var side := signf(dir.cross(back).y)
	if side == 0.0:
		side = 1.0
	return center + dir.rotated(Vector3.UP, side * 0.6) * radius


func _nav_ready() -> bool:
	var map := _agent.get_navigation_map()
	return NavigationServer3D.map_get_iteration_id(map) != 0 \
			and not NavigationServer3D.map_get_regions(map).is_empty()


func _ground_move(dir: Vector3, delta: float) -> void:
	if is_on_floor():
		var wanted := dir * run_speed
		velocity.x = move_toward(velocity.x, wanted.x, ground_accel * delta)
		velocity.z = move_toward(velocity.z, wanted.z, ground_accel * delta)
	_face(dir, delta)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.16:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), turn_speed * delta)


func _update_animation() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or odm.is_hooked():
		animation.play_base(&"Jump")
	elif speed > 0.5:
		animation.play_base(&"RunForward", clampf(speed / 4.0, 0.5, 1.0))
	else:
		animation.play_base(&"Idle")
