extends SceneTree
func _init():
	var bad := 0
	var t: PackedScene = load("res://scenes/test_character.tscn")
	if t == null: print("TEST SCENE FAILED TO LOAD"); quit(1); return
	var r: Node = t.instantiate()
	print("TEST ROOT children=", r.get_children().size())
	for c in r.get_children():
		print("  - ", c.name, " (", c.get_class(), ")")
	var mesh := _find_mesh(r)
	if mesh == null:
		print("HUNTER MESH NOT FOUND"); bad += 1
	else:
		var mo := mesh.material_override
		print("HUNTER mesh=", mesh.name)
		print("HUNTER material_override=", ("NONE" if mo == null else mo.get_class()))
		if mo is BaseMaterial3D:
			var tex := (mo as BaseMaterial3D).albedo_texture
			print("HUNTER albedo=", ("NONE" if tex == null else tex.resource_path))
			if tex == null: bad += 1
		else:
			bad += 1
		var sk := _find_skel(r)
		print("HUNTER bones=", (0 if sk == null else sk.get_bone_count()))
		if sk == null or sk.get_bone_count() != 50: bad += 1
		print("HUNTER height_m=%.3f" % mesh.get_aabb().size.y)
	print("MAIN_SCENE=", ProjectSettings.get_setting("application/run/main_scene",""))
	print("RESULT=", ("OK" if bad == 0 else "FAIL(%d)" % bad))
	quit(bad)
func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and n.name == "SM_Chr_Hunter_Male_01": return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null: return r
	return null
func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null: return r
	return null
