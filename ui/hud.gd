extends CanvasLayer

signal restart_requested()

@onready var score_label: Label = $ScoreLabel
@onready var status_label: Label = $StatusLabel
@onready var game_over_panel: Control = $GameOverPanel
@onready var final_score_label: Label = $GameOverPanel/VBox/FinalScoreLabel
@onready var restart_button: Button = $GameOverPanel/VBox/RestartButton

var _last_displayed_score: int = -1
var _last_displayed_bonus: int = -1
var _status_timer: float = 0.0


func _ready() -> void:
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if game_over_panel:
		game_over_panel.visible = false
	if status_label:
		status_label.text = ""


func _process(delta: float) -> void:
	if _status_timer > 0.0:
		_status_timer = maxf(0.0, _status_timer - delta)
		if _status_timer <= 0.0 and status_label:
			status_label.text = ""


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
