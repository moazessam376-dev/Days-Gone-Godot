extends CharacterBody3D

# Phase 2 player: camera-relative movement on a CharacterBody3D, driving the
# AnimationTree's locomotion axes (blend positions, stance, carry arm lock)
# and the torso/head LookAt aim. The WeaponManager sibling owns the weapon
# axes (WeaponBlend / HolsterBlend / one-shot pickers), switching and stow.
# Carry: the body turns to face where it moves. ADS (hold `aim`): the body
# faces the camera and movement becomes strafing at walk speed. ADS needs a
# gun actually in the hand — while holstered the manager auto-draws first.
# Deliberately NOT here yet: sprint/roll/jump (Phase 3), firing/reload (M4).

## Model-forward correction: the Synty character faces +Z, Godot bodies face
## -Z, so the visual yaw gets PI added on top of the movement heading.
const MODEL_YAW_OFFSET := PI

## How far ahead of the camera the aim target sits, metres.
const AIM_RAY_LENGTH := 30.0

## LookAt influence targets (torso, head): full while aiming, a subtle
## residual while carrying so the character keeps some life.
const LOOKAT_ADS := Vector2(0.6, 0.35)
const LOOKAT_CARRY := Vector2(0.15, 0.1)

@export var tuning: PlayerTuning

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _stance := 0.0

@onready var _weapons: WeaponManager = $WeaponManager
@onready var _camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var _hunter: Node3D = $Hunter
@onready var _tree: AnimationTree = $AnimationTree
@onready var _aim_target: Node3D = $Hunter/AimTarget
@onready var _torso_look: SkeletonModifier3D = $Hunter/GeneralSkeleton/TorsoLookAt
@onready var _head_look: SkeletonModifier3D = $Hunter/GeneralSkeleton/HeadLookAt
@onready var _left_ik: SkeletonModifier3D = $Hunter/GeneralSkeleton/LeftArmIK
@onready var _hand_tuner: SkeletonModifier3D = $Hunter/GeneralSkeleton/SupportHandTuner
@onready var _weapon_socket: Node3D = $Hunter/GeneralSkeleton/RightHandAttach/WeaponSocket
@onready var _support_grip: Node3D = _weapon_socket.get_node("SupportGrip")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# hunter.tscn autoplays an idle so the standalone calibration scene shows a
	# pose. Here the AnimationTree owns the skeleton; if the player keeps
	# playing, both mixers write every frame and the last one wins — on screen
	# that looked like clips frozen at a static pose while the body moved.
	var hunter_player: AnimationPlayer = $Hunter/AnimationPlayer
	hunter_player.stop()
	hunter_player.active = false
	_tree.active = true


func _unhandled_input(event: InputEvent) -> void:
	# Dev convenience until Phase 3's pause menu: Esc frees the mouse,
	# clicking back into the window recaptures it.
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	# ADS requires a gun on screen: while holstered the WeaponManager
	# auto-draws on `aim`, and the stance raise follows once the gun is in
	# the hand; during a swap the crossfade stays in carry.
	var ads := (
		Input.is_action_pressed("aim") and _weapons.gun_in_hand() and not _weapons.is_swapping()
	)
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
	_update_anim_tree(ads, delta)
	_update_aim(ads, delta)


func _update_body_yaw(ads: bool, move_dir: Vector3, delta: float) -> void:
	var target_yaw := _hunter.rotation.y
	if ads:
		target_yaw = _camera_rig.rotation.y + MODEL_YAW_OFFSET
	elif move_dir.length_squared() > 0.01:
		target_yaw = atan2(move_dir.x, move_dir.z)
	_hunter.rotation.y = lerp_angle(
		_hunter.rotation.y, target_yaw, 1.0 - exp(-tuning.turn_lerp_speed * delta)
	)


func _update_anim_tree(ads: bool, delta: float) -> void:
	var stance_target := 1.0 if ads else 0.0
	_stance = move_toward(_stance, stance_target, delta / tuning.aim_raise_time)

	# Planar velocity in the model's facing frame: y = forward, x = strafe.
	var facing := Vector3(sin(_hunter.rotation.y), 0.0, cos(_hunter.rotation.y))
	var right := Vector3(-facing.z, 0.0, facing.x)
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var fwd_speed := planar.dot(facing)
	var strafe_speed := planar.dot(right)

	var aim_pos := Vector2(
		clampf(strafe_speed / tuning.aim_walk_speed, -1.0, 1.0),
		clampf(fwd_speed / tuning.aim_walk_speed, -1.0, 1.0)
	)
	var carry_pos := clampf(planar.length() / tuning.jog_speed, 0.0, 1.0)

	_tree.set("parameters/PistolAim/blend_position", aim_pos)
	_tree.set("parameters/RifleAimLegs/blend_position", aim_pos)
	# Rifle aim upper body locked to the calibrated aim pose; legs walk the
	# direction underneath (see build_anim_tree.gd).
	_tree.set("parameters/RifleAim/blend_amount", 1.0)
	_tree.set("parameters/PistolCarryLegs/blend_position", carry_pos)
	# Composite carry: body from the walk space, gun arm held hanging by the
	# side (see build_anim_tree.gd); lock strength is live-tunable. The inner
	# finger blend (grip fingers over the unarmed idle's open hand) stays
	# fully on.
	_tree.set("parameters/PistolCarry/blend_amount", tuning.pistol_carry_arm_lock)
	_tree.set("parameters/PistolCarryUpper/blend_amount", 1.0)
	_tree.set("parameters/RifleCarryLegs/blend_position", carry_pos)
	_tree.set("parameters/RifleCarry/blend_amount", tuning.rifle_carry_arm_lock)
	_tree.set("parameters/Unarmed/blend_position", carry_pos)
	_tree.set("parameters/PistolMove/blend_amount", _stance)
	_tree.set("parameters/RifleMove/blend_amount", _stance)


func _update_aim(ads: bool, delta: float) -> void:
	var origin := _camera.global_position
	var target := origin - _camera.global_transform.basis.z * AIM_RAY_LENGTH
	_aim_target.global_position = target

	var goal := LOOKAT_ADS if ads else LOOKAT_CARRY
	var w := 1.0 - exp(-3.0 * delta / maxf(tuning.aim_raise_time, 0.01))
	_torso_look.influence = lerpf(_torso_look.influence, goal.x, w)
	_head_look.influence = lerpf(_head_look.influence, goal.y, w)

	# The support hand belongs on the gun while aiming — and, for the RIFLE,
	# during carry too: rifle carry is two-handed, and the IK is what welds
	# the left palm to the handguard across every gait. The PISTOL keeps the
	# IK aim-only: its carry is one-handed, and carry-time IK chased the grip
	# across the body ("left hand going through the body" — user).
	var weapon := _weapons.equipped_weapon()
	var rifle_in_hand := _weapons.gun_in_hand() and weapon.anim_set == 1
	var ik_goal := 1.0 if ads or rifle_in_hand else 0.0
	_left_ik.influence = lerpf(_left_ik.influence, ik_goal, w)
	_hand_tuner.influence = _left_ik.influence

	# The support hand slides between its two calibrated points on the gun
	# with the stance: cradle near the receiver in carry (the handguard
	# point over-reached the arm), out on the handguard in ADS.
	_support_grip.position = weapon.carry_support_grip_pos.lerp(weapon.support_grip_pos, _stance)
