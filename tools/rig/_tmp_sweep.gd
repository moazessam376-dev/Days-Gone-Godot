extends SceneTree

# Pose sweep of the rifle clip family vs approved baselines (skill:
# godot-animation-pipeline — choose/diagnose clips by measurement).
# Metrics per clip, sampled at 3 timestamps:
#   lean  = spine lean from vertical, + = forward (+Z), via Head-Hips
#   Lh/Rh = wrist height above Hips ; Lz/Rz = wrist forward offset vs Hips
#   Larm  = left upper-arm tilt from straight-down ; Lelb = elbow angle
#   grip  = distance between the two wrists (two-handed tell)

const CLIPS := [
	"U_Idle",
	"W1_Stand_Aim_Idle_IPC",
	"UAL_Jog_Fwd",
	"W2_Stand_Relaxed_Idle_v2",
	"W2_Stand_Aim_Idle_v2",
	"W2_Walk_Aim_F_Loop_IPC",
	"R_Carry_Walk_F",
	"R_Carry_Jog_F",
	"R_Aim_Walk_B",
]


func _init() -> void:
	for c: String in CLIPS:
		_measure(c)
	quit(0)


func _measure(clip: String) -> void:
	var ps: PackedScene = load("res://scenes/characters/hunter.tscn")
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	var ap: AnimationPlayer = inst.get_node("AnimationPlayer")
	var skel: Skeleton3D = inst.get_node("%GeneralSkeleton")
	if not ap.has_animation(clip):
		print(clip, "  MISSING")
		inst.free()
		return
	var length := ap.get_animation(clip).length
	var lines := []
	for frac: float in [0.2, 0.5, 0.8]:
		ap.stop()
		ap.play(clip)
		ap.advance(length * frac)
		skel.force_update_all_bone_transforms()
		var hips := skel.get_bone_global_pose(skel.find_bone("Hips")).origin
		var head := skel.get_bone_global_pose(skel.find_bone("Head")).origin
		var lw := skel.get_bone_global_pose(skel.find_bone("LeftHand")).origin
		var rw := skel.get_bone_global_pose(skel.find_bone("RightHand")).origin
		var lua := skel.get_bone_global_pose(skel.find_bone("LeftUpperArm")).origin
		var lel := skel.get_bone_global_pose(skel.find_bone("LeftLowerArm")).origin
		var spine := head - hips
		var lean := rad_to_deg(atan2(spine.z, spine.y))
		var arm_v := (lel - lua).normalized()
		var larm := rad_to_deg(acos(clampf(-arm_v.y, -1.0, 1.0)))
		var e1 := (lua - lel).normalized()
		var e2 := (lw - lel).normalized()
		var lelb := rad_to_deg(acos(clampf(e1.dot(e2), -1.0, 1.0)))
		lines.append(
			(
				"  t=%.1f lean=%+5.1f  Lh=%+.2f Lz=%+.2f  Rh=%+.2f Rz=%+.2f  Larm=%4.1f Lelb=%5.1f grip=%.2f"
				% [
					frac,
					lean,
					lw.y - hips.y,
					lw.z - hips.z,
					rw.y - hips.y,
					rw.z - hips.z,
					larm,
					lelb,
					lw.distance_to(rw)
				]
			)
		)
	print(clip)
	for l: String in lines:
		print(l)
	inst.free()
