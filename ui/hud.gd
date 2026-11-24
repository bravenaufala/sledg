extends CanvasLayer

signal restart_requested()

@onready var score_label: Label = $ScoreLabel
@onready var powerup_label: Label = $PowerUpLabel
@onready var status_label: Label = $StatusLabel
@onready var game_over_panel: Control = $GameOverPanel
@onready var final_score_label: Label = $GameOverPanel/VBox/FinalScoreLabel
@onready var restart_button: Button = $GameOverPanel/VBox/RestartButton
@onready var speed_lines: Control = $SpeedLinesOverlay

var _last_displayed_score: int = -1
var _last_displayed_bonus: int = -1
var _status_timer: float = 0.0
var _shield_count: int = 0
var _shields_consumed: int = 0
var _boost_active: bool = false
var _boost_stacks: int = 0
var _boost_remaining: float = 0.0


func _ready() -> void:
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if game_over_panel:
		game_over_panel.visible = false
	if status_label:
		status_label.text = ""
	if powerup_label:
		powerup_label.text = ""


func _process(delta: float) -> void:
	if _status_timer > 0.0:
		_status_timer = maxf(0.0, _status_timer - delta)
		if _status_timer <= 0.0 and status_label:
			status_label.text = ""
	if _boost_active:
		_boost_remaining = maxf(0.0, _boost_remaining - delta)
		if _boost_remaining <= 0.0:
			_boost_active = false
			_boost_stacks = 0
		_refresh_powerup_label()


func update_score(score: int, distance_m: int, bonus: int) -> void:
	if score == _last_displayed_score and bonus == _last_displayed_bonus:
		return
	_last_displayed_score = score
	_last_displayed_bonus = bonus
	if score_label:
		if bonus > 0:
			score_label.text = "SCORE: %d  (%dm + %d bonus)" % [score, distance_m, bonus]
		else:
			score_label.text = "SCORE: %d" % score


func update_speed_effect(downhill_speed: float, boost_stacks: int) -> void:
	if not speed_lines:
		return
	if downhill_speed > 45.0 or boost_stacks > 0:
		var speed_alpha := clampf((downhill_speed - 45.0) / 75.0, 0.0, 1.0)
		var boost_alpha := clampf(float(boost_stacks) * 0.28, 0.0, 1.0)
		var target := maxf(speed_alpha, boost_alpha)
		speed_lines.call("set_speed_intensity", target)
	else:
		speed_lines.call("set_speed_intensity", 0.0)


func show_status(text: String, duration: float = 1.5) -> void:
	if status_label:
		status_label.text = text
	_status_timer = duration


func set_powerup_status(
	id: StringName,
	active: bool,
	remaining: float,
	shield_count: int = 0,
	shields_consumed: int = 0,
	boost_stacks: int = 0
) -> void:
	_shield_count = shield_count
	_shields_consumed = shields_consumed
	if id == &"boost":
		_boost_active = active and boost_stacks > 0
		_boost_stacks = boost_stacks if active else 0
		_boost_remaining = remaining if active else 0.0
	_refresh_powerup_label()


func reset_powerups() -> void:
	_shield_count = 0
	_shields_consumed = 0
	_boost_active = false
	_boost_stacks = 0
	_boost_remaining = 0.0
	_refresh_powerup_label()
	update_speed_effect(0.0, 0)


func _refresh_powerup_label() -> void:
	if not powerup_label:
		return
	var parts: Array[String] = []
	if _shield_count > 0 or _shields_consumed > 0:
		parts.append("SHIELDS: x%d" % _shield_count)
		parts.append("USED: %d" % _shields_consumed)
	if _boost_active and _boost_stacks > 0:
		parts.append("BOOST x%d: %.1fs" % [_boost_stacks, _boost_remaining])
	powerup_label.text = "  |  ".join(parts)


func show_game_over(final_score: int, distance_m: int, bonus: int, shields_used: int = 0) -> void:
	update_speed_effect(0.0, 0)
	if final_score_label:
		final_score_label.text = "Score: %d (%dm + %d bonus | Shields Used: %d)" % [
			final_score,
			distance_m,
			bonus,
			shields_used,
		]
	if game_over_panel:
		game_over_panel.visible = true
	if restart_button:
		restart_button.grab_focus()


func hide_game_over() -> void:
	if game_over_panel:
		game_over_panel.visible = false


func _on_restart_pressed() -> void:
	restart_requested.emit()
