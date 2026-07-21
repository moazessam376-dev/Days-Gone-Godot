extends SceneTree
# Proves the retargeted MoCap clip actually drives the Synty skeleton, by
# measuring bone rotations at bind pose vs mid-animation. If the retarget were
# broken these deltas would all be ~0 and the character would stay T-posed.
func _init():
	var ps: PackedScene = load("res://scenes/characters/hunter.tscn")
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	var skel: Skeleton3D = inst.get_node_or_null("%GeneralSkeleton")
	if skel == null: print("SKELETON %GeneralSkeleton NOT RESOLVED"); quit(1); return
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap == null: print("NO ANIMATIONPLAYER"); quit(1); return
	print("ANIM_LIST=", ap.get_animation_list().size(), " autoplay=", ap.autoplay)

	var watch := ["RightUpperArm","RightLowerArm","RightHand","LeftUpperArm","LeftLowerArm",
		"LeftHand","Spine","Chest","Head","RightIndexProximal","RightThumbMetacarpal"]
	var rest := {}
	for b in watch:
		var i := skel.find_bone(b)
		rest[b] = skel.get_bone_pose_rotation(i) if i >= 0 else Quaternion()

	ap.play("W1_Stand_Aim_Idle_IPC")
	ap.advance(0.75)

	var moved := 0
	print("--- bone rotation delta from bind pose (degrees) ---")
	for b in watch:
		var i := skel.find_bone(b)
		if i < 0:
			print("  %-22s BONE MISSING" % b); continue
		var now := skel.get_bone_pose_rotation(i)
		var deg := rad_to_deg(now.angle_to(rest[b]))
		if deg > 1.0: moved += 1
		print("  %-22s %7.2f deg" % [b, deg])
	print("BONES_MOVED=", moved, "/", watch.size())
	print("RESULT=", ("OK" if moved >= 8 else "SUSPECT"))
	quit(0 if moved >= 8 else 1)
