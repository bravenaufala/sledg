# Icy Downhill Slider (`sledg`) — Architecture Plan

This document defines the Godot 4.x architecture for **Phase 2** (modular endless track, obstacles, engagement features, score HUD, game-over/restart) while establishing clean extension hooks for **Phase 3** (power-ups) and **Phase 4** (multiple biomes/maps).

---

## 1. Core Design Principles & Spatial Conventions

1. **Signals Up, Methods Down**: Child nodes emit signals (`player.crashed`, `player.near_miss_scored`, `player.boost_activated`, `hud.restart_requested`); parent coordinators (`Main`, `TrackSpawner`) call explicit methods on children.
2. **Connector-Driven Modularity**: Each track chunk is tilted at `-16°` around `X` (or inherits its pitch from the previous chunk's exit connector) and exposes an `ExitMarker` (`Marker3D`) at its downhill end so chunks snap together with zero trig drift:
   ```gdscript
   next_chunk.global_transform = last_chunk.exit_marker.global_transform
   ```
3. **Dimensions & Coordinate System** (preserving Phase 1 feel):
   - Forward downhill direction: `-Z` (tilted `-16°` around `+X`).
   - Usable track bed width: `14.0m` (`x ∈ [-6.5, +6.5]` accounting for player capsule radius `0.45m`), bordered by `1.0m` side rails at `x = ±7.5m`.
   - Standard chunk length: `80.0m` along the chunk's local `-Z` axis (`0.0` to `-80.0`).
4. **Collision Layers**:
   - Layer 1 (`world`): Track floor and side guard rails (`StaticBody3D`).
   - Layer 2 (`player`): `Player` (`CharacterBody3D`).
   - Layer 3 (`hazards`): Obstacles and `NearMissZone` (`Area3D`).
   - Layer 4 (`pickups`): Phase 3 power-up pickups (`Area3D`).

---

## 2. File & Directory Structure

```text
res://
├── main.tscn                   # Root game scene
├── main.gd                     # Run state machine, distance/score loop, restart orchestration
├── player.gd                   # CharacterBody3D sled movement, airtime/landing, boost, crash & near-miss hooks
├── track/
│   ├── track_spawner.gd        # Spawns, recycles, and alternates TrackChunk variants
│   ├── track_chunk.tscn        # Variant 1: Modular 80m standard obstacle + boost/ramp chunk
│   ├── track_chunk_ramp.tscn   # Variant 2: Modular 80m boost-into-ramp-over-barrier chunk
│   ├── track_chunk.gd          # Populates lane slots and applies active biome materials
│   ├── obstacle.tscn           # Greybox hazard with core hit box + NearMissZone Area3D
│   ├── obstacle.gd             # Crash trigger and +25 near-miss bonus detection
│   ├── ramp.tscn               # Wedge jump ramp Area3D
│   ├── ramp.gd                 # Launches player into airtime on contact
│   ├── boost_pad.tscn          # Speed boost strip Area3D
│   └── boost_pad.gd            # Triggers speed burst + camera FOV kick
├── ui/
│   ├── hud.tscn                # CanvasLayer with live score, status banner, and Game Over overlay
│   └── hud.gd                  # Score/bonus display and restart signal emission
└── data/                       # Phase 3 & 4 custom Resource definitions
    ├── powerup_data.gd         # (Phase 3) PowerUpData Resource class
    └── biome_data.gd           # (Phase 4) BiomeData Resource class
```

---

## 3. Scene Tree Hierarchy (`main.tscn`)

The node tree stays flat and focused, replacing the single static 400m `Track` node from Phase 1 with `TrackSpawner` and adding a `HUD` `CanvasLayer`:

```text
Main (Node3D) [main.gd]
├── WorldEnvironment
├── DirectionalLight3D
├── TrackSpawner (Node3D) [track_spawner.gd]
│   └── TrackChunk_0..N (StaticBody3D, instanced from track_chunk.tscn / track_chunk_ramp.tscn) [track_chunk.gd]
│       ├── TrackBed (CSGBox3D, 14m × 1m × 80m at z = -40)
│       ├── LeftRail (CSGBox3D, 1m × 1.2m × 80m at x = -7.5, z = -40)
│       ├── RightRail (CSGBox3D, 1m × 1.2m × 80m at x = +7.5, z = -40)
│       ├── TrackFloorCollision (CollisionShape3D)
│       ├── LeftWallCollision (CollisionShape3D)
│       ├── RightWallCollision (CollisionShape3D)
│       ├── ExitMarker (Marker3D at local position (0, 0, -80))
│       └── SpawnedItems (Node3D: runtime obstacles, ramps, boost pads)
├── Player (CharacterBody3D) [player.gd]
│   ├── CollisionShape3D
│   ├── SledVisual (Node3D)
│   │   ├── SledBody (CSGBox3D)
│   │   └── RiderCapsule (MeshInstance3D)
│   └── Camera3D
└── HUD (CanvasLayer) [hud.gd]
    ├── ScoreLabel (Label)
    ├── StatusLabel (Label: "+25 NEAR MISS!" / "SPEED BOOST!")
    └── GameOverPanel (Panel, hidden during gameplay)
        ├── TitleLabel (Label: "CRASHED!")
        ├── FinalScoreLabel (Label)
        └── RestartButton (Button: "Slide Again [Space / Enter]")
```

---

## 4. Phase 2 Systems Plan

### 4.1 Modular Endless Track Chunks & Chunk Variety (`track_spawner.gd` & `track_chunk.gd`)
- **Chunk Variants (`track_chunk.tscn` & `track_chunk_ramp.tscn`)**:
  - `track_chunk.tscn` (`&"standard"`): Standard 80m icy track with 3 obstacle rows (`z = -22, -48, -70`) across 4 lanes (`x ∈ {-4.5, -1.5, +1.5, +4.5}`), guaranteeing at least 1 open lane per row, plus optional boost pads or ramps in open lanes.
  - `track_chunk_ramp.tscn` (`&"ramp_barrier"`): Distinct ramp-over-barrier chunk featuring a lead-in speed boost row (`z = -18`), amber side arch pillars (`z = -36`), jump ramps (`z = -36`), a multi-lane obstacle barrier (`z = -46`) that the player vaults over (with one ground bypass lane at `x = +4.5`), and a post-landing obstacle row (`z = -68`).
- **Spawn & Recycle Loop**:
  - `TrackSpawner` maintains `active_chunks: Array[Node3D]` with `active_chunk_count = 6` (`480m` of track) chained via each chunk's `ExitMarker.global_transform`.
  - The first `safe_start_chunks = 2` (`160m`) spawn without obstacles so the player accelerates cleanly before meeting hazards.
  - In `update_spawner()`, once the oldest chunk's `ExitMarker` passes behind the player beyond `recycle_behind_distance`, it is freed/recycled and the next variant chunk is instantiated and snapped to the tail chunk's `ExitMarker`, alternating cleanly between standard and ramp-barrier variants.
- **Floating-Origin Recenter**:
  - When `player.global_position.length() > 2500.0`, subtract `player.global_position` from `Player`, `Camera3D`, and all `active_chunks` in one physics frame so endless runs never suffer float precision jitter.

### 4.2 Jump Ramps & Airtime Physics (`ramp.tscn`, `ramp.gd`, `player.gd`)
- **Structure**: `ramp.tscn` (`Area3D`) pairs an angled amber wedge (`RampWedge` `CSGBox3D` pitched `+18°`) with a trigger collider (`CollisionShape3D`).
- **Launch & Airtime**:
  - Contact calls `player.launch_from_ramp(upward_speed, forward_boost)`.
  - `player.gd` starts an `airborne_grace_timer = 0.25s`, sets `floor_snap_length = 0.0` so ground snapping does not pull the sled back onto the slope on frame 1, adds upward + forward launch velocity, arcs cleanly under gravity with mid-air steering and velocity-aligned sled pitch, and seamlessly restores `floor_snap_length` and downhill momentum upon landing back on the `-16°` slope.

### 4.3 Speed Boost Pads & Camera FOV Kick (`boost_pad.tscn`, `boost_pad.gd`, `player.gd`)
- **Structure**: `boost_pad.tscn` (`Area3D`) renders a flat glowing cyan strip (`PadVisual`) flush on the ice bed.
- **Boost & FOV Kick**:
  - Contact calls `player.trigger_boost_pad(mult, duration, instant_add, fov_kick)`, adding an immediate downhill speed burst, raising the effective max speed via `boost_multiplier` for `duration` seconds, emitting `boost_activated`, and kicking `Camera3D.fov` smoothly upward (`75° → 87°`) before easing back as the boost expires.

### 4.4 Obstacles & Near-Miss Bonus (`obstacle.tscn`, `obstacle.gd`)
- **Core Hazard**: `Obstacle` (`Area3D`) uses a `BoxShape3D` and contrast crimson-slate `CSGBox3D` (`2.0m × 1.6m × 1.2m`). Overlapping the player calls `player.on_obstacle_hit(self)`.
- **Near-Miss Bonus (+25 `bonus_points`)**:
  - Child `NearMissZone` (`Area3D` with a wider `4.8m × 2.4m × 2.0m` box around the obstacle) listens to `body_exited`.
  - If the player exits `NearMissZone` without having triggered `hit_player`, `obstacle.gd` calls `player.register_near_miss(25)`, adding `+25` to `Main.bonus_points` and flashing `"+25 NEAR MISS!"` on the HUD.

### 4.5 Score HUD & Game-Over / Restart (`hud.tscn`, `hud.gd`, `main.gd`)
- **Distance + Bonus Scoring**:
  - `Main` accumulates `total_distance += player.downhill_speed * delta` while `run_state == RunState.RUNNING`, computes `score = int(total_distance) + bonus_points`, and updates `HUD.update_score(score, int(total_distance), bonus_points)`.
- **Crash & Instant Restart**:
  - `Player.crashed` transitions `Main` to `RunState.GAME_OVER`, freezing sled motion and revealing `GameOverPanel`.
  - Pressing `RestartButton` or `ui_accept` (`Space` / `Enter`) calls `Main.start_new_run()`, resetting `total_distance`, `bonus_points`, `TrackSpawner.reset_track()`, `Player.reset_to_start()`, and hiding the overlay.

---

## 5. Phase 3 Extension Hooks — Power-Ups (Shield, Boost)

Phase 2 leaves three small, zero-overhead hooks so Phase 3 power-ups drop in without refactoring `Player`, `TrackChunk`, or `HUD`:

1. **`PowerUpData` Resource (`res://data/powerup_data.gd`)**:
   ```gdscript
   class_name PowerUpData
   extends Resource

   @export var id: StringName = &"shield"  # &"shield", &"boost"
   @export var duration: float = 4.0       # 0.0 for single-hit shield until consumed
   @export var speed_multiplier: float = 1.0
   @export var accent_color: Color = Color.CYAN
   ```
2. **Player Modifier & Hit-Resolution Hook (`player.gd`)**:
   - `var has_shield: bool = false`
   - `var speed_multiplier: float = 1.0`
   - `signal powerup_changed(id: StringName, active: bool, remaining: float)`
   - `func apply_powerup(data: PowerUpData) -> void`: activates shield or timed boost multiplier.
   - `func on_obstacle_hit(obstacle: Node3D) -> void`:
     - If `has_shield`: sets `has_shield = false`, calls `obstacle.shatter()` (`queue_free()`), and continues sliding.
     - Else: emits `crashed`.
   - In `_physics_process(delta)`: effective max downhill speed is `max_downhill_speed * _effective_speed_mult()`.
3. **Chunk Slot Hook (`track_chunk.gd`)**:
   - Open lane positions in a spawn row that do not receive an obstacle or ramp can spawn a Phase 3 `Pickup` (`Area3D` on layer 4) at a configurable `pickup_spawn_chance`.

---

## 6. Phase 4 Extension Hooks — Multiple Biomes & Maps

Phase 2 isolates visual materials, physics friction, and chunk templates behind a `BiomeData` resource contract so Phase 4 can switch maps or transition biomes mid-run:

1. **`BiomeData` Resource (`res://data/biome_data.gd`)**:
   ```gdscript
   class_name BiomeData
   extends Resource

   @export var biome_id: StringName = &"alpine_ice"
   @export var track_material: Material
   @export var rail_material: Material
   @export var obstacle_material: Material
   @export var sky_top_color: Color = Color(0.38, 0.45, 0.55)
   @export var ice_friction: float = 0.12
   @export var slope_angle_deg: float = -16.0
   @export var chunk_variants: Array[PackedScene] = []
   @export var obstacle_variants: Array[PackedScene] = []
   ```
2. **Spawner & Chunk Biome Hook (`track_spawner.gd` & `track_chunk.gd`)**:
   - `TrackSpawner` holds `@export var current_biome: BiomeData` (defaulting to Phase 2's built-in icy greybox palette when `null`).
   - Whenever a `TrackChunk` is spawned or recycled, `TrackSpawner` calls `chunk.configure_for_biome(current_biome)` and supports reading `current_biome.chunk_variants` and `current_biome.slope_angle_deg`.
   - `TrackChunk.get_ice_friction()` provides per-biome surface friction without modifying `player.gd`.
