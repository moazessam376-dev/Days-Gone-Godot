extends SceneTree
func _init():
	var a := _bones("res://assets/characters/Characters.fbx")
	var b := _bones("res://assets/animations/pistol/W1_Stand_Aim_Idle_IPC.fbx")
	print("SYNTY bones=", a.size())
	print("MOCAP bones=", b.size())
	var key := ["Hips","Spine","Chest","UpperChest","Neck","Head",
		"LeftShoulder","LeftUpperArm","LeftLowerArm","LeftHand",
		"RightShoulder","RightUpperArm","RightLowerArm","RightHand",
		"LeftUpperLeg","LeftLowerLeg","LeftFoot","RightUpperLeg","RightLowerLeg","RightFoot"]
	var bad := 0
	print("--- shared humanoid bones ---")
	for k in key:
		var ina: bool = a.has(k)
		var inb: bool = b.has(k)
		if not (ina and inb): bad += 1
		print("  %-16s synty=%s  mocap=%s" % [k, ("Y" if ina else "n"), ("Y" if inb else "n")])
	var shared := 0
	for n in a: if b.has(n): shared += 1
	print("SHARED_BONE_NAMES=", shared)
	print("RESULT=", ("OK" if bad == 0 else "FAIL(%d)" % bad))
	# Animation present?
	var ps: PackedScene = load("res://assets/animations/pistol/W1_Stand_Aim_Idle_IPC.fbx")
	var r: Node = ps.instantiate()
	var ap := _find_ap(r)
	if ap == null: print("NO ANIMATIONPLAYER"); bad += 1
	else:
		var list := ap.get_animation_list()
		print("ANIMATIONS=", list)
		for n in list:
			var an := ap.get_animation(n)
			print("  '%s' len=%.2fs tracks=%d" % [n, an.length, an.get_track_count()])
	quit(bad)
func _bones(p: String) -> Dictionary:
	var out := {}
	var ps: PackedScene = load(p)
	if ps == null: return out
	var sk := _find_skel(ps.instantiate())
	if sk == null: return out
	for i in sk.get_bone_count(): out[sk.get_bone_name(i)] = true
	return out
func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null: return r
	return null
func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null: return r
	return null
