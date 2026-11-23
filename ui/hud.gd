extends CanvasLayer

signal restart_requested()

@onready var score_label: Label = $ScoreLabel
@onready var powerup_label: Label = $PowerUpLabel
@onready var status_label: Label = $StatusLabel
@onready var game_over_panel: Control = $GameOverPanel
@onready var final_score_label: Label = $GameOverPanel/VBox/FinalScoreLabel
@onready var restart_button: Button = $GameOverPanel/VBox/RestartButton

var _last_displayed_score: int = -1
var _last_displayed_bonus: int = -1
var _status_timer: float = 0.0
var _shield_active: bool = false
var _boost_active: bool = false
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


func show_status(text: String, duration: float = 1.5) -> void:
	if status_label:
		status_label.text = text
	_status_timer = duration


func set_powerup_status(id: StringName, active: bool, remaining: float) -> void:
	if id == &"shield":
		_shield_active = active
	elif id == &"boost":
		_boost_active = active
		_boost_remaining = remaining if active else 0.0
	_refresh_powerup_label()


func reset_powerups() -> void:
	_shield_active = false
	_boost_active = false
	_boost_remaining = 0.0
	_refresh_powerup_label()


func _refresh_powerup_label() -> void:
	if not powerup_label:
		return
	var parts: Array[String] = []
	if _shield_active:
		parts.append("SHIELD: ACTIVE")
	if _boost_active:
		parts.append("BOOST: %.1fs" % _boost_remaining)
	powerup_label.text = "  |  ".join(parts)


func show_game_over(final_score: int, distance_m: int, bonus: int) -> void:
	if final_score_label:
		final_score_label.text = "Score: %d (%dm + %d bonus)" % [final_score, distance_m, bonus]
	if game_over_panel:
		game_over_panel.visible = true
	if restart_button:
		restart_button.grab_focus()


func hide_game_over() -> void:
	if game_over_panel:
		game_over_panel.visible = false


func _on_restart_pressed() -> void:
	restart_requested.emit()
