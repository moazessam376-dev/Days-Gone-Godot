@tool
extends SkeletonModifier3D

# @tool for parity with the rest of the rig modifiers, so the editor preview
# matches the runtime pose. Ships with every pitch at 0.0, so it is a no-op
# either way -- see docs/rig-tuning.md for why the global version stays zeroed.

# Global posture bias: additive pitch on the spine chain, applied on top of
# every clip. Exists because the sourced mocap holds a forward hunch with the
# chest pushed out (user-flagged on both weapon sets); rather than editing
# dozens of clips, the correction is one live-tunable modifier.
#
# Negative degrees lean the bone BACK (straighten a forward hunch).
# Runs before TorsoLookAt in the modifier stack so aim still solves against
# the corrected posture. Tuned by the user in the running game (Remote tree),
# then baked into tools/build_character.gd.

@export_range(-30.0, 30.0, 0.1) var spine_pitch_deg := 0.0:
	set(v):
		spine_pitch_deg = v
@export_range(-30.0, 30.0, 0.1) var chest_pitch_deg := 0.0:
	set(v):
		chest_pitch_deg = v
@export_range(-30.0, 30.0, 0.1) var upper_chest_pitch_deg := 0.0:
	set(v):
		upper_chest_pitch_deg = v

## Swings the gun arm away from the body in the frontal plane (positive =
## outward for the right arm) so the held pistol stops clipping the hip
## during carry locomotion.
@export_range(-30.0, 30.0, 0.1) var right_arm_out_deg := 0.0:
	set(v):
		right_arm_out_deg = v


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	_rotate(skel, "Spine", Vector3.RIGHT, spine_pitch_deg)
	_rotate(skel, "Chest", Vector3.RIGHT, chest_pitch_deg)
	_rotate(skel, "UpperChest", Vector3.RIGHT, upper_chest_pitch_deg)
	# Character faces +Z after retarget normalisation, so the frontal plane is
	# XY and rotation about +Z abducts the down-hanging arm; negative Z moves
	# the RIGHT arm outward (toward -X).
	_rotate(skel, "RightUpperArm", Vector3(0, 0, -1), right_arm_out_deg)


func _rotate(skel: Skeleton3D, bone_name: String, axis: Vector3, deg: float) -> void:
	if absf(deg) < 0.01:
		return
	var b := skel.find_bone(bone_name)
	if b == -1:
		return
	var pose := skel.get_bone_pose_rotation(b)
	skel.set_bone_pose_rotation(b, Quaternion(axis, deg_to_rad(deg)) * pose)
