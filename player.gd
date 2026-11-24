extends CharacterBody3D

signal crashed()
signal near_miss_scored(points: int)
signal boost_activated(duration: float)
signal powerup_changed(id: StringName, active: bool, remaining: float)

const BASE_SPRAY_VEL_MIN := 2.5
const BASE_SPRAY_VEL_MAX := 5.5
const BASE_SPRAY_SPREAD := 28.0

@export var slope_gravity_scale: float = 2.5
@export var max_downhill_speed: float = 28.0
@export var safety_speed_ceiling: float = 150.0
@export var boost_stack_base: float = 1.25
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
@export var max_camera_roll_degrees: float = 4.5
@export var camera_roll_lerp_speed: float = 7.0
@export var landing_dip_strength: float = 0.55
@export var landing_spring_stiffness: float = 42.0
@export var landing_spring_damping: float = 9.5
@export var min_fov: float = 70.0
@export var max_fov: float = 98.0

var is_active: bool = true
var is_crashed: bool = false
var downhill_speed: float = 0.0
var lateral_speed: float = 0.0
var airborne_grace_timer: float = 0.0
var was_on_floor: bool = false

var boost_timer: float = 0.0
var boost_multiplier: float = 1.0
var base_fov: float = 70.0

var shield_count: int = 0
var shields_consumed: int = 0
var boost_stacks: int = 0
var speed_multiplier: float = 1.0
var _powerup_timer: float = 0.0
var _active_powerup_id: StringName = &""

var _camera_roll_rad: float = 0.0
var _camera_dip_offset: float = 0.0
var _camera_dip_velocity: float = 0.0
var _air_time: float = 0.0
var _prev_vertical_velocity: float = 0.0
var _spray_mat: ParticleProcessMaterial = null

@onready var visual: Node3D = $SledVisual
@onready var cam: Camera3D = $Camera3D
@onready var snow_spray: GPUParticles3D = $SledVisual/SnowSpray


func _ready() -> void:
	floor_stop_on_slope = false
	floor_max_angle = deg_to_rad(60.0)
	wall_min_slide_angle = 0.0
	floor_snap_length = 0.15
	if snow_spray:
		_spray_mat = snow_spray.process_material as ParticleProcessMaterial
	if cam:
		base_fov = min_fov
		cam.fov = min_fov
		cam.top_level = true
		cam.global_position = global_position + camera_offset
		cam.look_at(global_position + camera_look_ahead, Vector3.UP)


func _physics_process(delta: float) -> void:
	var spring_accel := -landing_spring_stiffness * _camera_dip_offset - landing_spring_damping * _camera_dip_velocity
	_camera_dip_velocity += spring_accel * delta
	_camera_dip_offset = clampf(_camera_dip_offset + _camera_dip_velocity * delta, -0.85, 0.35)

	if cam:
		var desired_fov := min_fov
		if is_active and not is_crashed:
			var speed_factor := clampf(
				(downhill_speed - max_downhill_speed) / maxf(1.0, safety_speed_ceiling - max_downhill_speed),
				0.0,
				1.0
			)
			var stack_factor := clampf(float(boost_stacks) / 5.0, 0.0, 1.0)
			var pad_factor := 0.22 if boost_timer > 0.0 else 0.0
			var fov_alpha := clampf(maxf(speed_factor, stack_factor * 0.85) + pad_factor, 0.0, 1.0)
			desired_fov = lerpf(min_fov, max_fov, fov_alpha)
		var fov_t := 1.0 - exp(-fov_lerp_speed * delta)
		cam.fov = lerpf(cam.fov, desired_fov, fov_t)

	if not is_active:
		if snow_spray:
			snow_spray.emitting = false
		if cam:
			var roll_t := 1.0 - exp(-camera_roll_lerp_speed * delta)
			_camera_roll_rad = lerp_angle(_camera_roll_rad, 0.0, roll_t)
			var cam_t := 1.0 - exp(-camera_follow_speed * delta)
			var target_pos := global_position + camera_offset + Vector3(0.0, _camera_dip_offset, 0.0)
			cam.global_position = cam.global_position.lerp(target_pos, cam_t)
			cam.look_at(global_position + camera_look_ahead + Vector3(0.0, _camera_dip_offset * 0.4, 0.0), Vector3.UP)
			cam.rotate_object_local(Vector3.BACK, _camera_roll_rad)
		return

	if airborne_grace_timer > 0.0:
		airborne_grace_timer = maxf(0.0, airborne_grace_timer - delta)

	if boost_timer > 0.0:
		boost_timer = maxf(0.0, boost_timer - delta)
		if boost_timer <= 0.0:
			boost_multiplier = 1.0

	if _powerup_timer > 0.0:
		_powerup_timer = maxf(0.0, _powerup_timer - delta)
		if _powerup_timer <= 0.0:
			boost_stacks = 0
			speed_multiplier = 1.0
			var expired_id := _active_powerup_id
			_active_powerup_id = &""
			if not expired_id.is_empty():
				powerup_changed.emit(expired_id, false, 0.0)

	var steer_input := Input.get_axis("steer_left", "steer_right")
	if is_zero_approx(steer_input):
		steer_input = Input.get_axis("ui_left", "ui_right")

	var speed_ratio := clampf(downhill_speed / maxf(1.0, max_downhill_speed), 1.0, 3.5)
	var current_steer_speed := steer_speed * (1.0 + (speed_ratio - 1.0) * 0.35)
	var current_steer_accel := steer_accel * (1.0 + (speed_ratio - 1.0) * 0.45)
	lateral_speed = move_toward(lateral_speed, steer_input * current_steer_speed, current_steer_accel * delta)

	var grounded := is_on_floor() and airborne_grace_timer <= 0.0

	if grounded:
		floor_snap_length = 0.15
		if not was_on_floor:
			downhill_speed = clampf(maxf(downhill_speed, Vector2(velocity.y, velocity.z).length()), 0.0, safety_speed_ceiling)
			if _air_time > 0.12:
				var impact := clampf(absf(_prev_vertical_velocity) / 16.0, 0.35, 1.35)
				_camera_dip_velocity -= landing_dip_strength * impact * 7.5
			_air_time = 0.0
		var floor_normal := get_floor_normal()
		var slope_vec := get_gravity().slide(floor_normal)
		var slope_dir := slope_vec.normalized()
		if slope_dir.is_zero_approx():
			slope_dir = Vector3.FORWARD
		var mult := _effective_speed_mult()
		var effective_friction := ice_friction / maxf(1.0, mult * 0.6)
		downhill_speed += slope_vec.length() * slope_gravity_scale * mult * delta
		downhill_speed *= maxf(0.0, 1.0 - effective_friction * delta)
		downhill_speed = clampf(downhill_speed, 0.0, safety_speed_ceiling)
		velocity = slope_dir * downhill_speed + Vector3.RIGHT * lateral_speed - floor_normal * 0.25
	else:
		_air_time += delta
		_prev_vertical_velocity = velocity.y
		velocity += get_gravity() * delta
		velocity.x = lateral_speed

	was_on_floor = grounded
	move_and_slide()
	lateral_speed = velocity.x

	var carve_ratio := clampf(lateral_speed / maxf(1.0, current_steer_speed), -1.0, 1.0)

	if snow_spray:
		var spraying := is_active and not is_crashed and grounded and downhill_speed > 2.0
		snow_spray.emitting = spraying
		if spraying:
			var speed_norm := clampf(downhill_speed / 80.0, 0.0, 1.5)
			var carve_abs := absf(carve_ratio)
			snow_spray.amount_ratio = clampf(0.45 + speed_norm * 0.4 + carve_abs * 0.35, 0.35, 1.0)
			if _spray_mat:
				_spray_mat.initial_velocity_min = BASE_SPRAY_VEL_MIN + speed_norm * 3.5 + carve_abs * 1.8
				_spray_mat.initial_velocity_max = BASE_SPRAY_VEL_MAX + speed_norm * 5.5 + carve_abs * 3.0
				_spray_mat.spread = BASE_SPRAY_SPREAD + speed_norm * 10.0 + carve_abs * 24.0
				_spray_mat.direction = Vector3(-carve_ratio * 0.55, 0.45 + carve_abs * 0.15, 1.0).normalized()

	if visual:
		var t := 1.0 - exp(-bank_lerp_speed * delta)
		visual.rotation.z = lerp_angle(visual.rotation.z, deg_to_rad(-carve_ratio * max_bank_degrees), t)
		visual.rotation.y = lerp_angle(visual.rotation.y, deg_to_rad(-carve_ratio * max_yaw_degrees), t)
		if grounded:
			var floor_normal := get_floor_normal()
			var slope_pitch := atan2(floor_normal.z, floor_normal.y)
			visual.rotation.x = lerp_angle(visual.rotation.x, slope_pitch, t)
		else:
			var horiz := maxf(0.1, -velocity.z)
			var air_pitch := clampf(atan2(velocity.y, horiz), deg_to_rad(-35.0), deg_to_rad(30.0))
			visual.rotation.x = lerp_angle(visual.rotation.x, air_pitch, t)

	if cam:
		var roll_t := 1.0 - exp(-camera_roll_lerp_speed * delta)
		_camera_roll_rad = lerp_angle(_camera_roll_rad, deg_to_rad(-carve_ratio * max_camera_roll_degrees), roll_t)
		var cam_t := 1.0 - exp(-camera_follow_speed * delta)
		var target_pos := global_position + camera_offset + Vector3(0.0, _camera_dip_offset, 0.0)
		cam.global_position = cam.global_position.lerp(target_pos, cam_t)
		cam.look_at(global_position + camera_look_ahead + Vector3(0.0, _camera_dip_offset * 0.4, 0.0), Vector3.UP)
		cam.rotate_object_local(Vector3.BACK, _camera_roll_rad)


func get_current_steer_speed() -> float:
	var speed_ratio := clampf(downhill_speed / maxf(1.0, max_downhill_speed), 1.0, 3.5)
	return steer_speed * (1.0 + (speed_ratio - 1.0) * 0.35)


func get_camera_roll_degrees() -> float:
	return rad_to_deg(_camera_roll_rad)


func get_camera_dip_offset() -> float:
	return _camera_dip_offset


func _effective_speed_mult() -> float:
	return boost_multiplier * speed_multiplier


func launch_from_ramp(base_launch_speed: float = 3.5, forward_boost: float = 4.5, ramp_angle_deg: float = 29.0) -> void:
	if not is_active or is_crashed:
		return
	airborne_grace_timer = 0.25
	floor_snap_length = 0.0
	was_on_floor = false
	downhill_speed = minf(safety_speed_ceiling, downhill_speed + forward_boost)
	var slope_pitch := deg_to_rad(-16.0)
	var forward_dir := Vector3(0.0, sin(slope_pitch), -cos(slope_pitch)).normalized()
	var ramp_tan := tan(deg_to_rad(ramp_angle_deg))
	var lift_speed := clampf(base_launch_speed + downhill_speed * ramp_tan, 9.5, 68.0)
	velocity = forward_dir * downhill_speed + Vector3(lateral_speed, lift_speed, 0.0)


func trigger_boost_pad(mult: float = 1.35, duration: float = 1.6, instant_add: float = 8.0, _fov_kick: float = 12.0) -> void:
	if not is_active or is_crashed:
		return
	boost_timer = maxf(boost_timer, duration)
	boost_multiplier = maxf(boost_multiplier, mult)
	downhill_speed = minf(safety_speed_ceiling, downhill_speed + instant_add)
	boost_activated.emit(duration)


func apply_powerup(data: PowerUpData) -> void:
	if data == null or not is_active or is_crashed:
		return
	if data.id == &"shield":
		shield_count += 1
		powerup_changed.emit(&"shield", shield_count > 0, float(shield_count))
	else:
		boost_stacks += 1
		speed_multiplier = pow(boost_stack_base, float(boost_stacks))
		_powerup_timer = maxf(_powerup_timer, data.duration)
		_active_powerup_id = data.id
		downhill_speed = minf(safety_speed_ceiling, downhill_speed + 7.0 * speed_multiplier)
		powerup_changed.emit(data.id, true, _powerup_timer)


func on_obstacle_hit(obstacle: Node3D) -> void:
	if not is_active or is_crashed:
		return
	if shield_count > 0:
		shield_count -= 1
		shields_consumed += 1
		powerup_changed.emit(&"shield", shield_count > 0, float(shield_count))
		if obstacle and obstacle.has_method("shatter"):
			obstacle.shatter()
		return
	is_crashed = true
	is_active = false
	velocity = Vector3.ZERO
	downhill_speed = 0.0
	lateral_speed = 0.0
	if snow_spray:
		snow_spray.emitting = false
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
	shield_count = 0
	shields_consumed = 0
	boost_stacks = 0
	speed_multiplier = 1.0
	_powerup_timer = 0.0
	_active_powerup_id = &""
	_camera_roll_rad = 0.0
	_camera_dip_offset = 0.0
	_camera_dip_velocity = 0.0
	_air_time = 0.0
	_prev_vertical_velocity = 0.0
	floor_snap_length = 0.15
	if snow_spray:
		snow_spray.emitting = false
		snow_spray.amount_ratio = 0.45
	if _spray_mat:
		_spray_mat.initial_velocity_min = BASE_SPRAY_VEL_MIN
		_spray_mat.initial_velocity_max = BASE_SPRAY_VEL_MAX
		_spray_mat.spread = BASE_SPRAY_SPREAD
		_spray_mat.direction = Vector3(0.0, 0.45, 1.0).normalized()
	if visual:
		visual.rotation = Vector3.ZERO
	if cam:
		cam.fov = min_fov
		cam.global_position = global_position + camera_offset
		cam.look_at(global_position + camera_look_ahead, Vector3.UP)


func shift_origin(offset: Vector3) -> void:
	global_position -= offset
	if cam:
		cam.global_position -= offset
