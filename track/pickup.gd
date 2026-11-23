extends Area3D

@export var powerup_data: PowerUpData
@export var spin_speed: float = 2.6
@export var bob_amplitude: float = 0.22
@export var bob_frequency: float = 3.2

var _time: float = 0.0
var _base_visual_y: float = 0.85
var _collected: bool = false

@onready var visual: Node3D = $Visual


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if visual:
		_base_visual_y = visual.position.y
	_apply_visual_tint()


func _process(delta: float) -> void:
	_time += delta
	if visual:
		visual.rotation.y += spin_speed * delta
		visual.position.y = _base_visual_y + sin(_time * bob_frequency) * bob_amplitude


func configure_powerup(data: PowerUpData) -> void:
	powerup_data = data
	_apply_visual_tint()


func _apply_visual_tint() -> void:
	if powerup_data == null or visual == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = powerup_data.accent_color
	mat.emission_enabled = true
	mat.emission = powerup_data.accent_color
	mat.emission_energy_multiplier = 0.45
	mat.roughness = 0.15
	mat.metallic = 0.25
	for child in visual.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).material_override = mat


func _on_body_entered(body: Node3D) -> void:
	if _collected:
		return
	if body.has_method("apply_powerup") and powerup_data != null:
		_collected = true
		body.apply_powerup(powerup_data)
		queue_free()
