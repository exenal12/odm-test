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
var _ui_click: AudioStream
var _last_gas: float = -1.0
var _next_refill_ms: int = 0


## Loads all configured audio resources after the node enters the scene tree.
func _ready() -> void:
	_load_streams()


## Loads footstep sets per surface plus landing, hook, boost, impact, reel, refill,
## and UI audio streams.
func _load_streams() -> void:
	for surface in SURFACES:
		var name := String(surface).trim_prefix("surface_")
		_footsteps[surface] = _load_variants("res://assets/audio/sfx/footstep_%s_%%03d.ogg" % name, 5)
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


## Plays randomized footsteps for the surface under the player at a
## stance-dependent interval while grounded and moving.
func play_footsteps(delta: float, moving: bool, sprinting: bool, on_floor: bool,
		floor_collider: Object = null) -> void:
	var set: Array = _footsteps.get(_surface_of(floor_collider), [])
	if set.is_empty():
		set = _footsteps.get(SURFACE_DEFAULT, [])
	if not on_floor or not moving or set.is_empty():
		_footstep_timer = 0.0
		return
	var interval := footstep_interval * (sprint_footstep_scale if sprinting else 1.0)
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = interval
		_play_random(footstep_player, set, 0.92, 1.08)


## Plays the landing sound when a landing stream is available.
func play_land() -> void:
	if _land == null:
		return
	land_player.stream = _land
	land_player.play()


## Plays the configured UI click sound.
func play_ui_click() -> void:
	if _ui_click == null:
		return
	ui_player.stream = _ui_click
	ui_player.play()


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


## Plays a random stream from the list on the given player with slight pitch variation.
func _play_random(player: AudioStreamPlayer3D, streams: Array, pitch_min: float,
		pitch_max: float) -> void:
	if streams.is_empty():
		return
	player.stream = streams[randi() % streams.size()]
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.play()
