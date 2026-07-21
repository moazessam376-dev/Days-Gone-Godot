extends SceneTree

# Authors the BoneMap for MoCap Online's MotusMan_v55 rig, which every clip in
# the Pistol/Rifle packs is animated on.
#
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
#       --script tools/rig/make_motusman_bonemap.gd
#
# MotusMan uses classic HumanIK / 3ds Max Biped naming (Hips, Spine, Spine1,
# LeftArm, LeftForeArm, LeftHandIndex1...) — the same convention Mixamo uses
# without its `mixamorig:` prefix. That is why Mixamo is a viable fallback:
# swapping animation source costs one BoneMap, not a re-rig.
#
# Verified against the real imported rig: 80 bones.
#
# HOW RETARGETING ACTUALLY WORKS HERE: with a BoneMap assigned at import,
# Godot RENAMES the skeleton's bones to the profile's names. Import the Synty
# character through its map and these clips through this one, and both end up
# speaking `LeftUpperArm` — at which point the animation just drives the
# character. Nothing is retargeted at runtime.
#
# Deliberately unmapped: the ik_* helper bones, the Leaf*Roll1 twist bones,
# and hand_l_wep / hand_r_wep (MotusMan's own weapon sockets). None have a
# humanoid-profile equivalent, and the Synty rig has no counterpart for them.

const MAP := {
	"Root": "Root",
	"Hips": "Hips",
	"Spine": "Spine",
	"Chest": "Spine1",
	"UpperChest": "Spine2",
	"Neck": "Neck",
	"Head": "Head",

	"LeftShoulder": "LeftShoulder",
	"LeftUpperArm": "LeftArm",
	"LeftLowerArm": "LeftForeArm",
	"LeftHand": "LeftHand",
	"LeftThumbMetacarpal": "LeftHandThumb1",
	"LeftThumbProximal": "LeftHandThumb2",
	"LeftThumbDistal": "LeftHandThumb3",
	"LeftIndexProximal": "LeftHandIndex1",
	"LeftIndexIntermediate": "LeftHandIndex2",
	"LeftIndexDistal": "LeftHandIndex3",
	"LeftMiddleProximal": "LeftHandMiddle1",
	"LeftMiddleIntermediate": "LeftHandMiddle2",
	"LeftMiddleDistal": "LeftHandMiddle3",
	"LeftRingProximal": "LeftHandRing1",
	"LeftRingIntermediate": "LeftHandRing2",
	"LeftRingDistal": "LeftHandRing3",
	"LeftLittleProximal": "LeftHandPinky1",
	"LeftLittleIntermediate": "LeftHandPinky2",
	"LeftLittleDistal": "LeftHandPinky3",

	"RightShoulder": "RightShoulder",
	"RightUpperArm": "RightArm",
	"RightLowerArm": "RightForeArm",
	"RightHand": "RightHand",
	"RightThumbMetacarpal": "RightHandThumb1",
	"RightThumbProximal": "RightHandThumb2",
	"RightThumbDistal": "RightHandThumb3",
	"RightIndexProximal": "RightHandIndex1",
	"RightIndexIntermediate": "RightHandIndex2",
	"RightIndexDistal": "RightHandIndex3",
	"RightMiddleProximal": "RightHandMiddle1",
	"RightMiddleIntermediate": "RightHandMiddle2",
	"RightMiddleDistal": "RightHandMiddle3",
	"RightRingProximal": "RightHandRing1",
	"RightRingIntermediate": "RightHandRing2",
	"RightRingDistal": "RightHandRing3",
	"RightLittleProximal": "RightHandPinky1",
	"RightLittleIntermediate": "RightHandPinky2",
	"RightLittleDistal": "RightHandPinky3",

	"LeftUpperLeg": "LeftUpLeg",
	"LeftLowerLeg": "LeftLeg",
	"LeftFoot": "LeftFoot",
	"LeftToes": "LeftToeBase",
	"RightUpperLeg": "RightUpLeg",
	"RightLowerLeg": "RightLeg",
	"RightFoot": "RightFoot",
	"RightToes": "RightToeBase",
}

const SRC := "res://assets/rigs/MotusMan_v55.fbx"
const OUT := "res://resources/rigs/motusman_v55_bonemap.tres"


func _init() -> void:
	var ps: PackedScene = load(SRC)
	if ps == null:
		push_error("cannot load " + SRC)
		quit(1)
		return
	var sk := _find_skel(ps.instantiate())
	if sk == null:
		push_error("no Skeleton3D")
		quit(1)
		return

	var actual := {}
	for i in sk.get_bone_count():
		actual[sk.get_bone_name(i)] = true

	var profile := SkeletonProfileHumanoid.new()
	var bm := BoneMap.new()
	bm.profile = profile

	var slots := {}
	for i in profile.bone_size:
		slots[profile.get_bone_name(i)] = true

	var missing: Array[String] = []
	var bad_slot: Array[String] = []
	for slot: String in MAP:
		if not slots.has(slot):
			bad_slot.append(slot)
		elif not actual.has(MAP[slot]):
			missing.append("%s -> %s (NOT IN SKELETON)" % [slot, MAP[slot]])
		else:
			bm.set_skeleton_bone_name(slot, MAP[slot])

	print("SKELETON_BONES=", sk.get_bone_count())
	print("PROFILE_SLOTS=", profile.bone_size)
	print("MAPPED=", MAP.size() - missing.size() - bad_slot.size())
	print("--- missing bones (must be empty) ---")
	for m in missing:
		print("  ", m)
	print("--- bad slot names (must be empty) ---")
	for b in bad_slot:
		print("  ", b)

	var err := ResourceSaver.save(bm, OUT)
	print("SAVE_ERR=", err, " -> ", OUT)
	quit(0 if (missing.is_empty() and bad_slot.is_empty() and err == OK) else 1)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null
