extends CharacterBody3D

# Phase 2 M1 player: camera-relative movement on a CharacterBody3D.
# Carry: the body turns to face where it moves. ADS (hold `aim`): the body
# faces the camera and movement becomes strafing at walk speed.
# Deliberately NOT here yet: sprint/roll/jump (Phase 3), AnimationTree (M2),
# weapons (M3), firing (M4).

## Model-forward correction: the Synty character faces +Z, Godot bodies face
## -Z, so the visual yaw gets PI added on top of the movement heading.
const MODEL_YAW_OFFSET := PI

@export var tuning: PlayerTuning

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _camera_rig: Node3D = $CameraRig
@onready var _hunter: Node3D = $Hunter


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Dev convenience until Phase 3's pause menu: Esc frees the mouse,
	# clicking back into the window recaptures it.
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var ads := Input.is_action_pressed("aim")
	_camera_rig.ads = ads

	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_dir: Vector3 = (
		_camera_rig.flat_forward() * -input_2d.y + _camera_rig.flat_right() * input_2d.x
	)

	var speed: float = tuning.aim_walk_speed if ads else tuning.jog_speed
	var target_h: Vector3 = move_dir * speed
	velocity.x = move_toward(velocity.x, target_h.x, tuning.acceleration * delta)
	velocity.z = move_toward(velocity.z, target_h.z, tuning.acceleration * delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()

	_update_body_yaw(ads, move_dir, delta)


func _update_body_yaw(ads: bool, move_dir: Vector3, delta: float) -> void:
	var target_yaw := _hunter.rotation.y
	if ads:
		target_yaw = _camera_rig.rotation.y + MODEL_YAW_OFFSET
	elif move_dir.length_squared() > 0.01:
		target_yaw = atan2(move_dir.x, move_dir.z)
	_hunter.rotation.y = lerp_angle(
		_hunter.rotation.y, target_yaw, 1.0 - exp(-tuning.turn_lerp_speed * delta)
	)
