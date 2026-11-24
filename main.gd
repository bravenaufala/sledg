extends Node3D

enum RunState { RUNNING, GAME_OVER }

const SPAWN_POS := Vector3(0.0, 1.2, -4.0)
const FLOATING_ORIGIN_THRESHOLD := 2500.0
const BIOME_ALPINE := preload("res://data/alpine_ice.tres")
const BIOME_AUTUMN := preload("res://data/autumn_canyon.tres")
const BIOME_MIDNIGHT := preload("res://data/midnight_glacier.tres")

@export var biome_cycle_distance: float = 1500.0
@export var sky_lerp_speed: float = 2.5

var run_state: RunState = RunState.RUNNING
var total_distance: float = 0.0
var bonus_points: int = 0
var score: int = 0
var _last_shield_count: int = 0
var biomes: Array[BiomeData] = []
var current_biome_index: int = 0
var target_sky_top_color: Color = Color(0.23, 0.41, 0.60)
var target_sky_horizon_color: Color = Color(0.66, 0.80, 0.88)

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var track_spawner: Node3D = $TrackSpawner
@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	biomes = [BIOME_ALPINE, BIOME_AUTUMN, BIOME_MIDNIGHT]
	if player:
		player.crashed.connect(_on_player_crashed)
		player.near_miss_scored.connect(_on_near_miss_scored)
		player.boost_activated.connect(_on_boost_activated)
		player.powerup_changed.connect(_on_player_powerup_changed)
	if hud:
		hud.restart_requested.connect(start_new_run)
	start_new_run()


func _physics_process(delta: float) -> void:
	var sky_mat := _get_sky_material()
	if sky_mat:
		var sky_t := 1.0 - exp(-sky_lerp_speed * delta)
		sky_mat.sky_top_color = sky_mat.sky_top_color.lerp(target_sky_top_color, sky_t)
		sky_mat.sky_horizon_color = sky_mat.sky_horizon_color.lerp(target_sky_horizon_color, sky_t)
		sky_mat.ground_horizon_color = sky_mat.ground_horizon_color.lerp(target_sky_horizon_color, sky_t)

	if run_state == RunState.RUNNING:
		total_distance += player.downhill_speed * delta
		score = int(total_distance) + bonus_points
		if not biomes.is_empty():
			var desired_biome_idx: int = int(total_distance / biome_cycle_distance) % biomes.size()
			if desired_biome_idx != current_biome_index:
				set_active_biome(desired_biome_idx, true)
		if hud:
			hud.update_score(score, int(total_distance), bonus_points)
			hud.update_speed_effect(player.downhill_speed, player.boost_stacks)
		if track_spawner:
			track_spawner.update_spawner(player.global_position, total_distance)
		if player and player.global_position.length() > FLOATING_ORIGIN_THRESHOLD:
			var offset := player.global_position
			player.shift_origin(offset)
			if track_spawner:
				track_spawner.shift_origin(offset)
	elif Input.is_action_just_pressed("ui_accept"):
		start_new_run()


func _get_sky_material() -> ProceduralSkyMaterial:
	if world_env and world_env.environment and world_env.environment.sky:
		return world_env.environment.sky.sky_material as ProceduralSkyMaterial
	return null


func set_active_biome(index: int, announce: bool = true) -> void:
	if biomes.is_empty():
		return
	current_biome_index = posmod(index, biomes.size())
	var biome: BiomeData = biomes[current_biome_index]
	if biome == null:
		return
	if track_spawner and track_spawner.has_method("set_biome"):
		track_spawner.set_biome(biome, true)
	if player:
		player.ice_friction = biome.ice_friction
	target_sky_top_color = biome.sky_top_color
	target_sky_horizon_color = biome.sky_horizon_color
	if not announce:
		var sky_mat := _get_sky_material()
		if sky_mat:
			sky_mat.sky_top_color = target_sky_top_color
			sky_mat.sky_horizon_color = target_sky_horizon_color
			sky_mat.ground_horizon_color = target_sky_horizon_color
	elif hud:
		hud.show_status("ENTERING: %s" % biome.display_name, 2.2)


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
	if biomes.is_empty():
		biomes = [BIOME_ALPINE, BIOME_AUTUMN, BIOME_MIDNIGHT]
	total_distance = 0.0
	bonus_points = 0
	score = 0
	_last_shield_count = 0
	run_state = RunState.RUNNING
	set_active_biome(0, false)
	if track_spawner:
		track_spawner.reset_track()
	if player:
		player.reset_to_start(Transform3D(Basis.IDENTITY, SPAWN_POS))
	if hud:
		hud.hide_game_over()
		hud.reset_powerups()
		hud.show_status("", 0.0)
		hud.update_score(0, 0, 0)
