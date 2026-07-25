@tool
extends SkeletonModifier3D

# @tool is LOAD-BEARING, not decoration. Without it this modifier only runs at
# runtime -- and the runtime has no gizmo (the editor viewport draws the EDITED
# scene, so a node picked in the Remote dock is inspectable but not draggable).
# That left the wrist correction with a gizmo in the editor where the code did
# not run, and running code in the game where there was no gizmo: numerically
# correct, practically unusable. The whole point of WristTarget is that it can
# be dragged and SEEN, so the modifier has to execute in the editor.

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
##   WRIST rotation ......... rotate the `WristTarget` node with the E gizmo
##                            (SupportGrip/WristTarget). `wrist_offset_deg`
##                            below MIRRORS it for reading and baking.
##   FINGER curl ............ `thumb_curl` / `index_curl` / `middle_curl`.
##                            Synty hands have only three chains: thumb, index,
##                            and one merged chain covering middle+ring+little.
##                            Sliders, not a gizmo — Godot 4 has no in-viewport
##                            bone gizmo (godot-proposals#887, #2891), so
##                            per-joint posing physically cannot happen here.
##                            It moves to Blender once authoring lands.
##
## Curl values are DEGREES added to whatever the animation already does, so 0
## everywhere means "exactly the mocap pose" and this node is a no-op.

const CHAINS := {
	"thumb": ["LeftThumbMetacarpal", "LeftThumbProximal", "LeftThumbDistal"],
	"index": ["LeftIndexProximal", "LeftIndexIntermediate", "LeftIndexDistal"],
	"middle": ["LeftMiddleProximal", "LeftMiddleIntermediate", "LeftMiddleDistal"],
}

## The GUN (right) hand. It had no controls at all until 2026-07-25 — the user
## hit "I have 0 control over the right hand, and it's not properly placed",
## which is a plumbing bug by this project's own rule: if there is no control
## for part of the pose, that is Claude's fault, not a question.
const RIGHT_CHAINS := {
	"thumb": ["RightThumbMetacarpal", "RightThumbProximal", "RightThumbDistal"],
	"index": ["RightIndexProximal", "RightIndexIntermediate", "RightIndexDistal"],
	"middle": ["RightMiddleProximal", "RightMiddleIntermediate", "RightMiddleDistal"],
}

## The draggable wrist control: a Node3D whose ROTATION is the correction.
## Rotate it with the E gizmo instead of typing Euler triples — a number field
## is what put the user back into the adjust-screenshot-adjust loop this whole
## layer exists to avoid (see .claude/skills/godot-human-in-the-loop/).
##
## Authoritative when set. WeaponManager writes the per-weapon value HERE on
## equip, and `wrist_offset_deg` mirrors it back for reading and baking.
@export var wrist_target: NodePath

## Extra rotation on the left wrist, in degrees. MIRRORS `wrist_target` when one
## is wired — this is the read-back you hand to Claude for baking into
## tools/build_weapons.gd, not the thing to type into. It stays writable so the
## tuner still works on a rig with no gizmo attached.
@export var wrist_offset_deg := Vector3.ZERO

@export_group("Finger curl (degrees, added to the animation)")
@export_range(-90.0, 90.0, 0.5) var thumb_curl := 0.0
@export_range(-90.0, 90.0, 0.5) var index_curl := 0.0
@export_range(-90.0, 90.0, 0.5) var middle_curl := 0.0

@export_group("Gun (right) hand")
## Draggable roll for the GUN hand: rotate `RightWristTarget` with the E gizmo.
##
## CAUTION, and it is the whole reason this is separate from the grip: the
## weapon hangs off the RightHand bone via BoneAttachment3D, so rotating this
## rotates the GUN with the hand. It aims the weapon; it does not re-seat the
## hand on it. To fix how the hand SITS on the gun, move the gun instead —
## `WeaponSocket` (gizmo) or the weapon's `mesh_offset` — and wrap the fingers
## with the curls below.
@export var right_wrist_target: NodePath

## Mirrors `right_wrist_target` when one is wired. Read-back for baking.
@export var right_wrist_offset_deg := Vector3.ZERO

## Curl for the gun hand, degrees on top of the animation. This is the control
## for "the fingers are not wrapping the pistol grip" — it closes the hand
## around the weapon without moving the weapon.
@export_range(-90.0, 90.0, 0.5) var right_thumb_curl := 0.0
@export_range(-90.0, 90.0, 0.5) var right_index_curl := 0.0
@export_range(-90.0, 90.0, 0.5) var right_middle_curl := 0.0

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
var _right_wrist := -1
var _resolved := false
var _target_cache: Node3D = null
var _right_target_cache: Node3D = null


# A @tool script that gains a new @export while the editor is holding a LIVE
# instance leaves that property NIL on the existing node until the scene is
# reloaded. Reading it then throws "Cannot convert argument 2 from Nil to float"
# every single frame, which reads as a logic bug in this file and is not one.
#
# Costs nothing to be defensive, and it means adding a control never floods the
# user's editor with errors mid-session.
func _f(prop: StringName) -> float:
	var v: Variant = get(prop)
	return float(v) if v != null else 0.0


func _v3(prop: StringName) -> Vector3:
	var v: Variant = get(prop)
	return v if v is Vector3 else Vector3.ZERO


func _right_wrist_target() -> Node3D:
	if _right_target_cache != null and is_instance_valid(_right_target_cache):
		return _right_target_cache
	if right_wrist_target.is_empty():
		return null
	_right_target_cache = get_node_or_null(right_wrist_target) as Node3D
	return _right_target_cache


# Resolved every call rather than cached on _ready: this modifier runs inside
# the editor too, where the gizmo node can be added, moved or renamed while the
# scene is open.
func _wrist_target() -> Node3D:
	if _target_cache != null and is_instance_valid(_target_cache):
		return _target_cache
	if wrist_target.is_empty():
		return null
	_target_cache = get_node_or_null(wrist_target) as Node3D
	return _target_cache


# Do NOT verify this with get_bone_global_pose(): that reads the pose from
# BEFORE the modifier stack runs, so working code looks like a no-op. Count
# `modification_processed`, and judge the result on screen.
func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if not _resolved:
		_resolve(skel)

	# The gizmo node wins when present; its Euler is mirrored back so the value
	# stays readable in the Inspector and bakeable into build_weapons.gd.
	var target := _wrist_target()
	if target != null:
		wrist_offset_deg = target.rotation_degrees

	if _wrist >= 0 and wrist_offset_deg != Vector3.ZERO:
		var off := Quaternion.from_euler(wrist_offset_deg * (PI / 180.0))
		skel.set_bone_pose_rotation(_wrist, skel.get_bone_pose_rotation(_wrist) * off)

	_curl("thumb", thumb_curl, thumb_axis, skel)
	_curl("index", index_curl, curl_axis, skel)
	_curl("middle", middle_curl, curl_axis, skel)

	# --- gun (right) hand ---
	var right_target := _right_wrist_target()
	if right_target != null:
		right_wrist_offset_deg = right_target.rotation_degrees

	var right_off := _v3(&"right_wrist_offset_deg")
	if _right_wrist >= 0 and right_off != Vector3.ZERO:
		var roff := Quaternion.from_euler(right_off * (PI / 180.0))
		skel.set_bone_pose_rotation(
			_right_wrist, skel.get_bone_pose_rotation(_right_wrist) * roff
		)

	_curl("right_thumb", _f(&"right_thumb_curl"), thumb_axis, skel)
	_curl("right_index", _f(&"right_index_curl"), curl_axis, skel)
	_curl("right_middle", _f(&"right_middle_curl"), curl_axis, skel)


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
	_right_wrist = skel.find_bone("RightHand")
	_bones.clear()
	for chain: String in CHAINS:
		_bones[chain] = _resolve_chain(skel, CHAINS[chain])
	for chain: String in RIGHT_CHAINS:
		_bones["right_" + chain] = _resolve_chain(skel, RIGHT_CHAINS[chain])


func _resolve_chain(skel: Skeleton3D, names: Array) -> Array[int]:
	var idxs: Array[int] = []
	for n: String in names:
		var i := skel.find_bone(n)
		if i >= 0:
			idxs.append(i)
	return idxs
