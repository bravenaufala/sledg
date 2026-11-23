extends Area3D

@export var boost_multiplier: float = 1.35
@export var boost_duration: float = 1.6
@export var instant_speed_add: float = 8.0
@export var fov_kick: float = 12.0

var _triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _triggered:
		return
	if body.has_method("trigger_boost_pad"):
		_triggered = true
		body.trigger_boost_pad(boost_multiplier, boost_duration, instant_speed_add, fov_kick)
