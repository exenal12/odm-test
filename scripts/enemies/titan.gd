class_name Titan
extends CharacterBody3D
## Titan enemy: state-machine AI with distance-scaled sight and hearing.
## Only hits on the nape kill it; body hits are ignored.

signal died(titan: Titan)
signal hit_player(player: CharacterBody3D, damage: float)

enum State { WANDER, INVESTIGATE, ALERT, CHASE, ATTACK, DEAD }

const NAPE_BONE := "B-neck"
## Nape offset from the neck bone in skeleton space (unscaled model units, -Z is the back).
const NAPE_OFFSET := Vector3(0.0, 0.05, -0.13)
## Hook and hit capsules: [from bone, to bone or skeleton-space offset, radius in model units].
const SEGMENTS := [
	["B-hips", "B-chest", 0.2], ["B-chest", "B-neck", 0.19],
	["B-neck", "B-head", 0.08], ["B-head", Vector3(0.0, 0.2, 0.0), 0.12],
	["B-upperArm.L", "B-forearm.L", 0.06], ["B-forearm.L", "B-hand.L", 0.05],
	["B-upperArm.R", "B-forearm.R", 0.06], ["B-forearm.R", "B-hand.R", 0.05],
	["B-thigh.L", "B-shin.L", 0.1], ["B-shin.L", "B-foot.L", 0.07], ["B-foot.L", "B-toe.L", 0.05],
	["B-thigh.R", "B-shin.R", 0.1], ["B-shin.R", "B-foot.R", 0.07], ["B-foot.R", "B-toe.R", 0.05],
]

@export_group("Movement")
@export var wander_speed: float = 4.0
@export var chase_speed: float = 10.0
@export var acceleration: float = 12.0
@export var turn_speed: float = 1.6
@export var gravity: float = 40.0
@export var wander_radius: float = 45.0
## Model-units of ground speed per 1.0 of Walk clip speed; higher = slower stride.
@export var walk_anim_stride: float = 24.0

@export_group("Awareness")
## Sight and hearing gains fall off with distance: gain = base * (1 - d / range) ^ falloff.
@export var sight_range: float = 70.0
@export var sight_half_angle_deg: float = 70.0
@export var sight_gain: float = 1.6
@export var hearing_range: float = 70.0
@export var hearing_gain: float = 1.0
@export var distance_falloff: float = 1.5
## Inside this range the titan senses the player regardless of facing.
@export var close_range: float = 14.0
@export var awareness_decay: float = 0.2
@export_range(0.0, 1.0) var suspicious_threshold: float = 0.35
@export_range(0.0, 1.0) var alert_threshold: float = 1.0
@export_range(0.0, 1.0) var lose_threshold: float = 0.2
@export var alert_duration: float = 1.2

@export_group("Attack")
@export var attack_range: float = 9.0
@export var attack_damage: float = 25.0
@export var attack_speed: float = 0.8
@export var attack_cooldown: float = 2.0
@export_range(0.0, 1.0) var hit_start_fraction: float = 0.35
@export_range(0.0, 1.0) var hit_end_fraction: float = 0.6
## A hand hits if the player is within this horizontal radius and vertical reach of it.
@export var hit_radius: float = 5.5
@export var hit_vertical_reach: float = 10.0
@export var knockback: float = 30.0
@export var knockback_up: float = 12.0

@export_group("Debug")
@export var show_debug: bool = true

@export var sink_duration: float = 1.5

@onready var nape: Area3D = $Nape
@onready var body_collider: CollisionShape3D = $CollisionShape3D
@onready var skeleton: Skeleton3D = $Model/Skeleton3D
@onready var animation_player: AnimationPlayer = $Model/AnimationPlayer
@onready var flash_mesh: MeshInstance3D = $Model/Skeleton3D/HumanM_BodyMesh
@onready var agent: NavigationAgent3D = $NavAgent

var state: State = State.WANDER
var alive: bool = true
var awareness: float = 0.0
var player: CharacterBody3D
var last_known: Vector3

var _neck_bone: int = -1
var _segments: Array[Dictionary] = []
var _exclude: Array[RID] = []
var _home: Vector3
var _nav_ready: bool = false
var _wandering: bool = false
var _has_target: bool = false
var _wait_timer: float = 2.0
var _state_timer: float = 0.0
var _cooldown_left: float = 0.0
var _attack_time: float = 0.0
var _attack_length: float = 1.0
var _attack_landed: bool = false
var _hand_bones: Array[int] = []
var _debug_label: Label3D


func _ready() -> void:
	_neck_bone = skeleton.find_bone(NAPE_BONE)
	_exclude.append(get_rid())
	for def in SEGMENTS:
		_add_segment(def[0], def[1], def[2])
	_hand_bones = [skeleton.find_bone("B-hand.L"), skeleton.find_bone("B-hand.R")]
	_attack_length = animation_player.get_animation(&"titan/Attack").length
	_home = global_position
	last_known = global_position
	if show_debug:
		_debug_label = Label3D.new()
		_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_debug_label.no_depth_test = true
		_debug_label.pixel_size = 0.04
		_debug_label.font_size = 48
		_debug_label.position = Vector3(0.0, 17.0, 0.0)
		add_child(_debug_label)


## Builds a kinematic capsule that follows the bones every physics frame.
## It is on the world and grappleable layers, so it blocks the player and takes hooks.
func _add_segment(from_bone: String, to: Variant, radius: float) -> void:
	var body := AnimatableBody3D.new()
	body.name = "Seg_" + from_bone
	body.collision_layer = 3
	body.collision_mask = 0
	body.add_to_group("grappleable")
	var shape := CapsuleShape3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	add_collision_exception_with(body)
	_exclude.append(body.get_rid())
	_segments.append({
		"body": body, "shape": shape, "from": skeleton.find_bone(from_bone),
		"to": skeleton.find_bone(to) if to is String else -1,
		"offset": to if to is Vector3 else Vector3.ZERO, "radius": radius,
	})


func _process(_delta: float) -> void:
	if _neck_bone < 0:
		return
	var neck := skeleton.get_bone_global_pose(_neck_bone).origin
	nape.global_position = skeleton.global_transform * (neck + NAPE_OFFSET)


func _physics_process(delta: float) -> void:
	_update_segments()
	if state == State.DEAD:
		_stop(delta)
		_finish_move(delta)
		return
	_acquire_player()
	if not _check_nav_ready() or player == null:
		_stop(delta)
		_play_locomotion()
		_finish_move(delta)
		return
	_sense(delta)
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	match state:
		State.WANDER: _state_wander(delta)
		State.INVESTIGATE: _state_investigate(delta)
		State.ALERT: _state_alert(delta)
		State.CHASE: _state_chase(delta)
		State.ATTACK: _state_attack(delta)
	if state != State.ATTACK and state != State.DEAD:
		_play_locomotion()
	_finish_move(delta)


# --- Perception ---

func _acquire_player() -> void:
	if player != null and is_instance_valid(player):
		return
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player != null:
		add_collision_exception_with(player)


func _check_nav_ready() -> bool:
	if _nav_ready:
		return true
	var map := agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0 or NavigationServer3D.map_get_regions(map).is_empty():
		return false
	var closest := NavigationServer3D.map_get_closest_point(map, global_position)
	_nav_ready = closest.distance_to(global_position) < 15.0
	return _nav_ready


func _eye_position() -> Vector3:
	var head := skeleton.find_bone("B-head")
	return skeleton.global_transform * skeleton.get_bone_global_pose(head).origin


func _sense(delta: float) -> void:
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var gain := 0.0
	var sensed := false
	if dist <= sight_range and (dist <= close_range or _in_view(to_player)) \
			and _line_of_sight(player.global_position + Vector3.UP):
		gain += sight_gain * pow(1.0 - dist / sight_range, distance_falloff)
		sensed = true
	var heard_range := hearing_range * _player_noise()
	if dist < heard_range:
		gain += hearing_gain * pow(1.0 - dist / heard_range, distance_falloff)
		sensed = true
	if sensed:
		last_known = player.global_position
		awareness = minf(1.0, awareness + gain * delta)
	else:
		awareness = maxf(0.0, awareness - awareness_decay * delta)


func _in_view(to_player: Vector3) -> bool:
	var flat := Vector3(to_player.x, 0.0, to_player.z).normalized()
	var forward := Vector3(global_basis.z.x, 0.0, global_basis.z.z).normalized()
	return forward.dot(flat) >= cos(deg_to_rad(sight_half_angle_deg))


func _line_of_sight(target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(_eye_position(), target)
	query.collision_mask = 1
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == player


func _player_noise() -> float:
	var noise := 0.1 + 0.9 * clampf(player.velocity.length() / 30.0, 0.0, 1.0)
	var odm := player.get_node_or_null("ODMController")
	if odm != null and odm.has_method("is_hooked") and odm.is_hooked():
		noise = maxf(noise, 0.8)
	return noise


# --- States ---

func _set_state(new_state: State) -> void:
	state = new_state
	_state_timer = 0.0
	if new_state == State.ATTACK:
		_attack_time = 0.0
		_attack_landed = false
		animation_player.play(&"titan/Attack", 0.3)
		animation_player.speed_scale = attack_speed


func _state_wander(delta: float) -> void:
	if awareness >= suspicious_threshold:
		_wandering = false
		_set_state(State.INVESTIGATE)
		return
	if _wandering:
		if agent.is_navigation_finished():
			_wandering = false
			_wait_timer = randf_range(2.0, 5.0)
		else:
			_steer(wander_speed, delta)
			return
	_stop(delta)
	_wait_timer -= delta
	if _wait_timer <= 0.0:
		var offset := Vector3(randf_range(-wander_radius, wander_radius), 0.0,
			randf_range(-wander_radius, wander_radius))
		agent.target_position = NavigationServer3D.map_get_closest_point(
			agent.get_navigation_map(), _home + offset)
		_has_target = true
		_wandering = true


func _state_investigate(delta: float) -> void:
	if awareness >= alert_threshold:
		_set_state(State.ALERT)
		return
	if awareness < 0.1:
		_set_state(State.WANDER)
		return
	_set_target(last_known)
	if agent.is_navigation_finished():
		_stop(delta)
		_turn_toward(_flat_dir(last_known - global_position), delta)
	else:
		_steer(wander_speed * 1.3, delta)


func _state_alert(delta: float) -> void:
	_stop(delta)
	_turn_toward(_flat_dir(last_known - global_position), delta)
	_state_timer += delta
	if _state_timer >= alert_duration:
		_set_state(State.CHASE)


func _state_chase(delta: float) -> void:
	if awareness < lose_threshold:
		_home = global_position
		_set_state(State.WANDER)
		return
	var to_player := player.global_position - global_position
	var flat_dist := Vector2(to_player.x, to_player.z).length()
	if awareness >= 0.5 and _cooldown_left <= 0.0 and flat_dist <= attack_range \
			and absf(to_player.y) < 14.0:
		_set_state(State.ATTACK)
		return
	_set_target(last_known)
	if agent.is_navigation_finished():
		_stop(delta)
	else:
		_steer(chase_speed, delta)


func _state_attack(delta: float) -> void:
	_stop(delta)
	var fraction := _attack_time / _attack_length
	if fraction < hit_start_fraction:
		_turn_toward(_flat_dir(player.global_position - global_position), delta * 0.5)
	_attack_time += delta * attack_speed
	fraction = _attack_time / _attack_length
	if not _attack_landed and fraction >= hit_start_fraction and fraction <= hit_end_fraction:
		_try_land_hit()
	if _attack_time >= _attack_length:
		_cooldown_left = attack_cooldown
		_set_state(State.CHASE)


func _try_land_hit() -> void:
	var center := player.global_position + Vector3.UP * 0.9
	var xform := skeleton.global_transform
	for bone in _hand_bones:
		var hand := xform * skeleton.get_bone_global_pose(bone).origin
		var offset := hand - center
		if Vector2(offset.x, offset.z).length() <= hit_radius and absf(offset.y) <= hit_vertical_reach:
			_attack_landed = true
			var away := _flat_dir(player.global_position - global_position)
			player.velocity += away * knockback + Vector3.UP * knockback_up
			if player.has_method(&"take_damage"):
				player.take_damage(attack_damage, self)
			hit_player.emit(player, attack_damage)
			return


# --- Movement helpers ---

func _set_target(pos: Vector3) -> void:
	if not _has_target or pos.distance_to(agent.target_position) > 1.5:
		agent.target_position = pos
		_has_target = true


func _flat_dir(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.ZERO


func _turn_toward(dir: Vector3, delta: float) -> void:
	if dir == Vector3.ZERO:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(turn_speed * delta, 0.0, 1.0))


func _steer(speed: float, delta: float) -> void:
	var dir := _flat_dir(agent.get_next_path_position() - global_position)
	if dir == Vector3.ZERO:
		_stop(delta)
		return
	_turn_toward(dir, delta)
	var forward := _flat_dir(global_basis.z)
	var target_velocity := forward * speed * maxf(0.0, forward.dot(dir))
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)


func _stop(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * 2.0 * delta)


func _finish_move(delta: float) -> void:
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	if _debug_label != null:
		_debug_label.text = "%s  awareness %.2f" % [State.keys()[state], awareness]


func _play_locomotion() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.4:
		if animation_player.current_animation != "titan/Idle":
			animation_player.play(&"titan/Idle", 0.4)
		animation_player.speed_scale = 1.0
	else:
		if animation_player.current_animation != "titan/Walk":
			animation_player.play(&"titan/Walk", 0.4)
		animation_player.speed_scale = speed / walk_anim_stride


func _update_segments() -> void:
	var xform := skeleton.global_transform
	var scale_factor := xform.basis.get_scale().x
	for seg in _segments:
		var a: Vector3 = xform * skeleton.get_bone_global_pose(seg.from).origin
		var b: Vector3 = xform * (skeleton.get_bone_global_pose(seg.to).origin if seg.to >= 0
			else skeleton.get_bone_global_pose(seg.from).origin + seg.offset)
		var direction := b - a
		var length := direction.length()
		if length < 0.01:
			continue
		var radius: float = seg.radius * scale_factor
		var shape := seg.shape as CapsuleShape3D
		shape.radius = radius
		shape.height = length + radius * 2.0
		var body := seg.body as AnimatableBody3D
		body.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, direction / length)), (a + b) * 0.5)


# --- Damage ---

## Called by SwordCombat for any node the blade overlaps.
func on_sword_hit(target: Node3D, _damage: float) -> void:
	if state == State.DEAD:
		return
	if target == nape:
		_die()
	else:
		_flash_deflect()


func _die() -> void:
	alive = false
	state = State.DEAD
	body_collider.set_deferred("disabled", true)
	for seg in _segments:
		(seg.body as AnimatableBody3D).collision_layer = 0
	nape.set_deferred("monitorable", false)
	animation_player.speed_scale = 1.0
	animation_player.play(&"titan/Death", 0.15)
	died.emit(self)
	await animation_player.animation_finished
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - 3.0, sink_duration)
	tween.tween_callback(queue_free)


func _flash_deflect() -> void:
	var material := flash_mesh.material_override as StandardMaterial3D
	if material == null:
		return
	var tween := create_tween()
	tween.tween_property(material, "emission_energy_multiplier", 1.5, 0.04)
	tween.tween_property(material, "emission_energy_multiplier", 0.0, 0.2)
