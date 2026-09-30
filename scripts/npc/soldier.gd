class_name Soldier
extends CharacterBody3D
## NPC that walks to the nearest titan, hooks toward its nape with ODM gear, and strikes it.

signal titan_killed(titan: Titan)
signal died(soldier: Soldier)

@export_group("Health")
@export var max_health: float = 20.0
## Seconds a body stays before sinking away.
@export var corpse_time: float = 8.0
@export var sink_duration: float = 2.0

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

@export_group("Traversal")
## Hook onto scenery and reel to get around, like the player does.
@export var use_traversal: bool = true
## Walk instead of hooking once the goal is this close.
@export var traverse_distance: float = 20.0
## How far ahead anchors are searched; keep below the ODM cable length.
@export var traverse_range: float = 35.0
## Minimum distance an anchor must bring the soldier toward its goal.
@export var traverse_min_progress: float = 6.0
## Let go of a traversal hook this close to its anchor.
@export var traverse_release_distance: float = 5.0
## Longest time a traversal hook is held.
@export var traverse_max_hold: float = 3.0
## Minimum seconds between traversal swings.
@export var traverse_cooldown: float = 1.25
## Anchors higher than this above the soldier are ignored.
@export var traverse_max_height: float = 10.0

@export_group("Gas")
## Head for a gas station at or below this fraction of full gas.
@export_range(0.0, 1.0) var low_gas_fraction: float = 0.25
## Return to fighting once gas is back above this fraction.
@export_range(0.0, 1.0) var resume_gas_fraction: float = 0.9

@export_group("Tactics")
## Seconds spent in position before the first hook is fired.
@export var reaction_time: float = 0.5
## Only strike while the titan is focused on something other than this soldier.
@export var require_distraction: bool = false
## Seconds hooked onto a titan without landing a strike before giving up and re-flanking.
@export var max_hook_time: float = 5
## Most soldiers allowed hooked onto one titan at once. 0 means unlimited.
@export var max_attackers: int = 1
## Ground distance to the titan under which a front-hooked or targeted soldier bails out.
@export var danger_distance: float = 14.0
## While airborne, anchors are still sought when the goal is at least this far.
@export var air_traverse_distance: float = 6.0
## Extra height to seek while fleeing so the next approach starts above the titan.
@export var flee_height_gain: float = 12.0

@export_group("Attack")
@export var strike_range: float = 5.0
@export_range(0.0, 1.0) var strike_chance: float = 0.7
@export var strike_damage: float = 20.0
@export var strike_cooldown: float = 1.5
## Delay from swing start to the hit landing.
@export var strike_hit_delay: float = 0.25

## Aim offsets from the nape in titan-local space: X right, Y up, Z toward its back.
const AIM_OFFSETS: Array[Vector3] = [
	Vector3.ZERO, Vector3(0.0, -2.5, 0.5), Vector3(0.0, -5.0, 1.0), Vector3(0.0, 1.5, 0.5),
	Vector3(2.5, -3.0, 1.0), Vector3(-2.5, -3.0, 1.0), Vector3(0.0, -6.0, 1.5),
	Vector3(2.0, -8.5, 1.5), Vector3(-2.0, -8.5, 1.5), Vector3(0.0, -11.0, 2.0),
]
const EYE_HEIGHT := 1.4
## Longest time spent retreating after a missed strike before trying again.
const REFLANK_TIMEOUT := 12.0
## Instant push away from the titan when a strike misses.
const MISS_RETREAT_SPEED := 18.0
const MISS_RETREAT_UP := 10.0
## Look-ahead distance for trunk avoidance, and stuck detection timings.
const AVOID_DISTANCE := 3.5
const STUCK_TIME := 1.0
const UNSTICK_DURATION := 1.2
## Start circling to the titan's back inside flank_radius times this.
const FLANK_START_FACTOR := 1.3
## How long to circle to a new angle after trees block every shot.
const BLOCKED_SIDESTEP_TIME := 2.0

@onready var odm: ODMController = $ODMController
@onready var odm_gear: Node3D = $ODMGear
@onready var animation: PlayerAnimation = $PlayerAnimation
@onready var audio: Node = $PlayerAudio

var target: Titan
var _forced_titan: Titan
var _forced_until_msec: int = 0
var health: float = 0.0
var alive: bool = true

var _agent: NavigationAgent3D
var _hook_timer: float = 0.0
var _strike_timer: float = 0.0
var _retarget_timer: float = 0.0
var _hit_timer: float = -1.0
var _aim_attempt: int = 0
var _check_pending: bool = false
var _hook_hold: float = 0.0
var _refueling: bool = false
var _refuel_goal: Vector3 = Vector3.ZERO
var _traversing: bool = false
var _trav_time: float = 0.0
var _trav_fired: bool = false
var _reaction_left: float = -1.0
var _reflank_left: float = 0.0
var _stuck_time: float = 0.0
var _unstick_left: float = 0.0
var _unstick_sign: float = 1.0
var _blocked_left: float = 0.0
var _sidestep: float = 1.0
var _climbing: bool = false
var _climb_time: float = 0.0
var _climb_retry: float = 0.0
var _was_on_floor: bool = true
var _air_time: float = 0.0
var _debug_label: Label3D
var _gs: Node


func _ready() -> void:
	add_to_group("soldier")
	health = max_health
	odm.ai_controlled = true
	odm.setup(self, null, odm_gear)
	audio.bind_odm(odm)
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.5
	_agent.height = 1.8
	_agent.path_desired_distance = 1.5
	_agent.target_desired_distance = 2.0
	add_child(_agent)
	_hook_timer = randf() * hook_retry
	_gs = get_node("/root/GameSettings")
	_gs.settings_changed.connect(_sync_debug_settings)
	_sync_debug_settings()


## Titans call this (same signature as the player's).
func take_damage(amount: float, _source: Node = null, _ignore_invulnerable: bool = false) -> void:
	if not alive or amount <= 0.0:
		return
	health -= amount
	if health <= 0.0:
		_die()


func _die() -> void:
	var airborne := not is_on_floor() or odm.is_hooked() or _climbing
	_climbing = false
	alive = false
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	odm.release_hooks(true)
	odm.ai_steer = Vector3.ZERO
	animation.play_death(airborne)
	died.emit(self)
	await get_tree().create_timer(corpse_time).timeout
	var model := animation.model
	var tween := create_tween()
	tween.tween_property(model, "position:y", model.position.y - 0.6, sink_duration).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	if not alive:
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, ground_accel * delta)
			velocity.z = move_toward(velocity.z, 0.0, ground_accel * delta)
		velocity += get_gravity() * delta
		move_and_slide()
		if animation.update_death(delta, is_on_floor(), velocity):
			audio.play_land(get_last_slide_collision().get_collider() if get_slide_collision_count() > 0 else null)
		return
	_hook_timer = maxf(0.0, _hook_timer - delta)
	_strike_timer = maxf(0.0, _strike_timer - delta)
	_climb_retry = maxf(0.0, _climb_retry - delta)
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or not _target_valid():
		_retarget_timer = 0.5
		_pick_target()

	if not is_on_floor():
		velocity += get_gravity() * delta

	_update_gas_state()
	var walk_dir := Vector3.ZERO
	if _refueling:
		walk_dir = _refuel_think(delta)
	elif _target_valid():
		var nape := target.nape.global_position
		_think(nape, delta)
		walk_dir = _ground_direction()
	else:
		odm.ai_steer = Vector3.ZERO
		odm.ai_boost = false
		if odm.is_hooked():
			odm.release_hooks()
	_update_strike(delta)

	if _unstick_left > 0.0:
		_unstick_left -= delta
		walk_dir = walk_dir.rotated(Vector3.UP, _unstick_sign * 1.2)
	walk_dir = _steer_clear(walk_dir)

	if odm.is_active():
		odm.physics_tick(delta)
		_face(Vector3(velocity.x, 0.0, velocity.z), delta)
	else:
		_ground_move(walk_dir, delta)
		odm.physics_tick(delta)
	move_and_slide()
	_update_stuck(walk_dir, delta)
	_update_animation()
	_update_audio(delta)
	_update_debug_label()


func _target_valid() -> bool:
	return target != null and is_instance_valid(target) and target.alive


## Locks this soldier onto a titan, overriding nearest-titan selection for a while.
func command_target(titan: Titan, duration: float) -> void:
	_forced_titan = titan
	_forced_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)
	_retarget_timer = 0.0


func _pick_target() -> void:
	if Time.get_ticks_msec() < _forced_until_msec and is_instance_valid(_forced_titan) and _forced_titan.alive:
		if target != _forced_titan:
			_aim_attempt = 0
			_reflank_left = 0.0
			_reaction_left = -1.0
		target = _forced_titan
		return
	_forced_until_msec = 0
	_forced_titan = null
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
		_reflank_left = 0.0
		_reaction_left = -1.0
	target = best


func _eye() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT


## Decides hook actions and strikes for this frame.
func _think(nape: Vector3, delta: float) -> void:
	var dist := _eye().distance_to(nape)
	var hooked := odm.is_hooked()
	_update_reflank(delta)
	_blocked_left = maxf(0.0, _blocked_left - delta)

	# Don't abort a committed titan latch just because it looked at us.
	if _reflank_left <= 0.0 and not (hooked and _anchor_on_titan()) \
			and _is_threatened(hooked):
		_miss()
		return

	if _traversing:
		var can_attack := _behind_titan() and dist <= hook_range and _reflank_left <= 0.0
		if can_attack:
			# Wind up mid-swing; only let go once ready to fire.
			if _reaction_left < 0.0:
				_reaction_left = reaction_time
			_reaction_left -= delta
			if _reaction_left > 0.0:
				_update_traversal(delta)
				return
			odm.release_hooks()
			_traversing = false
			hooked = false
			# Fire this frame; don't let the ground path re-arm windup.
			_reaction_left = 0.0
		else:
			_update_traversal(delta)
			return

	if _check_pending:
		_check_pending = false
		if hooked:
			# Keep any latch on the titan; only reject scenery. Re-hook nearer the
			# nape later via reattach_range once they reel in.
			if not _anchor_on_titan():
				odm.request_release(true)
				odm.request_release(false)
				_aim_attempt += 1
				_hook_timer = hook_retry
				hooked = false
		else:
			_aim_attempt += 1

	if hooked:
		_hook_hold += delta
		if _hook_hold >= max_hook_time:
			_miss()
			return
		if _anchor_on_titan():
			# Face / front latch: get out immediately instead of hovering.
			if not _behind_titan():
				_miss()
				return
			# Titan staring us down with distraction required — abort the climb.
			if require_distraction and target.target == self:
				_miss()
				return
			if dist <= strike_range:
				_begin_strike()
			elif dist <= reattach_range and _hook_timer <= 0.0 \
					and odm.get_anchor().distance_to(nape) > strike_range + 2.0:
				if _shot_clear(_aim_world(nape, 0)):
					_fire_at(nape, 0)
			var flat_titan := nape - global_position
			flat_titan.y = 0.0
			odm.ai_steer = flat_titan
			# Normal reel only while attacking — save gas for escapes.
			odm.ai_boost = false
			return
	else:
		_hook_hold = 0.0

	var flat := nape - global_position
	flat.y = 0.0
	if _reflank_left > 0.0:
		var away := global_position - target.global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = -flat
		# Steer out and up so the escape gains height on the titan.
		odm.ai_steer = away.normalized() + Vector3.UP * 0.85
		odm.ai_boost = true
		_reaction_left = -1.0
		if _traversing:
			_update_traversal(delta)
		else:
			_try_traverse(true)
		return
	odm.ai_steer = flat
	odm.ai_boost = false

	var behind := _behind_titan()
	if hooked:
		# Non-titan latch left over — drop it and escape.
		_miss()
		return

	var can_hook := behind and dist <= hook_range and _slot_free()
	if not can_hook:
		_reaction_left = -1.0
		_try_traverse()
		return
	# Already in attack position: stay committed. Sidestep if blocked, don't traverse.
	if _reaction_left < 0.0:
		_reaction_left = reaction_time
	_reaction_left -= delta
	if _reaction_left <= 0.0 and _hook_timer <= 0.0:
		var pick := _pick_clear_aim(nape)
		if pick < 0:
			if _blocked_left <= 0.0:
				_sidestep = -_sidestep
			_blocked_left = BLOCKED_SIDESTEP_TIME
			_hook_timer = hook_retry
			return
		_fire_at(nape, pick)


## True when the current ODM latch is on the targeted titan (any body segment).
func _anchor_on_titan() -> bool:
	if not odm.is_hooked() or not _target_valid():
		return false
	var node := odm.get_anchored_body() as Node
	if node == null:
		# Fallback: treat a latch near the titan as on-target.
		return odm.get_anchor().distance_to(target.global_position) < 22.0
	for _i in 4:
		if node == null:
			return false
		if node == target or node is Titan:
			return true
		node = node.get_parent()
	return false


## First aim offset with an unobstructed line to the titan, or -1 if trees block them all.
func _pick_clear_aim(nape: Vector3) -> int:
	for i in AIM_OFFSETS.size():
		var idx := (_aim_attempt + i) % AIM_OFFSETS.size()
		if _shot_clear(_aim_world(nape, idx)):
			return idx
	return -1


## Nape aim point from a titan-local offset (Z is toward the titan's back).
func _aim_world(nape: Vector3, attempt: int) -> Vector3:
	var local := AIM_OFFSETS[attempt % AIM_OFFSETS.size()]
	var basis := target.global_basis
	var right := Vector3(basis.x.x, 0.0, basis.x.z)
	var back := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	if back.length_squared() < 0.01:
		back = Vector3.FORWARD
	else:
		back = back.normalized()
	return nape + right * local.x + Vector3.UP * local.y + back * local.z


## True when a hook fired at aim_point would latch onto the titan rather than scenery.
func _shot_clear(aim_point: Vector3) -> bool:
	var origin := _eye()
	var dir := aim_point - origin
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir + dir.normalized() * 2.0)
	query.collision_mask = odm.grapple_collision_mask
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var node := hit.collider as Node
	for _i in 3:
		if node == null:
			return false
		if node is Titan:
			return true
		node = node.get_parent()
	return false


## True when too close to a titan that is hunting us, or hooked onto its front.
func _is_threatened(hooked: bool) -> bool:
	var offset := global_position - target.global_position
	offset.y = 0.0
	if offset.length() > danger_distance:
		return false
	if target.target == self:
		return true
	return hooked and not _behind_titan()


## Minimum goal distance for starting or keeping a traversal hook; lower in the air.
func _traverse_threshold() -> float:
	return traverse_distance if is_on_floor() else minf(traverse_distance, air_traverse_distance)


## Switches into refuel mode when gas runs low, and back out once topped up.
func _update_gas_state() -> void:
	var fraction := odm.get_gas() / maxf(odm.get_gas_max(), 1.0)
	if not _refueling:
		if fraction <= low_gas_fraction and _nearest_station() != null:
			_refueling = true
			odm.release_hooks()
			odm.ai_boost = false
			_traversing = false
			_check_pending = false
			_hit_timer = -1.0
			_reaction_left = -1.0
	elif fraction >= resume_gas_fraction:
		_refueling = false


func _nearest_station() -> Node3D:
	var best: Node3D
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("gas_station") \
			+ get_tree().get_nodes_in_group("gas_supplier"):
		var station := node as Node3D
		if station == null or (station.has_method("climb_route") and station.climb_route().is_empty()):
			continue
		var d := global_position.distance_squared_to(station.global_position)
		if d < best_dist:
			best_dist = d
			best = station
	return best


## Heads for the nearest gas station, hooking toward it when far, and waits there.
func _refuel_think(delta: float) -> Vector3:
	var station := _nearest_station()
	if station == null:
		_refueling = false
		return Vector3.ZERO
	_refuel_goal = station.global_position
	if station.has_method("climb_route"):
		if _climbing:
			return _update_climb(station, delta)
		var landing: Vector3 = station.landing_point()
		if landing.y <= global_position.y + 3.0:
			return _deck_walk(station)
		var start: Vector3 = station.climb_route().start
		_refuel_goal = Vector3(start.x, global_position.y, start.z)
		if Vector2(start.x - global_position.x, start.z - global_position.z).length() < 2.5 \
				and is_on_floor() and _climb_retry <= 0.0:
			_begin_climb(station)
			return Vector3.ZERO
	var flat := _refuel_goal - global_position
	flat.y = 0.0
	odm.ai_steer = flat
	if flat.length() < 2.0:
		if odm.is_hooked():
			odm.release_hooks()
		_traversing = false
		return Vector3.ZERO
	if _traversing:
		_update_traversal(delta)
	elif odm.get_gas() > 0.0:
		_try_traverse()
	return _ground_direction()


## Fires both hooks at the platform's trunk anchor and reels straight up over the deck edge.
func _begin_climb(station: Node3D) -> void:
	odm.release_hooks()
	_traversing = false
	var origin := _eye()
	odm.set_aim(origin, station.climb_route().anchor - origin)
	odm.request_fire(true)
	odm.request_fire(false)
	_climbing = true
	_climb_time = 0.0
	_hook_timer = hook_retry


## Lets go once over the deck, or gives up if the hooks missed or the reel stalls.
func _update_climb(station: Node3D, delta: float) -> Vector3:
	_climb_time += delta
	odm.ai_steer = Vector3.ZERO
	var center: Vector3 = station.deck_center()
	var radial := Vector2(global_position.x - center.x, global_position.z - center.z).length()
	if radial < float(station.deck_radius) - 0.6 and global_position.y > center.y + 0.1:
		odm.release_hooks()
		# Keep only a small hop so the reel's upward speed does not launch us off the deck.
		var flat := Vector3(velocity.x, 0.0, velocity.z).limit_length(3.0)
		velocity = flat + Vector3.UP * minf(velocity.y, 2.5)
		_climbing = false
	elif (_climb_time > 0.2 and not odm.is_hooked()) or _climb_time > 15.0:
		odm.release_hooks()
		_climbing = false
		_climb_retry = 2.0
	return Vector3.ZERO


## On the deck: walk to the landing spot, going around the trunk rather than into it.
func _deck_walk(station: Node3D) -> Vector3:
	odm.ai_steer = Vector3.ZERO
	if odm.is_hooked():
		odm.release_hooks()
	_traversing = false
	var to: Vector3 = station.landing_point() - global_position
	to.y = 0.0
	if to.length() < 0.8:
		return Vector3.ZERO
	var center: Vector3 = station.deck_center()
	var radial := global_position - center
	radial.y = 0.0
	var wanted: Vector3 = station.landing_point() - center
	wanted.y = 0.0
	if radial.angle_to(wanted) > 0.6:
		var tangent := Vector3.UP.cross(radial).normalized()
		return tangent if tangent.dot(wanted) > 0.0 else -tangent
	return to.normalized()


## Starts a hook-and-reel hop toward the goal when it is far away.
## Pass fleeing to keep swinging even when the retreat goal is nearby.
func _try_traverse(fleeing: bool = false) -> void:
	if not use_traversal or _hook_timer > 0.0:
		return
	var goal := _goal_point()
	var flat := goal - global_position
	flat.y = 0.0
	var threshold := air_traverse_distance if fleeing else _traverse_threshold()
	if flat.length() <= threshold:
		return
	var anchor := _find_anchor(goal, fleeing)
	if not anchor.is_finite():
		_hook_timer = hook_retry if fleeing else traverse_cooldown
		return
	var origin := _eye()
	odm.set_aim(origin, anchor - origin)
	odm.request_fire(true)
	odm.request_fire(false)
	_traversing = true
	_trav_time = 0.0
	_trav_fired = true
	_hook_timer = hook_retry if fleeing else traverse_cooldown


## Follows a traversal hook and lets go once close to the anchor or held too long.
func _update_traversal(delta: float) -> void:
	_trav_time += delta
	var goal := _goal_point()
	var to_goal := goal - global_position
	var flat := to_goal
	flat.y = 0.0
	# Flee swings steer toward the elevated escape point, not just flat ground.
	odm.ai_steer = to_goal if _reflank_left > 0.0 else flat
	odm.ai_boost = _reflank_left > 0.0
	var flee_cd := hook_retry if _reflank_left > 0.0 else traverse_cooldown
	if _trav_fired:
		_trav_fired = false
		if not odm.is_hooked():
			_traversing = false
			_hook_timer = flee_cd
		return
	var release_gap := air_traverse_distance if _reflank_left > 0.0 else _traverse_threshold()
	var done := not odm.is_hooked() or _trav_time >= traverse_max_hold \
			or _eye().distance_to(odm.get_anchor()) <= traverse_release_distance \
			or flat.length() <= release_gap or odm.get_gas() <= 0.0
	if done:
		odm.release_hooks()
		_traversing = false
		_hook_timer = flee_cd


## Fans rays up and toward the goal; returns the grapple point making the most progress.
func _find_anchor(goal: Vector3, fleeing: bool = false) -> Vector3:
	var origin := _eye()
	var base := goal - origin
	base.y = 0.0
	if base.length_squared() < 0.01:
		return Vector3.INF
	base = base.normalized()
	var current_gap := Vector2(goal.x - origin.x, goal.z - origin.z).length()
	var space := get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_score := -INF
	var max_y := global_position.y + (flee_height_gain + 8.0 if fleeing else traverse_max_height)
	var pitches: Array = [0.3, 0.55, 0.85, 1.1] if fleeing else [0.12, 0.28, 0.45]
	for yaw in [-0.6, -0.3, 0.0, 0.3, 0.6, -1.0, 1.0, -1.4, 1.4]:
		var flat_dir := base.rotated(Vector3.UP, yaw)
		var pitch_axis := flat_dir.cross(Vector3.UP).normalized()
		if pitch_axis.length_squared() < 0.01:
			continue
		for pitch in pitches:
			var dir := flat_dir.rotated(pitch_axis, pitch)
			var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * traverse_range)
			query.collision_mask = odm.grapple_collision_mask
			query.exclude = [get_rid()]
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var collider := hit.collider as Node
			var on_titan := false
			var walk := collider
			for _i in 3:
				if walk == null:
					break
				if walk is Titan:
					on_titan = true
					break
				walk = walk.get_parent()
			# Flee may climb the titan; approach swings stay on scenery only.
			if on_titan and not fleeing:
				continue
			var point: Vector3 = hit.position
			if point.y < global_position.y + 1.5 or point.y > max_y:
				continue
			if on_titan and point.y < global_position.y + 3.0:
				continue
			var gap := Vector2(goal.x - point.x, goal.z - point.z).length()
			var progress := current_gap - gap
			if not fleeing and progress < traverse_min_progress:
				continue
			if fleeing and progress < traverse_min_progress * 0.35 and not on_titan:
				continue
			var height := point.y - global_position.y
			# Flee rewards height; normal traversal prefers staying lower.
			var score := progress + height * (0.9 if fleeing else -0.35)
			if on_titan:
				score += height * 0.5
			if score > best_score:
				best_score = score
				best = point
	return best


## Where the soldier is trying to get to on the ground plane.
func _goal_point() -> Vector3:
	if _refueling:
		return _refuel_goal
	var goal := target.global_position
	if _reflank_left > 0.0:
		var away := global_position - goal
		away.y = 0.0
		var dir := away.normalized() if away.length_squared() > 0.01 else Vector3.BACK
		goal += dir * flank_radius
		# Climb while escaping so the next pass starts near nape height.
		var nape_y := target.nape.global_position.y if target.nape != null \
			else target.global_position.y + 14.0
		goal.y = clampf(nape_y, global_position.y + 3.0, global_position.y + flee_height_gain)
		return goal
	elif _blocked_left > 0.0:
		var offset := global_position - goal
		offset.y = 0.0
		if offset.length_squared() > 0.01:
			goal += offset.rotated(Vector3.UP, _sidestep * 0.9)
	elif not _behind_titan():
		var gap := global_position - goal
		gap.y = 0.0
		# Close the distance first; only circle to its back once nearby.
		if gap.length() <= flank_radius * FLANK_START_FACTOR:
			goal = _flank_point()
	return goal


## Clears the re-flank state once the soldier has backed off far enough.
func _update_reflank(delta: float) -> void:
	if _reflank_left <= 0.0:
		return
	_reflank_left -= delta
	var offset := global_position - target.global_position
	offset.y = 0.0
	if offset.length() >= flank_radius * 0.8:
		_reflank_left = 0.0


## True when fewer than max_attackers other soldiers are hooked onto the target.
func _slot_free() -> bool:
	if max_attackers <= 0:
		return true
	var count := 0
	for node in get_tree().get_nodes_in_group("soldier"):
		var other := node as Soldier
		if other != null and other != self and other.alive and other.target == target \
				and other.odm.is_hooked() and not other._traversing:
			count += 1
	return count < max_attackers


## A failed strike: let go and retreat to flank again.
func _miss() -> void:
	odm.release_hooks()
	_hook_hold = 0.0
	_check_pending = false
	_traversing = false
	_hit_timer = -1.0
	_blocked_left = 0.0
	_reflank_left = REFLANK_TIMEOUT
	_reaction_left = -1.0
	_hook_timer = 0.0
	if _target_valid():
		var away := global_position - target.global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = -global_basis.z
			away.y = 0.0
		away = away.normalized()
		velocity = away * MISS_RETREAT_SPEED + Vector3.UP * MISS_RETREAT_UP
		odm.ai_steer = away
		odm.ai_boost = true
		_try_traverse(true)
	else:
		odm.ai_boost = false


## True when the soldier is inside the rear cone of the titan.
func _behind_titan() -> bool:
	var back := Vector3(-target.global_basis.z.x, 0.0, -target.global_basis.z.z).normalized()
	var to_me := global_position - target.global_position
	to_me.y = 0.0
	if to_me.length_squared() < 0.01:
		return true
	return back.dot(to_me.normalized()) >= cos(deg_to_rad(rear_angle_deg))


func _fire_at(nape: Vector3, attempt: int) -> void:
	var aim_point := _aim_world(nape, attempt)
	var origin := _eye()
	odm.set_aim(origin, aim_point - origin)
	odm.request_fire(true)
	odm.request_fire(false)
	_hook_timer = hook_retry
	_check_pending = true


func _begin_strike() -> void:
	if _strike_timer > 0.0 or _hit_timer >= 0.0:
		return
	if require_distraction and target.target == self:
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
		_miss()
		return
	var victim := target
	victim.on_sword_hit(victim.nape, strike_damage, global_position)
	if not victim.alive:
		odm.release_hooks()
		titan_killed.emit(victim)
		return
	# Keep the latch and swing again after cooldown; don't full-retreat on a hit.


## Horizontal direction toward the titan, following the navmesh when it exists.
func _ground_direction() -> Vector3:
	var goal := _goal_point()
	var retreating := _reflank_left > 0.0 or _refueling
	var to_goal := goal - global_position
	to_goal.y = 0.0
	if not retreating and _blocked_left <= 0.0 and _behind_titan() \
			and to_goal.length() < min_ground_distance:
		return Vector3.ZERO
	if to_goal.length() < 2.0:
		return Vector3.ZERO
	var dir := to_goal
	if _nav_ready():
		_agent.target_position = goal
		dir = _agent.get_next_path_position() - global_position
		dir.y = 0.0
		# A path that ends far from the goal is useless; head straight for it instead.
		var path_end := _agent.get_final_position()
		path_end.y = goal.y
		if dir.length_squared() < 0.01 or path_end.distance_to(goal) > 15.0:
			dir = to_goal
	return dir.normalized()


## Bends the walk direction around trunks and rocks detected just ahead.
func _steer_clear(dir: Vector3) -> Vector3:
	if dir.length_squared() < 0.01 or odm.is_active():
		return dir
	if _refueling and Vector2(_refuel_goal.x - global_position.x,
			_refuel_goal.z - global_position.z).length() < 8.0:
		return dir
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 1.0
	for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5]:
		var probe := dir.rotated(Vector3.UP, angle * _unstick_sign)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + probe * AVOID_DISTANCE)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		if space.intersect_ray(query).is_empty():
			return probe
	return dir


## Detects walking into something without moving and triggers a sidestep.
func _update_stuck(walk_dir: Vector3, delta: float) -> void:
	var wants_move := walk_dir.length_squared() > 0.01 and is_on_floor() and not odm.is_hooked()
	if wants_move and Vector2(velocity.x, velocity.z).length() < 0.6:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time >= STUCK_TIME:
		_stuck_time = 0.0
		_unstick_left = UNSTICK_DURATION
		_unstick_sign = -_unstick_sign
		_hook_timer = 0.0
		_climb_retry = 0.0


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


## Feeds the shared player audio system: footsteps, and a landing sound after airtime.
func _update_audio(delta: float) -> void:
	var on_floor := is_on_floor()
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5 and not odm.is_hooked()
	var collider: Object = audio.get_floor_collider(self) if on_floor else null
	audio.play_footsteps(delta, moving, false, on_floor, collider)
	if on_floor and not _was_on_floor and _air_time > 0.25:
		audio.play_land(collider)
	_air_time = 0.0 if on_floor else _air_time + delta
	_was_on_floor = on_floor


func _update_animation() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or odm.is_hooked():
		animation.play_base(&"Jump")
	elif speed > 0.5:
		animation.play_base(&"RunForward", clampf(speed / 4.0, 0.5, 1.0))
	else:
		animation.play_base(&"Idle")


func _sync_debug_settings() -> void:
	if _gs != null and bool(_gs.get("debug_soldier_ai")):
		if _debug_label == null:
			_debug_label = Label3D.new()
			_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_debug_label.no_depth_test = true
			_debug_label.pixel_size = 0.02
			_debug_label.font_size = 32
			_debug_label.position = Vector3(0.0, 2.4, 0.0)
			_debug_label.modulate = Color(0.75, 0.95, 1.0)
			add_child(_debug_label)
		_debug_label.visible = true
	elif _debug_label != null:
		_debug_label.visible = false


func _update_debug_label() -> void:
	if _debug_label == null or not _debug_label.visible:
		return
	_debug_label.text = _ai_status_text()


func _ai_status_text() -> String:
	if not alive:
		return "DEAD"
	if _refueling:
		return "REFUEL CLIMB" if _climbing else "REFUEL"
	if _hit_timer >= 0.0:
		return "STRIKE"
	if _climbing:
		return "CLIMB"
	if _traversing:
		return "TRAVERSE"
	if _reflank_left > 0.0:
		return "REFLANK"
	if not _target_valid():
		return "IDLE"
	if odm.is_hooked():
		return "HOOKED"
	if _reaction_left > 0.0:
		return "WINDUP"
	return "APPROACH"
