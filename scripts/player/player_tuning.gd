class_name PlayerTuning
extends Resource

# THE single home for every player-feel constant (CLAUDE.md rule: all tuning
# constants live in one place, exposed for live tuning). One instance is saved
# as resources/tuning/player_tuning.tres and shared by every consumer, so
# edits in the Inspector while the game runs apply immediately.
#
# Camera numbers come from docs/r1-player-handling.md (user-approved spec).

@export_group("Camera")
@export var rest_distance := 2.8
@export var ads_distance := 1.55
@export var shoulder_x_rest := 0.45
@export var shoulder_x_ads := 0.62
@export var fov_rest := 55.0
@export var fov_ads := 42.0
@export var ads_in_time := 0.25
@export var ads_out_time := 0.18
@export var shoulder_swap_time := 0.15
@export var mouse_sensitivity := 0.0025
@export var pitch_min_deg := -70.0
@export var pitch_max_deg := 60.0

@export_group("Movement")
@export var jog_speed := 4.6
@export var aim_walk_speed := 2.07
@export var acceleration := 18.0
@export var turn_lerp_speed := 10.0

@export_group("Aim")
@export var aim_raise_time := 0.25
