extends Node
## Plays locomotion + ODM SFX. Swap files under assets/audio/ freely.

## Time between normal footsteps while walking or jogging.
@export var footstep_interval: float = 0.38
## Multiplier applied to the footstep interval while sprinting.
@export var sprint_footstep_scale: float = 0.7
## Minimum seconds between gas-refill hisses while gas keeps rising.
@export var refill_sound_cooldown: float = 0.4

## Gas hiss loop volume while reeling and while boosting.
const HISS_REEL_DB := -18.0
const HISS_BOOST_DB := -8.0

## Landing pitch range per surface; grass is pitched down for a heavy, dull thud.
const LAND_PITCH := {
	&"surface_grass": Vector2(0.65, 0.8),
}

## Extra footstep volume per surface (dB); grass files are recorded quietly.
const FOOTSTEP_GAIN_DB := {
	&"surface_grass": 6.0,
}

## Extra landing volume per surface (dB); grass reuses quieter footstep sounds.
const LAND_GAIN_DB := {
	&"surface_grass": 8.0,
}

## Kenney impact sets used for landings, per surface.
const LAND_SOUNDS := {
	&"surface_concrete": ["impactGeneric_light", "impactPunch_medium"],
	&"surface_grass": ["footstep_grass"],
	&"surface_wood": ["impactWood_heavy", "impactPlank_medium"],
	&"surface_carpet": ["impactSoft_medium"],
	&"surface_snow": ["impactSoft_heavy"],
}

## Foot bones whose height marks a footstep.
const FOOT_BONES: Array[StringName] = [&"B-foot.L", &"B-foot.R"]
## A foot counts as planted within this height of the lowest it has reached.
const FOOT_CONTACT_HEIGHT := 0.05
## How fast the remembered lowest foot height recovers upward (m/s).
const FOOT_FLOOR_DRIFT := 0.05
## Minimum seconds between animation-driven steps.
const MIN_STEP_GAP := 0.12

const SURFACE_DEFAULT := &"surface_concrete"
const SURFACES: Array[StringName] = [
	&"surface_concrete", &"surface_grass", &"surface_wood", &"surface_carpet", &"surface_snow",
]

@onready var footstep_player: AudioStreamPlayer3D = $Footstep
@onready var land_player: AudioStreamPlayer3D = $Land
@onready var odm_player: AudioStreamPlayer3D = $ODM
@onready var boost_player: AudioStreamPlayer3D = $Boost
@onready var reel_player: AudioStreamPlayer3D = $Reel
@onready var impact_player: AudioStreamPlayer3D = $Impact
@onready var refill_player: AudioStreamPlayer3D = $Refill
@onready var ui_player: AudioStreamPlayer = $UI

var _footsteps: Dictionary = {}
var _footstep_timer: float = 0.0
var _hook_fire: Array[AudioStream] = []
var _impacts: Array[AudioStream] = []
var _reel_hiss: AudioStream
var _reeling: bool = false
var _boosting: bool = false
var _hiss_tween: Tween
var _gas_boost: Array[AudioStream] = []
var _refill: Array[AudioStream] = []
var _land: AudioStream
var _land_sets: Dictionary = {}
var _last_surface: StringName = SURFACE_DEFAULT
var _last_footstep: AudioStream
var _skeleton: Skeleton3D
var _foot_bones: Array[int] = []
var _foot_planted: Array[bool] = [true, true]
var _foot_floor: float = 0.0
var _step_allowed: bool = false
var _sprinting: bool = false
var _step_gap: float = 0.0
var _ui_click: AudioStream
var _last_gas: float = -1.0
var _next_refill_ms: int = 0


## Loads all configured audio resources after the node enters the scene tree.
func _ready() -> void:
	_load_streams()
	_find_feet()


## Finds the skeleton's foot bones so steps can follow the animation.
func _find_feet() -> void:
	var body := get_parent()
	_skeleton = body.find_child("Skeleton3D", true, false) as Skeleton3D if body != null else null
	if _skeleton == null:
		return
	for bone_name in FOOT_BONES:
		var index := _skeleton.find_bone(bone_name)
		if index < 0:
			_foot_bones.clear()
			return
		_foot_bones.append(index)


## Plays a footstep whenever a foot touches down in the animation.
func _process(delta: float) -> void:
	if _foot_bones.is_empty():
		return
	_step_gap -= delta
	var heights: Array[float] = []
	for index in _foot_bones:
		var world := _skeleton.global_transform * _skeleton.get_bone_global_pose(index).origin
		heights.append(world.y - get_parent().global_position.y)
	var lowest := minf(heights[0], heights[1])
	_foot_floor = minf(_foot_floor + FOOT_FLOOR_DRIFT * delta, lowest) if _foot_floor != 0.0 else lowest
	for i in heights.size():
		var planted := heights[i] <= _foot_floor + FOOT_CONTACT_HEIGHT
		if planted and not _foot_planted[i] and _step_allowed and _step_gap <= 0.0:
			_step_gap = MIN_STEP_GAP
			_play_step()
		_foot_planted[i] = planted


## Loads footstep sets per surface plus landing, hook, boost, impact, reel, refill,
## and UI audio streams.
func _load_streams() -> void:
	for surface in SURFACES:
		var name := String(surface).trim_prefix("surface_")
		_footsteps[surface] = _load_variants("res://assets/audio/sfx/footstep_%s_%%03d.ogg" % name, 5)
	for surface in LAND_SOUNDS:
		var variants: Array[AudioStream] = []
		for base in LAND_SOUNDS[surface]:
			variants.append_array(_load_variants("res://assets/audio/sfx/%s_%%03d.ogg" % base, 5))
		_land_sets[surface] = variants
	_land = _load_stream("res://assets/audio/sfx/impact_land.wav")
	_hook_fire = _load_variants("res://assets/audio/odm/hook_launch_%03d.wav", 2)
	_impacts = _load_variants("res://assets/audio/sfx/impactWood_medium_%03d.ogg", 5)
	_reel_hiss = _load_stream("res://assets/audio/odm/gas_hiss_loop.wav")
	_gas_boost = _load_variants("res://assets/audio/odm/gas_burst_%03d.wav", 3)
	_refill = _load_variants("res://assets/audio/sfx/gas_refill_%03d.wav", 2)
	_ui_click = _load_stream("res://assets/audio/ui/click_001.wav")


## Loads one audio resource when it exists, returning null for optional files.
func _load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


## Loads numbered variants (pattern uses %03d) that exist on disk.
func _load_variants(pattern: String, count: int) -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	for i in count:
		var stream := _load_stream(pattern % i)
		if stream != null:
			result.append(stream)
	return result


## Connects ODM signals to the matching player sound effects.
func bind_odm(odm: ODMController) -> void:
	if odm == null:
		return
	odm.hook_fired.connect(_on_hook_fired)
	odm.hook_latched.connect(_on_hook_latched)
	odm.reeling_changed.connect(_on_reeling_changed)
	odm.boosting_changed.connect(_on_boosting_changed)
	odm.boosted.connect(_on_boosted)
	odm.gas_changed.connect(_on_gas_changed)


## Tracks the surface and whether steps should sound. Without foot bones it
## falls back to a timed footstep at a stance-dependent interval.
func play_footsteps(delta: float, moving: bool, sprinting: bool, on_floor: bool,
		floor_collider: Object = null) -> void:
	if floor_collider != null:
		_last_surface = _surface_of(floor_collider)
	_sprinting = sprinting
	_step_allowed = on_floor and moving
	if not _foot_bones.is_empty():
		return
	if not _step_allowed:
		_footstep_timer = 0.0
		return
	var interval := footstep_interval * (sprint_footstep_scale if sprinting else 1.0)
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = interval
		_play_step()


## Plays one footstep for the current surface.
func _play_step() -> void:
	var set: Array = _footsteps.get(_last_surface, [])
	if set.is_empty():
		set = _footsteps.get(SURFACE_DEFAULT, [])
	if set.is_empty():
		return
	_last_footstep = _play_random(footstep_player, set, 0.9, 1.1, _last_footstep)
	footstep_player.volume_db = randf_range(-2.0, 0.0) + (2.0 if _sprinting else 0.0) \
			+ FOOTSTEP_GAIN_DB.get(_last_surface, 0.0)


## Plays a landing impact matching the surface (falls back to the last known
## surface when the collider is unknown).
func play_land(floor_collider: Object = null) -> void:
	var surface := _surface_of(floor_collider) if floor_collider != null else _last_surface
	var set: Array = _land_sets.get(surface, [])
	if not set.is_empty():
		var pitch: Vector2 = LAND_PITCH.get(surface, Vector2(0.92, 1.08))
		_play_random(land_player, set, pitch.x, pitch.y)
		land_player.volume_db = 2.0 + LAND_GAIN_DB.get(surface, 0.0)
	elif _land != null:
		land_player.stream = _land
		land_player.pitch_scale = 1.0
		land_player.play()


## Plays the configured UI click sound.
func play_ui_click() -> void:
	if _ui_click == null:
		return
	ui_player.stream = _ui_click
	ui_player.play()


## Returns the collider a character body is standing on, or null in the air.
func get_floor_collider(body: CharacterBody3D) -> Object:
	for i in body.get_slide_collision_count():
		var collision := body.get_slide_collision(i)
		if collision.get_normal().y >= cos(body.floor_max_angle):
			return collision.get_collider()
	# Resting contact may not report a slide collision, so probe straight down.
	var query := PhysicsRayQueryParameters3D.create(
		body.global_position + Vector3.UP * 0.2, body.global_position + Vector3.DOWN * 0.8)
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") if not hit.is_empty() else null


## Maps a floor collider to a surface name using its groups.
func _surface_of(collider: Object) -> StringName:
	var node := collider as Node
	if node == null:
		return SURFACE_DEFAULT
	for surface in SURFACES:
		if node.is_in_group(surface):
			return surface
	return SURFACE_DEFAULT


## Responds to a hook-fired signal with the hook-launch sound.
func _on_hook_fired(_is_left: bool) -> void:
	_play_random(odm_player, _hook_fire, 0.96, 1.04)


## Plays a wood impact when a hook lands (trees are the main grapple surface).
func _on_hook_latched(_is_left: bool) -> void:
	_play_random(impact_player, _impacts, 0.92, 1.08)


## Tracks whether the cables are actively reeling.
func _on_reeling_changed(active: bool) -> void:
	_reeling = active
	_update_hiss()


## Tracks whether gas boost is active.
func _on_boosting_changed(active: bool) -> void:
	_boosting = active
	_update_hiss()


## Loops the gas hiss while reeling or boosting, louder when boosting.
func _update_hiss() -> void:
	if _hiss_tween != null:
		_hiss_tween.kill()
	if not _reeling and not _boosting:
		reel_player.stop()
		return
	if _reel_hiss == null:
		return
	if not reel_player.playing:
		reel_player.volume_db = HISS_REEL_DB
		reel_player.stream = _reel_hiss
		reel_player.play()
	_hiss_tween = create_tween()
	_hiss_tween.tween_property(reel_player, "volume_db",
		HISS_BOOST_DB if _boosting else HISS_REEL_DB, 0.15)


## Starts the boost sound once per boost activation rather than every frame.
func _on_boosted() -> void:
	if not boost_player.playing:
		_play_random(boost_player, _gas_boost, 0.95, 1.05)


## Plays a short hiss while gas is increasing, rate-limited by a cooldown.
func _on_gas_changed(current: float, _maximum: float) -> void:
	var previous := _last_gas
	_last_gas = current
	if previous < 0.0 or current <= previous + 0.01:
		return
	var now := Time.get_ticks_msec()
	if now < _next_refill_ms:
		return
	_next_refill_ms = now + int(refill_sound_cooldown * 1000.0)
	_play_random(refill_player, _refill, 0.97, 1.03)


## Plays a random stream (never the same one as `avoid`) with slight pitch
## variation and returns the stream that was chosen.
func _play_random(player: AudioStreamPlayer3D, streams: Array, pitch_min: float,
		pitch_max: float, avoid: AudioStream = null) -> AudioStream:
	if streams.is_empty():
		return null
	var stream: AudioStream = streams[randi() % streams.size()]
	if streams.size() > 1 and stream == avoid:
		stream = streams[(streams.find(stream) + 1 + randi() % (streams.size() - 1)) % streams.size()]
	player.stream = stream
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.play()
	return stream
