@tool
extends SkeletonModifier3D

## Curls the 4th finger joint, which the humanoid retarget cannot reach.
##
## @tool so the hand previews correctly in the EDITOR while the user drags
## WristTarget. Without it the tip joints sit in bind pose while the rest of the
## finger curls, so a grip that is actually fine reads as broken.
##
## THE PROBLEM: Synty fingers have FOUR joints. Godot's SkeletonProfileHumanoid
## defines only three (Proximal / Intermediate / Distal). So the 4th joint of
## every finger — IndexFinger_04, Finger_04 and their `_2` right-side twins —
## is never mapped, never renamed, and never receives an animation track. It
## stays frozen in bind pose while the rest of the finger curls, leaving a
## fingertip sticking straight out of an otherwise closed fist.
##
## It reads worse on the LEFT hand because those tips sit at ~225 degrees in
## rest versus ~105 on the right, so freezing them is about twice as wrong.
##
## THE FIX: propagate the parent Distal joint's animated rotation onto the tip,
## scaled by `follow`. This is not inventing a pose — it is completing a chain
## the profile truncates, driven entirely by the mocap data already on the
## parent joint. If a future rig maps all four joints, set influence to 0.
##
## Runs as a SkeletonModifier3D so it executes AFTER the AnimationMixer has
## posed the skeleton, and so `influence` can blend it out.

## How much of the parent's curl the tip inherits. Real fingertips flex a
## little less than the joint below them.
@export_range(0.0, 1.0) var follow: float = 0.7

## Tip bone -> parent bone. Populated automatically when left empty.
@export var tip_bones: PackedStringArray = []

var _pairs: Array[Vector2i] = []
var _rest_cache: Array[Quaternion] = []
var _resolved := false


func _ready() -> void:
	_resolved = false


# HARD-WON NOTE: do not "verify" a modifier with get_bone_global_pose(). That
# returns the pose BEFORE the modifier stack runs, so a perfectly working
# modifier reads as a no-op and you will chase it for an hour. Confirm a
# modifier is live by counting its `modification_processed` signal, and judge
# the result on screen.
func _process_modification() -> void:
	_apply_tips()


func _process_modification_with_delta(_delta: float) -> void:
	_apply_tips()


func _apply_tips() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if not _resolved:
		_resolve(skel)
	for i in _pairs.size():
		var tip := _pairs[i].x
		var parent := _pairs[i].y
		# The parent's rotation relative to ITS rest is the curl the animation
		# actually applied. Reapply a fraction of that to the tip's own rest,
		# so the tip's authored orientation is preserved.
		var p_rest := skel.get_bone_rest(parent).basis.get_rotation_quaternion()
		var p_pose := skel.get_bone_pose_rotation(parent)
		var curl := p_rest.inverse() * p_pose
		var scaled := Quaternion.IDENTITY.slerp(curl.normalized(), follow)
		# PRE-multiply, not post-multiply. `curl` was measured in the PARENT's
		# local frame, so it has to be applied in that frame too. Post-
		# multiplying would apply it in the TIP's own frame, and these tips are
		# exactly the bones the retarget did NOT axis-normalise (unmapped bones
		# skip Overwrite Axis), so their local axes do not line up with their
		# parent's — the finger then bends sideways/inward instead of curling.
		skel.set_bone_pose_rotation(tip, scaled * _rest_cache[i])


func _resolve(skel: Skeleton3D) -> void:
	_resolved = true
	_pairs.clear()
	_rest_cache.clear()

	var names := tip_bones
	if names.is_empty():
		# Auto-detect: any bone whose PARENT is a mapped *Distal joint is a
		# fourth joint the humanoid profile had no slot for.
		var found: PackedStringArray = []
		for i in skel.get_bone_count():
			var parent_idx := skel.get_bone_parent(i)
			if parent_idx < 0:
				continue
			if skel.get_bone_name(parent_idx).ends_with("Distal"):
				found.append(skel.get_bone_name(i))
		names = found

	for n in names:
		var tip := skel.find_bone(n)
		if tip < 0:
			push_warning("finger_tip_modifier: no bone named %s" % n)
			continue
		var parent := skel.get_bone_parent(tip)
		if parent < 0:
			continue
		_pairs.append(Vector2i(tip, parent))
		_rest_cache.append(skel.get_bone_rest(tip).basis.get_rotation_quaternion())
