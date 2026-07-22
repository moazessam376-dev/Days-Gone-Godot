extends SceneTree

# M3 verification: loads THE MAIN SCENE (test_range.tscn — the artefact that
# actually runs), injects real weapon/aim input, and asserts the WeaponManager
# side effects: mesh visibility (hand vs stow), socket calibration matching
# the .tres, AnimationTree weapon/holster axes, holster + auto-draw.

var _fails := 0


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
	var skel := player.get_node("Hunter/GeneralSkeleton")
	var socket: Node3D = skel.get_node("RightHandAttach/WeaponSocket")
	var tree: AnimationTree = player.get_node("AnimationTree")
	var hand_rev: Node3D = socket.get_node("Revolver")
	var hand_ar: Node3D = socket.get_node("AssaultRifle")
	var stow_rev: Node3D = skel.get_node("HipSocket/HipStow/Revolver")
	var stow_ar: Node3D = skel.get_node("BackSocket/BackStow/AssaultRifle")
	var rev: Resource = load("res://resources/weapons/revolver.tres")
	var ar: Resource = load("res://resources/weapons/assault_rifle.tres")

	# --- spawn state: revolver in hand, rifle stowed on the back
	_check("spawn: revolver in hand", hand_rev.visible and not stow_rev.visible)
	_check("spawn: rifle stowed visible", stow_ar.visible and not hand_ar.visible)
	_check(
		"spawn: socket = revolver tres", socket.transform.is_equal_approx(rev.socket_transform())
	)
	_check(
		"spawn: weapon_blend 0",
		is_zero_approx(float(tree.get("parameters/WeaponBlend/blend_amount")))
	)

	# --- swap to rifle (weapon_2): mesh+rig at midpoint, blend reaches 1
	_press("weapon_2")
	await _wait(12)  # ~0.2 s < midpoint
	_check("mid-swap: still revolver in hand", hand_rev.visible and not hand_ar.visible)
	var mid: float = tree.get("parameters/WeaponBlend/blend_amount")
	_check("mid-swap: blend moving", mid > 0.05 and mid < 0.95, str(mid))
	await _wait(35)  # past 0.6 s total
	_check("post-swap: rifle in hand", hand_ar.visible and not stow_ar.visible)
	_check("post-swap: revolver stowed on hip", stow_rev.visible and not hand_rev.visible)
	_check(
		"post-swap: socket = rifle tres", socket.transform.is_equal_approx(ar.socket_transform())
	)
	_check("post-swap: hand rifle at mesh_offset", hand_ar.position.is_equal_approx(ar.mesh_offset))
	_check(
		"post-swap: weapon_blend 1",
		absf(float(tree.get("parameters/WeaponBlend/blend_amount")) - 1.0) < 0.001
	)
	_check(
		"post-swap: one-shot pickers on rifle",
		absf(float(tree.get("parameters/FireClip/blend_amount")) - 1.0) < 0.001
	)
	_check(
		"support grip = rifle tres",
		(socket.get_node("SupportGrip") as Node3D).position.is_equal_approx(ar.support_grip_pos)
	)
	_check(
		"tuner curls = rifle tres",
		(
			absf(float(skel.get_node("SupportHandTuner").get("thumb_curl")) - float(ar.thumb_curl))
			< 0.001
		)
	)

	# --- same-key holster: both weapons stowed, unarmed set
	_press("weapon_2")
	await _wait(35)  # past 0.4 s
	_check("holstered: no gun in either hand", not hand_ar.visible and not hand_rev.visible)
	_check("holstered: both stows visible", stow_ar.visible and stow_rev.visible)
	_check(
		"holstered: holster_blend 1",
		absf(float(tree.get("parameters/HolsterBlend/blend_amount")) - 1.0) < 0.001
	)
	_check("holstered: manager reports no gun", not mgr.gun_in_hand())

	# --- aim auto-draws the equipped rifle
	Input.action_press("aim")
	await _wait(35)
	Input.action_release("aim")
	_check("auto-draw: rifle back in hand", hand_ar.visible and not stow_ar.visible)
	_check(
		"auto-draw: holster_blend 0",
		is_zero_approx(float(tree.get("parameters/HolsterBlend/blend_amount")))
	)

	# --- scroll swaps back to the revolver (never holsters)
	_press("weapon_next")
	await _wait(45)
	_check("scroll: revolver in hand", hand_rev.visible and not hand_ar.visible)
	_check("scroll: rifle stowed", stow_ar.visible)
	_check(
		"scroll: socket = revolver tres", socket.transform.is_equal_approx(rev.socket_transform())
	)
	_check(
		"scroll: tuner curls = revolver tres",
		absf(float(skel.get_node("SupportHandTuner").get("thumb_curl")) - 57.5) < 0.001
	)

	print("RESULT  fails=", _fails)
	quit(1 if _fails > 0 else 0)
