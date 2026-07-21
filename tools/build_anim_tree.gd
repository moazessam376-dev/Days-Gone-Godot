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

# Pistol carry uses the unarmed walk/jog: no free relaxed pistol locomotion
# exists (Mixamo's "pistol walk" clips are all two-handed aim walks), and the
# aim-pose placeholders read as "always aiming" — the user flagged it. Arms
# swing with the revolver in hand, the Days Gone low-carry look.
const PISTOL_CARRY := ["W1_Stand_Relaxed_Idle_IPC", "U_Walk_F", "U_Jog_F"]
const RIFLE_CARRY := ["W2_Stand_Relaxed_Idle_v2", "R_Carry_Walk_F", "R_Carry_Jog_F"]
const UNARMED := ["U_Idle", "U_Walk_F", "U_Jog_F"]

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
	var filter_paths := _upper_body_paths()
	if filter_paths.is_empty():
		push_error("could not measure upper-body bones")
		quit(1)
		return

	var tree := AnimationNodeBlendTree.new()

	tree.add_node("PistolCarry", _space_1d(PISTOL_CARRY), Vector2(-600, -200))
	tree.add_node("RifleCarry", _space_1d(RIFLE_CARRY), Vector2(-600, 0))
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
	var positions := [0.0, 0.5, 1.0]
	for i in clips.size():
		space.add_blend_point(_anim(clips[i]), positions[i])
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


# The upper body = the Spine subtree, measured off the real skeleton so the
# list survives BoneMap changes. Legs and Hips stay unfiltered.
func _upper_body_paths() -> Array[String]:
	var out: Array[String] = []
	var ps: PackedScene = load(CHARACTER)
	if ps == null:
		return out
	var hunter: Node = ps.instantiate()
	var skel: Skeleton3D = hunter.get_node("%GeneralSkeleton")
	if skel == null:
		return out
	var stack := [skel.find_bone("Spine")]
	while stack.size() > 0:
		var b: int = stack.pop_back()
		out.append("%GeneralSkeleton:" + skel.get_bone_name(b))
		for c in skel.get_bone_children(b):
			stack.append(c)
	hunter.free()
	return out
