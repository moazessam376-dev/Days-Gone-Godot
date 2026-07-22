extends SceneTree

# Generates resources/animation/player_anim_tree.tres — the player's
# AnimationNodeBlendTree. Generated (not hand-built in the editor) so the
# ~35-entry upper-body filter lists stay reproducible and the graph can be
# rebuilt after any clip change. Run with the editor CLOSED:
#
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
#       --script tools/build_anim_tree.gd
#
# Graph (see docs/phase-2-weapon-slice.md):
#
#   PistolCarry(1D)  PistolAim(2D)   RifleCarry(1D)  RifleAim(2D)
#         \            /                   \            /
#        PistolMove(Blend2 stance)      RifleMove(Blend2 stance)
#                    \                      /
#                   WeaponBlend(Blend2 weapon)      Unarmed(1D)
#                              \                     /
#                             HolsterBlend(Blend2 holster)
#                                        |
#              FireShot(OneShot, upper-body filter, shot=FireClip)
#                                        |
#              ReloadShot(OneShot, upper-body filter, shot=ReloadClip)
#                                        |
#                                     output
#
# Aim blend spaces are (x = strafe -1..1, y = forward -1..1). Honest gaps,
# stated at the M2 checkpoint: the pistol set has no relaxed walk (carry
# reuses the aim walk) and no backward walk (reuses the forward walk clip).
#
# The one-shot FILTERS carry the ROADMAP's upper/lower split: fire/reload
# override only the Spine subtree (measured from the skeleton, not typed by
# hand), so legs keep playing locomotion underneath.

const CHARACTER := "res://scenes/characters/hunter.tscn"
const OUT := "res://resources/animation/player_anim_tree.tres"

# Pistol carry is a COMPOSITE of real clips: body from Quaternius' CC0
# neutral walk/jog (the Mixamo "Walking"/"Jogging" clips sway too much —
# "very zesty" per the user), with ONLY the right (gun) arm held on the
# Mixamo unarmed standing idle. Chosen by MEASUREMENT, not name: U_Idle
# hangs both arms by the side (upper-arm tilt ~9 deg from vertical, elbow
# ~170 deg, hands below hip line, stable across all 8.3 s) — the user's
# requested neutral. UAL_Pistol_Idle, despite the name, is a two-handed
# READY pose (right hand 0.53 m ABOVE the hips) and W1's relaxed idle holds
# the gun two-handed in front; both failed user review. On top of the
# hanging arm, ONLY the finger bones are held on the W1 pistol-grip idle so
# the revolver sits in a wrapped hand instead of floating in the unarmed
# clip's open palm. Composing sourced clips at the tree level is NOT the
# forbidden pose synthesis: every input is unedited mocap.
const PISTOL_CARRY := ["U_Idle", "UAL_Walk", "UAL_Jog_Fwd"]
const PISTOL_CARRY_UPPER := "U_Idle"
const PISTOL_CARRY_GRIP := "W1_Stand_Aim_Idle_IPC"
# Rifle carry is the SAME composite trick as the pistol: body/legs from the
# gait clips, both ARMS held on the two-handed low-carry idle. Forced by
# measurement (2026-07-23): R_Carry_Jog_F, despite the name, jogs with the
# rifle RAISED to a high ready (left wrist +0.50 m above hips, upper arm 73
# deg — an aim pose; user: "the weapon is aimed on jogging"), while
# R_Carry_Walk_F is a genuine low carry (arm 20 deg, wrist +0.15). The arm
# filter covers BOTH clavicle subtrees — the rifle is two-handed — and the
# support-hand IK stays on during rifle carry to weld the left palm to the
# handguard at every gait.
const RIFLE_CARRY := ["W2_Stand_Relaxed_Idle_v2", "R_Carry_Walk_F", "R_Carry_Jog_F"]
const RIFLE_CARRY_HOLD := "W2_Stand_Relaxed_Idle_v2"
const UNARMED := ["UAL_Idle", "UAL_Walk", "UAL_Jog_Fwd"]

# [clip, x, y]
const PISTOL_AIM := [
	["W1_Stand_Aim_Idle_IPC", 0.0, 0.0],
	["W1_Walk_Aim_F_Loop_IPC", 0.0, 1.0],
	["W1_Aim_Walk_B", 0.0, -1.0],
	["W1_Aim_Strafe_A", -1.0, 0.0],
	["W1_Aim_Strafe_B", 1.0, 0.0],
]
const RIFLE_AIM := [
	["W2_Stand_Aim_Idle_v2", 0.0, 0.0],
	["W2_Walk_Aim_F_Loop_IPC", 0.0, 1.0],
	["R_Aim_Walk_B", 0.0, -1.0],
	["R_Aim_Strafe_L", -1.0, 0.0],
	["R_Aim_Strafe_R", 1.0, 0.0],
]

const FIRE_CLIPS := ["W1_Stand_Fire_Single", "R_Fire"]
const RELOAD_CLIPS := ["W1_Reload", "R_Reload"]


func _init() -> void:
	var filter_paths := _subtree_paths("Spine")
	var right_arm_paths := _subtree_paths("RightShoulder")
	var left_arm_paths := _subtree_paths("LeftShoulder")
	var finger_paths := _subtree_paths("RightHand")
	finger_paths = finger_paths.filter(
		func(p: String) -> bool: return not p.ends_with(":RightHand")
	)
	if (
		filter_paths.is_empty()
		or right_arm_paths.is_empty()
		or left_arm_paths.is_empty()
		or finger_paths.is_empty()
	):
		push_error("could not measure filter bones")
		quit(1)
		return

	var tree := AnimationNodeBlendTree.new()

	# PistolCarryUpper = the gun arm's held pose: the hanging U_Idle arm with
	# ONLY the finger bones (RightHand subtree minus the wrist) overridden by
	# the W1 pistol-grip idle. blend_amount pinned to 1.0 by player.gd.
	tree.add_node("CarryArmPose", _anim(PISTOL_CARRY_UPPER), Vector2(-1000, -180))
	tree.add_node("CarryGrip", _anim(PISTOL_CARRY_GRIP), Vector2(-1000, -80))
	var finger_mix := AnimationNodeBlend2.new()
	finger_mix.filter_enabled = true
	for p in finger_paths:
		finger_mix.set_filter_path(p, true)
	tree.add_node("PistolCarryUpper", finger_mix, Vector2(-800, -150))
	tree.connect_node("PistolCarryUpper", 0, "CarryArmPose")
	tree.connect_node("PistolCarryUpper", 1, "CarryGrip")

	# PistolCarry = Blend2 with a RIGHT-ARM filter: unfiltered tracks (body,
	# legs, left arm) come from the walk/jog space, filtered tracks (the gun
	# arm) hold the composed carry pose. blend_amount = the live-tunable
	# pistol_carry_arm_lock.
	tree.add_node("PistolCarryLegs", _space_1d(PISTOL_CARRY), Vector2(-800, -250))
	var carry_mix := AnimationNodeBlend2.new()
	carry_mix.filter_enabled = true
	for p in right_arm_paths:
		carry_mix.set_filter_path(p, true)
	tree.add_node("PistolCarry", carry_mix, Vector2(-600, -200))
	tree.connect_node("PistolCarry", 0, "PistolCarryLegs")
	tree.connect_node("PistolCarry", 1, "PistolCarryUpper")
	# RifleCarry = Blend2 with a BOTH-ARMS filter: unfiltered tracks (body,
	# legs, spine) come from the gait space, filtered tracks (both clavicle
	# subtrees) hold the two-handed low-carry idle. blend_amount = the
	# live-tunable rifle_carry_arm_lock.
	tree.add_node("RifleCarryLegs", _space_1d(RIFLE_CARRY), Vector2(-800, 20))
	tree.add_node("RifleCarryHold", _anim(RIFLE_CARRY_HOLD), Vector2(-800, 100))
	var rifle_carry_mix := AnimationNodeBlend2.new()
	rifle_carry_mix.filter_enabled = true
	for p in right_arm_paths:
		rifle_carry_mix.set_filter_path(p, true)
	for p in left_arm_paths:
		rifle_carry_mix.set_filter_path(p, true)
	tree.add_node("RifleCarry", rifle_carry_mix, Vector2(-600, 0))
	tree.connect_node("RifleCarry", 0, "RifleCarryLegs")
	tree.connect_node("RifleCarry", 1, "RifleCarryHold")
	tree.add_node("Unarmed", _space_1d(UNARMED), Vector2(-600, 200))
	tree.add_node("PistolAim", _space_2d(PISTOL_AIM), Vector2(-600, -300))
	tree.add_node("RifleAim", _space_2d(RIFLE_AIM), Vector2(-600, -100))

	tree.add_node("PistolMove", AnimationNodeBlend2.new(), Vector2(-400, -250))
	tree.add_node("RifleMove", AnimationNodeBlend2.new(), Vector2(-400, -50))
	tree.add_node("WeaponBlend", AnimationNodeBlend2.new(), Vector2(-200, -150))
	tree.add_node("HolsterBlend", AnimationNodeBlend2.new(), Vector2(0, -50))

	tree.add_node("FirePistol", _anim(FIRE_CLIPS[0]), Vector2(-200, -450))
	tree.add_node("FireRifle", _anim(FIRE_CLIPS[1]), Vector2(-200, -350))
	tree.add_node("FireClip", AnimationNodeBlend2.new(), Vector2(0, -400))
	tree.add_node("ReloadPistol", _anim(RELOAD_CLIPS[0]), Vector2(0, -550))
	tree.add_node("ReloadRifle", _anim(RELOAD_CLIPS[1]), Vector2(0, -450))
	tree.add_node("ReloadClip", AnimationNodeBlend2.new(), Vector2(200, -500))
	tree.add_node("FireShot", _one_shot(filter_paths), Vector2(200, -100))
	tree.add_node("ReloadShot", _one_shot(filter_paths), Vector2(400, -100))
	tree.connect_node("FireClip", 0, "FirePistol")
	tree.connect_node("FireClip", 1, "FireRifle")
	tree.connect_node("ReloadClip", 0, "ReloadPistol")
	tree.connect_node("ReloadClip", 1, "ReloadRifle")

	tree.connect_node("PistolMove", 0, "PistolCarry")
	tree.connect_node("PistolMove", 1, "PistolAim")
	tree.connect_node("RifleMove", 0, "RifleCarry")
	tree.connect_node("RifleMove", 1, "RifleAim")
	tree.connect_node("WeaponBlend", 0, "PistolMove")
	tree.connect_node("WeaponBlend", 1, "RifleMove")
	tree.connect_node("HolsterBlend", 0, "WeaponBlend")
	tree.connect_node("HolsterBlend", 1, "Unarmed")
	tree.connect_node("FireShot", 0, "HolsterBlend")
	tree.connect_node("FireShot", 1, "FireClip")
	tree.connect_node("ReloadShot", 0, "FireShot")
	tree.connect_node("ReloadShot", 1, "ReloadClip")
	tree.connect_node("output", 0, "ReloadShot")

	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var err := ResourceSaver.save(tree, OUT)
	print("ANIMTREE  filters=", filter_paths.size(), " saved=", OUT, " err=", err)
	quit(0 if err == OK else 1)


func _anim(clip: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node


func _space_1d(clips: Array) -> AnimationNodeBlendSpace1D:
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = 1.0
	# Evenly spaced over 0..1 regardless of clip count (a hardcoded 3-point
	# table crashed on the day a 4th gait clip appeared — issue #10).
	var last := maxi(clips.size() - 1, 1)
	for i in clips.size():
		space.add_blend_point(_anim(clips[i]), float(i) / float(last))
	return space


func _space_2d(points: Array) -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-1, -1)
	space.max_space = Vector2(1, 1)
	for p: Array in points:
		space.add_blend_point(_anim(p[0]), Vector2(p[1], p[2]))
	return space


func _one_shot(filter_paths: Array[String]) -> AnimationNodeOneShot:
	var shot := AnimationNodeOneShot.new()
	shot.filter_enabled = true
	for p in filter_paths:
		shot.set_filter_path(p, true)
	return shot


# Track paths for a bone subtree, measured off the real skeleton so lists
# survive BoneMap changes. "Spine" = the upper body (legs/hips unfiltered);
# "RightShoulder" = the gun arm.
func _subtree_paths(root_bone: String) -> Array[String]:
	var out: Array[String] = []
	var ps: PackedScene = load(CHARACTER)
	if ps == null:
		return out
	var hunter: Node = ps.instantiate()
	var skel: Skeleton3D = hunter.get_node("%GeneralSkeleton")
	if skel == null:
		return out
	# A BoneMap rename must fail loudly here, not emit a junk filter list
	# built from index -1 (issue #10).
	var root_idx := skel.find_bone(root_bone)
	if root_idx == -1:
		push_error("filter root bone not found: " + root_bone)
		hunter.free()
		return out
	var stack := [root_idx]
	while stack.size() > 0:
		var b: int = stack.pop_back()
		out.append("%GeneralSkeleton:" + skel.get_bone_name(b))
		for c in skel.get_bone_children(b):
			stack.append(c)
	hunter.free()
	return out
