extends SceneTree

# Authors a BoneMap for the Synty POLYGON Apocalypse rig against
# SkeletonProfileHumanoid, using bone names VERIFIED by dumping the real
# imported skeleton (50 bones) rather than trusting auto-mapping.
#
# THE TRAP this exists to avoid: Synty's `Shoulder_L` is the UPPER ARM and
# `Clavicle_L` is the SHOULDER. The hierarchy proves it:
#   Spine_03 -> Clavicle_L -> Shoulder_L -> Elbow_L -> Hand_L
# Godot's auto-mapper guesses by name and gets this backwards, which is the
# documented cause of twisted-arm retargets.

const MAP := {
	"Root": "Root",
	"Hips": "Hips",
	"Spine": "Spine_01",
	"Chest": "Spine_02",
	"UpperChest": "Spine_03",
	"Neck": "Neck",
	"Head": "Head",
	"Jaw": "Jaw",

	# --- Left arm (note the Clavicle/Shoulder swap) ---
	"LeftShoulder": "Clavicle_L",
	"LeftUpperArm": "Shoulder_L",
	"LeftLowerArm": "Elbow_L",
	"LeftHand": "Hand_L",
	"LeftThumbMetacarpal": "Thumb_01",
	"LeftThumbProximal": "Thumb_02",
	"LeftThumbDistal": "Thumb_03",
	"LeftIndexProximal": "IndexFinger_01",
	"LeftIndexIntermediate": "IndexFinger_02",
	"LeftIndexDistal": "IndexFinger_03",
	# Synty hands have only THREE chains: thumb, index, and one merged finger.
	# The merged chain is mapped to MIDDLE (not ring) because it carries the
	# most visual mass on a gun grip, so incoming 5-finger animation drives the
	# most representative curl.
	"LeftMiddleProximal": "Finger_01",
	"LeftMiddleIntermediate": "Finger_02",
	"LeftMiddleDistal": "Finger_03",

	# --- Right arm (ufbx suffixes duplicated finger names with _2) ---
	"RightShoulder": "Clavicle_R",
	"RightUpperArm": "Shoulder_R",
	"RightLowerArm": "Elbow_R",
	"RightHand": "Hand_R",
	"RightThumbMetacarpal": "Thumb_01_2",
	"RightThumbProximal": "Thumb_02_2",
	"RightThumbDistal": "Thumb_03_2",
	"RightIndexProximal": "IndexFinger_01_2",
	"RightIndexIntermediate": "IndexFinger_02_2",
	"RightIndexDistal": "IndexFinger_03_2",
	"RightMiddleProximal": "Finger_01_2",
	"RightMiddleIntermediate": "Finger_02_2",
	"RightMiddleDistal": "Finger_03_2",

	# --- Legs. Synty: Ankle -> Ball -> Toes. Godot's "Toes" is the toe BASE,
	# so it maps to Ball_*; Toes_* is the tip and stays unmapped. ---
	"LeftUpperLeg": "UpperLeg_L",
	"LeftLowerLeg": "LowerLeg_L",
	"LeftFoot": "Ankle_L",
	"LeftToes": "Ball_L",
	"RightUpperLeg": "UpperLeg_R",
	"RightLowerLeg": "LowerLeg_R",
	"RightFoot": "Ankle_R",
	"RightToes": "Ball_R",
}


func _init() -> void:
	var ps := load("res://Characters.fbx")
	var root: Node = ps.instantiate()
	var sk: Skeleton3D = _find_skel(root)
	if sk == null:
		print("NO_SKELETON")
		quit(1)
		return

	var actual := {}
	for i in sk.get_bone_count():
		actual[sk.get_bone_name(i)] = true

	var profile := SkeletonProfileHumanoid.new()
	var bm := BoneMap.new()
	bm.profile = profile

	var missing: Array[String] = []
	var unmapped: Array[String] = []
	var bad_slot: Array[String] = []

	for i in profile.bone_size:
		var slot := profile.get_bone_name(i)
		if MAP.has(slot):
			var bone: String = MAP[slot]
			if not actual.has(bone):
				missing.append("%s -> %s (BONE NOT IN SKELETON)" % [slot, bone])
			else:
				bm.set_skeleton_bone_name(slot, bone)
		else:
			unmapped.append(slot)

	# Catch typos in MAP keys that do not exist as profile slots at all.
	var slots := {}
	for i in profile.bone_size:
		slots[profile.get_bone_name(i)] = true
	for k in MAP.keys():
		if not slots.has(k):
			bad_slot.append(k)

	print("PROFILE_SLOTS=", profile.bone_size)
	print("MAPPED=", MAP.size() - missing.size())
	print("--- missing bones (must be empty) ---")
	for m in missing:
		print("  ", m)
	print("--- bad profile slot names in MAP (must be empty) ---")
	for b in bad_slot:
		print("  ", b)
	print("--- intentionally unmapped profile slots ---")
	print("  ", ", ".join(unmapped))

	var err := ResourceSaver.save(bm, "res://synty_apocalypse_bonemap.tres")
	print("SAVE_ERR=", err)
	quit(0 if (missing.is_empty() and bad_slot.is_empty() and err == OK) else 1)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null
