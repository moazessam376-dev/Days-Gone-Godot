extends SceneTree

func _init():
	var ps := load("res://Characters.fbx")
	if ps == null:
		print("LOAD_FAILED")
		quit(1); return
	var root: Node = ps.instantiate()
	var skels: Array[Node] = []
	_find(root, "Skeleton3D", skels)
	print("SKELETONS=", skels.size())
	for s in skels:
		var sk := s as Skeleton3D
		print("--- skeleton: ", sk.name, "  bones=", sk.get_bone_count(), " ---")
		for i in sk.get_bone_count():
			print(i, "\t", sk.get_bone_name(i), "\tparent=", sk.get_bone_parent(i))
	var meshes: Array[Node] = []
	_find(root, "MeshInstance3D", meshes)
	print("MESHCOUNT=", meshes.size())
	for m in meshes:
		print("MESH\t", m.name)
	quit()

func _find(n: Node, cls: String, out: Array[Node]) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_find(c, cls, out)
