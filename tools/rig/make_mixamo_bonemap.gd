extends SceneTree

# Authors the BoneMap for Adobe Mixamo's auto-rigged skeleton (X Bot et al).
#
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
#       --script tools/rig/make_mixamo_bonemap.gd
#
# Mixamo uses HumanIK naming with a `mixamorig:` prefix — the same convention
# as MotusMan without the prefix (see make_motusman_bonemap.gd). 65 bones,
# five full finger chains.
#
# NO ASSUMPTIONS: this script validates every mapped bone name against the
# skeleton actually produced by the importer (ufbx may sanitise the `:`), and
# fails loudly if any name is absent. Run tools/rig/dump_skeleton.gd on
# XBot_TPose.fbx first if it fails, and fix PREFIX / MAP from what you see.
#
# The five-finger chains are mapped in full. After retargeting, ring/little
# tracks reference profile bones the 3-finger Synty rig does not have; those
# tracks simply do not resolve, which is harmless.

# ufbx sanitises the `:` in Mixamo's `mixamorig:Hips` to an underscore.
# MEASURED from the imported XBot_TPose.fbx (65 bones) — not assumed.
const PREFIX := "mixamorig_"

const MAP := {
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

const SRC := "res://assets/rigs/XBot_TPose.fbx"
const OUT := "res://resources/rigs/mixamo_bonemap.tres"


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
		var bone: String = PREFIX + MAP[slot]
		if not slots.has(slot):
			bad_slot.append(slot)
		elif not actual.has(bone):
			missing.append("%s -> %s (NOT IN SKELETON)" % [slot, bone])
		else:
			bm.set_skeleton_bone_name(slot, bone)

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
