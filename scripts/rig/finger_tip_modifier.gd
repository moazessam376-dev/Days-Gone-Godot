extends SkeletonModifier3D

## Curls the 4th finger joint, which the humanoid retarget cannot reach.
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
	# Both _process_modification() and _process_modification_with_delta() were
	# measured NOT to dispatch on 4.7 for a script attached to a bare
	# SkeletonModifier3D node (verified live: node active, influence 1.0,
	# get_skeleton() valid, has_method() true, yet the tips stayed at rest;
	# calling the method by hand moved them correctly). Skeleton3D's
	# `pose_updated` signal is documented to fire when the pose is updated and
	# explicitly NOT during modifier processing, so it drives this without
	# re-entrancy.
	var skel := get_skeleton()
	if skel != null and not skel.pose_updated.is_connected(_apply_tips):
		skel.pose_updated.connect(_apply_tips)


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
		skel.set_bone_pose_rotation(tip, _rest_cache[i] * scaled)


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
