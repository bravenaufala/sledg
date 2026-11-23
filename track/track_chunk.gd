extends StaticBody3D

const OBSTACLE_SCENE := preload("res://track/obstacle.tscn")
const RAMP_SCENE := preload("res://track/ramp.tscn")
const BOOST_SCENE := preload("res://track/boost_pad.tscn")

const LANE_X: Array[float] = [-4.5, -1.5, 1.5, 4.5]
const ROW_Z: Array[float] = [-22.0, -48.0, -70.0]

@export var chunk_variant: StringName = &"standard"
@export var chunk_length: float = 80.0
@export var pickup_spawn_chance: float = 0.0

var _ice_friction: float = 0.12
var _obstacle_material: Material = null

@onready var exit_marker: Marker3D = $ExitMarker
@onready var spawned_container: Node3D = $SpawnedItems
@onready var track_bed: CSGBox3D = $TrackBed
@onready var left_rail: CSGBox3D = $LeftRail
@onready var right_rail: CSGBox3D = $RightRail


func clear_spawned_items() -> void:
	if not spawned_container:
		return
	for child in spawned_container.get_children():
		spawned_container.remove_child(child)
		child.queue_free()


func populate_chunk(difficulty: float, safe_chunk: bool = false, rng: RandomNumberGenerator = null, chunk_index: int = 0) -> void:
	clear_spawned_items()
	if not spawned_container:
		return
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	if safe_chunk:
		if chunk_index == 1:
			_spawn_item(BOOST_SCENE, Vector3(0.0, 0.0, -50.0))
		return

	if chunk_variant == &"ramp_barrier":
		_populate_ramp_barrier(difficulty, rng)
	else:
		_populate_standard(difficulty, rng)


func _populate_standard(difficulty: float, rng: RandomNumberGenerator) -> void:
	var max_obstacles := clampi(1 + int(difficulty * 2.5), 1, 3)
	for row_idx in ROW_Z.size():
		var z_pos := ROW_Z[row_idx]
		var lanes: Array[int] = [0, 1, 2, 3]
		_shuffle_ints(lanes, rng)
		var obstacle_count := rng.randi_range(1, max_obstacles)
		for i in obstacle_count:
			var lane_x := LANE_X[lanes[i]]
			var obs := _spawn_item(OBSTACLE_SCENE, Vector3(lane_x, 0.0, z_pos))
			_apply_obstacle_material(obs)

		if row_idx < 2:
			var open_lane_x := LANE_X[lanes[obstacle_count]]
			var roll := rng.randf()
			if roll < 0.35:
				_spawn_item(BOOST_SCENE, Vector3(open_lane_x, 0.0, z_pos))
			elif roll < 0.60:
				_spawn_item(RAMP_SCENE, Vector3(open_lane_x, 0.0, z_pos))


func _populate_ramp_barrier(difficulty: float, rng: RandomNumberGenerator) -> void:
	_spawn_item(BOOST_SCENE, Vector3(-1.5, 0.0, -18.0))
	_spawn_item(BOOST_SCENE, Vector3(1.5, 0.0, -18.0))

	for ramp_x in [-4.5, -1.5, 1.5]:
		_spawn_item(RAMP_SCENE, Vector3(ramp_x, 0.0, -36.0))

	for barrier_x in [-4.5, -1.5, 1.5]:
		var obs := _spawn_item(OBSTACLE_SCENE, Vector3(barrier_x, 0.0, -46.0))
		_apply_obstacle_material(obs)

	var lanes: Array[int] = [0, 1, 2, 3]
	_shuffle_ints(lanes, rng)
	var post_count := 1 if difficulty < 0.5 else 2
	for i in post_count:
		var obs := _spawn_item(OBSTACLE_SCENE, Vector3(LANE_X[lanes[i]], 0.0, -68.0))
		_apply_obstacle_material(obs)


func _spawn_item(scene: PackedScene, local_pos: Vector3) -> Node3D:
	var item := scene.instantiate() as Node3D
	spawned_container.add_child(item)
	item.position = local_pos
	return item


func _apply_obstacle_material(obs: Node3D) -> void:
	if _obstacle_material == null or obs == null:
		return
	var visual := obs.get_node_or_null("Visual") as GeometryInstance3D
	if visual:
		visual.material_override = _obstacle_material


func _shuffle_ints(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func configure_for_biome(biome: BiomeData) -> void:
	if biome == null:
		return
	_ice_friction = biome.ice_friction
	_obstacle_material = biome.obstacle_material
	if biome.track_material and track_bed:
		track_bed.material_override = biome.track_material
	if biome.rail_material:
		if left_rail:
			left_rail.material_override = biome.rail_material
		if right_rail:
			right_rail.material_override = biome.rail_material


func get_ice_friction() -> float:
	return _ice_friction
