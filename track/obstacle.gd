extends Area3D

@export var near_miss_points: int = 25

var hit_player: bool = false
var near_miss_awarded: bool = false

@onready var near_miss_zone: Area3D = $NearMissZone


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if near_miss_zone:
		near_miss_zone.body_exited.connect(_on_near_miss_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("on_obstacle_hit"):
		hit_player = true
		body.on_obstacle_hit(self)


func _on_near_miss_body_exited(body: Node3D) -> void:
	if hit_player or near_miss_awarded:
		return
	if body.get("is_active") and not body.get("is_crashed") and body.has_method("register_near_miss"):
		near_miss_awarded = true
		body.register_near_miss(near_miss_points)


func shatter() -> void:
	queue_free()
