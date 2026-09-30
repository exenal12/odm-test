extends Node
## Session-only gameplay and debug options. Never written to disk; closing the game
## discards changes. Reset restores the snapshot taken when the process launched.

signal settings_changed

## Master bus volume as a linear 0–1 scale (1 = launch default).
var master_volume: float = 1.0
## Player hit-point cap (matches PlayerHealth default).
var player_max_health: float = 100.0
## Multiplier for ODM reel / boost / grapple speed caps.
var odm_speed_scale: float = 1.0
## Gas tank capacity.
var gas_max: float = 100.0
## Gas drained per second while boosting (matches player.tscn).
var gas_boost_drain: float = 15.0
## Gas drained per second while reeling (matches player.tscn).
var gas_reel_drain: float = 3.0
## >1 spawns titans more often (shorter intervals).
var titan_spawn_rate: float = 1.0
## >1 spawns soldiers more often (shorter intervals).
var soldier_spawn_rate: float = 1.0

var debug_sword_hitboxes: bool = false
var debug_titan_hitboxes: bool = false
## Titan AI status label; off at launch (enable in Settings → Debug).
var debug_titan_ai: bool = false
var debug_soldier_ai: bool = false

var _defaults: Dictionary = {}


func _ready() -> void:
	_defaults = snapshot()
	settings_changed.connect(apply_master_volume)
	apply_master_volume()


## Copies every tunable into a dictionary for reset / UI sync.
func snapshot() -> Dictionary:
	return {
		"master_volume": master_volume,
		"player_max_health": player_max_health,
		"odm_speed_scale": odm_speed_scale,
		"gas_max": gas_max,
		"gas_boost_drain": gas_boost_drain,
		"gas_reel_drain": gas_reel_drain,
		"titan_spawn_rate": titan_spawn_rate,
		"soldier_spawn_rate": soldier_spawn_rate,
		"debug_sword_hitboxes": debug_sword_hitboxes,
		"debug_titan_hitboxes": debug_titan_hitboxes,
		"debug_titan_ai": debug_titan_ai,
		"debug_soldier_ai": debug_soldier_ai,
	}


## Restores values from a snapshot dictionary and notifies listeners.
func apply_snapshot(data: Dictionary, emit_change: bool = true) -> void:
	master_volume = clampf(float(data.get("master_volume", master_volume)), 0.0, 1.0)
	player_max_health = float(data.get("player_max_health", player_max_health))
	odm_speed_scale = float(data.get("odm_speed_scale", odm_speed_scale))
	gas_max = float(data.get("gas_max", gas_max))
	gas_boost_drain = float(data.get("gas_boost_drain", gas_boost_drain))
	gas_reel_drain = float(data.get("gas_reel_drain", gas_reel_drain))
	titan_spawn_rate = float(data.get("titan_spawn_rate", titan_spawn_rate))
	soldier_spawn_rate = float(data.get("soldier_spawn_rate", soldier_spawn_rate))
	debug_sword_hitboxes = bool(data.get("debug_sword_hitboxes", debug_sword_hitboxes))
	debug_titan_hitboxes = bool(data.get("debug_titan_hitboxes", debug_titan_hitboxes))
	debug_titan_ai = bool(data.get("debug_titan_ai", debug_titan_ai))
	debug_soldier_ai = bool(data.get("debug_soldier_ai", debug_soldier_ai))
	if emit_change:
		settings_changed.emit()
	else:
		apply_master_volume()


## Pushes master_volume onto the Master audio bus.
func apply_master_volume() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	if bus < 0:
		return
	var linear := clampf(master_volume, 0.0, 1.0)
	AudioServer.set_bus_mute(bus, linear <= 0.0001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(linear, 0.0001)))


## Restores the launch-time defaults.
func reset_to_defaults() -> void:
	apply_snapshot(_defaults)


## Call after mutating fields from UI so gameplay listeners refresh.
func notify_changed() -> void:
	settings_changed.emit()
