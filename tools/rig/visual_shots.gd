extends Node

# Visual-validation driver: runs THE REAL GAME (test_range.tscn) windowed,
# injects the same input a player would, and captures viewport PNGs of every
# weapon state (carry idle/jog, ADS, holstered stows, pistol regression).
# Camera positions are model-facing-relative so "front" stays the
# character's front in every state. Headless rendering is impossible on
# macOS; this is the scriptable window into what the player actually sees
# (it needs no editor and no MCP). Run:
#   /Applications/Godot.app/Contents/MacOS/Godot --path . \
#       --resolution 960x540 res://tools/rig/visual_shots.tscn
# PNGs land in SHOTS_DIR (env var) or user://shots.

var _out: String = OS.get_environment("SHOTS_DIR")

var _cam := Camera3D.new()
var _player: Node3D
var _hunter: Node3D


func _ready() -> void:
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(_out)
	add_child((load("res://scenes/levels/test_range.tscn") as PackedScene).instantiate())
	_cam.fov = 40.0
	add_child(_cam)
	_run.call_deferred()


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _shot(shot_name: String, front: float, left: float, up: float) -> void:
	var p: Vector3 = _player.global_position
	var yaw: float = _hunter.global_rotation.y
	var f := Vector3(sin(yaw), 0.0, cos(yaw))
	var l := Vector3(cos(yaw), 0.0, -sin(yaw))
	_cam.global_position = p + f * front + l * left + Vector3.UP * up
	_cam.look_at(p + Vector3(0.0, 1.15, 0.0))
	_cam.make_current()
	await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + "/" + shot_name + ".png")
	print("SHOT ", shot_name)


func _run() -> void:
	_player = get_node("TestRange/Player")
	_hunter = _player.get_node("Hunter")
	await _phys(20)

	_press("weapon_2")
	await _phys(50)
	var ar_c: Node3D = _player.get_node(
		"Hunter/GeneralSkeleton/RightHandAttach/WeaponSocket/AssaultRifle"
	)
	var cf: Vector3 = ar_c.global_transform.basis.z
	print("CARRY_GUN_PITCH_DEG=", rad_to_deg(atan2(cf.y, Vector2(cf.x, cf.z).length())))
	await _shot("r1_carry_idle_frontL", 2.0, 1.4, 1.5)
	await _shot("r1_carry_idle_sideR", 0.0, -2.6, 1.4)
	await _shot("r1_carry_idle_frontR", 2.0, -1.4, 1.5)
	await _shot("r1_carry_hand_close", 1.3, 0.9, 1.1)

	Input.action_press("move_left")
	await _phys(40)
	await _shot("r2_jog_frontL", 2.2, 1.3, 1.5)
	await _shot("r2_jog_sideL", 0.0, 2.6, 1.4)
	Input.action_release("move_left")
	await _phys(30)

	Input.action_press("move_back")
	await _phys(50)
	Input.action_release("move_back")
	await _phys(30)
	Input.action_press("aim")
	await _phys(40)
	var ar_hand: Node3D = _player.get_node(
		"Hunter/GeneralSkeleton/RightHandAttach/WeaponSocket/AssaultRifle"
	)
	var gf: Vector3 = ar_hand.global_transform.basis.z
	print("ADS_GUN_PITCH_DEG=", rad_to_deg(atan2(gf.y, Vector2(gf.x, gf.z).length())))
	await _shot("r3_ads_frontL", 2.0, 1.5, 1.5)
	await _shot("r3_ads_sideR", 0.0, -2.6, 1.4)
	await _shot("r3_ads_hand_close", 1.4, 1.0, 1.5)
	Input.action_release("aim")
	await _phys(20)

	_press("weapon_2")
	await _phys(40)
	await _shot("s1_stow_back", -2.6, 0.0, 1.6)
	await _shot("s2_stow_front", 2.6, 0.0, 1.2)
	await _shot("s3_stow_sideR", 0.3, -2.6, 1.1)
	await _shot("s4_stow_back34_top", -2.0, -1.2, 2.4)

	_press("weapon_1")
	await _phys(50)
	await _shot("p1_carry_idle_sideR", 0.0, -2.6, 1.4)
	await _shot("p2_carry_idle_frontL", 2.0, 1.4, 1.5)

	get_tree().quit(0)
