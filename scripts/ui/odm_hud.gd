extends CanvasLayer
## Minimal ODM HUD: gas bar + left/right hook indicators + aim reticle.

@onready var gas_bar: ProgressBar = %GasBar
@onready var gas_label: Label = %GasLabel
@onready var left_hook_indicator: ColorRect = %LeftHook
@onready var right_hook_indicator: ColorRect = %RightHook
@onready var reticle: Control = %Reticle
@onready var hint_label: Label = %HintLabel

var _odm: ODMController


func bind_odm(odm: ODMController) -> void:
	if _odm:
		if _odm.gas_changed.is_connected(_on_gas_changed):
			_odm.gas_changed.disconnect(_on_gas_changed)
		if _odm.hooks_changed.is_connected(_on_hooks_changed):
			_odm.hooks_changed.disconnect(_on_hooks_changed)
	_odm = odm
	if _odm == null:
		return
	_odm.gas_changed.connect(_on_gas_changed)
	_odm.hooks_changed.connect(_on_hooks_changed)
	_on_gas_changed(_odm.get_gas(), _odm.get_gas_max())
	_on_hooks_changed(_odm.left_attached(), _odm.right_attached())


func _on_gas_changed(current: float, maximum: float) -> void:
	if gas_bar:
		gas_bar.max_value = maximum
		gas_bar.value = current
	if gas_label:
		gas_label.text = "GAS %d%%" % int(round((current / maxf(maximum, 1.0)) * 100.0))


func _on_hooks_changed(left_attached: bool, right_attached: bool) -> void:
	if left_hook_indicator:
		left_hook_indicator.color = Color(0.2, 0.85, 0.35) if left_attached else Color(0.25, 0.25, 0.28, 0.7)
	if right_hook_indicator:
		right_hook_indicator.color = Color(0.2, 0.85, 0.35) if right_attached else Color(0.25, 0.25, 0.28, 0.7)
