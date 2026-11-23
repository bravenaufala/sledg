extends Area3D

@export var base_launch_speed: float = 3.5
@export var launch_forward_boost: float = 4.5
@export var ramp_angle_deg: float = 29.0

var _triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _triggered:
		return
	if body.has_method("launch_from_ramp"):
		_triggered = true
		body.launch_from_ramp(base_launch_speed, launch_forward_boost, ramp_angle_deg)
