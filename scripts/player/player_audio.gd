extends Node
## Plays locomotion + ODM SFX. Swap files under assets/audio/ freely.

@export var footstep_interval: float = 0.38
@export var sprint_footstep_scale: float = 0.7

@onready var footstep_player: AudioStreamPlayer3D = $Footstep
@onready var land_player: AudioStreamPlayer3D = $Land
@onready var odm_player: AudioStreamPlayer3D = $ODM
@onready var boost_player: AudioStreamPlayer3D = $Boost
@onready var ui_player: AudioStreamPlayer = $UI

var _footstep_streams: Array[AudioStream] = []
var _footstep_timer: float = 0.0
var _hook_fire: AudioStream
var _hook_latch: AudioStream
var _hook_detach: AudioStream
var _cable_reel: AudioStream
var _gas_boost: AudioStream
var _land: AudioStream
var _ui_click: AudioStream


func _ready() -> void:
	_load_streams()


func _load_streams() -> void:
	for i in 5:
		var path := "res://assets/audio/sfx/footstep_concrete_%03d.wav" % i
		if ResourceLoader.exists(path):
			_footstep_streams.append(load(path))
	_land = _load_stream("res://assets/audio/sfx/impact_land.wav")
	_hook_fire = _load_stream("res://assets/audio/odm/hook_fire.wav")
	_hook_latch = _load_stream("res://assets/audio/odm/hook_latch.wav")
	_hook_detach = _load_stream("res://assets/audio/odm/hook_detach.wav")
	_cable_reel = _load_stream("res://assets/audio/odm/cable_reel.wav")
	_gas_boost = _load_stream("res://assets/audio/odm/gas_boost.wav")
	_ui_click = _load_stream("res://assets/audio/ui/click_001.wav")


func _load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


func bind_odm(odm: ODMController) -> void:
	if odm == null:
		return
	odm.hook_fired.connect(_on_hook_fired)
	odm.hook_latched.connect(_on_hook_latched)
	odm.hook_detached.connect(_on_hook_detached)
	odm.boosted.connect(_on_boosted)


func play_footsteps(delta: float, moving: bool, sprinting: bool, on_floor: bool) -> void:
	if not on_floor or not moving or _footstep_streams.is_empty():
		_footstep_timer = 0.0
		return
	var interval := footstep_interval * (sprint_footstep_scale if sprinting else 1.0)
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = interval
		footstep_player.stream = _footstep_streams[randi() % _footstep_streams.size()]
		footstep_player.pitch_scale = randf_range(0.92, 1.08)
		footstep_player.play()


func play_land() -> void:
	if _land == null:
		return
	land_player.stream = _land
	land_player.play()


func play_ui_click() -> void:
	if _ui_click == null:
		return
	ui_player.stream = _ui_click
	ui_player.play()


func _on_hook_fired(_is_left: bool) -> void:
	_play_odm(_hook_fire)


func _on_hook_latched(_is_left: bool) -> void:
	_play_odm(_hook_latch)


func _on_hook_detached(_is_left: bool) -> void:
	_play_odm(_hook_detach)


func _on_boosted() -> void:
	if _gas_boost == null:
		return
	if not boost_player.playing:
		boost_player.stream = _gas_boost
		boost_player.play()


func _play_odm(stream: AudioStream) -> void:
	if stream == null:
		return
	odm_player.stream = stream
	odm_player.play()
