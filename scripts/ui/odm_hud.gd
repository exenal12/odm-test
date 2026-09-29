extends CanvasLayer
## Minimal ODM HUD: gas bar + left/right hook indicators + aim reticle.

@onready var gas_bar: ProgressBar = %GasBar
@onready var gas_label: Label = %GasLabel
@onready var left_hook_indicator: ColorRect = %LeftHook
@onready var right_hook_indicator: ColorRect = %RightHook
@onready var reticle: Control = %Reticle
@onready var hint_label: Label = %HintLabel
@onready var reel_icon: Control = %ReelIcon
@onready var reel_status: Label = %ReelStatus

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var damage_flash: ColorRect = %DamageFlash
@onready var death_screen: Control = %DeathScreen
@onready var restart_button: Button = %RestartButton

@onready var escape_panel: Control = %EscapePanel
@onready var escape_label: Label = %EscapeLabel
@onready var escape_bar: ProgressBar = %EscapeBar

var _odm: ODMController
var _health: PlayerHealth
var _low_health_alpha: float = 0.0


func _ready() -> void:
	death_screen.hide()
	restart_button.pressed.connect(_restart)


func _unhandled_input(event: InputEvent) -> void:
	if death_screen.visible and event.is_action_pressed("ui_accept"):
		_restart()


## Binds the HUD to the player's health component.
func bind_health(health: PlayerHealth) -> void:
	_health = health
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_on_health_changed(health.health, health.max_health)


## Shows the escape prompt while a titan holds the player.
func bind_player(player: Node) -> void:
	player.grab_progress.connect(_on_grab_progress)


func _on_grab_progress(active: bool, progress: float, hits_left: int) -> void:
	escape_panel.visible = active
	escape_bar.value = progress
	escape_label.text = "ATTACK TO ESCAPE  (%d)" % hits_left


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "HEALTH %d" % int(ceil(current))
	var ratio := current / maxf(maximum, 1.0)
	_low_health_alpha = clampf((0.4 - ratio) / 0.4, 0.0, 1.0) * 0.35
	damage_flash.color.a = maxf(damage_flash.color.a, _low_health_alpha)


func _on_damaged(_amount: float, _source: Node) -> void:
	damage_flash.color.a = 0.5
	create_tween().tween_property(damage_flash, "color:a", _low_health_alpha, 0.5)


func _on_died() -> void:
	death_screen.show()
	restart_button.grab_focus()


func _restart() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


## Binds the HUD to one ODM controller, disconnecting any previous controller
## and immediately synchronizing gas and hook indicator state.
func bind_odm(odm: ODMController) -> void:
	if _odm:
		if _odm.gas_changed.is_connected(_on_gas_changed):
			_odm.gas_changed.disconnect(_on_gas_changed)
		if _odm.hooks_changed.is_connected(_on_hooks_changed):
			_odm.hooks_changed.disconnect(_on_hooks_changed)
		if _odm.reel_mode_changed.is_connected(_on_reel_mode_changed):
			_odm.reel_mode_changed.disconnect(_on_reel_mode_changed)
	_odm = odm
	if _odm == null:
		return
	_odm.gas_changed.connect(_on_gas_changed)
	_odm.hooks_changed.connect(_on_hooks_changed)
	_odm.reel_mode_changed.connect(_on_reel_mode_changed)
	_on_gas_changed(_odm.get_gas(), _odm.get_gas_max())
	_on_hooks_changed(_odm.left_attached(), _odm.right_attached())
	_on_reel_mode_changed(_odm.is_reel_enabled())


## Updates the gas bar maximum/value and formats the percentage label.
func _on_gas_changed(current: float, maximum: float) -> void:
	if gas_bar:
		gas_bar.max_value = maximum
		gas_bar.value = current
	if gas_label:
		gas_label.text = "GAS %d%%" % int(round((current / maxf(maximum, 1.0)) * 100.0))


## Changes each hook indicator color to show whether that hook is attached.
func _on_hooks_changed(left_attached: bool, right_attached: bool) -> void:
	if left_hook_indicator:
		left_hook_indicator.color = Color(0.2, 0.85, 0.35) if left_attached else Color(0.25, 0.25, 0.28, 0.7)
	if right_hook_indicator:
		right_hook_indicator.color = Color(0.2, 0.85, 0.35) if right_attached else Color(0.25, 0.25, 0.28, 0.7)


func _on_reel_mode_changed(enabled: bool) -> void:
	if reel_icon:
		reel_icon.reel_enabled = enabled
	if reel_status:
		reel_status.text = "REEL ON" if enabled else "REEL OFF"
		reel_status.modulate = Color(0.29, 0.91, 0.49) if enabled else Color(0.95, 0.36, 0.32)
