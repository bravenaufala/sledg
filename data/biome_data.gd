@tool
class_name BiomeData
extends Resource

@export var biome_id: String = "kyoto_ice"
@export var display_name: String = "KYOTO WATER-ICE"
@export var use_water_ice_shader: bool = true
@export var spray_color: Color = Color(0.82, 0.96, 1.0, 1.0)
@export var track_material: Material
@export var rail_material: Material
@export var obstacle_material: Material
@export var water_ice_albedo: Color = Color(0.54, 0.84, 0.97, 1.0)
@export var water_ice_shimmer: Color = Color(0.90, 0.99, 1.0, 1.0)
@export var water_ice_roughness: float = 0.10
@export var water_ice_fresnel_strength: float = 0.55
@export var sky_top_color: Color = Color(0.32, 0.50, 0.68, 1.0)
@export var sky_horizon_color: Color = Color(0.68, 0.84, 0.94, 1.0)
@export var ice_friction: float = 0.10
@export var slope_angle_deg: float = -16.0
@export var chunk_variants: Array[PackedScene] = []
@export var obstacle_variants: Array[PackedScene] = []
