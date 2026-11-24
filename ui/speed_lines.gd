extends Control

@export var line_count: int = 32
@export var inner_radius_ratio: float = 0.36
@export var outer_radius_ratio: float = 0.78
@export var line_color: Color = Color(0.88, 0.96, 1.0, 0.65)
@export var fade_speed: float = 7.0

var intensity: float = 0.0
var _target_intensity: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_speed_intensity(target: float) -> void:
	_target_intensity = clampf(target, 0.0, 1.0)


func _process(delta: float) -> void:
	var t := 1.0 - exp(-fade_speed * delta)
	intensity = lerpf(intensity, _target_intensity, t)
	if intensity > 0.01:
		_time += delta * (4.0 + intensity * 6.0)
		queue_redraw()
	elif intensity > 0.0:
		intensity = 0.0
		queue_redraw()


func _draw() -> void:
	if intensity <= 0.01:
		return
	var rect_size := size
	if rect_size.x <= 1.0 or rect_size.y <= 1.0:
		return
	var center := rect_size * 0.5
	var max_dim := maxf(rect_size.x, rect_size.y)
	var base_inner := max_dim * inner_radius_ratio
	var base_outer := max_dim * outer_radius_ratio

	for i in line_count:
		var angle := (TAU * float(i)) / float(line_count) + sin(float(i) * 1.73) * 0.03
		var pulse := 0.5 + 0.5 * sin(_time * 2.2 + float(i) * 2.31)
		var dir := Vector2(cos(angle), sin(angle))
		var inner_r := base_inner + (1.0 - pulse) * max_dim * 0.12 - intensity * max_dim * 0.05
		var outer_r := base_outer + pulse * max_dim * 0.08
		var alpha := line_color.a * intensity * (0.35 + 0.65 * pulse)
		var col := Color(line_color.r, line_color.g, line_color.b, alpha)
		var width := 1.5 + intensity * (1.2 + pulse * 1.6)
		draw_line(center + dir * inner_r, center + dir * outer_r, col, width, true)
