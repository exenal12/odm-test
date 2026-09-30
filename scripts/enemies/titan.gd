class_name Titan
extends CharacterBody3D
## Titan enemy: state-machine AI with distance-scaled sight and hearing.
## Only hits on the nape kill it; body hits are ignored.

signal died(titan: Titan)
signal hit_player(player: CharacterBody3D, damage: float)

enum State { WANDER, INVESTIGATE, ALERT, CHASE, ATTACK, GRAB, DEAD }

const GrabArm := preload("res://scripts/enemies/titan_grab_arm.gd")
const OpenHands := preload("res://scripts/enemies/titan_open_hands.gd")
const NAPE_BONE := "B-neck"
## Nape offset from the neck bone in skeleton space (unscaled model units, -Z is the back).
const NAPE_OFFSET := Vector3(0.0, 0.05, -0.13)
## Center of the red paint on the neck, in skeleton space (unscaled model units).
const NAPE_PAINT_OFFSET := Vector3(0.0, 0.045, -0.05)
const SKIN_SHADER := preload("res://scenes/enemies/titan_skin.gdshader")
## Hook and hit capsules: [from bone, to bone or skeleton-space offset, radius in model units].
const SEGMENTS := [
	["B-hips", "B-chest", 0.2], ["B-chest", "B-neck", 0.19],
	# TitanFeatures scales the head by 1.25, so its capsule is sized to match.
	["B-neck", "B-head", 0.08], ["B-head", Vector3(0.0, 0.25, 0.0), 0.15],
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

@export_group("Targeting")
## A soldier this close is noticed regardless of facing or line of sight.
@export var soldier_notice_range: float = 12.0
## A rival target only steals focus when closer than current distance times this.
@export_range(0.1, 1.0) var retarget_bias: float = 0.6
## The nape only counts when the attacker is within this angle of the titan's back.
@export_range(10.0, 180.0) var nape_rear_angle_deg: float = 100.0

@export_group("Attack")
@export var attack_range: float = 9.0
@export var attack_damage: float = 25.0
@export var attack_speed: float = 0.8
@export var attack_cooldown: float = 2.0
## Swat and grab clips peak at about 25% of their length.
@export_range(0.0, 1.0) var hit_start_fraction: float = 0.2
@export_range(0.0, 1.0) var hit_end_fraction: float = 0.42
## A hand hits if the player is within this horizontal radius and vertical reach of it.
@export var hit_radius: float = 5.5
@export var hit_vertical_reach: float = 10.0
## How open the hands are during a swat; the source clips grip a sword (0 = clip, 1 = relaxed).
@export_range(0.0, 1.0) var swat_open_hand: float = 1.0
@export var knockback: float = 30.0
@export var knockback_up: float = 12.0

@export_group("Grab")
## Chance that an attack is a grab instead of a swipe.
@export_range(0.0, 1.0) var grab_chance: float = 0.35
## Crush damage dealt every grab_tick seconds while holding the player.
@export var grab_damage: float = 8.0
@export var grab_tick: float = 0.5
## Damage the gripping arm must take before the titan lets go.
@export var hand_health_max: float = 80.0
@export var grab_cooldown: float = 6.0
## Grab zone, measured from the titan's feet. It may reach past the arm; the lift covers the gap.
@export var grab_range: float = 10.0
## Highest the player's centre can be above the titan's feet (shoulder is about 10).
@export var grab_max_height: float = 7.5
@export var grab_half_angle_deg: float = 55.0
## How strongly the swinging arm is bent toward the player during the wind-up (0..1).
@export_range(0.0, 1.0) var grab_reach_assist: float = 0.85
## Seconds to lift the player from the catch point to the hold point.
@export var grab_lift_time: float = 0.5
## Nudges the hold point, in arm-reach units: x = toward the gripping side, y = up, z = forward.
@export var grab_hold_offset: Vector3 = Vector3.ZERO
## Nudges the player within the palm, in metres along the palm's own axes.
@export var grab_player_offset: Vector3 = Vector3.ZERO
## Extra rotation (degrees) applied on top of the palm orientation.
@export var grab_rotation_offset_deg: Vector3 = Vector3.ZERO
## Speed the player is thrown away at when freed.
@export var release_speed: float = 12.0

@export_group("Debug")
@export var show_debug: bool = true

@export_group("Death")
## Playback speed of the collapse; below 1 so the fall reads at titan scale.
@export_range(0.1, 1.0, 0.01) var death_speed: float = 0.38
## Seconds the body lies still before sinking.
@export var corpse_time: float = 3.0
@export var sink_duration: float = 4.0

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
## Current focus: the player or a soldier.
var target: CharacterBody3D
var last_known: Vector3

var _neck_bone: int = -1
var _skin_material: ShaderMaterial
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
var _pending_grab: bool = false
var _attack_hand: int = 0
var _grab_cooldown_left: float = 0.0
var _grab_tick_left: float = 0.0
var _step_player: AudioStreamPlayer3D
var _step_streams: Array[AudioStream] = []
var _last_step_index: int = -1
var _hand_health: float = 0.0
var _grab_bone: int = -1
var _grab_arm: GrabArm
var _grab_shoulder: int = -1
var _grab_time: float = 0.0
var _grab_start: Vector3
var _grab_start_basis: Basis
var _grab_weight_start: float = 0.0
var _arm_tween: Tween
var _open_hands: OpenHands
var _hands_tween: Tween
var _grab_side: float = 1.0
var _arm_reach: float = 1.0
var _squeeze: float = 0.0
var _last_hit_damage: float = 20.0

func _ready() -> void:
	_setup_step_audio()
	_skin_material = ShaderMaterial.new()
	_skin_material.shader = SKIN_SHADER
	flash_mesh.material_override = _skin_material
	skeleton.add_child(TitanFeatures.new())
	_neck_bone = skeleton.find_bone(NAPE_BONE)
	_exclude.append(get_rid())
	for def in SEGMENTS:
		_add_segment(def[0], def[1], def[2])
	_hand_bones = [skeleton.find_bone("B-hand.L"), skeleton.find_bone("B-hand.R")]
	_open_hands = OpenHands.new()
	skeleton.add_child(_open_hands)
	_open_hands.setup(animation_player.get_animation(&"titan/Idle"))
	_grab_arm = GrabArm.new()
	skeleton.add_child(_grab_arm)
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
	var neck_pose := skeleton.get_bone_global_pose(_neck_bone)
	var neck := neck_pose.origin
	nape.global_position = skeleton.global_transform * (neck + NAPE_OFFSET)
	var up := (skeleton.global_basis * neck_pose.basis.y).normalized()
	var back := -global_basis.z
	back = (back - up * back.dot(up)).normalized()
	_skin_material.set_shader_parameter(&"nape_position", skeleton.global_transform * (neck + NAPE_PAINT_OFFSET))
	_skin_material.set_shader_parameter(&"nape_up", up)
	_skin_material.set_shader_parameter(&"nape_back", back)


func _physics_process(delta: float) -> void:
	_update_segments()
	# The body collider is off once dead, so moving would drop it through the floor.
	if state == State.DEAD:
		return
	_acquire_player()
	_select_target()
	if not _check_nav_ready():
		_stop(delta)
		_play_locomotion()
		_finish_move(delta)
		return
	if target == null:
		if state != State.WANDER and state != State.GRAB:
			awareness = 0.0
			_home = global_position
			_set_state(State.WANDER)
		if state == State.WANDER:
			_state_wander(delta)
		_play_locomotion()
		_finish_move(delta)
		return
	_sense(delta)
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_grab_cooldown_left = maxf(0.0, _grab_cooldown_left - delta)
	match state:
		State.WANDER: _state_wander(delta)
		State.INVESTIGATE: _state_investigate(delta)
		State.ALERT: _state_alert(delta)
		State.CHASE: _state_chase(delta)
		State.ATTACK: _state_attack(delta)
		State.GRAB: _state_grab(delta)
	if state != State.ATTACK and state != State.GRAB and state != State.DEAD:
		_play_locomotion()
	_finish_move(delta)


# --- Perception ---

func _acquire_player() -> void:
	if player != null and is_instance_valid(player):
		return
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player != null:
		add_collision_exception_with(player)


func _valid_target(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return node.get(&"alive") != false


## Picks the player or nearest soldier; the current target is favoured by retarget_bias.
func _select_target() -> void:
	if state == State.GRAB and _valid_target(target):
		return
	var candidates: Array[CharacterBody3D] = []
	if _valid_target(player):
		candidates.append(player)
	for node in get_tree().get_nodes_in_group("soldier"):
		if node is CharacterBody3D and _valid_target(node):
			candidates.append(node)
	var best: CharacterBody3D
	var best_score := INF
	for candidate in candidates:
		var score := global_position.distance_to(candidate.global_position)
		if candidate != target:
			score /= retarget_bias
		if score < best_score:
			best_score = score
			best = candidate
	target = best


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
	var to_player := target.global_position - global_position
	var dist := to_player.length()
	var gain := 0.0
	var sensed := false
	if dist <= sight_range and (dist <= close_range or _in_view(to_player)) \
			and _line_of_sight(target.global_position + Vector3.UP):
		gain += sight_gain * pow(1.0 - dist / sight_range, distance_falloff)
		sensed = true
	var heard_range := hearing_range * _target_noise()
	if dist < heard_range:
		gain += hearing_gain * pow(1.0 - dist / heard_range, distance_falloff)
		sensed = true
	if target != player and dist <= soldier_notice_range:
		gain += sight_gain
		sensed = true
	if sensed:
		last_known = target.global_position
		awareness = minf(1.0, awareness + gain * delta)
	else:
		awareness = maxf(0.0, awareness - awareness_decay * delta)


func _in_view(to_player: Vector3) -> bool:
	var flat := Vector3(to_player.x, 0.0, to_player.z).normalized()
	var forward := Vector3(global_basis.z.x, 0.0, global_basis.z.z).normalized()
	return forward.dot(flat) >= cos(deg_to_rad(sight_half_angle_deg))


func _line_of_sight(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(_eye_position(), point)
	query.collision_mask = 1
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target


func _target_noise() -> float:
	var noise := 0.1 + 0.9 * clampf(target.velocity.length() / 30.0, 0.0, 1.0)
	var odm := target.get_node_or_null("ODMController")
	if odm != null and odm.has_method("is_hooked") and odm.is_hooked():
		noise = maxf(noise, 0.8)
	return noise


# --- States ---

func _set_state(new_state: State) -> void:
	if new_state != State.GRAB and _grab_arm.weight > 0.0:
		_fade_grab_arm()
	if (new_state == State.ATTACK) != (state == State.ATTACK):
		_blend_open_hands(swat_open_hand if new_state == State.ATTACK else 0.0)
	state = new_state
	_state_timer = 0.0
	if new_state == State.ATTACK:
		_attack_time = 0.0
		_attack_landed = false
		_pending_grab = target == player and _grab_cooldown_left <= 0.0 \
				and player.get(&"grabbed") != true and _in_grab_zone() and randf() < grab_chance
		_attack_hand = _nearest_hand()
		if _pending_grab:
			_prepare_grab_arm()
		var clip := &"titan/SwatL" if _attack_hand == 0 else &"titan/SwatR"
		_attack_length = animation_player.get_animation(clip).length
		animation_player.play(clip, 0.3)
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
	var to_player := target.global_position - global_position
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
		_turn_toward(_flat_dir(target.global_position - global_position), delta * 0.5)
	_attack_time += delta * attack_speed
	fraction = _attack_time / _attack_length
	if _pending_grab and not _attack_landed:
		_reach_toward_target(fraction)
	if not _attack_landed and fraction >= hit_start_fraction and fraction <= hit_end_fraction:
		_try_land_hit()
		if state != State.ATTACK:
			return
	if _attack_time >= _attack_length:
		_cooldown_left = attack_cooldown
		_set_state(State.CHASE)


func _try_land_hit() -> void:
	if _pending_grab:
		if _in_grab_zone():
			_attack_landed = true
			_begin_grab(_hand_bones[_attack_hand])
		return
	var bone := _hand_in_reach()
	if bone < 0:
		return
	_attack_landed = true
	var away := _flat_dir(target.global_position - global_position)
	target.velocity += away * knockback + Vector3.UP * knockback_up
	if target.has_method(&"take_damage"):
		target.take_damage(attack_damage, self)
	if target == player:
		hit_player.emit(player, attack_damage)


## Index into _hand_bones (0 = left, 1 = right) of the hand closest to the target.
func _nearest_hand() -> int:
	var xform := skeleton.global_transform
	var best := 0
	var best_dist := INF
	for i in _hand_bones.size():
		var hand := xform * skeleton.get_bone_global_pose(_hand_bones[i]).origin
		var dist := hand.distance_squared_to(target.global_position)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


## Returns the swinging hand's bone if it is within reach of the target, or -1.
func _hand_in_reach() -> int:
	var bone: int = _hand_bones[_attack_hand]
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	var offset := hand - (target.global_position + Vector3.UP * 0.9)
	if Vector2(offset.x, offset.z).length() <= hit_radius and absf(offset.y) <= hit_vertical_reach:
		return bone
	return -1


# --- Grab ---

## True if the target is in front of the titan, within grab_range and below grab_max_height.
func _in_grab_zone() -> bool:
	var to_target := target.global_position - global_position
	var height := to_target.y + 0.9
	if height > grab_max_height or height < -2.0:
		return false
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	if flat.length() > grab_range:
		return false
	return flat.length() < 1.0 or _flat_dir(global_basis.z).dot(flat.normalized()) >= cos(deg_to_rad(grab_half_angle_deg))


## Binds the IK arm to the swinging hand before the wind-up so it can steer the reach.
func _prepare_grab_arm() -> void:
	if _arm_tween != null:
		_arm_tween.kill()
	var side := ".L" if _attack_hand == 0 else ".R"
	# basis.x is the titan's left, since it faces +Z.
	_grab_side = 1.0 if _attack_hand == 0 else -1.0
	_grab_arm.setup("B-upperArm" + side, "B-forearm" + side, "B-hand" + side, side)
	_grab_shoulder = skeleton.find_bone("B-upperArm" + side)
	var scale_factor := skeleton.global_transform.basis.get_scale().x
	var shoulder_pos := skeleton.get_bone_global_pose(_grab_shoulder).origin
	var elbow_pos := skeleton.get_bone_global_pose(skeleton.find_bone("B-forearm" + side)).origin
	var hand_pos := skeleton.get_bone_global_pose(_hand_bones[_attack_hand]).origin
	_arm_reach = (shoulder_pos.distance_to(elbow_pos) + elbow_pos.distance_to(hand_pos)) * scale_factor
	_grab_arm.grip = 0.0
	_grab_arm.squeeze = 0.0


## Bends the swinging arm toward the target during the wind-up, open-handed.
func _reach_toward_target(fraction: float) -> void:
	var ramp := smoothstep(0.0, 1.0, fraction / maxf(hit_start_fraction, 0.01))
	_grab_arm.target_world = target.global_position + Vector3.UP * 0.9
	_grab_arm.pole_world = global_basis.x.normalized() * _grab_side + Vector3.DOWN * 0.6
	_grab_arm.grip = 0.0
	_grab_arm.weight = grab_reach_assist * ramp


func _blend_open_hands(amount: float) -> void:
	if _hands_tween != null:
		_hands_tween.kill()
	_hands_tween = create_tween()
	_hands_tween.tween_property(_open_hands, "amount", amount, 0.2 if amount > 0.0 else 0.35)


func _fade_grab_arm() -> void:
	if _arm_tween != null:
		_arm_tween.kill()
	_arm_tween = create_tween()
	_arm_tween.tween_property(_grab_arm, "weight", 0.0, 0.25)


func _begin_grab(bone: int) -> void:
	_grab_bone = bone
	_hand_health = hand_health_max
	_grab_tick_left = grab_tick
	_grab_time = 0.0
	_squeeze = 0.0
	_grab_start = player.global_position
	_grab_start_basis = player.global_basis.orthonormalized()
	_grab_weight_start = _grab_arm.weight
	_set_state(State.GRAB)
	# Idle keeps the body alive; the IK arm is layered on top of it.
	animation_player.speed_scale = 1.0
	animation_player.play(&"titan/Idle", 0.4)
	var sword := player.get_node_or_null("SwordCombat")
	if sword != null:
		_last_hit_damage = maxf(1.0, sword.damage)
	player.on_grabbed(self)
	_hold_player(0.0)
	_report_grab_progress()


func _report_grab_progress() -> void:
	var hits_left := int(ceil(maxf(_hand_health, 0.0) / _last_hit_damage))
	player.set_grab_progress(1.0 - clampf(_hand_health / hand_health_max, 0.0, 1.0), hits_left)


func _state_grab(delta: float) -> void:
	_stop(delta)
	if player == null or not is_instance_valid(player) or player.get(&"grabbed") != true:
		_end_grab(false)
		return
	_grab_time += delta
	_squeeze = move_toward(_squeeze, 0.0, delta * 3.0)
	_hold_player(clampf(_grab_time / grab_lift_time, 0.0, 1.0))
	_grab_tick_left -= delta
	if _grab_tick_left <= 0.0:
		_grab_tick_left += grab_tick
		_squeeze = 1.0
		player.take_damage(grab_damage, self, true)
		hit_player.emit(player, grab_damage)


## Lifts the player from where they were caught to a point held out in front of the
## shoulder, tightening the fist on each crush tick.
func _hold_player(lift: float) -> void:
	var eased := smoothstep(0.0, 1.0, lift)
	var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(_grab_shoulder).origin
	var chest := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("B-chest")).origin
	var forward := _flat_dir(global_basis.z)
	# Centred in front of the body at shoulder height, slightly toward the gripping arm.
	var hold := Vector3(chest.x, shoulder.y, chest.z) \
			+ forward * _arm_reach * (0.85 - 0.05 * _squeeze) \
			+ global_basis.x.normalized() * _grab_side * _arm_reach * 0.05 \
			+ Vector3.DOWN * _arm_reach * 0.05 \
			+ (global_basis.x.normalized() * grab_hold_offset.x + Vector3.UP * grab_hold_offset.y \
			+ forward * grab_hold_offset.z) * _arm_reach
	var catch_center := _grab_start + Vector3.UP * 0.9
	# The arm aims at the fixed hold point, never at the player, so there is no feedback loop.
	_grab_arm.target_world = catch_center.lerp(hold, eased)
	_grab_arm.squeeze = _squeeze
	_grab_arm.grip = eased
	# Continues from the reach-assist weight so the arm doesn't pop back to the clip.
	_grab_arm.weight = lerpf(_grab_weight_start, 1.0, eased)
	var palm_basis := _grab_arm.palm_basis * Basis.from_euler(grab_rotation_offset_deg * (PI / 180.0))
	var wanted := _grab_start.lerp(hold - Vector3.UP * 0.9, eased)
	if _grab_time > 0.0:
		var in_palm := _grab_arm.palm_world + palm_basis * grab_player_offset - Vector3.UP * 0.9
		wanted = wanted.lerp(in_palm, eased)
	player.global_position = wanted
	# Match the palm's orientation, blending from the catch pose.
	player.global_basis = _grab_start_basis.slerp(palm_basis.orthonormalized(), eased)
	_grab_arm.pole_world = global_basis.x.normalized() * _grab_side + Vector3.DOWN * 0.6


## Frees the player (if still held) and returns to chasing.
func _end_grab(throw_player: bool) -> void:
	if player != null and is_instance_valid(player) and player.get(&"grabbed") == true:
		var impulse := Vector3.ZERO
		if throw_player:
			impulse = _flat_dir(player.global_position - global_position) * release_speed \
					+ Vector3.UP * release_speed * 0.5
		player.on_released(impulse)
	_grab_cooldown_left = grab_cooldown
	_cooldown_left = attack_cooldown
	if state == State.GRAB:
		_set_state(State.CHASE)


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


## Creates the positional player and loads titan footstep variants.
func _setup_step_audio() -> void:
	_step_player = AudioStreamPlayer3D.new()
	_step_player.bus = &"SFX"
	_step_player.max_distance = 160.0
	_step_player.unit_size = 25.0
	add_child(_step_player)
	for i in 3:
		var path := "res://assets/audio/sfx/footstep_titan_%03d.wav" % i
		if ResourceLoader.exists(path):
			_step_streams.append(load(path))


## Plays a footstep twice per walk cycle (assumes contacts at 0% and 50%).
func _update_step_audio() -> void:
	if _step_streams.is_empty() or animation_player.current_animation != "titan/Walk":
		_last_step_index = -1
		return
	var length := animation_player.current_animation_length
	if length <= 0.0:
		return
	var index := int(animation_player.current_animation_position / length * 2.0)
	if _last_step_index != -1 and index != _last_step_index:
		_step_player.stream = _step_streams[randi() % _step_streams.size()]
		_step_player.pitch_scale = randf_range(0.9, 1.1)
		_step_player.play()
	_last_step_index = index


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
		_update_step_audio()


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
func on_sword_hit(target: Node3D, _damage: float, attacker_pos: Vector3 = Vector3.INF) -> void:
	if state == State.DEAD:
		return
	if target == nape and _attacker_behind(attacker_pos):
		_die()
	else:
		_flash_deflect()


## True when the attacker stands within nape_rear_angle_deg of the titan's back.
func _attacker_behind(attacker_pos: Vector3) -> bool:
	if not attacker_pos.is_finite():
		return true
	var to_attacker := _flat_dir(attacker_pos - global_position)
	var back := _flat_dir(-global_basis.z)
	if to_attacker == Vector3.ZERO:
		return true
	return back.dot(to_attacker) >= cos(deg_to_rad(nape_rear_angle_deg))


## Called by the held player's sword swings; always damages the gripping hand.
func on_grab_struck(damage: float) -> void:
	if state != State.GRAB:
		return
	_hand_health -= damage
	_last_hit_damage = maxf(1.0, damage)
	_report_grab_progress()
	_flash_deflect()
	if _hand_health <= 0.0:
		_end_grab(true)


func _die() -> void:
	if state == State.GRAB:
		_end_grab(false)
	if _grab_arm.weight > 0.0:
		_fade_grab_arm()
	if _open_hands.amount > 0.0:
		_blend_open_hands(0.0)
	alive = false
	state = State.DEAD
	body_collider.set_deferred("disabled", true)
	for seg in _segments:
		(seg.body as AnimatableBody3D).collision_layer = 0
	nape.set_deferred("monitorable", false)
	animation_player.speed_scale = death_speed
	animation_player.play(&"titan/Death", 0.5)
	died.emit(self)
	create_tween().tween_method(func(v: float) -> void: _skin_material.set_shader_parameter(&"nape_strength", v), 1.0, 0.0, 1.5)
	# Clip times where the knees, then the body, hit the ground.
	_thud_after(0.12 / death_speed, 0.75)
	_thud_after(0.4 / death_speed, 0.6)
	await animation_player.animation_finished
	await get_tree().create_timer(corpse_time).timeout
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - 4.0, sink_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(queue_free)


func _thud_after(delay: float, pitch: float) -> void:
	await get_tree().create_timer(delay).timeout
	if _step_streams.is_empty() or not is_inside_tree():
		return
	_step_player.stream = _step_streams[randi() % _step_streams.size()]
	_step_player.pitch_scale = pitch
	_step_player.play()


func _flash_deflect() -> void:
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: _skin_material.set_shader_parameter(&"flash", v), 0.35, 0.0, 0.25)
