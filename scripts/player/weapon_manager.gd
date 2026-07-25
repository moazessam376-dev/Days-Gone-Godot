class_name WeaponManager
extends Node

# Weapon state owner (Phase 2 M3+M4): which weapon is equipped and whether it
# is in the hand, plus everything that hangs off that — the AnimationTree's
# WeaponBlend / HolsterBlend / FireClip / ReloadClip axes, hand-vs-stow mesh
# visibility, the per-weapon rig calibration (socket, grips, pole, tuner) and
# the camera's ADS fov. player.gd keeps locomotion and aim; firing and reload
# (M4) live here because ammo does.
#
# M4 firing model, per the approved r1 rules pulled forward into the slice:
# aim-to-shoot (LMB only fires while ADS), rpm-gated, no input buffering (a
# blocked press is dropped, not queued), reload keeps stance but blocks fire,
# and starting a swap or holstering cancels an in-flight reload. Dry fire
# auto-starts a reload (r1: "auto-reload on next dry fire"). The hitscan ray
# leaves the CAMERA centre — what the reticle covers is what gets hit; muzzle
# flash/tracers are Phase 9 (no FX assets are imported yet).
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
signal fired(weapon: WeaponResource)
signal reload_started
signal reload_finished

## Slot order matches the weapon_1 / weapon_2 input actions.
@export var weapons: Array[WeaponResource] = []
@export var tuning: PlayerTuning

## CALIBRATION SWITCH — tick this in the Remote tree while the game runs to
## freeze every runtime rig write (socket, support grips, tuner values), so
## a tuning session can adjust those nodes live without player.gd or an
## equip overwriting the changes. Weapon switching still works, it just
## stops re-applying calibration. Ship value: off.
@export var calibration_freeze := false

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
## Seconds until the rpm gate reopens.
var _fire_cooldown := 0.0
## Reload progress in seconds; -1 = not reloading.
var _reload_t := -1.0

@onready var _tree: AnimationTree = $"../AnimationTree"
@onready var _camera_rig: Node3D = $"../CameraRig"
@onready var _camera: Camera3D = $"../CameraRig/SpringArm3D/Camera3D"
@onready var _anim_player: AnimationPlayer = $"../Hunter/AnimationPlayer"
@onready var _body: PhysicsBody3D = get_parent()
@onready var _skel: Skeleton3D = $"../Hunter/GeneralSkeleton"
@onready var _socket: Node3D = _skel.get_node("RightHandAttach/WeaponSocket")
@onready var _support_grip: Node3D = _socket.get_node("SupportGrip")
@onready var _elbow_pole: Node3D = _skel.get_node("LeftElbowPole")
@onready var _tuner: SkeletonModifier3D = _skel.get_node("SupportHandTuner")
@onready var _wrist_target: Node3D = _support_grip.get_node_or_null("WristTarget")
@onready var _right_wrist_target: Node3D = _socket.get_node_or_null("RightWristTarget")


func _ready() -> void:
	if weapons.is_empty():
		push_error("WeaponManager has no weapons assigned")
		return
	for w in weapons:
		_mag.append(w.mag_size)
		_reserve.append(w.reserve)
	# Re-assert the saved scene's state (the generator ships slot 0 in hand):
	# calibration sessions toggle eye icons freely; runtime truth starts here.
	# Stow placement too — the .tres is authoritative at runtime, so a
	# build_weapons.gd change shows up on the next run without a scene
	# rebuild (the scene's baked copy only serves editor gizmo sessions).
	for w in weapons:
		var stow := _stow_node(w)
		if stow != null:
			stow.transform = w.stow_transform()
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
	elif event.is_action_pressed("reload"):
		_try_reload()


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

	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	_tick_reload(delta)
	_tick_fire()


## True while a weapon mesh is in the hand — the gate for ADS and the
## support-hand IK (aiming a stowed gun reads as mime).
func gun_in_hand() -> bool:
	return _gun_in_hand


func is_swapping() -> bool:
	return _swap_t >= 0.0


func equipped_weapon() -> WeaponResource:
	return weapons[_equipped]


## Mag / reserve of the equipped weapon (x = mag, y = reserve) — lets the HUD
## draw its first frame; every later update arrives via ammo_changed.
func ammo() -> Vector2i:
	if _mag.is_empty():
		return Vector2i.ZERO
	return Vector2i(_mag[_equipped], _reserve[_equipped])


func is_reloading() -> bool:
	return _reload_t >= 0.0


func _tick_fire() -> void:
	var w := weapons[_equipped]
	# Semi-auto fires per press, full-auto while held. A press that arrives
	# blocked is dropped (r1: no input buffering).
	var pulled := (
		Input.is_action_pressed("fire") if w.auto_fire else Input.is_action_just_pressed("fire")
	)
	if not pulled:
		return
	# Aim-to-shoot: _camera_rig.ads is the single source of ADS truth,
	# written by player.gd earlier this frame (parents process first).
	if not _camera_rig.ads or not _gun_in_hand or is_swapping() or is_reloading():
		return
	if _fire_cooldown > 0.0:
		return
	if _mag[_equipped] <= 0:
		_try_reload()  # r1: dry fire auto-reloads
		return
	_fire(w)


func _fire(w: WeaponResource) -> void:
	_fire_cooldown = 60.0 / maxf(w.rpm, 1.0)
	_mag[_equipped] -= 1
	ammo_changed.emit(_mag[_equipped], _reserve[_equipped])
	_tree.set("parameters/FireShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_camera_rig.add_recoil(w.recoil_pitch_deg)
	_hitscan(w)
	fired.emit(w)


# Camera-centre hitscan: what the reticle covers is what gets hit. Spread is
# a uniform cone of spread_deg around the view ray; the player's own body is
# excluded so the over-shoulder camera can't shoot the character in the back.
func _hitscan(w: WeaponResource) -> void:
	var origin := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	if w.spread_deg > 0.0:
		var half_angle := deg_to_rad(w.spread_deg)
		var theta := randf() * TAU
		var r := tan(half_angle) * sqrt(randf())
		var side := _camera.global_transform.basis.x
		var up := _camera.global_transform.basis.y
		dir = (dir + side * (r * cos(theta)) + up * (r * sin(theta))).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * w.hitscan_range)
	query.exclude = [_body.get_rid()]
	var hit := _body.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_method("on_shot"):
		hit.collider.on_shot(hit.position, hit.normal, w.damage)


func _try_reload() -> void:
	var w := weapons[_equipped]
	if is_reloading() or is_swapping() or not _gun_in_hand or _holstered:
		return
	if _mag[_equipped] >= w.mag_size or _reserve[_equipped] <= 0:
		return
	_reload_t = 0.0
	# Play the reload clip at clip_length / reload_time so the hands finish
	# exactly when the mag refills — the stat stays authoritative.
	var clip := _anim_player.get_animation(w.reload_clip)
	var scale := 1.0
	if clip != null and w.reload_time > 0.0:
		scale = clip.length / w.reload_time
	_tree.set("parameters/ReloadScale/scale", scale)
	_tree.set("parameters/ReloadShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	reload_started.emit()


func _tick_reload(delta: float) -> void:
	if not is_reloading():
		return
	_reload_t += delta
	var w := weapons[_equipped]
	if _reload_t < w.reload_time:
		return
	_reload_t = -1.0
	var take := mini(w.mag_size - _mag[_equipped], _reserve[_equipped])
	_mag[_equipped] += take
	_reserve[_equipped] -= take
	ammo_changed.emit(_mag[_equipped], _reserve[_equipped])
	reload_finished.emit()


# r1 interrupt rule: starting a swap or holstering cancels the reload —
# progress lost, no refill, the one-shot fades back out.
func _cancel_reload() -> void:
	if not is_reloading():
		return
	_reload_t = -1.0
	_tree.set("parameters/ReloadShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


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
	_cancel_reload()
	_swap_pending = slot
	_swap_t = 0.0


## Apply everything that IS the weapon: rig calibration onto the shared
## socket/grip/pole/tuner nodes, camera fov, mesh visibility, signals.
func _apply_weapon(slot: int) -> void:
	_equipped = slot
	var w := weapons[slot]
	if not calibration_freeze:
		_socket.transform = w.socket_transform()
		_support_grip.position = w.support_grip_pos
		_elbow_pole.position = w.elbow_pole_pos
		# Write the wrist correction to the GIZMO node, not the tuner's Euler:
		# the node is authoritative and the tuner mirrors it back every frame, so
		# setting the Euler here would be overwritten within a frame and the
		# per-weapon value would silently not apply.
		if _wrist_target != null:
			_wrist_target.rotation_degrees = w.wrist_offset_deg
		else:
			_tuner.set("wrist_offset_deg", w.wrist_offset_deg)
		_tuner.set("thumb_curl", w.thumb_curl)
		_tuner.set("index_curl", w.index_curl)
		_tuner.set("middle_curl", w.middle_curl)
		_tuner.set("curl_axis", w.curl_axis)
		_tuner.set("thumb_axis", w.thumb_axis)
		if _right_wrist_target != null:
			_right_wrist_target.rotation_degrees = w.right_wrist_offset_deg
		else:
			_tuner.set("right_wrist_offset_deg", w.right_wrist_offset_deg)
		_tuner.set("right_thumb_curl", w.right_thumb_curl)
		_tuner.set("right_index_curl", w.right_index_curl)
		_tuner.set("right_middle_curl", w.right_middle_curl)
	_camera_rig.set("ads_fov", w.ads_fov)
	_refresh_visibility()
	weapon_changed.emit(w)
	ammo_changed.emit(_mag[slot], _reserve[slot])


func _set_holstered(holstered: bool) -> void:
	if _holstered == holstered:
		return
	if holstered:
		_cancel_reload()
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


func _stow_node(w: WeaponResource) -> Node3D:
	var stow_path := "HipSocket/HipStow" if w.stow_socket == "hip" else "BackSocket/BackStow"
	return _skel.get_node_or_null(NodePath(stow_path)) as Node3D


func _stow_mesh(w: WeaponResource) -> Node3D:
	var stow := _stow_node(w)
	if stow == null:
		return null
	return stow.get_node_or_null(NodePath(String(w.id))) as Node3D
