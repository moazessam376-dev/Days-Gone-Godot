extends Node3D

# Third-person over-shoulder camera rig: yaw on this node, pitch on the
# SpringArm3D, per-state distance/FOV/shoulder from PlayerTuning
# (docs/r1-player-handling.md camera table). The rig only READS input for
# mouse look; aim state is pushed in by player.gd so there is one source of
# truth for ADS.

@export var tuning: PlayerTuning

## Set by player.gd every physics frame.
var ads := false

## +1 = camera over the right shoulder, -1 = left. Toggled with shoulder_swap.
var shoulder_side := 1.0

## Per-weapon ADS fov, written by the WeaponManager on equip (falls back to
## the tuning default until the first equip).
var ads_fov := 42.0

## Recoil pitch still owed back to the baseline, radians. A shot kicks the
## camera up instantly; this drains it back down over recoil_recover_time so
## there is no permanent aim drift (per-weapon recoil IDENTITY is Phase 9 —
## this is the M4 minimum that makes a shot feel like a shot).
var _recoil_debt := 0.0

@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	_arm.spring_length = tuning.rest_distance
	_camera.fov = tuning.fov_rest
	ads_fov = tuning.fov_ads
	# Start at the rest shoulder offset instead of sliding into it over the
	# first fraction of a second after launch (issue #10).
	_arm.position.x = tuning.shoulder_x_rest * shoulder_side


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * tuning.mouse_sensitivity
		_arm.rotation.x = clampf(
			_arm.rotation.x - event.relative.y * tuning.mouse_sensitivity,
			deg_to_rad(tuning.pitch_min_deg),
			deg_to_rad(tuning.pitch_max_deg)
		)
	elif event.is_action_pressed("shoulder_swap"):
		shoulder_side = -shoulder_side


func _physics_process(delta: float) -> void:
	var target_len: float = tuning.ads_distance if ads else tuning.rest_distance
	var target_fov: float = ads_fov if ads else tuning.fov_rest
	var target_x: float = (tuning.shoulder_x_ads if ads else tuning.shoulder_x_rest) * shoulder_side
	var blend_time: float = tuning.ads_in_time if ads else tuning.ads_out_time

	var w := _smooth_weight(blend_time, delta)
	_arm.spring_length = lerpf(_arm.spring_length, target_len, w)
	_camera.fov = lerpf(_camera.fov, target_fov, w)

	var sw := _smooth_weight(tuning.shoulder_swap_time, delta)
	_arm.position.x = lerpf(_arm.position.x, target_x, sw)

	if _recoil_debt > 0.0:
		var back := _recoil_debt * _smooth_weight(tuning.recoil_recover_time, delta)
		_recoil_debt -= back
		_set_pitch(_arm.rotation.x - back)


## Kick the camera pitch up by a shot's recoil; the kick eases back to the
## baseline in _physics_process. Called by the WeaponManager per shot.
func add_recoil(pitch_deg: float) -> void:
	var kick := deg_to_rad(pitch_deg)
	_recoil_debt += kick
	_set_pitch(_arm.rotation.x + kick)


func _set_pitch(pitch: float) -> void:
	_arm.rotation.x = clampf(
		pitch, deg_to_rad(tuning.pitch_min_deg), deg_to_rad(tuning.pitch_max_deg)
	)


## Frame-rate-independent smoothing weight that covers ~95% of the remaining
## distance in `time` seconds.
func _smooth_weight(time: float, delta: float) -> float:
	if time <= 0.0:
		return 1.0
	return 1.0 - exp(-3.0 * delta / time)


## Horizontal forward direction of the camera, for camera-relative movement.
func flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func flat_right() -> Vector3:
	var r := global_transform.basis.x
	r.y = 0.0
	return r.normalized()
