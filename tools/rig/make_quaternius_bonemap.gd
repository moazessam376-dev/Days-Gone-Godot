extends SceneTree

# Authors the BoneMap for Quaternius' Universal Animation Library rig
# (UE-mannequin naming: pelvis, spine_01..03, clavicle_l, upperarm_l...).
#
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
#       --script tools/rig/make_quaternius_bonemap.gd
#
# Measured off the imported UAL1_Standard.glb (65 bones, five fingers with
# _04_leaf tips). Validates every mapped name against the real skeleton and
# fails loudly — same discipline as the MotusMan/Mixamo maps.

const MAP := {
	"Root": "root",
	"Hips": "pelvis",
	"Spine": "spine_01",
	"Chest": "spine_02",
	"UpperChest": "spine_03",
	"Neck": "neck_01",
	"Head": "Head",

	"LeftShoulder": "clavicle_l",
	"LeftUpperArm": "upperarm_l",
	"LeftLowerArm": "lowerarm_l",
	"LeftHand": "hand_l",
	"LeftThumbMetacarpal": "thumb_01_l",
	"LeftThumbProximal": "thumb_02_l",
	"LeftThumbDistal": "thumb_03_l",
	"LeftIndexProximal": "index_01_l",
	"LeftIndexIntermediate": "index_02_l",
	"LeftIndexDistal": "index_03_l",
	"LeftMiddleProximal": "middle_01_l",
	"LeftMiddleIntermediate": "middle_02_l",
	"LeftMiddleDistal": "middle_03_l",
	"LeftRingProximal": "ring_01_l",
	"LeftRingIntermediate": "ring_02_l",
	"LeftRingDistal": "ring_03_l",
	"LeftLittleProximal": "pinky_01_l",
	"LeftLittleIntermediate": "pinky_02_l",
	"LeftLittleDistal": "pinky_03_l",

	"RightShoulder": "clavicle_r",
	"RightUpperArm": "upperarm_r",
	"RightLowerArm": "lowerarm_r",
	"RightHand": "hand_r",
	"RightThumbMetacarpal": "thumb_01_r",
	"RightThumbProximal": "thumb_02_r",
	"RightThumbDistal": "thumb_03_r",
	"RightIndexProximal": "index_01_r",
	"RightIndexIntermediate": "index_02_r",
	"RightIndexDistal": "index_03_r",
	"RightMiddleProximal": "middle_01_r",
	"RightMiddleIntermediate": "middle_02_r",
	"RightMiddleDistal": "middle_03_r",
	"RightRingProximal": "ring_01_r",
	"RightRingIntermediate": "ring_02_r",
	"RightRingDistal": "ring_03_r",
	"RightLittleProximal": "pinky_01_r",
	"RightLittleIntermediate": "pinky_02_r",
	"RightLittleDistal": "pinky_03_r",

	"LeftUpperLeg": "thigh_l",
	"LeftLowerLeg": "calf_l",
	"LeftFoot": "foot_l",
	"LeftToes": "ball_l",
	"RightUpperLeg": "thigh_r",
	"RightLowerLeg": "calf_r",
	"RightFoot": "foot_r",
	"RightToes": "ball_r",
}

const SRC := "res://assets/animations/ual/UAL1_Standard.glb"
const OUT := "res://resources/rigs/quaternius_ual_bonemap.tres"


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
