class_name WeaponManager
extends Node

# Weapon state owner (Phase 2 M3): which weapon is equipped and whether it is
# in the hand, plus everything that hangs off that — the AnimationTree's
# WeaponBlend / HolsterBlend / FireClip / ReloadClip axes, hand-vs-stow mesh
# visibility, the per-weapon rig calibration (socket, grips, pole, tuner) and
# the camera's ADS fov. player.gd keeps locomotion and aim; M4 builds
# firing/reload on the signals and ammo state here.
#
# Swap and holster are BLENDS, not clips — no draw/holster animations exist
# in the free set (stated honestly at the Phase 2 gate). A swap crossfades
# WeaponBlend through the carry stance over swap_time, with mesh + rig values
# flipping at the midpoint; holstering blends HolsterBlend toward the unarmed
# set over holster_time, the gun moving to its body stow at the blend middle.
# Days Gone carry rule: the non-equipped weapon is ALWAYS visible, stowed on
# its body socket (rifle diagonal on the back, revolver on the hip).

signal weapon_changed(weapon: WeaponResource)
signal holster_changed(holstered: bool)
signal ammo_changed(mag: int, reserve: int)
# M4 contract — reload will live here because ammo does.
@warning_ignore("unused_signal")
signal reload_started
@warning_ignore("unused_signal")
signal reload_finished

## Slot order matches the weapon_1 / weapon_2 input actions.
@export var weapons: Array[WeaponResource] = []
@export var tuning: PlayerTuning

var _equipped := 0
var _holstered := false
## True while a weapon mesh is actually in the hand — flips exactly when the
## meshes swap, so IK/ADS gates track what is on screen, not the input state.
var _gun_in_hand := true
var _weapon_blend := 0.0
var _holster_blend := 0.0
var _swap_t := -1.0
var _swap_pending := -1
var _mag: Array[int] = []
var _reserve: Array[int] = []

@onready var _tree: AnimationTree = $"../AnimationTree"
@onready var _camera_rig: Node3D = $"../CameraRig"
@onready var _skel: Skeleton3D = $"../Hunter/GeneralSkeleton"
@onready var _socket: Node3D = _skel.get_node("RightHandAttach/WeaponSocket")
@onready var _support_grip: Node3D = _socket.get_node("SupportGrip")
@onready var _elbow_pole: Node3D = _skel.get_node("LeftElbowPole")
@onready var _tuner: SkeletonModifier3D = _skel.get_node("SupportHandTuner")


func _ready() -> void:
	if weapons.is_empty():
		push_error("WeaponManager has no weapons assigned")
		return
	for w in weapons:
		_mag.append(w.mag_size)
		_reserve.append(w.reserve)
	# Re-assert the saved scene's state (the generator ships slot 0 in hand):
	# calibration sessions toggle eye icons freely; runtime truth starts here.
	_weapon_blend = float(weapons[_equipped].anim_set)
	_apply_weapon(_equipped)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("weapon_1"):
		_request(0)
	elif event.is_action_pressed("weapon_2"):
		_request(1)
	elif event.is_action_pressed("weapon_next"):
		_request((_equipped + 1) % weapons.size(), false)
	elif event.is_action_pressed("weapon_prev"):
		_request((_equipped - 1 + weapons.size()) % weapons.size(), false)


func _physics_process(delta: float) -> void:
	if weapons.is_empty():
		return

	# Days Gone reflex: aiming while everything is stowed draws the weapon.
	if _holstered and Input.is_action_pressed("aim"):
		_set_holstered(false)

	var h_target := 1.0 if _holstered else 0.0
	_holster_blend = move_toward(_holster_blend, h_target, delta / tuning.holster_time)
	# The gun moves hand <-> stow at the middle of the holster blend.
	if _gun_in_hand and _holstered and _holster_blend >= 0.5:
		_set_gun_in_hand(false)
	elif not _gun_in_hand and not _holstered and _holster_blend <= 0.5:
		_set_gun_in_hand(true)

	if _swap_t >= 0.0:
		_swap_t += delta
		if _swap_pending >= 0 and _swap_t >= tuning.swap_time * 0.5:
			_apply_weapon(_swap_pending)
			_swap_pending = -1
		if _swap_t >= tuning.swap_time:
			_swap_t = -1.0
	# The blend heads for the swap DESTINATION from the first frame — the
	# mesh + rig flip at the midpoint happens under a blend already halfway.
	var target_set := float(weapons[_swap_pending if _swap_pending >= 0 else _equipped].anim_set)
	if _holster_blend >= 0.999:
		# Fully stowed = the unarmed set covers everything; snap, don't drag
		# a visible crossfade into the draw.
		_weapon_blend = target_set
	else:
		_weapon_blend = move_toward(_weapon_blend, target_set, delta / tuning.swap_time)

	_tree.set("parameters/WeaponBlend/blend_amount", _weapon_blend)
	_tree.set("parameters/HolsterBlend/blend_amount", _holster_blend)
	# One-shot pickers snap: they only matter the frame a shot/reload fires.
	_tree.set("parameters/FireClip/blend_amount", float(weapons[_equipped].anim_set))
	_tree.set("parameters/ReloadClip/blend_amount", float(weapons[_equipped].anim_set))


## True while a weapon mesh is in the hand — the gate for ADS and the
## support-hand IK (aiming a stowed gun reads as mime).
func gun_in_hand() -> bool:
	return _gun_in_hand


func is_swapping() -> bool:
	return _swap_t >= 0.0


func equipped_weapon() -> WeaponResource:
	return weapons[_equipped]


func _request(slot: int, same_key_holsters := true) -> void:
	if slot < 0 or slot >= weapons.size() or is_swapping():
		return
	if slot == _equipped:
		# Same number key = the Days Gone stow toggle (scroll never holsters).
		if same_key_holsters:
			_set_holstered(not _holstered)
		elif _holstered:
			_set_holstered(false)
		return
	if _holstered:
		# Hands are empty — no crossfade to stage, just re-rig and draw.
		_apply_weapon(slot)
		_set_holstered(false)
		return
	_swap_pending = slot
	_swap_t = 0.0


## Apply everything that IS the weapon: rig calibration onto the shared
## socket/grip/pole/tuner nodes, camera fov, mesh visibility, signals.
func _apply_weapon(slot: int) -> void:
	_equipped = slot
	var w := weapons[slot]
	_socket.transform = w.socket_transform()
	_support_grip.position = w.support_grip_pos
	_elbow_pole.position = w.elbow_pole_pos
	_tuner.set("wrist_offset_deg", w.wrist_offset_deg)
	_tuner.set("thumb_curl", w.thumb_curl)
	_tuner.set("index_curl", w.index_curl)
	_tuner.set("middle_curl", w.middle_curl)
	_tuner.set("curl_axis", w.curl_axis)
	_tuner.set("thumb_axis", w.thumb_axis)
	_camera_rig.set("ads_fov", w.ads_fov)
	_refresh_visibility()
	weapon_changed.emit(w)
	ammo_changed.emit(_mag[slot], _reserve[slot])


func _set_holstered(holstered: bool) -> void:
	if _holstered == holstered:
		return
	_holstered = holstered
	holster_changed.emit(holstered)


func _set_gun_in_hand(in_hand: bool) -> void:
	_gun_in_hand = in_hand
	_refresh_visibility()


# Two instances per weapon (hand + stow), visibility-swapped — never
# reparented. Equipped + in hand -> hand instance; everything else rides its
# body stow, always visible.
func _refresh_visibility() -> void:
	for i in weapons.size():
		var w := weapons[i]
		var in_hand := i == _equipped and _gun_in_hand
		var hand := _socket.get_node_or_null(NodePath(String(w.id)))
		if hand != null:
			(hand as Node3D).visible = in_hand
		var stow := _stow_mesh(w)
		if stow != null:
			stow.visible = not in_hand


func _stow_mesh(w: WeaponResource) -> Node3D:
	var stow_path := "HipSocket/HipStow" if w.stow_socket == "hip" else "BackSocket/BackStow"
	return _skel.get_node_or_null(NodePath(stow_path + "/" + String(w.id))) as Node3D
