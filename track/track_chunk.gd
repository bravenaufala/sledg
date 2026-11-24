extends StaticBody3D

const OBSTACLE_SCENE := preload("res://track/obstacle.tscn")
const RAMP_SCENE := preload("res://track/ramp.tscn")
const BOOST_SCENE := preload("res://track/boost_pad.tscn")
const PICKUP_SCENE := preload("res://track/pickup.tscn")
const SHIELD_POWERUP := preload("res://data/shield_powerup.tres")
const BOOST_POWERUP := preload("res://data/boost_powerup.tres")
const WATER_ICE_SHADER := preload("res://shaders/water_ice.gdshader")

const LANE_X: Array[float] = [-4.5, -1.5, 1.5, 4.5]
const ROW_Z: Array[float] = [-22.0, -48.0, -70.0]

@export var chunk_variant: StringName = &"standard"
@export var chunk_length: float = 80.0
@export var pickup_spawn_chance: float = 0.55

var _ice_friction: float = 0.12
var _obstacle_material: Material = null
var _biome_id: String = "kyoto_ice"
var _chunk_index: int = 0
var _chunk_seed: int = 1
var _has_transition_gate: bool = false
var _water_ice_mat: ShaderMaterial = null
var _prop_mats: Dictionary = {}
var _prop_meshes: Dictionary = {}

@onready var exit_marker: Marker3D = $ExitMarker
@onready var spawned_container: Node3D = $SpawnedItems
@onready var roadside_container: Node3D = get_node_or_null("RoadsideProps") as Node3D
@onready var track_bed: CSGBox3D = $TrackBed
@onready var left_rail: CSGBox3D = $LeftRail
@onready var right_rail: CSGBox3D = $RightRail


func clear_spawned_items() -> void:
	if not spawned_container:
		return
	for child in spawned_container.get_children():
		spawned_container.remove_child(child)
		child.queue_free()


func clear_roadside_props() -> void:
	if not roadside_container:
		return
	for child in roadside_container.get_children():
		roadside_container.remove_child(child)
		child.queue_free()


func populate_chunk(difficulty: float, safe_chunk: bool = false, rng: RandomNumberGenerator = null, chunk_index: int = 0) -> void:
	clear_spawned_items()
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	_chunk_index = chunk_index
	_chunk_seed = rng.randi()

	if spawned_container:
		if safe_chunk:
			if chunk_index == 1:
				_spawn_item(BOOST_SCENE, Vector3(0.0, 0.0, -50.0))
		elif chunk_variant == &"ramp_barrier":
			_populate_ramp_barrier(difficulty, rng)
		else:
			_populate_standard(difficulty, rng)

	populate_roadside_props(_has_transition_gate)


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

		var placed_feature_in_first_open := false
		var open_lane_x := LANE_X[lanes[obstacle_count]]
		if row_idx < 2:
			var roll := rng.randf()
			if roll < 0.35:
				_spawn_item(BOOST_SCENE, Vector3(open_lane_x, 0.0, z_pos))
				placed_feature_in_first_open = true
			elif roll < 0.60:
				_spawn_item(RAMP_SCENE, Vector3(open_lane_x, 0.0, z_pos))
				placed_feature_in_first_open = true

		if not placed_feature_in_first_open:
			if rng.randf() < pickup_spawn_chance:
				_spawn_pickup(Vector3(open_lane_x, 0.0, z_pos), rng)
		elif obstacle_count + 1 < lanes.size() and rng.randf() < pickup_spawn_chance:
			var extra_lane_x := LANE_X[lanes[obstacle_count + 1]]
			_spawn_pickup(Vector3(extra_lane_x, 0.0, z_pos), rng)


func _populate_ramp_barrier(difficulty: float, rng: RandomNumberGenerator) -> void:
	_spawn_item(BOOST_SCENE, Vector3(-1.5, 0.0, -18.0))
	_spawn_item(BOOST_SCENE, Vector3(1.5, 0.0, -18.0))

	for ramp_x in [-4.5, -1.5, 1.5]:
		_spawn_item(RAMP_SCENE, Vector3(ramp_x, 0.0, -36.0))

	for barrier_x in [-4.5, -1.5, 1.5]:
		var obs := _spawn_item(OBSTACLE_SCENE, Vector3(barrier_x, 0.0, -46.0))
		_apply_obstacle_material(obs)

	_spawn_pickup(Vector3(4.5, 0.0, -46.0), rng)

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


func _spawn_pickup(local_pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var pickup := PICKUP_SCENE.instantiate() as Node3D
	spawned_container.add_child(pickup)
	pickup.position = local_pos
	var data: PowerUpData = SHIELD_POWERUP if rng.randf() < 0.5 else BOOST_POWERUP
	if pickup.has_method("configure_powerup"):
		pickup.configure_powerup(data)
	return pickup


func _apply_obstacle_material(obs: Node3D) -> void:
	if _obstacle_material == null or obs == null:
		return
	var visual := obs.get_node_or_null("Visual") as GeometryInstance3D
	if visual:
		visual.material_override = _obstacle_material
		for child in visual.get_children():
			if child is GeometryInstance3D:
				(child as GeometryInstance3D).material_override = _obstacle_material


func _shuffle_ints(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func configure_for_biome(biome: BiomeData) -> void:
	if biome == null:
		return
	var previous_biome_id := _biome_id
	_biome_id = biome.biome_id
	_ice_friction = biome.ice_friction
	_obstacle_material = biome.obstacle_material

	if track_bed:
		if biome.use_water_ice_shader:
			if _water_ice_mat == null:
				_water_ice_mat = ShaderMaterial.new()
				_water_ice_mat.shader = WATER_ICE_SHADER
			_water_ice_mat.set_shader_parameter("albedo_color", biome.water_ice_albedo)
			_water_ice_mat.set_shader_parameter("shimmer_color", biome.water_ice_shimmer)
			_water_ice_mat.set_shader_parameter("roughness_amount", biome.water_ice_roughness)
			_water_ice_mat.set_shader_parameter("fresnel_strength", biome.water_ice_fresnel_strength)
			track_bed.material_override = _water_ice_mat
		elif biome.track_material:
			track_bed.material_override = biome.track_material

	if biome.rail_material:
		if left_rail:
			left_rail.material_override = biome.rail_material
		if right_rail:
			right_rail.material_override = biome.rail_material

	if spawned_container:
		for child in spawned_container.get_children():
			if child.has_method("shatter"):
				_apply_obstacle_material(child as Node3D)

	if roadside_container and previous_biome_id != _biome_id and roadside_container.get_child_count() > 0:
		populate_roadside_props(_has_transition_gate)


func get_ice_friction() -> float:
	return _ice_friction


func spawn_transition_torii_gate() -> void:
	_has_transition_gate = true
	if not roadside_container:
		return
	var existing := roadside_container.get_node_or_null("TransitionToriiGate")
	if existing:
		return
	var decorative := roadside_container.get_node_or_null("ToriiGate")
	if decorative:
		roadside_container.remove_child(decorative)
		decorative.queue_free()
	var gate := _create_torii_gate(true, -16.0)
	gate.name = "TransitionToriiGate"
	roadside_container.add_child(gate)


func populate_roadside_props(force_transition_gate: bool = false) -> void:
	_has_transition_gate = force_transition_gate
	if not roadside_container:
		return
	clear_roadside_props()

	var prop_rng := RandomNumberGenerator.new()
	prop_rng.seed = hash(Vector2i(_chunk_seed, _chunk_index))

	match _biome_id:
		"golden_hayfield":
			_populate_hayfield_props(prop_rng)
		"midnight_shrine":
			_populate_shrine_props(prop_rng, true)
		_:
			_populate_shrine_props(prop_rng, false)

	if force_transition_gate:
		var gate := _create_torii_gate(true, -16.0)
		gate.name = "TransitionToriiGate"
		roadside_container.add_child(gate)
	elif (_biome_id == "kyoto_ice" or _biome_id == "midnight_shrine") and _chunk_index > 0 and _chunk_index % 3 == 1:
		var gate_z := -18.0 if chunk_variant == &"ramp_barrier" else -38.0
		var gate := _create_torii_gate(false, gate_z)
		gate.name = "ToriiGate"
		roadside_container.add_child(gate)


func _populate_shrine_props(prop_rng: RandomNumberGenerator, is_midnight: bool) -> void:
	var tree_z_list: Array[float] = [-10.0, -24.0, -38.0, -52.0, -66.0, -76.0]
	for z_pos in tree_z_list:
		for side in [-1.0, 1.0]:
			var tree_x: float = side * prop_rng.randf_range(11.6, 17.8)
			var tree_scale: float = prop_rng.randf_range(0.85, 1.35)
			var tree := _create_pine_tree(is_midnight)
			tree.position = Vector3(tree_x, -0.3, z_pos + prop_rng.randf_range(-2.2, 2.2))
			tree.scale = Vector3.ONE * tree_scale
			tree.rotation.y = prop_rng.randf_range(0.0, TAU)
			roadside_container.add_child(tree)

	var lantern_z_list: Array[float] = [-14.0, -40.0, -66.0]
	for idx in lantern_z_list.size():
		var z_pos := lantern_z_list[idx]
		for side in [-1.0, 1.0]:
			var lantern := _create_lantern(is_midnight, (idx + int(side > 0.0)) % 2 == 0)
			lantern.position = Vector3(side * 9.3, -0.15, z_pos)
			roadside_container.add_child(lantern)


func _populate_hayfield_props(prop_rng: RandomNumberGenerator) -> void:
	for side in [-1.0, 1.0]:
		var fence := _create_ranch_fence_side()
		fence.position = Vector3(side * 9.1, -0.1, 0.0)
		roadside_container.add_child(fence)

	var bale_z_list: Array[float] = [-14.0, -34.0, -54.0, -72.0]
	for z_pos in bale_z_list:
		for side in [-1.0, 1.0]:
			if prop_rng.randf() < 0.78:
				var stack := _create_hay_bale_stack(prop_rng.randf() < 0.55)
				stack.position = Vector3(side * prop_rng.randf_range(11.6, 15.2), -0.15, z_pos + prop_rng.randf_range(-2.0, 2.0))
				stack.rotation.y = prop_rng.randf_range(-0.45, 0.45)
				roadside_container.add_child(stack)

	if _chunk_index % 2 == 1:
		var barn_side: float = -1.0 if (_chunk_index % 4 == 1) else 1.0
		var barn := _create_red_barn()
		barn.position = Vector3(barn_side * 19.0, -0.35, -46.0)
		barn.rotation.y = -barn_side * 0.28
		roadside_container.add_child(barn)


func _get_prop_material(key: String, albedo: Color, roughness: float = 0.75, emission_color: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	if _prop_mats.has(key):
		return _prop_mats[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission_color
		mat.emission_energy_multiplier = emission_energy
	_prop_mats[key] = mat
	return mat


func _get_cylinder_mesh(key: String, top_r: float, bottom_r: float, height: float, radial_segments: int = 8) -> CylinderMesh:
	if _prop_meshes.has(key):
		return _prop_meshes[key] as CylinderMesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = 1
	_prop_meshes[key] = mesh
	return mesh


func _get_box_mesh(key: String, size: Vector3) -> BoxMesh:
	if _prop_meshes.has(key):
		return _prop_meshes[key] as BoxMesh
	var mesh := BoxMesh.new()
	mesh.size = size
	_prop_meshes[key] = mesh
	return mesh


func _get_prism_mesh(key: String, size: Vector3) -> PrismMesh:
	if _prop_meshes.has(key):
		return _prop_meshes[key] as PrismMesh
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.left_to_right = 0.5
	_prop_meshes[key] = mesh
	return mesh


func _add_mesh_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _create_pine_tree(is_midnight: bool) -> Node3D:
	var root := Node3D.new()
	var trunk_mat := _get_prop_material("pine_trunk_%s" % str(is_midnight), Color(0.18, 0.14, 0.16) if is_midnight else Color(0.32, 0.21, 0.14), 0.9)
	var leaf_mat := _get_prop_material("pine_leaf_%s" % str(is_midnight), Color(0.06, 0.10, 0.20) if is_midnight else Color(0.12, 0.34, 0.24), 0.85)
	var cap_mat := _get_prop_material("pine_cap_%s" % str(is_midnight), Color(0.24, 0.42, 0.62) if is_midnight else Color(0.90, 0.96, 1.0), 0.55)

	_add_mesh_part(root, _get_cylinder_mesh("trunk", 0.26, 0.38, 2.2, 6), trunk_mat, Vector3(0.0, 1.1, 0.0))
	_add_mesh_part(root, _get_cylinder_mesh("cone_bot", 0.0, 2.2, 2.8, 7), leaf_mat, Vector3(0.0, 2.8, 0.0))
	_add_mesh_part(root, _get_cylinder_mesh("cone_mid", 0.0, 1.7, 2.4, 7), leaf_mat, Vector3(0.0, 4.3, 0.0))
	_add_mesh_part(root, _get_cylinder_mesh("cone_top", 0.0, 1.15, 2.0, 7), cap_mat, Vector3(0.0, 5.7, 0.0))
	return root


func _create_lantern(is_midnight: bool, use_cyan_glow: bool) -> Node3D:
	var root := Node3D.new()
	var post_mat := _get_prop_material("lantern_post_%s" % str(is_midnight), Color(0.16, 0.16, 0.24) if is_midnight else Color(0.56, 0.58, 0.62), 0.85)
	var glow_key := "lantern_glow_%s_%s" % [str(is_midnight), str(use_cyan_glow)]
	var glow_col := Color(0.25, 0.90, 1.0) if (is_midnight and use_cyan_glow) else Color(1.0, 0.72, 0.32)
	var glow_mat := _get_prop_material(glow_key, glow_col, 0.25, glow_col, 2.1 if is_midnight else 1.35)

	_add_mesh_part(root, _get_box_mesh("lan_base", Vector3(0.85, 0.45, 0.85)), post_mat, Vector3(0.0, 0.22, 0.0))
	_add_mesh_part(root, _get_cylinder_mesh("lan_shaft", 0.18, 0.24, 2.0, 6), post_mat, Vector3(0.0, 1.4, 0.0))
	_add_mesh_part(root, _get_box_mesh("lan_core", Vector3(0.68, 0.68, 0.68)), glow_mat, Vector3(0.0, 2.75, 0.0))
	_add_mesh_part(root, _get_cylinder_mesh("lan_roof", 0.08, 0.78, 0.52, 4), post_mat, Vector3(0.0, 3.35, 0.0), Vector3(0.0, PI * 0.25, 0.0))
	return root


func _create_torii_gate(is_transition: bool, z_pos: float) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.0, 0.0, z_pos)
	var is_midnight := (_biome_id == "midnight_shrine")
	var vermilion_col := Color(0.52, 0.09, 0.12) if is_midnight else Color(0.82, 0.17, 0.13)
	var wood_mat := _get_prop_material("torii_wood_%s" % _biome_id, vermilion_col, 0.42)
	var cap_mat := _get_prop_material("torii_cap_%s" % _biome_id, Color(0.09, 0.11, 0.16), 0.55)
	var stone_mat := _get_prop_material("torii_stone_%s" % _biome_id, Color(0.18, 0.20, 0.26) if is_midnight else Color(0.32, 0.34, 0.38), 0.8)

	# Keep Nuki and Kasagi high above ramp arc (bottom >= 9.0m) and pillars outside rails (x = +/-8.9)
	for side in [-1.0, 1.0]:
		var px: float = side * 8.9
		_add_mesh_part(root, _get_cylinder_mesh("torii_pedestal", 0.72, 0.84, 1.1, 8), stone_mat, Vector3(px, 0.25, 0.0))
		_add_mesh_part(root, _get_cylinder_mesh("torii_pillar", 0.46, 0.52, 11.4, 8), wood_mat, Vector3(px, 5.7, 0.0))
		if is_transition:
			var accent := _create_lantern(is_midnight, is_midnight)
			accent.position = Vector3(side * 10.6, -0.15, 0.0)
			root.add_child(accent)

	_add_mesh_part(root, _get_box_mesh("torii_nuki", Vector3(20.4, 0.55, 0.55)), wood_mat, Vector3(0.0, 9.35, 0.0))
	_add_mesh_part(root, _get_box_mesh("torii_kasagi", Vector3(23.0, 0.85, 0.95)), wood_mat, Vector3(0.0, 11.15, 0.0))
	_add_mesh_part(root, _get_box_mesh("torii_roof", Vector3(24.0, 0.36, 1.18)), cap_mat, Vector3(0.0, 11.72, 0.0))

	var tablet_mat := _get_prop_material(
		"torii_tablet_%s_%s" % [_biome_id, str(is_transition)],
		Color(0.98, 0.80, 0.24) if is_transition else Color(0.14, 0.14, 0.18),
		0.35,
		Color(0.98, 0.72, 0.22) if is_transition else Color.BLACK,
		1.1 if is_transition else 0.0
	)
	_add_mesh_part(root, _get_box_mesh("torii_gakuzuka", Vector3(1.5, 1.35, 0.48)), tablet_mat, Vector3(0.0, 10.25, 0.0))
	return root


func _create_ranch_fence_side() -> Node3D:
	var root := Node3D.new()
	var wood_mat := _get_prop_material("ranch_wood", Color(0.46, 0.30, 0.16), 0.88)
	var post_mesh := _get_box_mesh("fence_post", Vector3(0.24, 1.65, 0.24))
	var rail_mesh := _get_box_mesh("fence_rail", Vector3(0.14, 0.18, 76.0))

	for i in 8:
		var pz := -5.0 - float(i) * 10.0
		_add_mesh_part(root, post_mesh, wood_mat, Vector3(0.0, 0.75, pz))

	_add_mesh_part(root, rail_mesh, wood_mat, Vector3(0.0, 0.65, -40.0))
	_add_mesh_part(root, rail_mesh, wood_mat, Vector3(0.0, 1.28, -40.0))
	return root


func _create_hay_bale_stack(stacked_three: bool) -> Node3D:
	var root := Node3D.new()
	var hay_mat := _get_prop_material("hay_straw", Color(0.88, 0.69, 0.22), 0.92)
	var bale_mesh := _get_cylinder_mesh("hay_bale", 0.95, 0.95, 1.65, 10)
	var bale_rot := Vector3(0.0, 0.0, PI * 0.5)

	_add_mesh_part(root, bale_mesh, hay_mat, Vector3(0.0, 0.95, 0.0), bale_rot)
	if stacked_three:
		_add_mesh_part(root, bale_mesh, hay_mat, Vector3(0.0, 0.95, -2.05), bale_rot)
		_add_mesh_part(root, bale_mesh, hay_mat, Vector3(0.0, 2.55, -1.02), bale_rot)
	return root


func _create_red_barn() -> Node3D:
	var root := Node3D.new()
	var wall_mat := _get_prop_material("barn_red", Color(0.70, 0.17, 0.14), 0.78)
	var roof_mat := _get_prop_material("barn_roof", Color(0.26, 0.22, 0.20), 0.85)
	var trim_mat := _get_prop_material("barn_trim", Color(0.94, 0.91, 0.84), 0.75)

	_add_mesh_part(root, _get_box_mesh("barn_body", Vector3(6.8, 4.6, 9.2)), wall_mat, Vector3(0.0, 2.3, 0.0))
	_add_mesh_part(root, _get_prism_mesh("barn_roof", Vector3(7.6, 2.8, 9.8)), roof_mat, Vector3(0.0, 6.0, 0.0))
	_add_mesh_part(root, _get_box_mesh("barn_trim_door", Vector3(7.0, 2.8, 2.6)), trim_mat, Vector3(0.0, 1.45, 0.0))
	return root
