@tool
class_name BiomeData
extends Resource

@export var biome_id: StringName = &"alpine_ice"
@export var display_name: String = "ALPINE ICE"
@export var track_material: Material
@export var rail_material: Material
@export var obstacle_material: Material
@export var sky_top_color: Color = Color(0.38, 0.45, 0.55)
@export var sky_horizon_color: Color = Color(0.65, 0.67, 0.70)
@export var ice_friction: float = 0.12
@export var slope_angle_deg: float = -16.0
@export var chunk_variants: Array[PackedScene] = []
@export var obstacle_variants: Array[PackedScene] = []
