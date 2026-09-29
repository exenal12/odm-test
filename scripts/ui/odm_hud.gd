extends CanvasLayer
## Minimal ODM HUD: gas bar + left/right hook indicators + aim reticle.

@onready var gas_bar: ProgressBar = %GasBar
@onready var gas_label: Label = %GasLabel
@onready var left_hook_indicator: Control = %LeftHook
@onready var right_hook_indicator: Control = %RightHook
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

const GAS_NORMAL := Color(0.82, 0.86, 0.84)
const GAS_LOW := Color(0.95, 0.65, 0.2)
const GAS_EMPTY := Color(0.85, 0.15, 0.1)

@onready var kill_count: Label = %KillCount
@onready var health_ghost: ProgressBar = %HealthGhost

var _kills: int = 0
var _odm: ODMController
var _health: PlayerHealth
var _low_health_alpha: float = 0.0
var _gas_fill: StyleBoxFlat
var _ghost_tween: Tween
var _escape_tween: Tween
var _shake_tween: Tween


func _ready() -> void:
	death_screen.hide()
	restart_button.pressed.connect(_restart)
	_gas_fill = gas_bar.get_theme_stylebox("fill").duplicate()
	gas_bar.add_theme_stylebox_override("fill", _gas_fill)
	escape_panel.visibility_changed.connect(_on_escape_visibility)
	get_tree().node_added.connect(_track_titan)
	call_deferred("_track_existing_titans")


func _track_existing_titans() -> void:
	for node in get_tree().root.find_children("*", "Titan", true, false):
		_track_titan(node)


func _track_titan(node: Node) -> void:
	if node is Titan and not node.died.is_connected(_on_titan_died):
		node.died.connect(_on_titan_died)


func _on_titan_died(_titan: Titan) -> void:
	_kills += 1
	kill_count.text = str(_kills)
	kill_count.pivot_offset = Vector2(0.0, kill_count.size.y * 0.5)
	kill_count.scale = Vector2.ONE * 1.5
	create_tween().tween_property(kill_count, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


func _process(_delta: float) -> void:
	if _odm and not death_screen.visible:
		reticle.set_locked(_odm.can_hook_target())


func _on_hook_fired(_is_left: bool) -> void:
	reticle.pulse()


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
	if player.sword_combat:
		player.sword_combat.sword_hit.connect(func(_l, _t, _d): reticle.hit_marker())


func _on_grab_progress(active: bool, progress: float, hits_left: int) -> void:
	escape_panel.visible = active
	escape_bar.value = progress
	escape_label.text = "ATTACK TO ESCAPE  (%d)" % hits_left


func _on_escape_visibility() -> void:
	if _escape_tween:
		_escape_tween.kill()
	escape_panel.modulate.a = 1.0
	if escape_panel.visible:
		_escape_tween = create_tween().set_loops()
		_escape_tween.tween_property(escape_panel, "modulate:a", 0.55, 0.3)
		_escape_tween.tween_property(escape_panel, "modulate:a", 1.0, 0.3)


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_ghost.max_value = maximum
	health_bar.value = current
	if current >= health_ghost.value:
		health_ghost.value = current
	else:
		if _ghost_tween:
			_ghost_tween.kill()
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(0.6)
		_ghost_tween.tween_property(health_ghost, "value", current, 0.5)
	health_label.text = "HEALTH  %d" % int(ceil(current))
	var ratio := current / maxf(maximum, 1.0)
	_low_health_alpha = clampf((0.4 - ratio) / 0.4, 0.0, 1.0) * 0.35
	damage_flash.color.a = maxf(damage_flash.color.a, _low_health_alpha)


func _on_damaged(_amount: float, _source: Node) -> void:
	damage_flash.color.a = 0.5
	create_tween().tween_property(damage_flash, "color:a", _low_health_alpha, 0.5)
	var root_ui: Control = $Root
	if _shake_tween:
		_shake_tween.kill()
	_shake_tween = create_tween()
	for i in 5:
		var strength := 8.0 * (1.0 - i / 5.0)
		_shake_tween.tween_property(root_ui, "position", Vector2(randf_range(-strength, strength), randf_range(-strength, strength)), 0.03)
	_shake_tween.tween_property(root_ui, "position", Vector2.ZERO, 0.03)


func _on_died() -> void:
	death_screen.modulate.a = 0.0
	death_screen.show()
	create_tween().tween_property(death_screen, "modulate:a", 1.0, 1.2)
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
		if _odm.hook_fired.is_connected(_on_hook_fired):
			_odm.hook_fired.disconnect(_on_hook_fired)
		if _odm.reel_mode_changed.is_connected(_on_reel_mode_changed):
			_odm.reel_mode_changed.disconnect(_on_reel_mode_changed)
	_odm = odm
	if _odm == null:
		return
	_odm.gas_changed.connect(_on_gas_changed)
	_odm.hooks_changed.connect(_on_hooks_changed)
	_odm.reel_mode_changed.connect(_on_reel_mode_changed)
	_odm.hook_fired.connect(_on_hook_fired)
	_on_gas_changed(_odm.get_gas(), _odm.get_gas_max())
	_on_hooks_changed(_odm.left_attached(), _odm.right_attached())
	_on_reel_mode_changed(_odm.is_reel_enabled())


## Updates the gas bar maximum/value and formats the percentage label.
func _on_gas_changed(current: float, maximum: float) -> void:
	var ratio := current / maxf(maximum, 1.0)
	if gas_bar:
		gas_bar.max_value = maximum
		gas_bar.value = current
		_gas_fill.bg_color = GAS_NORMAL if ratio > 0.3 else (GAS_LOW if ratio > 0.1 else GAS_EMPTY)
	if gas_label:
		gas_label.text = "GAS  %d%%" % int(round(ratio * 100.0))


## Changes each hook indicator color to show whether that hook is attached.
func _on_hooks_changed(left_attached: bool, right_attached: bool) -> void:
	if left_hook_indicator:
		left_hook_indicator.active = left_attached
	if right_hook_indicator:
		right_hook_indicator.active = right_attached


func _on_reel_mode_changed(enabled: bool) -> void:
	if reel_icon:
		reel_icon.reel_enabled = enabled
	if reel_status:
		reel_status.text = "REEL ON" if enabled else "REEL OFF"
		reel_status.modulate = Color(0.85, 0.8, 0.65) if enabled else Color(0.85, 0.25, 0.18)
