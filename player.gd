extends CharacterBody3D

signal crashed()
signal near_miss_scored(points: int)
signal boost_activated(duration: float)
signal powerup_changed(id: StringName, active: bool, remaining: float)

@export var slope_gravity_scale: float = 2.5
@export var max_downhill_speed: float = 28.0
@export var ice_friction: float = 0.12
@export var steer_speed: float = 10.0
@export var steer_accel: float = 14.0
@export var max_bank_degrees: float = 18.0
@export var max_yaw_degrees: float = 10.0
@export var bank_lerp_speed: float = 10.0
@export var camera_follow_speed: float = 8.0
@export var camera_offset: Vector3 = Vector3(0.0, 4.2, 6.5)
@export var camera_look_ahead: Vector3 = Vector3(0.0, -0.5, -6.0)
@export var fov_lerp_speed: float = 6.0

var is_active: bool = true
var is_crashed: bool = false
var downhill_speed: float = 0.0
var lateral_speed: float = 0.0
var airborne_grace_timer: float = 0.0
var was_on_floor: bool = false

var boost_timer: float = 0.0
var boost_multiplier: float = 1.0
var base_fov: float = 75.0
var target_fov_bonus: float = 0.0

var has_shield: bool = false
var speed_multiplier: float = 1.0
var _powerup_timer: float = 0.0
var _active_powerup_id: StringName = &""

@onready var visual: Node3D = $SledVisual
@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	floor_stop_on_slope = false
	floor_max_angle = deg_to_rad(60.0)
	wall_min_slide_angle = 0.0
	floor_snap_length = 0.15
	if cam:
		base_fov = cam.fov
		cam.top_level = true
		cam.global_position = global_position + camera_offset
		cam.look_at(global_position + camera_look_ahead, Vector3.UP)


func _physics_process(delta: float) -> void:
	if cam:
		var fov_t := 1.0 - exp(-fov_lerp_speed * delta)
		cam.fov = lerpf(cam.fov, base_fov + target_fov_bonus, fov_t)

	if not is_active:
		if cam:
			var cam_t := 1.0 - exp(-camera_follow_speed * delta)
			cam.global_position = cam.global_position.lerp(global_position + camera_offset, cam_t)
			cam.look_at(global_position + camera_look_ahead, Vector3.UP)
		return

	if airborne_grace_timer > 0.0:
		airborne_grace_timer = maxf(0.0, airborne_grace_timer - delta)

	if boost_timer > 0.0:
		boost_timer = maxf(0.0, boost_timer - delta)
		if boost_timer <= 0.0:
			boost_multiplier = 1.0
			target_fov_bonus = 0.0

	if _powerup_timer > 0.0:
		_powerup_timer = maxf(0.0, _powerup_timer - delta)
		if _powerup_timer <= 0.0:
			speed_multiplier = 1.0
			var expired_id := _active_powerup_id
			_active_powerup_id = &""
			if not expired_id.is_empty():
				powerup_changed.emit(expired_id, false, 0.0)

	var steer_input := Input.get_axis("steer_left", "steer_right")
	if is_zero_approx(steer_input):
		steer_input = Input.get_axis("ui_left", "ui_right")

	lateral_speed = move_toward(lateral_speed, steer_input * steer_speed, steer_accel * delta)

	var effective_max := max_downhill_speed * _effective_speed_mult()
	var grounded := is_on_floor() and airborne_grace_timer <= 0.0

	if grounded:
		floor_snap_length = 0.15
		if not was_on_floor:
			downhill_speed = clampf(maxf(downhill_speed, Vector2(velocity.y, velocity.z).length()), 0.0, effective_max)
		var floor_normal := get_floor_normal()
		var slope_vec := get_gravity().slide(floor_normal)
		var slope_dir := slope_vec.normalized()
		if slope_dir.is_zero_approx():
			slope_dir = Vector3.FORWARD
		downhill_speed += slope_vec.length() * slope_gravity_scale * delta
		downhill_speed *= maxf(0.0, 1.0 - ice_friction * delta)
		downhill_speed = clampf(downhill_speed, 0.0, effective_max)
		velocity = slope_dir * downhill_speed + Vector3.RIGHT * lateral_speed - floor_normal * 0.25
	else:
		velocity += get_gravity() * delta
		velocity.x = lateral_speed

	was_on_floor = grounded
	move_and_slide()
	lateral_speed = velocity.x

	if visual:
		var t := 1.0 - exp(-bank_lerp_speed * delta)
		visual.rotation.z = lerp_angle(visual.rotation.z, deg_to_rad(-steer_input * max_bank_degrees), t)
		visual.rotation.y = lerp_angle(visual.rotation.y, deg_to_rad(-steer_input * max_yaw_degrees), t)
		if grounded:
			var floor_normal := get_floor_normal()
			var slope_pitch := atan2(floor_normal.z, floor_normal.y)
			visual.rotation.x = lerp_angle(visual.rotation.x, slope_pitch, t)
		else:
			var horiz := maxf(0.1, -velocity.z)
			var air_pitch := clampf(atan2(velocity.y, horiz), deg_to_rad(-35.0), deg_to_rad(30.0))
			visual.rotation.x = lerp_angle(visual.rotation.x, air_pitch, t)

	if cam:
		var cam_t := 1.0 - exp(-camera_follow_speed * delta)
		cam.global_position = cam.global_position.lerp(global_position + camera_offset, cam_t)
		cam.look_at(global_position + camera_look_ahead, Vector3.UP)


func _effective_speed_mult() -> float:
	return boost_multiplier * speed_multiplier


func launch_from_ramp(upward_speed: float = 8.5, forward_boost: float = 4.5) -> void:
	if not is_active or is_crashed:
		return
	airborne_grace_timer = 0.25
	floor_snap_length = 0.0
	was_on_floor = false
	var effective_max := max_downhill_speed * _effective_speed_mult()
	downhill_speed = minf(effective_max, downhill_speed + forward_boost)
	var slope_pitch := deg_to_rad(-16.0)
	var forward_dir := Vector3(0.0, sin(slope_pitch), -cos(slope_pitch)).normalized()
	velocity = forward_dir * downhill_speed + Vector3(lateral_speed, upward_speed, 0.0)


func trigger_boost_pad(mult: float = 1.35, duration: float = 1.6, instant_add: float = 8.0, fov_kick: float = 12.0) -> void:
	if not is_active or is_crashed:
		return
	boost_timer = maxf(boost_timer, duration)
	boost_multiplier = maxf(boost_multiplier, mult)
	target_fov_bonus = maxf(target_fov_bonus, fov_kick)
	var effective_max := max_downhill_speed * _effective_speed_mult()
	downhill_speed = minf(effective_max, downhill_speed + instant_add)
	boost_activated.emit(duration)


func apply_powerup(data: PowerUpData) -> void:
	if data == null or not is_active or is_crashed:
		return
	if data.id == &"shield":
		has_shield = true
		powerup_changed.emit(&"shield", true, data.duration)
	else:
		speed_multiplier = data.speed_multiplier
		_powerup_timer = data.duration
		_active_powerup_id = data.id
		powerup_changed.emit(data.id, true, data.duration)


func on_obstacle_hit(obstacle: Node3D) -> void:
	if not is_active or is_crashed:
		return
	if has_shield:
		has_shield = false
		powerup_changed.emit(&"shield", false, 0.0)
		if obstacle and obstacle.has_method("shatter"):
			obstacle.shatter()
		return
	is_crashed = true
	is_active = false
	velocity = Vector3.ZERO
	downhill_speed = 0.0
	lateral_speed = 0.0
	target_fov_bonus = 0.0
	crashed.emit()


func register_near_miss(points: int = 25) -> void:
	if is_active and not is_crashed:
		near_miss_scored.emit(points)


func reset_to_start(start_transform: Transform3D) -> void:
	global_transform = start_transform
	is_crashed = false
	is_active = true
	downhill_speed = 0.0
	lateral_speed = 0.0
	velocity = Vector3.ZERO
	airborne_grace_timer = 0.0
	was_on_floor = false
	boost_timer = 0.0
	boost_multiplier = 1.0
	target_fov_bonus = 0.0
	has_shield = false
	speed_multiplier = 1.0
	_powerup_timer = 0.0
	_active_powerup_id = &""
	floor_snap_length = 0.15
	if visual:
		visual.rotation = Vector3.ZERO
	if cam:
		cam.fov = base_fov
		cam.global_position = global_position + camera_offset
		cam.look_at(global_position + camera_look_ahead, Vector3.UP)


func shift_origin(offset: Vector3) -> void:
	global_position -= offset
	if cam:
		cam.global_position -= offset
