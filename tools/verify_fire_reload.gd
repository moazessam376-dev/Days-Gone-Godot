extends SceneTree

# M4 verification: loads THE MAIN SCENE (test_range.tscn — the artefact that
# actually runs), injects real fire/reload/aim input, and asserts the
# WeaponManager's firing model: aim-to-shoot, the rpm gate, hitscan reaching
# the range targets, reload refill and clip-speed sync, dry-fire auto-reload,
# and the r1 interrupt rule (swap cancels reload). Mirrors the r1 spec's
# S19-style scenario checks.

# Revolver rpm gate is 60/130 = 0.462 s = 27.7 physics frames.
const COOLDOWN_FRAMES := 30

var _fails := 0
var _reload_started := 0
var _reload_finished := 0


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label, "   ", detail)


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


## One semi-auto trigger pull: press, hold a frame, release. 3 frames total.
func _pull_trigger() -> void:
	Input.action_press("fire")
	await _wait(2)
	Input.action_release("fire")
	await _wait(1)


## Point the camera's view ray at a world position. The hitscan leaves the
## CAMERA, which rides the shoulder offset — so the rig must actually be
## yawed/pitched onto the target, exactly like a player putting the reticle
## on it. Two passes converge (the camera moves as the rig rotates).
func _aim_at(rig: Node3D, arm: SpringArm3D, camera: Camera3D, point: Vector3) -> void:
	for i in 3:
		var f := (point - camera.global_position).normalized()
		rig.rotation.y = atan2(-f.x, -f.z)
		arm.rotation.x = asin(f.y)
		await _wait(1)


func _run() -> void:
	var ps: PackedScene = load("res://scenes/levels/test_range.tscn")
	if ps == null:
		print("FAIL  cannot load main scene")
		quit(1)
		return
	root.add_child(ps.instantiate())
	await _wait(10)

	var player := root.get_node("TestRange/Player")
	var mgr := player.get_node("WeaponManager")
	var tree: AnimationTree = player.get_node("AnimationTree")
	var target: Node3D = root.get_node("TestRange/Target5m")
	var target_mesh: MeshInstance3D = target.get_node("Mesh")
	var rig: Node3D = player.get_node("CameraRig")
	var arm: SpringArm3D = player.get_node("CameraRig/SpringArm3D")
	var camera: Camera3D = player.get_node("CameraRig/SpringArm3D/Camera3D")
	var hud_ammo: Label = player.get_node("HUD/Ammo")
	var reticle: Control = player.get_node("HUD/Reticle")
	var rev: Resource = load("res://resources/weapons/revolver.tres")
	var reload_frames := int(ceil(rev.reload_time * 60.0)) + 10
	mgr.reload_started.connect(func() -> void: _reload_started += 1)
	mgr.reload_finished.connect(func() -> void: _reload_finished += 1)

	# --- spawn: full revolver mag, HUD shows it, no reticle outside ADS
	_check("spawn: ammo 6/24", mgr.ammo() == Vector2i(6, 24), str(mgr.ammo()))
	_check("spawn: HUD ammo label", hud_ammo.text == "6 / 24", hud_ammo.text)
	_check("spawn: reticle hidden outside ADS", not reticle.visible)

	# --- aim-to-shoot: LMB without ADS must not fire (r1 S19)
	await _pull_trigger()
	await _wait(5)
	_check("hipfire blocked: ammo unchanged", mgr.ammo() == Vector2i(6, 24), str(mgr.ammo()))

	# --- ADS + LMB fires: ammo down, target flashes, recoil kicks
	Input.action_press("aim")
	await _wait(20)
	_check("ADS: reticle visible", reticle.visible)
	await _aim_at(rig, arm, camera, target.global_position)
	var pitch_before: float = arm.rotation.x
	await _pull_trigger()
	_check("ADS fire: ammo 5", mgr.ammo() == Vector2i(5, 24), str(mgr.ammo()))
	_check("ADS fire: HUD updated", hud_ammo.text == "5 / 24", hud_ammo.text)
	_check(
		"ADS fire: Target5m flashed",
		target_mesh.material_override != null,
		"no material_override within flash window"
	)
	_check("ADS fire: recoil kicked pitch up", arm.rotation.x > pitch_before)

	# --- recoil compensation must not double-count (M4 playtest bug).
	# A player holding the reticle on target pulls the mouse down by the kick
	# they just took. If the rig ALSO gives that kick back, the aim sinks by
	# the burst's whole recoil total -- measured -9 deg over a rifle mag, which
	# put the camera in the dirt and then, over-corrected, in the sky.
	# Driven through the rig's own entry points rather than by spending rounds:
	# the ammo sequence downstream is exact, and the unit under test is the
	# camera's recoil model, not the fire path (covered directly above).
	await _wait(COOLDOWN_FRAMES)
	var settled_pitch: float = arm.rotation.x
	var kick := deg_to_rad(rev.recoil_pitch_deg)
	for i in 10:
		rig.add_recoil(rev.recoil_pitch_deg)
		rig._add_pitch(-kick)  # the player fighting the muzzle, via mouse-look's path
		await _wait(6)
	await _wait(30)
	var sink := rad_to_deg(settled_pitch - arm.rotation.x)
	_check(
		"recoil: compensated burst leaves aim where the player put it",
		absf(sink) < 0.2,
		"aim sank %.2f deg over 10 shots" % sink
	)

	# --- rpm gate: 14 pulls over ~0.7 s land exactly 2 shots (one
	# immediate, one when the 0.462 s cooldown reopens; a third would need
	# 0.92 s). Cooldown cleared first so the window starts clean.
	await _wait(COOLDOWN_FRAMES)
	for i in 14:
		await _pull_trigger()
	_check("rpm gate: exactly 2 shots in 0.7 s", mgr.ammo().x == 3, str(mgr.ammo()))
	await _wait(COOLDOWN_FRAMES)

	# --- manual reload: started signal, clip speed synced, refill on time
	_press("reload")
	await _wait(5)
	_check("reload: started", _reload_started == 1, str(_reload_started))
	var reload_scale := float(tree.get("parameters/ReloadScale/scale"))
	var expected: float = 4.966666666667 / rev.reload_time
	_check(
		"reload: clip speed synced to reload_time",
		absf(reload_scale - expected) < 0.01,
		str(reload_scale)
	)
	_check("reload: reloading state on", mgr.is_reloading())
	await _pull_trigger()
	_check("reload: shot dropped, not buffered", mgr.ammo().x == 3, str(mgr.ammo()))
	await _wait(reload_frames)
	_check("reload: mag refilled from reserve", mgr.ammo() == Vector2i(6, 21), str(mgr.ammo()))
	_check("reload: finished signal", _reload_finished == 1, str(_reload_finished))

	# --- swap cancels reload (r1 interrupt rule): no refill, no finish.
	# One shot first — a full mag refuses to reload.
	await _pull_trigger()
	_check("setup: one shot off", mgr.ammo() == Vector2i(5, 21), str(mgr.ammo()))
	await _wait(COOLDOWN_FRAMES)
	_press("reload")
	await _wait(5)
	_check("swap setup: reload running", mgr.is_reloading() and _reload_started == 2)
	_press("weapon_2")
	await _wait(45)
	_check("swap: cancelled the reload", not mgr.is_reloading())
	_press("weapon_1")
	await _wait(45)
	await _wait(reload_frames)
	_check(
		"swap: cancelled reload never refilled",
		mgr.ammo() == Vector2i(5, 21) and _reload_finished == 1,
		str(mgr.ammo()) + " finished=" + str(_reload_finished)
	)

	# --- dry fire auto-reloads: empty the mag, the next pull starts a reload
	var pulls: int = mgr.ammo().x
	for i in pulls:
		await _pull_trigger()
		await _wait(COOLDOWN_FRAMES)
	_check("dry setup: mag empty", mgr.ammo().x == 0, str(mgr.ammo()))
	var before_dry := _reload_started
	await _pull_trigger()
	await _wait(5)
	_check("dry fire: auto-reload started", _reload_started == before_dry + 1)
	await _wait(reload_frames)
	_check("dry fire: refilled", mgr.ammo() == Vector2i(6, 15), str(mgr.ammo()))

	# --- holstered: the trigger does nothing (no gun in hand)
	Input.action_release("aim")
	await _wait(5)
	_press("weapon_1")
	await _wait(35)
	_check("holstered: no gun in hand", not mgr.gun_in_hand())
	await _pull_trigger()
	await _wait(5)
	_check("holstered: fire blocked", mgr.ammo() == Vector2i(6, 15), str(mgr.ammo()))

	print("RESULT  fails=", _fails)
	quit(1 if _fails > 0 else 0)
