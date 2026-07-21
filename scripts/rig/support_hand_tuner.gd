extends SkeletonModifier3D

## Hand-authored corrections for the SUPPORT (left) hand, on top of the mocap.
##
## Everything here is meant to be dragged or typed in the editor while the game
## runs — this node exists so nobody has to edit code to fix a pose.
##
## MUST sit BELOW LeftArmIK in the Skeleton3D's child list. Modifiers run
## top-to-bottom, so the IK places the arm first and these offsets refine it.
##
## WHAT CONTROLS WHAT (all live, no restart):
##
##   Arm / hand POSITION .... drag `SupportGrip`
##                            (GeneralSkeleton/RightHandAttach/WeaponSocket)
##                            It is parented to the gun, so it stays correct in
##                            every animation.
##   Elbow direction ........ drag `LeftElbowPole`, or edit LeftArmIK's
##                            pole_direction_vector.
##   WRIST rotation ......... `wrist_offset_deg` on this node.
##   FINGER curl ............ `thumb_curl` / `index_curl` / `middle_curl`.
##                            Synty hands have only three chains: thumb, index,
##                            and one merged chain covering middle+ring+little.
##
## Curl values are DEGREES added to whatever the animation already does, so 0
## everywhere means "exactly the mocap pose" and this node is a no-op.

const CHAINS := {
	"thumb": ["LeftThumbMetacarpal", "LeftThumbProximal", "LeftThumbDistal"],
	"index": ["LeftIndexProximal", "LeftIndexIntermediate", "LeftIndexDistal"],
	"middle": ["LeftMiddleProximal", "LeftMiddleIntermediate", "LeftMiddleDistal"],
}

## Extra rotation on the left wrist, in degrees. Use this to roll the palm onto
## the grip when the IK has the position right but the hand is turned wrong.
@export var wrist_offset_deg := Vector3.ZERO

@export_group("Finger curl (degrees, added to the animation)")
@export_range(-90.0, 90.0, 0.5) var thumb_curl := 0.0
@export_range(-90.0, 90.0, 0.5) var index_curl := 0.0
@export_range(-90.0, 90.0, 0.5) var middle_curl := 0.0

@export_group("Bend axes (measured from the mocap — rarely need changing)")
## Axis the index/middle joints bend around. Measured off the animation's own
## rotation on LeftIndexProximal / LeftMiddleProximal, which curl about
## (0.99, 0.13, -0.03) and (0.997, 0.01, -0.07) — i.e. clean +X.
@export var curl_axis := Vector3(1, 0, 0)
## The thumb opposes rather than curls, so it rotates about a different axis.
## Measured off LeftThumbProximal: (0.728, -0.020, 0.685).
@export var thumb_axis := Vector3(0.728, 0.0, 0.685)

var _bones: Dictionary = {}
var _wrist := -1
var _resolved := false


# Do NOT verify this with get_bone_global_pose(): that reads the pose from
# BEFORE the modifier stack runs, so working code looks like a no-op. Count
# `modification_processed`, and judge the result on screen.
func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if not _resolved:
		_resolve(skel)

	if _wrist >= 0 and wrist_offset_deg != Vector3.ZERO:
		var off := Quaternion.from_euler(wrist_offset_deg * (PI / 180.0))
		skel.set_bone_pose_rotation(_wrist, skel.get_bone_pose_rotation(_wrist) * off)

	_curl("thumb", thumb_curl, thumb_axis, skel)
	_curl("index", index_curl, curl_axis, skel)
	_curl("middle", middle_curl, curl_axis, skel)


func _curl(chain: String, degrees: float, axis: Vector3, skel: Skeleton3D) -> void:
	if is_zero_approx(degrees):
		return
	var idxs: Array = _bones.get(chain, [])
	if idxs.is_empty():
		return
	# Spread the curl across the joints so the finger rolls closed rather than
	# hinging entirely at the knuckle.
	var per := deg_to_rad(degrees) / float(idxs.size())
	var q := Quaternion(axis.normalized(), per)
	for i: int in idxs:
		skel.set_bone_pose_rotation(i, skel.get_bone_pose_rotation(i) * q)


func _resolve(skel: Skeleton3D) -> void:
	_resolved = true
	_wrist = skel.find_bone("LeftHand")
	_bones.clear()
	for chain: String in CHAINS:
		var idxs: Array[int] = []
		for n: String in CHAINS[chain]:
			var i := skel.find_bone(n)
			if i >= 0:
				idxs.append(i)
		_bones[chain] = idxs
