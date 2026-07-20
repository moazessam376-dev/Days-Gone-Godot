extends SceneTree

# Builds a usable Hunter_Male_01 character scene out of the shared Synty
# Characters.fbx, plus a small test level you can press F5 on.
#
# Run with the editor CLOSED:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
#       --script tools/build_character.gd
#
# WHY THIS EXISTS: Characters.fbx packs 31 character meshes onto ONE shared
# skeleton, and the material baked into the FBX is `Chr:BloodDecal11`, pointing
# at a `Blood_Decal.tga` that does not exist anywhere in the pack. Synty's real
# material assignment lives in Unity .mat/.meta GUID references that Godot
# cannot read. So we keep the one mesh we want and assign the atlas ourselves.
#
# Synty shading is deliberately flat: one albedo atlas, no metallic, low
# roughness spec. Do not add PBR maps that the art style does not use.

const SRC := "res://assets/characters/Characters.fbx"
const ATLAS := "res://assets/textures/PolygonApocalypse_Texture_01_A.png"
const KEEP := "SM_Chr_Hunter_Male_01"

const OUT_CHAR := "res://scenes/characters/hunter.tscn"
const OUT_TEST := "res://scenes/test_character.tscn"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/characters")

	var ok := _build_character()
	if ok:
		ok = _build_test_level()
	quit(0 if ok else 1)


func _build_character() -> bool:
	var packed: PackedScene = load(SRC)
	if packed == null:
		push_error("cannot load " + SRC)
		return false
	var root: Node = packed.instantiate()

	var skel := _find_skeleton(root)
	if skel == null:
		push_error("no Skeleton3D in " + SRC)
		return false

	# Drop the 30 characters we are not using. They share the skeleton, so this
	# is purely removing MeshInstance3D siblings, not touching the rig.
	var removed := 0
	for child in skel.get_children():
		if child is MeshInstance3D and child.name != KEEP:
			skel.remove_child(child)
			child.queue_free()
			removed += 1

	var mesh := skel.get_node_or_null(NodePath(KEEP)) as MeshInstance3D
	if mesh == null:
		push_error("mesh %s not found under skeleton" % KEEP)
		return false

	var tex: Texture2D = load(ATLAS)
	if tex == null:
		push_error("cannot load atlas " + ATLAS)
		return false

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.metallic = 0.0
	mat.roughness = 0.9
	# Synty atlases are tiny colour swatches; smooth filtering bleeds
	# neighbouring swatches across UV seams. Nearest keeps colours crisp.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Assign as an override so it survives a re-import of the FBX.
	mesh.material_override = mat

	root.name = "Hunter"
	_own_all(root, root)

	var out := PackedScene.new()
	var err := out.pack(root)
	if err != OK:
		push_error("pack failed %d" % err)
		return false
	err = ResourceSaver.save(out, OUT_CHAR)

	var aabb := mesh.get_aabb()
	print("CHARACTER  removed_meshes=", removed)
	print("CHARACTER  bones=", skel.get_bone_count())
	print("CHARACTER  height_m=%.3f" % aabb.size.y)
	print("CHARACTER  atlas=", tex.resource_path, " ", tex.get_size())
	print("CHARACTER  saved=", OUT_CHAR, " err=", err)
	return err == OK


func _build_test_level() -> bool:
	var root := Node3D.new()
	root.name = "TestCharacter"

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gm := MeshInstance3D.new()
	gm.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.22, 0.23, 0.25)
	plane.material = gmat
	gm.mesh = plane
	ground.add_child(gm)
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, 20)
	col.shape = box
	col.position = Vector3(0, -0.1, 0)
	ground.add_child(col)
	root.add_child(ground)

	var char_scene: PackedScene = load(OUT_CHAR)
	if char_scene == null:
		push_error("cannot load " + OUT_CHAR)
		return false
	var hunter: Node = char_scene.instantiate()
	hunter.name = "Hunter"
	root.add_child(hunter)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 1.2, 3.2)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	root.add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)

	# Without an environment the viewport renders flat black in a built scene.
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	world.environment = env
	root.add_child(world)

	_own_all(root, root)

	var out := PackedScene.new()
	var err := out.pack(root)
	if err != OK:
		push_error("pack failed %d" % err)
		return false
	err = ResourceSaver.save(out, OUT_TEST)
	print("TESTLEVEL  saved=", OUT_TEST, " err=", err)

	if err == OK:
		ProjectSettings.set_setting("application/run/main_scene", OUT_TEST)
		var perr := ProjectSettings.save()
		print("TESTLEVEL  main_scene set, save err=", perr)
		return perr == OK
	return false


# Nodes built in code have no owner, and PackedScene.pack() silently drops
# unowned children. Every node must be owned by the scene root.
func _own_all(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_own_all(c, owner_node)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
