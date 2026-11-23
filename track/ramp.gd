extends Area3D

@export var launch_upward_speed: float = 8.5
@export var launch_forward_boost: float = 4.5

var _triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _triggered:
		return
	if body.has_method("launch_from_ramp"):
		_triggered = true
		body.launch_from_ramp(launch_upward_speed, launch_forward_boost)
