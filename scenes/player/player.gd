extends CharacterBody3D

## Maximum speed used for ordinary walking with no directional sprint input.
@export var walk_speed: float = 2.0
## Default ground speed used while moving without sprinting.
@export var jog_speed: float = 2.0
## Maximum ground speed while sprint is held.
@export var sprint_speed: float = 4.0
## Ground speed used while crouching.
@export var crouch_speed: float = 2.0
## Initial horizontal speed assigned when a slide starts.
@export var slide_speed: float = 10.0
## Duration of the looping slide phase before the exit animation begins.
@export var slide_loop_duration: float = 0.45
## Minimum horizontal speed required for a crouch press to start a slide.
@export var slide_min_speed: float = 3.5
## Initial upward velocity applied when a jump begins.
@export var jump_velocity: float = 4.5
@export_category("Physics Tuning")
## Multiplies the project gravity applied while airborne.
@export_range(0.0, 3.0, 0.05, "or_greater") var gravity_scale: float = 1.0
## Caps downward velocity so falls do not become uncontrollably fast.
@export_range(0.1, 100.0, 0.5, "or_greater") var terminal_fall_speed: float = 30.0
## Ground acceleration and braking control how quickly horizontal speed changes.
@export_range(0.0, 100.0, 0.5, "or_greater") var ground_acceleration: float = 28.0
## Rate used to slow horizontal movement on the ground.
@export_range(0.0, 100.0, 0.5, "or_greater") var ground_deceleration: float = 35.0
## Air acceleration and braking control steering after a jump.
@export_range(0.0, 100.0, 0.5, "or_greater") var air_acceleration: float = 10.0
## Light horizontal drag applied while airborne without movement input.
@export_range(0.0, 100.0, 0.1, "or_greater") var air_deceleration: float = 0.6
## Releasing jump while rising multiplies vertical velocity by this value.
@export_range(0.0, 1.0, 0.05) var jump_release_multiplier: float = 0.45
## Interpolation speed used when rotating toward movement direction.
@export var turn_speed: float = 12.0
## Mouse look sensitivity applied to third-person camera rotation.
@export var mouse_sensitivity: float = 0.08
## Minimum pitch for shoulder cameras.
@export var min_pitch: float = -60.0
## Maximum pitch for shoulder cameras.
@export var max_pitch: float = 45.0
## Minimum pitch for the overhead camera.
@export var overhead_min_pitch: float = -85.0
## Maximum pitch for the overhead camera.
@export var overhead_max_pitch: float = 10.0
## Priority assigned to whichever PhantomCamera is currently active.
@export var active_pcam_priority: int = 10
## Cycle order: right shoulder → left shoulder → overhead.
@export var camera_cycle_names: PackedStringArray = PackedStringArray([
	"RightShoulderCam",
	"LeftShoulderCam",
	"OverheadCam",
])

## Clip names baked onto the native HumanF rig in the glTF scene.
## Idle clip used when the player has no horizontal movement.
@export var idle_animation: StringName = &"Idle"
## Walking clip used at the lowest non-zero ground speed.
@export var walk_animation: StringName = &"Walk"
## Jogging clip used for regular movement.
@export var jog_animation: StringName = &"RunForward"
## Sprinting clip used while sprint input is held.
@export var sprint_animation: StringName = &"RunForward"
## Crouched idle clip used while crouching without movement.
@export var crouch_idle_animation: StringName = &"Crouch_Idle"
## Crouched movement clip used while moving in a crouch.
@export var crouch_walk_animation: StringName = &"Crouch_Fwd"
## One-shot clip played when a slide begins.
@export var slide_start_animation: StringName = &"Slide_Start"
## Looping clip used during the slide phase.
@export var slide_animation: StringName = &"Slide"
## One-shot clip played when a slide ends.
@export var slide_exit_animation: StringName = &"Slide_Exit"
## One-shot clip played at jump takeoff.
@export var jump_start_animation: StringName = &"Jump_Start"
## Looping clip used while falling.
@export var jump_fall_animation: StringName = &"Jump"
## One-shot clip played during a standing landing.
@export var jump_land_animation: StringName = &"Jump_Land"
## Horizontal speed threshold below which idle is selected.
@export var walk_speed_threshold: float = 0.4
## Crossfade time when switching clips (AnimationPlayer blend).
@export var anim_blend_time: float = 0.18
## If moving at least this fast on landing, skip the full Jump_Land and blend into locomotion.
@export var moving_land_speed_threshold: float = 1.25
## If still holding move during a standing land, cancel Jump_Land after this many seconds.
@export var land_interrupt_time: float = 0.2

@onready var animation_player: AnimationPlayer = $Model/AnimationPlayer
@onready var player_animation: PlayerAnimation = $PlayerAnimation
@onready var sword_combat: SwordCombat = $SwordCombat
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var odm: ODMController = $ODMController
@onready var odm_gear: Node3D = $ODMGear
@onready var player_audio: Node = $PlayerAudio
@onready var health: PlayerHealth = $PlayerHealth

## Emitted while held by a titan; progress is 0..1 toward escape.
signal grab_progress(active: bool, progress: float, hits_left: int)

enum SlidePhase { NONE, START, LOOP, EXIT }
enum AirPhase { NONE, START, FALL, LAND }

var _camera: Camera3D
var _pcam: PhantomCamera3D
var _pcams: Array[PhantomCamera3D] = []
var _pcam_local_offsets: Array[Vector3] = []
var _pcam_index: int = 0
var _current_anim: StringName = &""
var _is_crouching: bool = false
var _is_sliding: bool = false
var _slide_phase: SlidePhase = SlidePhase.NONE
var _slide_loop_time_left: float = 0.0
var _slide_phase_time: float = 0.0
var _slide_direction: Vector3 = Vector3.FORWARD
var _air_phase: AirPhase = AirPhase.NONE
var _was_on_floor: bool = true
var _land_timer: float = 0.0
var _standing_capsule_height: float = 1.8745117
var _standing_capsule_radius: float = 0.34814453
var _standing_shape_y: float = 0.93436825
var _hud: Node
var _dead: bool = false
## True while a titan is holding the player.
var grabbed: bool = false
var _grabber: Node3D

const LIB_HUMANF: StringName = &"humanf"
const CROUCH_HEIGHT_SCALE: float = 0.6


## Initializes player state, input bindings, animation libraries, ODM wiring,
## and the deferred camera lookup used by the third-person controller.
func _ready() -> void:
	add_to_group("player")
	_ensure_input_actions()
	_cache_capsule_defaults()
	_setup_animations()
	_setup_odm()
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Camera / pcam are later siblings in world.tscn; resolve after the tree is ready.
	call_deferred("_resolve_camera_nodes")


## Connects the player to the ODM controller and binds player audio and HUD
## dependencies that may not be ready until the scene tree has finished setup.
func _setup_odm() -> void:
	if odm == null:
		return
	odm.ensure_input_actions()
	odm.setup(self, _camera, odm_gear)
	if player_audio and player_audio.has_method("bind_odm"):
		player_audio.bind_odm(odm)
	call_deferred("_bind_hud")


## Finds the HUD instance and gives it the ODM controller so it can display
## gas and hook state.
func _bind_hud() -> void:
	_hud = get_tree().get_first_node_in_group("odm_hud")
	if _hud == null:
		_hud = get_tree().current_scene.get_node_or_null("ODMHUD")
	if _hud and _hud.has_method("bind_odm"):
		_hud.bind_odm(odm)
	if _hud and _hud.has_method("bind_player"):
		_hud.bind_player(self)
	if _hud and _hud.has_method("bind_health"):
		_hud.bind_health(health)


## Entry point for enemies: forwards damage to the health component.
func take_damage(amount: float, source: Node = null, ignore_invulnerable: bool = false) -> void:
	health.take_damage(amount, source, ignore_invulnerable)


## Called by a titan that catches the player; movement is driven by the titan until release.
func on_grabbed(titan: Node3D) -> void:
	if _dead or grabbed:
		return
	grabbed = true
	_grabber = titan
	odm.release_hooks()
	if _is_sliding:
		_finish_slide()
	_is_crouching = false
	_apply_capsule_stance()
	velocity = Vector3.ZERO
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_air_phase = AirPhase.FALL
	_play_library_animation(LIB_HUMANF, jump_fall_animation)


## Called by SwordCombat when a swing's hit window opens while held.
func strike_grabber(damage: float) -> void:
	if grabbed and is_instance_valid(_grabber) and _grabber.has_method(&"on_grab_struck"):
		_grabber.on_grab_struck(damage)


func set_grab_progress(progress: float, hits_left: int) -> void:
	grab_progress.emit(true, progress, hits_left)


func on_released(impulse: Vector3) -> void:
	if not grabbed:
		return
	grabbed = false
	grab_progress.emit(false, 0.0, 0)
	_grabber = null
	velocity = impulse
	# Stand back upright, keeping only the facing direction.
	var flat := Vector3(global_basis.z.x, 0.0, global_basis.z.z)
	var yaw := atan2(flat.x, flat.z) if flat.length() > 0.1 else rotation.y
	rotation = Vector3(0.0, yaw, 0.0)
	_was_on_floor = false
	_current_anim = &""


func _on_damaged(_amount: float, _source: Node) -> void:
	if player_audio and player_audio.has_method("play_land"):
		player_audio.play_land()


## Stops player control: hooks released, swords and ODM input disabled.
func _on_died() -> void:
	_dead = true
	on_released(Vector3.ZERO)
	odm.release_hooks()
	odm.set_process_input(false)
	sword_combat.set_process(false)
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Handles global player input: mouse capture, escape, camera cycling, and
## third-person camera look rotation.
func _input(event: InputEvent) -> void:
	if _dead:
		return
	# Use _input (not _unhandled_input) so HUD controls at screen center cannot eat look.
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event.is_action_pressed("camera_cycle"):
		_cycle_camera()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _pcam == null:
			_resolve_camera_nodes()
		if _pcam == null:
			return
		if _pcam.get_follow_mode() != PhantomCamera3D.FollowMode.THIRD_PERSON:
			return
		var pitch_min := overhead_min_pitch if _is_overhead_camera() else min_pitch
		var pitch_max := overhead_max_pitch if _is_overhead_camera() else max_pitch
		var rotation_degrees := _pcam.get_third_person_rotation_degrees()
		rotation_degrees.x -= event.relative.y * mouse_sensitivity
		rotation_degrees.x = clampf(rotation_degrees.x, pitch_min, pitch_max)
		rotation_degrees.y -= event.relative.x * mouse_sensitivity
		rotation_degrees.y = wrapf(rotation_degrees.y, 0.0, 360.0)
		_pcam.set_third_person_rotation_degrees(rotation_degrees)
		get_viewport().set_input_as_handled()


## Runs the main movement loop each physics frame, choosing between normal
## ground movement and ODM movement before applying collision resolution.
func _physics_process(delta: float) -> void:
	if _camera == null or _pcam == null:
		_resolve_camera_nodes()
		if odm and _camera:
			odm.set_camera(_camera)

	if _dead:
		if not is_on_floor():
			velocity += get_gravity() * gravity_scale * delta
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		move_and_slide()
		return

	if grabbed:
		if is_instance_valid(_grabber):
			velocity = Vector3.ZERO
			_update_camera_follow_offsets()
			return
		on_released(Vector3.ZERO)

	var odm_active := odm != null and odm.is_active()

	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta
		velocity.y = maxf(velocity.y, -terminal_fall_speed)
		if Input.is_action_just_released("jump") and velocity.y > 0.0:
			velocity.y *= jump_release_multiplier

	if odm_active:
		# Cancel slide if we leave grounded control for ODM.
		if _is_sliding:
			_finish_slide()
		odm.physics_tick(delta)
		_face_velocity(delta)
	else:
		_update_stance_state()

		if Input.is_action_just_pressed("jump") and is_on_floor() and not _is_sliding and _air_phase != AirPhase.LAND:
			_start_jump()

		if _is_sliding:
			_process_slide(delta)
		else:
			_process_move(delta)

		# Still allow firing hooks while grounded; physics applied next frame if attached.
		if odm:
			odm.physics_tick(delta)

	_update_camera_follow_offsets()
	move_and_slide()
	_update_air_state()
	_update_animation()
	_update_audio(delta)


## Rotates the player toward horizontal movement while preserving vertical
## velocity and avoiding jitter when movement is nearly stopped.
func _face_velocity(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() < 0.4:
		return
	var target_yaw := atan2(horizontal.x, horizontal.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


## Updates looping footsteps and sprint audio based on horizontal speed,
## stance, floor contact, and whether the player is using ODM hooks.
func _update_audio(delta: float) -> void:
	if player_audio == null:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var moving := horizontal_speed > walk_speed_threshold and not (odm != null and odm.is_hooked())
	var sprinting := Input.is_action_pressed("sprint") and not _is_crouching
	if player_audio.has_method("play_footsteps"):
		player_audio.play_footsteps(delta, moving, sprinting,
			is_on_floor() and not _is_sliding, _get_floor_collider())


## Returns the collider the player is standing on, or null in the air.
func _get_floor_collider() -> Object:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_normal().y >= cos(floor_max_angle):
			return collision.get_collider()
	return null


## Starts a jump by applying vertical velocity, leaving crouch, and selecting
## the jump-start animation before the normal falling phase.
func _start_jump() -> void:
	velocity.y = jump_velocity
	_is_crouching = false
	_apply_capsule_stance()
	_air_phase = AirPhase.START
	_was_on_floor = false
	if _has_clip(LIB_HUMANF, jump_start_animation):
		_play_library_animation(LIB_HUMANF, jump_start_animation)
	else:
		_begin_fall()


## Switches the air state to the looping fall phase and plays the fall clip.
func _begin_fall() -> void:
	if _air_phase == AirPhase.LAND:
		return
	_air_phase = AirPhase.FALL
	_play_library_animation(LIB_HUMANF, jump_fall_animation)


## Chooses between a dedicated landing animation and an immediate return to
## locomotion when momentum or input means the player is already moving.
func _begin_land() -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var wants_move := Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO

	if player_audio and player_audio.has_method("play_land"):
		player_audio.play_land()

	# Keep momentum: no dedicated "land into run" clip in UAL, so blend straight to locomotion.
	if horizontal_speed >= moving_land_speed_threshold or wants_move or (odm != null and odm.is_hooked()):
		_finish_land()
		return

	_air_phase = AirPhase.LAND
	_land_timer = 0.0
	if _has_clip(LIB_HUMANF, jump_land_animation):
		_play_library_animation(LIB_HUMANF, jump_land_animation)
	else:
		_finish_land()


## Clears the landing state so the regular locomotion selector can resume.
func _finish_land() -> void:
	_air_phase = AirPhase.NONE
	_land_timer = 0.0
	_current_anim = &""


## Detects walking off edges, the jump apex, landing, and early interruption
## of the landing pose.
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
		if (wants_move and _land_timer >= land_interrupt_time) or _land_timer >= player_animation.clip_length(jump_land_animation):
			_finish_land()

	_was_on_floor = on_floor


## Resolves crouch and slide requests, including the speed threshold that
## converts a sprinting crouch press into a slide.
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


## Enters the slide state, stores the travel direction, adjusts the capsule,
## and starts the slide-start animation.
func _start_slide() -> void:
	_is_sliding = true
	_is_crouching = true
	_slide_phase = SlidePhase.START
	_slide_loop_time_left = slide_loop_duration
	_slide_phase_time = 0.0
	_apply_capsule_stance()

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() < 0.1:
		horizontal = -global_transform.basis.z
	_slide_direction = horizontal.normalized()
	velocity.x = _slide_direction.x * slide_speed
	velocity.z = _slide_direction.z * slide_speed

	if _has_clip(LIB_HUMANF, slide_start_animation):
		_play_library_animation(LIB_HUMANF, slide_start_animation)
	else:
		_begin_slide_loop()


## Switches from the slide-start clip to the looping slide clip once the
## start animation has finished.
func _begin_slide_loop() -> void:
	if not _is_sliding:
		return
	if _slide_phase != SlidePhase.START and _slide_phase != SlidePhase.NONE:
		return
	_slide_phase = SlidePhase.LOOP
	_slide_loop_time_left = slide_loop_duration
	_slide_phase_time = 0.0
	_play_library_animation(LIB_HUMANF, slide_animation)


## Begins the slide exit animation, or finishes immediately if that clip is
## unavailable.
func _begin_slide_exit() -> void:
	if not _is_sliding or _slide_phase == SlidePhase.EXIT or _slide_phase == SlidePhase.NONE:
		return
	_slide_phase = SlidePhase.EXIT
	_slide_phase_time = 0.0
	if _has_clip(LIB_HUMANF, slide_exit_animation):
		_play_library_animation(LIB_HUMANF, slide_exit_animation)
	else:
		_finish_slide()


## Leaves the slide state, restores the requested crouch state, and allows
## locomotion animation selection to take over.
func _finish_slide() -> void:
	_is_sliding = false
	_slide_phase = SlidePhase.NONE
	_slide_phase_time = 0.0
	_is_crouching = Input.is_action_pressed("crouch")
	_apply_capsule_stance()
	_current_anim = &""


## Applies slide velocity and rotation, exits when the floor is lost, and
## counts down the loop duration before starting the exit phase.
func _process_slide(delta: float) -> void:
	var speed_scale := 1.0 if _slide_phase != SlidePhase.EXIT else 0.55
	velocity.x = _slide_direction.x * slide_speed * speed_scale
	velocity.z = _slide_direction.z * slide_speed * speed_scale

	var target_yaw := atan2(_slide_direction.x, _slide_direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)

	if not is_on_floor() and _slide_phase != SlidePhase.EXIT:
		_begin_slide_exit()
		return

	_slide_phase_time += delta
	if _slide_phase == SlidePhase.START and _slide_phase_time >= player_animation.clip_length(slide_start_animation):
		_begin_slide_loop()
	elif _slide_phase == SlidePhase.LOOP:
		_slide_loop_time_left -= delta
		if _slide_loop_time_left <= 0.0:
			_begin_slide_exit()
	elif _slide_phase == SlidePhase.EXIT and _slide_phase_time >= player_animation.clip_length(slide_exit_animation):
		_finish_slide()


## Converts keyboard movement into camera-relative target velocity, applies
## ground/air acceleration or braking, and turns toward the requested direction.
func _process_move(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_dir := _camera_relative_direction(input_dir)
	var current_speed := _get_move_speed()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if is_on_floor():
		if move_dir.length() > 0.0:
			var target_velocity := move_dir * current_speed
			horizontal.x = move_toward(horizontal.x, target_velocity.x, ground_acceleration * delta)
			horizontal.z = move_toward(horizontal.z, target_velocity.z, ground_acceleration * delta)
		else:
			horizontal = horizontal.move_toward(Vector3.ZERO, ground_deceleration * delta)
	elif move_dir.length() > 0.0:
		# Add control only up to ordinary air speed along the requested direction.
		# Existing speed, including momentum from an ODM launch, carries through.
		var available_speed := maxf(0.0, current_speed - horizontal.dot(move_dir))
		horizontal += move_dir * minf(air_acceleration * delta, available_speed)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, air_deceleration * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if move_dir.length() > 0.0:
		var facing := move_dir
		if _camera != null:
			facing = -_camera.global_transform.basis.z
			facing.y = 0.0
			facing = facing.normalized()
		var target_yaw := atan2(facing.x, facing.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


## Selects the current ground speed from crouch, sprint, or ordinary running input.
func _get_move_speed() -> float:
	if _is_crouching:
		return crouch_speed
	if Input.is_action_pressed("sprint") and Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO:
		return sprint_speed
	# Light stick / no sprint uses jog as the default run speed.
	if Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO:
		return jog_speed
	return walk_speed


## Stores the original capsule dimensions and vertical offset so crouching
## can be applied and later restored without hardcoding scene changes.
func _cache_capsule_defaults() -> void:
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		_standing_capsule_height = capsule.height
		_standing_capsule_radius = capsule.radius
		_standing_shape_y = collision_shape.position.y


## Resizes and repositions the collision capsule for crouching/sliding or
## restores the standing shape.
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


## Converts a 2D input vector into a world-space direction using the active
## camera's horizontal forward and right vectors.
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


## Resolves the gameplay camera and the ordered PhantomCamera cycle, then
## initializes the active camera and its follow offset.
func _resolve_camera_nodes() -> void:
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		_camera = get_tree().get_first_node_in_group("player_camera") as Camera3D
	if odm and _camera:
		odm.set_camera(_camera)

	_pcams.clear()
	_pcam_local_offsets.clear()
	var scene := get_tree().current_scene
	if scene:
		for cam_name in camera_cycle_names:
			var node := scene.get_node_or_null(NodePath(cam_name)) as PhantomCamera3D
			if node:
				_pcams.append(node)
				# Phantom Camera applies follow_offset in world space. Capture
				# the authored shoulder width and height; the offset is rebuilt
				# from the viewport direction below.
				_pcam_local_offsets.append(node.follow_offset)

	# Fallback: whatever is in the group, sorted by name for stability.
	if _pcams.is_empty():
		var found: Array = get_tree().get_nodes_in_group("player_pcam")
		found.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
		for node in found:
			if node is PhantomCamera3D:
				_pcams.append(node)
				_pcam_local_offsets.append(node.follow_offset)

	if _pcams.is_empty():
		_pcam = null
		return

	_pcam_index = clampi(_pcam_index, 0, _pcams.size() - 1)
	_set_active_pcam(_pcam_index, false)
	_update_camera_follow_offsets()


## Advances to the next configured PhantomCamera when camera cycling is
## requested.
func _cycle_camera() -> void:
	if _pcams.is_empty():
		_resolve_camera_nodes()
	if _pcams.size() < 2:
		return
	_set_active_pcam((_pcam_index + 1) % _pcams.size(), true)


## Applies a camera priority and optionally copies the previous camera's
## third-person rotation into the newly active camera.
func _set_active_pcam(index: int, copy_rotation: bool) -> void:
	if _pcams.is_empty():
		return
	index = clampi(index, 0, _pcams.size() - 1)

	var previous_rotation := Vector3.ZERO
	var had_previous := _pcam != null and is_instance_valid(_pcam)
	if copy_rotation and had_previous:
		previous_rotation = _pcam.get_third_person_rotation_degrees()

	for i in _pcams.size():
		_pcams[i].priority = active_pcam_priority if i == index else 0

	_pcam_index = index
	_pcam = _pcams[index]

	if copy_rotation and had_previous:
		var pitch_min := overhead_min_pitch if _is_overhead_camera() else min_pitch
		var pitch_max := overhead_max_pitch if _is_overhead_camera() else max_pitch
		previous_rotation.x = clampf(previous_rotation.x, pitch_min, pitch_max)
		_pcam.set_third_person_rotation_degrees(previous_rotation)


## Rebuilds shoulder-camera offsets from the actual viewport direction so the
## right and left shoulder views remain correct after the player turns.
func _update_camera_follow_offsets() -> void:
	if _pcams.size() != _pcam_local_offsets.size() or _camera == null:
		return

	# follow_offset is world-space in this Phantom Camera version. Use the
	# viewport's horizontal right vector so a "right shoulder" camera stays
	# on the correct side of the view even when the player turns around.
	var viewport_right := _camera.global_transform.basis.x
	viewport_right.y = 0.0
	if viewport_right.length_squared() < 0.001:
		return
	viewport_right = viewport_right.normalized()

	for i in _pcams.size():
		var authored_offset := _pcam_local_offsets[i]
		var world_offset := Vector3.UP * authored_offset.y
		var shoulder_width := absf(authored_offset.x)

		if _pcams[i].name == &"RightShoulderCam":
			# The follow target is shifted toward the camera. The opposite
			# viewport-right direction places the camera over the model's
			# right shoulder.
			world_offset -= viewport_right * shoulder_width
		elif _pcams[i].name == &"LeftShoulderCam":
			world_offset += viewport_right * shoulder_width
		else:
			world_offset += viewport_right * authored_offset.x

		_pcams[i].follow_offset = world_offset


## Reports whether the active PhantomCamera is the overhead camera so pitch
## limits can be adjusted for that view.
func _is_overhead_camera() -> bool:
	return _pcam != null and _pcam.name == &"OverheadCam"


## Checks that the native HumanF animation player is present.
func _setup_animations() -> void:
	if animation_player == null:
		push_error("HumanF AnimationPlayer missing")
		return
	_current_anim = &""


## Selects the highest-priority animation state: ODM falling, slide/air
## states, crouch movement, or regular idle/walk/run locomotion.
func _update_animation() -> void:
	if animation_player == null:
		return

	# While hooked / boosting in air, reuse fall clip.
	if odm != null and odm.is_active() and not is_on_floor():
		if _air_phase == AirPhase.NONE:
			_air_phase = AirPhase.FALL
		_play_library_animation(LIB_HUMANF, jump_fall_animation)
		return

	# Slide / air clips are driven by their own state machines.
	if _is_sliding or _air_phase != AirPhase.NONE:
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	if _is_crouching:
		if horizontal_speed > walk_speed_threshold:
			_play_library_animation(LIB_HUMANF, crouch_walk_animation)
		else:
			_play_library_animation(LIB_HUMANF, crouch_idle_animation)
		return

	if horizontal_speed <= walk_speed_threshold:
		_play_library_animation(LIB_HUMANF, idle_animation)
	elif horizontal_speed < 2.4:
		var travel_clip := _directional_run_clip()
		var walk_clip := walk_animation if travel_clip == jog_animation or travel_clip == sprint_animation else travel_clip
		_play_library_animation(LIB_HUMANF, walk_clip)
		player_animation.play_base(walk_clip, 1.0 if walk_clip == walk_animation else clampf(horizontal_speed / 4.0, 0.5, 1.0))
	else:
		_play_library_animation(LIB_HUMANF, _directional_run_clip())
		player_animation.play_base(_directional_run_clip(), clampf(horizontal_speed / 4.0, 0.5, 1.0))


## Selects the baked 4 m/s run or strafe cycle from local travel direction.
func _directional_run_clip() -> StringName:
	var local := global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	local = local.normalized()
	if absf(local.x) > 0.4:
		var side := "Left" if local.x >= 0.0 else "Right"
		if local.z > 0.4:
			return StringName("StrafeForward" + side)
		if local.z < -0.4:
			return StringName("StrafeBackward" + side)
		return StringName("Strafe" + side)
	if local.z > 0.0:
		return sprint_animation if Input.is_action_pressed("sprint") else jog_animation
	return &"RunBackward"


## Checks whether a fully qualified library/clip animation is available.
func _has_clip(library_name: StringName, clip_name: StringName) -> bool:
	var full_name := StringName("%s/%s" % [library_name, clip_name])
	return animation_player != null and animation_player.has_animation(full_name)


## Plays an animation with crossfade blending, falling back to another
## animation library when the requested clip name is found there.
func _play_library_animation(_library_name: StringName, clip_name: StringName) -> void:
	if player_animation == null or not player_animation.has_clip(clip_name):
		return
	var full_name := StringName("humanf/%s" % clip_name)
	if full_name == _current_anim:
		return
	player_animation.play_base(clip_name)
	_current_anim = full_name


## Ensures every player action exists even when the project input map is
## initially empty; existing bindings are left untouched.
func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("sprint", KEY_SHIFT)
	_add_key_action("crouch", KEY_CTRL)
	_add_key_action("camera_cycle", KEY_V)


## Adds one physical-key binding to an action only when that exact binding is
## not already present.
func _add_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == keycode:
			return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)
