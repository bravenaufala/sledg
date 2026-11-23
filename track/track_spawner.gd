extends Node3D

const DEFAULT_STANDARD_CHUNK := preload("res://track/track_chunk.tscn")
const DEFAULT_RAMP_CHUNK := preload("res://track/track_chunk_ramp.tscn")

@export var chunk_variants: Array[PackedScene] = []
@export var active_chunk_count: int = 6
@export var safe_start_chunks: int = 2
@export var recycle_behind_distance: float = 35.0
@export var slope_angle_deg: float = -16.0
@export var current_biome: BiomeData

var active_chunks: Array[Node3D] = []
var total_chunks_spawned: int = 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	if chunk_variants.is_empty():
		chunk_variants = [DEFAULT_STANDARD_CHUNK, DEFAULT_RAMP_CHUNK]


func reset_track() -> void:
	for chunk in active_chunks:
		if is_instance_valid(chunk):
			chunk.queue_free()
	active_chunks.clear()
	total_chunks_spawned = 0

	if chunk_variants.is_empty():
		chunk_variants = [DEFAULT_STANDARD_CHUNK, DEFAULT_RAMP_CHUNK]

	for i in active_chunk_count:
		_spawn_next_chunk(0.0)


func update_spawner(player_pos: Vector3, distance_traveled: float) -> void:
	if active_chunks.is_empty():
		return
	var difficulty := clampf(distance_traveled / 1200.0, 0.15, 1.0)
	while active_chunks.size() > 0:
		var front := active_chunks[0]
		var exit_marker := front.get_node_or_null("ExitMarker") as Marker3D
		if exit_marker == null:
			break
		if exit_marker.global_position.z - player_pos.z <= recycle_behind_distance:
			break
		active_chunks.pop_front()
		front.queue_free()
		_spawn_next_chunk(difficulty)


func _spawn_next_chunk(difficulty: float) -> void:
	var scene := _pick_chunk_scene(total_chunks_spawned)
	var chunk := scene.instantiate() as Node3D
	add_child(chunk)

	if active_chunks.is_empty():
		var pitch := deg_to_rad(current_biome.slope_angle_deg if current_biome else slope_angle_deg)
		chunk.global_transform = Transform3D(Basis(Vector3.RIGHT, pitch), Vector3.ZERO)
	else:
		var tail: Node3D = active_chunks.back()
		var exit_marker := tail.get_node("ExitMarker") as Marker3D
		chunk.global_transform = exit_marker.global_transform

	if current_biome and chunk.has_method("configure_for_biome"):
		chunk.configure_for_biome(current_biome)

	var is_safe := total_chunks_spawned < safe_start_chunks
	if chunk.has_method("populate_chunk"):
		chunk.populate_chunk(difficulty, is_safe, rng, total_chunks_spawned)

	active_chunks.append(chunk)
	total_chunks_spawned += 1


func _pick_chunk_scene(index: int) -> PackedScene:
	if current_biome and not current_biome.chunk_variants.is_empty():
		var list := current_biome.chunk_variants
		return list[index % list.size()]
	if index < safe_start_chunks:
		return chunk_variants[0]
	if chunk_variants.size() >= 2 and index % 3 == 2:
		return chunk_variants[1]
	return chunk_variants[0]


func shift_origin(offset: Vector3) -> void:
	for chunk in active_chunks:
		if is_instance_valid(chunk):
			chunk.global_position -= offset
