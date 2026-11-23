extends Node3D

enum RunState { RUNNING, GAME_OVER }

const SPAWN_POS := Vector3(0.0, 1.2, -4.0)
const FLOATING_ORIGIN_THRESHOLD := 2500.0

var run_state: RunState = RunState.RUNNING
var total_distance: float = 0.0
var bonus_points: int = 0
var score: int = 0
var _last_shield_count: int = 0

@onready var track_spawner: Node3D = $TrackSpawner
@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	if player:
		player.crashed.connect(_on_player_crashed)
		player.near_miss_scored.connect(_on_near_miss_scored)
		player.boost_activated.connect(_on_boost_activated)
		player.powerup_changed.connect(_on_player_powerup_changed)
	if hud:
		hud.restart_requested.connect(start_new_run)
	start_new_run()


func _physics_process(delta: float) -> void:
	if run_state == RunState.RUNNING:
		total_distance += player.downhill_speed * delta
		score = int(total_distance) + bonus_points
		if hud:
			hud.update_score(score, int(total_distance), bonus_points)
		if track_spawner:
			track_spawner.update_spawner(player.global_position, total_distance)
		if player and player.global_position.length() > FLOATING_ORIGIN_THRESHOLD:
			var offset := player.global_position
			player.shift_origin(offset)
			if track_spawner:
				track_spawner.shift_origin(offset)
	elif Input.is_action_just_pressed("ui_accept"):
		start_new_run()


func _on_near_miss_scored(points: int) -> void:
	if run_state != RunState.RUNNING:
		return
	bonus_points += points
	score = int(total_distance) + bonus_points
	if hud:
		hud.update_score(score, int(total_distance), bonus_points)
		hud.show_status("+%d NEAR MISS!" % points, 1.4)


func _on_boost_activated(_duration: float) -> void:
	if run_state != RunState.RUNNING:
		return
	if hud:
		hud.show_status("SPEED BOOST!", 1.2)


func _on_player_powerup_changed(id: StringName, active: bool, remaining: float) -> void:
	if hud and player:
		hud.set_powerup_status(
			id,
			active,
			remaining,
			player.shield_count,
			player.shields_consumed,
			player.boost_stacks
		)
		if id == &"shield":
			if player.shield_count > _last_shield_count:
				hud.show_status("SHIELD x%d!" % player.shield_count, 1.3)
			elif run_state == RunState.RUNNING:
				hud.show_status("SHIELD BLOCKED HIT!", 1.3)
			_last_shield_count = player.shield_count
		elif active:
			hud.show_status("BOOST x%d!" % player.boost_stacks, 1.3)


func _on_player_crashed() -> void:
	run_state = RunState.GAME_OVER
	score = int(total_distance) + bonus_points
	var shields_used: int = int(player.get("shields_consumed")) if player else 0
	if hud:
		hud.show_game_over(score, int(total_distance), bonus_points, shields_used)


func start_new_run() -> void:
	total_distance = 0.0
	bonus_points = 0
	score = 0
	_last_shield_count = 0
	run_state = RunState.RUNNING
	if track_spawner:
		track_spawner.reset_track()
	if player:
		player.reset_to_start(Transform3D(Basis.IDENTITY, SPAWN_POS))
	if hud:
		hud.hide_game_over()
		hud.reset_powerups()
		hud.show_status("", 0.0)
		hud.update_score(0, 0, 0)
