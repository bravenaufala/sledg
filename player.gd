extends CharacterBody3D

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

var downhill_speed: float = 0.0
var lateral_speed: float = 0.0

@onready var visual: Node3D = $SledVisual
@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	floor_stop_on_slope = false
	floor_max_angle = deg_to_rad(60.0)
	wall_min_slide_angle = 0.0
	if cam:
		cam.top_level = true
		cam.global_position = global_position + camera_offset
		cam.look_at(global_position + camera_look_ahead, Vector3.UP)


func _physics_process(delta: float) -> void:
	var steer_input := Input.get_axis("steer_left", "steer_right")
	if is_zero_approx(steer_input):
		steer_input = Input.get_axis("ui_left", "ui_right")

	lateral_speed = move_toward(lateral_speed, steer_input * steer_speed, steer_accel * delta)

	if is_on_floor():
		var floor_normal := get_floor_normal()
		var slope_vec := get_gravity().slide(floor_normal)
		var slope_dir := slope_vec.normalized()
		if slope_dir.is_zero_approx():
			slope_dir = Vector3.FORWARD
		downhill_speed += slope_vec.length() * slope_gravity_scale * delta
		downhill_speed *= maxf(0.0, 1.0 - ice_friction * delta)
		downhill_speed = clampf(downhill_speed, 0.0, max_downhill_speed)
		velocity = slope_dir * downhill_speed + Vector3.RIGHT * lateral_speed - floor_normal * 0.25
	else:
		velocity += get_gravity() * delta
		velocity.x = lateral_speed

	move_and_slide()
	lateral_speed = velocity.x

	if visual:
		var t := 1.0 - exp(-bank_lerp_speed * delta)
		visual.rotation.z = lerp_angle(visual.rotation.z, deg_to_rad(-steer_input * max_bank_degrees), t)
		visual.rotation.y = lerp_angle(visual.rotation.y, deg_to_rad(-steer_input * max_yaw_degrees), t)
		if is_on_floor():
			var floor_normal := get_floor_normal()
			var slope_pitch := atan2(floor_normal.z, floor_normal.y)
			visual.rotation.x = lerp_angle(visual.rotation.x, slope_pitch, t)

	if cam:
		var cam_t := 1.0 - exp(-camera_follow_speed * delta)
		cam.global_position = cam.global_position.lerp(global_position + camera_offset, cam_t)
		cam.look_at(global_position + camera_look_ahead, Vector3.UP)
