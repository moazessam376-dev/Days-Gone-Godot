extends SceneTree

# Wires the BoneMaps into each FBX's .import file and turns on the Rest Fixer.
#
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
#       --script tools/rig/configure_imports.gd
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
#
# This is THE step that makes animation sharing work, and it is the step the
# Three.js project had to hand-roll (and never got right across 14 rounds).
#
# With a BoneMap assigned, Godot RENAMES each skeleton's bones to the humanoid
# profile's names at import time. The Synty character and the MoCap clips are
# rigged completely differently — `Shoulder_L` vs `LeftArm`, 50 bones vs 80 —
# but after this both speak `LeftUpperArm`, and the clips simply play on the
# character. No runtime retargeting, no per-clip correction tables.
#
# `overwrite_axis` is the one that matters most. The Godot docs call it "the
# most important option for sharing animations in Godot 4": it unifies bone
# REST AXES across rigs. Without it, a weapon socket calibrated on one clip
# reads as visibly twisted on the next — which is precisely the per-clip hand
# roll that produced the old project's RIG_POSES table.
#
# `fix_silhouette` reconciles A-pose vs T-pose. MotusMan is authored in a
# relaxed A-pose and the Synty rig in a T-pose, so without it every clip
# arrives with the arms held at the wrong base angle.

const SYNTY_MAP := "res://resources/rigs/synty_apocalypse_bonemap.tres"
const MOTUS_MAP := "res://resources/rigs/motusman_v55_bonemap.tres"
const MIXAMO_MAP := "res://resources/rigs/mixamo_bonemap.tres"

const TARGETS := [
	{"fbx": "res://assets/characters/Characters.fbx", "map": SYNTY_MAP, "anim": false},
	{"dir": "res://assets/animations/pistol", "map": MOTUS_MAP, "anim": true},
	{"fbx": "res://assets/rigs/MotusMan_v55.fbx", "map": MOTUS_MAP, "anim": false},
	# Phase 2 (M0): free rifle/pistol-gap/unarmed clips.
	# rifle_mco = MoCap Online free demo pack samples, same MotusMan rig as pistol.
	# rifle / pistol_extra / unarmed = Mixamo X Bot clips through the Mixamo map.
	{"dir": "res://assets/animations/rifle_mco", "map": MOTUS_MAP, "anim": true},
	{"dir": "res://assets/animations/rifle", "map": MIXAMO_MAP, "anim": true},
	{"dir": "res://assets/animations/pistol_extra", "map": MIXAMO_MAP, "anim": true},
	{"dir": "res://assets/animations/unarmed", "map": MIXAMO_MAP, "anim": true},
	{"fbx": "res://assets/rigs/XBot_TPose.fbx", "map": MIXAMO_MAP, "anim": false},
]


func _init() -> void:
	var jobs: Array[Dictionary] = []
	for t: Dictionary in TARGETS:
		if t.has("fbx"):
			jobs.append({"fbx": t["fbx"], "map": t["map"], "anim": t["anim"]})
		else:
			for f in _list_fbx(t["dir"]):
				jobs.append({"fbx": f, "map": t["map"], "anim": t["anim"]})

	var ok := 0
	var failed := 0
	for j in jobs:
		if _configure(j["fbx"], j["map"], j["anim"]):
			ok += 1
		else:
			failed += 1
	print("CONFIGURED=", ok, " FAILED=", failed)
	quit(1 if failed > 0 else 0)


func _list_fbx(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		push_error("cannot open dir " + dir_path)
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() == "fbx":
			out.append(dir_path.path_join(f))
	out.sort()
	return out


func _configure(fbx: String, map_path: String, _is_anim: bool) -> bool:
	var import_path := fbx + ".import"
	var cfg := _load_import_cfg(import_path)
	if cfg == null:
		return false

	var subres: Dictionary = cfg.get_value("params", "_subresources", {})
	var nodes: Dictionary = subres.get("nodes", {})

	# IDEMPOTENCY GUARD (this trap already fired once): _skeleton_path() reads
	# the IMPORTED scene. After a first configured import, make_unique has
	# renamed the skeleton to GeneralSkeleton, so a re-run would key a second,
	# junk "PATH:GeneralSkeleton" block next to the real "PATH:Skeleton3D" one.
	# The importer keys by the SOURCE scene's node path, which never changes —
	# so if any node block already carries a bone_map, this file is done.
	var configured_key := _configured_key(nodes)
	if configured_key != "":
		print("  ok  %-58s already configured (%s)" % [fbx.get_file(), configured_key])
		return true

	var skel_path := _skeleton_path(fbx)
	if skel_path == "":
		push_error("no Skeleton3D in " + fbx)
		return false

	var bone_map: BoneMap = load(map_path)
	if bone_map == null:
		push_error("cannot load " + map_path)
		return false

	var key := "PATH:" + skel_path

	var opts: Dictionary = nodes.get(key, {})
	opts["retarget/bone_map"] = bone_map
	opts["retarget/bone_renamer/rename_bones"] = true
	opts["retarget/bone_renamer/unique_node/make_unique"] = true
	opts["retarget/rest_fixer/overwrite_axis"] = true
	opts["retarget/rest_fixer/fix_silhouette/enable"] = true
	opts["retarget/rest_fixer/normalize_position_tracks"] = true
	# Keep the root position track on animation clips: it is the only place
	# translation belongs. Everything else should be pure rotation, otherwise
	# differing limb lengths between the two rigs tear the mesh.
	opts["retarget/rest_fixer/keep_global_rest_on_leftovers"] = true
	# DELIBERATELY NOT SET: retarget/remove_tracks/*.
	# Measured: enabling them cut this clip from 57 tracks (24 animated) to
	# 20 tracks (2 animated) -- it strips the spine, neck, head, forearm and
	# hand channels, i.e. the actual mocap motion. The docs recommend them
	# when building a shared AnimationLibrary; here they destroy the clip.
	# Verify with tools/rig/verify_retarget.gd before ever turning them on.

	nodes[key] = opts
	subres["nodes"] = nodes
	cfg.set_value("params", "_subresources", subres)

	var err := cfg.save(import_path)
	if err != OK:
		push_error("cannot write %s (%d)" % [import_path, err])
		return false
	print("  ok  %-58s skel=%s" % [fbx.get_file(), skel_path])
	return true


func _load_import_cfg(import_path: String) -> ConfigFile:
	if not FileAccess.file_exists(import_path):
		push_error("no .import at " + import_path + " (run --import first)")
		return null
	var cfg := ConfigFile.new()
	var err := cfg.load(import_path)
	if err != OK:
		push_error("cannot read %s (%d)" % [import_path, err])
		return null
	return cfg


# Returns the key of a node block that already carries a bone_map, or "".
func _configured_key(nodes: Dictionary) -> String:
	for existing_key: String in nodes:
		var existing: Dictionary = nodes[existing_key]
		if existing.has("retarget/bone_map"):
			return existing_key
	return ""


func _skeleton_path(fbx: String) -> String:
	var ps: PackedScene = load(fbx)
	if ps == null:
		return ""
	var root: Node = ps.instantiate()
	var sk := _find_skel(root)
	if sk == null:
		return ""
	# The importer keys options by the node's path relative to the scene root.
	return String(root.get_path_to(sk))


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null
