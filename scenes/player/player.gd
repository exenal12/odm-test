extends CharacterBody3D

@export var walk_speed: float = 3.5
@export var jog_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.0
@export var slide_speed: float = 10.0
@export var slide_loop_duration: float = 0.45
@export var slide_min_speed: float = 6.0
@export var jump_velocity: float = 4.5
@export var turn_speed: float = 12.0
@export var mouse_sensitivity: float = 0.08
@export var min_pitch: float = -60.0
@export var max_pitch: float = 45.0

@export_file("*.glb") var ual1_path: String = "res://assets/anims/UAL1_Standard.glb"
@export_file("*.glb") var ual2_path: String = "res://assets/anims/UAL2_Standard.glb"

## Clip names as imported by Godot (UAL suffixes like "_Loop" are often stripped).
@export var idle_animation: StringName = &"Idle"
@export var walk_animation: StringName = &"Walk"
@export var jog_animation: StringName = &"Jog_Fwd"
@export var sprint_animation: StringName = &"Sprint"
@export var crouch_idle_animation: StringName = &"Crouch_Idle"
@export var crouch_walk_animation: StringName = &"Crouch_Fwd"
@export var slide_start_animation: StringName = &"Slide_Start"
@export var slide_animation: StringName = &"Slide"
@export var slide_exit_animation: StringName = &"Slide_Exit"
@export var jump_start_animation: StringName = &"Jump_Start"
@export var jump_fall_animation: StringName = &"Jump"
@export var jump_land_animation: StringName = &"Jump_Land"
@export var walk_speed_threshold: float = 0.4
## Crossfade time when switching clips (AnimationPlayer blend).
@export var anim_blend_time: float = 0.18
## If moving at least this fast on landing, skip the full Jump_Land and blend into locomotion.
@export var moving_land_speed_threshold: float = 1.25
## If still holding move during a standing land, cancel Jump_Land after this many seconds.
@export var land_interrupt_time: float = 0.2

@onready var animation_player: AnimationPlayer = $Model/Armature/AnimationPlayer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

enum SlidePhase { NONE, START, LOOP, EXIT }
enum AirPhase { NONE, START, FALL, LAND }

var _camera: Camera3D
var _pcam: PhantomCamera3D
var _current_anim: StringName = &""
var _is_crouching: bool = false
var _is_sliding: bool = false
var _slide_phase: SlidePhase = SlidePhase.NONE
var _slide_loop_time_left: float = 0.0
var _slide_direction: Vector3 = Vector3.FORWARD
var _air_phase: AirPhase = AirPhase.NONE
var _was_on_floor: bool = true
var _land_timer: float = 0.0
var _standing_capsule_height: float = 1.8745117
var _standing_capsule_radius: float = 0.34814453
var _standing_shape_y: float = 0.93436825

const LIB_UAL1: StringName = &"ual1"
const LIB_UAL2: StringName = &"ual2"
const CROUCH_HEIGHT_SCALE: float = 0.6


func _ready() -> void:
	_ensure_input_actions()
	_resolve_camera_nodes()
	_cache_capsule_defaults()
	_setup_animations()
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if _pcam == null:
		return
	if _pcam.get_follow_mode() != PhantomCamera3D.FollowMode.THIRD_PERSON:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rotation_degrees := _pcam.get_third_person_rotation_degrees()
		rotation_degrees.x -= event.relative.y * mouse_sensitivity
		rotation_degrees.x = clampf(rotation_degrees.x, min_pitch, max_pitch)
		rotation_degrees.y -= event.relative.x * mouse_sensitivity
		rotation_degrees.y = wrapf(rotation_degrees.y, 0.0, 360.0)
		_pcam.set_third_person_rotation_degrees(rotation_degrees)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	_update_stance_state()

	if Input.is_action_just_pressed("jump") and is_on_floor() and not _is_sliding and _air_phase != AirPhase.LAND:
		_start_jump()

	if _is_sliding:
		_process_slide(delta)
	else:
		_process_move(delta)

	move_and_slide()
	_update_air_state()
	_update_animation()


func _start_jump() -> void:
	velocity.y = jump_velocity
	_is_crouching = false
	_apply_capsule_stance()
	_air_phase = AirPhase.START
	_was_on_floor = false
	if _has_clip(LIB_UAL1, jump_start_animation):
		_play_library_animation(LIB_UAL1, jump_start_animation)
	else:
		_begin_fall()


func _begin_fall() -> void:
	if _air_phase == AirPhase.LAND:
		return
	_air_phase = AirPhase.FALL
	_play_library_animation(LIB_UAL1, jump_fall_animation)


func _begin_land() -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var wants_move := Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO

	# Keep momentum: no dedicated "land into run" clip in UAL, so blend straight to locomotion.
	if horizontal_speed >= moving_land_speed_threshold or wants_move:
		_finish_land()
		return

	_air_phase = AirPhase.LAND
	_land_timer = 0.0
	if _has_clip(LIB_UAL1, jump_land_animation):
		_play_library_animation(LIB_UAL1, jump_land_animation)
	else:
		_finish_land()


func _finish_land() -> void:
	_air_phase = AirPhase.NONE
	_land_timer = 0.0
	_current_anim = &""


func _update_air_state() -> void:
	if _is_sliding:
		_was_on_floor = is_on_floor()
		return

	var on_floor := is_on_floor()

	# Walked off a ledge.
	if _was_on_floor and not on_floor and _air_phase == AirPhase.NONE:
		_begin_fall()

	# Rising jump start -> fall loop near apex / after takeoff clip.
	if _air_phase == AirPhase.START and not on_floor and velocity.y <= 0.0:
		_begin_fall()

	# Landed.
	if not _was_on_floor and on_floor and _air_phase != AirPhase.NONE and _air_phase != AirPhase.LAND:
		_begin_land()

	# Allow breaking out of a standing land early if the player keeps moving.
	if _air_phase == AirPhase.LAND:
		_land_timer += get_physics_process_delta_time()
		var wants_move := Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO
		if wants_move and _land_timer >= land_interrupt_time:
			_finish_land()

	_was_on_floor = on_floor


func _update_stance_state() -> void:
	var wants_crouch := Input.is_action_pressed("crouch")
	var is_sprinting := Input.is_action_pressed("sprint")
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	# Crouch while sprinting (or still moving fast) starts a slide.
	if (
		not _is_sliding
		and is_on_floor()
		and Input.is_action_just_pressed("crouch")
		and (is_sprinting or horizontal_speed >= slide_min_speed)
	):
		_start_slide()
		return

	if _is_sliding:
		return

	_is_crouching = wants_crouch and is_on_floor()
	_apply_capsule_stance()


func _start_slide() -> void:
	_is_sliding = true
	_is_crouching = true
	_slide_phase = SlidePhase.START
	_slide_loop_time_left = slide_loop_duration
	_apply_capsule_stance()

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() < 0.1:
		horizontal = -global_transform.basis.z
	_slide_direction = horizontal.normalized()
	velocity.x = _slide_direction.x * slide_speed
	velocity.z = _slide_direction.z * slide_speed

	if _has_clip(LIB_UAL2, slide_start_animation):
		_play_library_animation(LIB_UAL2, slide_start_animation)
	else:
		_begin_slide_loop()


func _begin_slide_loop() -> void:
	if not _is_sliding:
		return
	if _slide_phase != SlidePhase.START and _slide_phase != SlidePhase.NONE:
		return
	_slide_phase = SlidePhase.LOOP
	_slide_loop_time_left = slide_loop_duration
	_play_library_animation(LIB_UAL2, slide_animation)


func _begin_slide_exit() -> void:
	if not _is_sliding or _slide_phase == SlidePhase.EXIT or _slide_phase == SlidePhase.NONE:
		return
	_slide_phase = SlidePhase.EXIT
	if _has_clip(LIB_UAL2, slide_exit_animation):
		_play_library_animation(LIB_UAL2, slide_exit_animation)
	else:
		_finish_slide()


func _finish_slide() -> void:
	_is_sliding = false
	_slide_phase = SlidePhase.NONE
	_is_crouching = Input.is_action_pressed("crouch")
	_apply_capsule_stance()
	_current_anim = &""


func _process_slide(delta: float) -> void:
	var speed_scale := 1.0 if _slide_phase != SlidePhase.EXIT else 0.55
	velocity.x = _slide_direction.x * slide_speed * speed_scale
	velocity.z = _slide_direction.z * slide_speed * speed_scale

	var target_yaw := atan2(_slide_direction.x, _slide_direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)

	if not is_on_floor() and _slide_phase != SlidePhase.EXIT:
		_begin_slide_exit()
		return

	if _slide_phase == SlidePhase.LOOP:
		_slide_loop_time_left -= delta
		if _slide_loop_time_left <= 0.0:
			_begin_slide_exit()


func _on_animation_finished(anim_name: StringName) -> void:
	var jump_start_name := StringName("%s/%s" % [LIB_UAL1, jump_start_animation])
	var jump_land_name := StringName("%s/%s" % [LIB_UAL1, jump_land_animation])
	var slide_start_name := StringName("%s/%s" % [LIB_UAL2, slide_start_animation])
	var slide_exit_name := StringName("%s/%s" % [LIB_UAL2, slide_exit_animation])

	if anim_name == jump_start_name and _air_phase == AirPhase.START:
		if is_on_floor():
			_begin_land()
		else:
			_begin_fall()
		return

	if anim_name == jump_land_name and _air_phase == AirPhase.LAND:
		_finish_land()
		return

	if not _is_sliding:
		return

	if anim_name == slide_start_name and _slide_phase == SlidePhase.START:
		_begin_slide_loop()
	elif anim_name == slide_exit_name and _slide_phase == SlidePhase.EXIT:
		_finish_slide()


func _process_move(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_dir := _camera_relative_direction(input_dir)
	var current_speed := _get_move_speed()

	if move_dir.length() > 0.0:
		velocity.x = move_dir.x * current_speed
		velocity.z = move_dir.z * current_speed
		var target_yaw := atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)


func _get_move_speed() -> float:
	if _is_crouching:
		return crouch_speed
	if Input.is_action_pressed("sprint") and Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO:
		return sprint_speed
	# Light stick / no sprint uses jog as the default run speed.
	if Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO:
		return jog_speed
	return walk_speed


func _cache_capsule_defaults() -> void:
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		_standing_capsule_height = capsule.height
		_standing_capsule_radius = capsule.radius
		_standing_shape_y = collision_shape.position.y


func _apply_capsule_stance() -> void:
	if collision_shape == null or not (collision_shape.shape is CapsuleShape3D):
		return

	var capsule := collision_shape.shape as CapsuleShape3D
	if _is_crouching or _is_sliding:
		capsule.height = _standing_capsule_height * CROUCH_HEIGHT_SCALE
		collision_shape.position.y = capsule.height * 0.5
	else:
		capsule.height = _standing_capsule_height
		capsule.radius = _standing_capsule_radius
		collision_shape.position.y = _standing_shape_y


func _camera_relative_direction(input_dir: Vector2) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO

	var basis: Basis
	if _camera:
		basis = _camera.global_transform.basis
	elif _pcam:
		basis = _pcam.global_transform.basis
	else:
		basis = global_transform.basis

	var forward := -basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	return (forward * -input_dir.y + right * input_dir.x).normalized()


func _resolve_camera_nodes() -> void:
	_pcam = get_tree().get_first_node_in_group("player_pcam") as PhantomCamera3D
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		_camera = get_tree().get_first_node_in_group("player_camera") as Camera3D


func _setup_animations() -> void:
	if animation_player == null:
		push_warning("Player AnimationPlayer missing")
		return

	_load_animation_library(ual1_path, LIB_UAL1)
	_load_animation_library(ual2_path, LIB_UAL2)

	for clip in [
		idle_animation,
		walk_animation,
		jog_animation,
		sprint_animation,
		crouch_idle_animation,
		crouch_walk_animation,
		jump_fall_animation,
	]:
		_force_loop(LIB_UAL1, clip)
	_force_oneshot(LIB_UAL1, jump_start_animation)
	_force_oneshot(LIB_UAL1, jump_land_animation)
	_force_loop(LIB_UAL2, slide_animation)
	_force_oneshot(LIB_UAL2, slide_start_animation)
	_force_oneshot(LIB_UAL2, slide_exit_animation)

	_play_library_animation(LIB_UAL1, idle_animation)


func _load_animation_library(path: String, library_name: StringName) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Could not load animation library: %s" % path)
		return

	var temp := packed.instantiate()
	var source_player := temp.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player == null:
		temp.queue_free()
		push_warning("No AnimationPlayer in %s" % path)
		return

	var source_libs := source_player.get_animation_library_list()
	if source_libs.is_empty():
		temp.queue_free()
		push_warning("No animation libraries in %s" % path)
		return

	var copied := source_player.get_animation_library(source_libs[0]).duplicate(true) as AnimationLibrary
	if animation_player.has_animation_library(library_name):
		animation_player.remove_animation_library(library_name)
	animation_player.add_animation_library(library_name, copied)
	temp.queue_free()


func _force_loop(library_name: StringName, clip_name: StringName) -> void:
	if not animation_player.has_animation_library(library_name):
		return
	var lib := animation_player.get_animation_library(library_name)
	if lib.has_animation(clip_name):
		lib.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR


func _force_oneshot(library_name: StringName, clip_name: StringName) -> void:
	if not animation_player.has_animation_library(library_name):
		return
	var lib := animation_player.get_animation_library(library_name)
	if lib.has_animation(clip_name):
		lib.get_animation(clip_name).loop_mode = Animation.LOOP_NONE


func _update_animation() -> void:
	if animation_player == null:
		return

	# Slide / air clips are driven by their own state machines.
	if _is_sliding or _air_phase != AirPhase.NONE:
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	if _is_crouching:
		if horizontal_speed > walk_speed_threshold:
			_play_library_animation(LIB_UAL1, crouch_walk_animation)
		else:
			_play_library_animation(LIB_UAL1, crouch_idle_animation)
		return

	if horizontal_speed <= walk_speed_threshold:
		_play_library_animation(LIB_UAL1, idle_animation)
	elif Input.is_action_pressed("sprint"):
		_play_library_animation(LIB_UAL1, sprint_animation)
	elif horizontal_speed > jog_speed * 0.85:
		_play_library_animation(LIB_UAL1, jog_animation)
	else:
		_play_library_animation(LIB_UAL1, walk_animation)


func _has_clip(library_name: StringName, clip_name: StringName) -> bool:
	var full_name := StringName("%s/%s" % [library_name, clip_name])
	return animation_player != null and animation_player.has_animation(full_name)


func _play_library_animation(library_name: StringName, clip_name: StringName) -> void:
	var full_name := StringName("%s/%s" % [library_name, clip_name])
	if full_name == _current_anim:
		return

	if not animation_player.has_animation(full_name):
		for lib_name in animation_player.get_animation_library_list():
			var candidate := StringName("%s/%s" % [lib_name, clip_name])
			if animation_player.has_animation(candidate):
				full_name = candidate
				break
		if not animation_player.has_animation(full_name):
			return

	animation_player.play(full_name, anim_blend_time)
	_current_anim = full_name


func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("sprint", KEY_SHIFT)
	_add_key_action("crouch", KEY_CTRL)


func _add_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == keycode:
			return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)
