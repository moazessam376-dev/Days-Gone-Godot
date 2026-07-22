extends SceneTree

# Builds a usable Hunter_Male_01 character scene out of the shared Synty
# Characters.fbx, plus a small test level you can press F5 on.
#
# !! THIS OVERWRITES scenes/characters/hunter.tscn AND scenes/test_character.tscn.
# Every hand-tuned value in those scenes is mirrored in the constants and
# _attach_weapon() below, so a rebuild reproduces them. If you tune something
# in the editor, bake it back HERE or the next rebuild silently reverts it.
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

# Every dir here feeds the character's AnimationPlayer. pistol + rifle_mco are
# MotusMan-rig clips (MoCap Online); rifle / pistol_extra / unarmed are Mixamo
# X Bot clips; ual is Quaternius' CC0 library (one GLB, ~43 clips — `allow`
# picks the ones we use, `prefix` marks provenance). All arrive speaking
# humanoid-profile bone names via their BoneMaps
# (tools/rig/configure_imports.gd), so they coexist in one library.
const ANIM_DIRS := [
	{"dir": "res://assets/animations/pistol"},
	{"dir": "res://assets/animations/rifle_mco"},
	{"dir": "res://assets/animations/rifle"},
	{"dir": "res://assets/animations/pistol_extra"},
	{"dir": "res://assets/animations/unarmed"},
	{
		"dir": "res://assets/animations/ual",
		"prefix": "UAL_",
		"allow": [
			"Idle",
			"Walk",
			"Jog_Fwd",
			"Sprint",
			"Roll",
			"Pistol_Idle",
			"Pistol_Shoot",
			"Pistol_Reload",
			"Pistol_Aim_Up",
			"Pistol_Aim_Neutral",
			"Pistol_Aim_Down",
		],
	},
]
const DEFAULT_ANIM := "W1_Stand_Aim_Idle_IPC"
const FINGER_TIP_SCRIPT := "res://scripts/rig/finger_tip_modifier.gd"
const REVOLVER := "res://assets/weapons/SM_Wep_Revolver_01.fbx"
const SUPPORT_TUNER_SCRIPT := "res://scripts/rig/support_hand_tuner.gd"

const OUT_CHAR := "res://scenes/characters/hunter.tscn"
const OUT_TEST := "res://scenes/test_character.tscn"

# The MoCap Online free demo pack's W2_ rifle FBXs carry a broken bind pose:
# their skeleton rests with hips at 0.506 m while the animation keys sit at
# ~1.70 m (the pistol pack is consistent: 0.941 rest vs 1.011 keys). The
# importer's normalize_position_tracks trusts the rest pose, silently skips
# scaling, and the clips play ~0.8 m in the air. MEASURED correction
# (2026-07-21, live against the pistol clips as ground truth):
#   * scale all position tracks by 1.011/1.695 = 0.596 (the two packs'
#     matching stand-aim-idle hips keys), then
#   * drop the hips track by 0.115 m — after scaling, every W2 clip's lowest
#     foot still hovered uniformly at ~0.17 m vs the pistol baseline's ~0.05.
# Verified on screen: feet plant identically to the pistol set.
const W2_POSITION_SCALE := 0.596
const W2_HIPS_Y_OFFSET := -0.115

# The Quaternius locomotion cycles read more theatrical than the Days Gone
# reference gait the user pointed at. Three measured compressions, all
# "scale deviation around the track's own mean" (character preserved, motion
# tightened), tuned across user reviews:
#   * hips bounce: vertical 0.35, lateral 0.7 ("going up and down" — fixed)
#   * stride width: leg rotations 0.75 ("the step itself is too wide")
#   * shoulder sway: spine-chain + clavicle rotations 0.5 ("shoulders heavily
#     going left and right")
#   * left-arm swing: 0.7, keeps the free hand from crossing the body.
const UAL_BOB_CLIPS := ["UAL_Walk", "UAL_Jog_Fwd", "UAL_Sprint"]
const UAL_BOB_Y_SCALE := 0.35
const UAL_BOB_XZ_SCALE := 0.7
const UAL_STRIDE_SCALE := 0.75
const UAL_STRIDE_BONES := [
	"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg"
]
const UAL_SWAY_SCALE := 0.5
const UAL_SWAY_BONES := ["Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder"]
const UAL_ARM_SCALE := 0.7
const UAL_ARM_BONES := ["LeftUpperArm", "LeftLowerArm"]
# "the head going right and left while jogging ... should be something like
# [ADS]: doesn't move or some slight move" — near-freeze it.
const UAL_HEAD_SCALE := 0.3
const UAL_HEAD_BONES := ["Neck", "Head"]

# Posture bias for the UAL clip family (negative = lean back / straighten
# the mocap hunch). The Quaternius rig holds a forward hunch — head pitched
# ~30 deg DOWN, measured — so the correction is BAKED into the UAL_* clips'
# spine-chain keys at build time. It must NOT be a runtime skeleton-wide
# modifier: that applied the same fix to every clip and pitched the
# level-headed U_Idle carry ~11 deg skyward (user-flagged; attributed by
# post-modifier probe A/B in the running game). PostureAdjust stays in the
# scene ZEROED as a live-tuning override only.
const POSTURE_SPINE_PITCH := -3.0
const POSTURE_CHEST_PITCH := -4.0
const POSTURE_UPPER_CHEST_PITCH := -4.0
# Was 8.0 as an anti-clipping bias; obsolete once the carry-time IK release
# fixed the real clipping cause, and it read as "hand way too far from the
# body" (user). Neutral now; the slider stays for live tuning if needed.
const POSTURE_RIGHT_ARM_OUT := 0.0


# Reduce locomotion bob: scale each hips position component's deviation from
# its own mean. Keeps the gait's character, shrinks the bounce.
func _reduce_bob(anim: Animation) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not String(anim.track_get_path(t)).ends_with(":Hips"):
			continue
		var n := anim.track_get_key_count(t)
		if n == 0:
			continue
		var mean := Vector3.ZERO
		for k in n:
			mean += anim.track_get_key_value(t, k) as Vector3
		mean /= float(n)
		for k in n:
			var v: Vector3 = anim.track_get_key_value(t, k)
			v.x = mean.x + (v.x - mean.x) * UAL_BOB_XZ_SCALE
			v.z = mean.z + (v.z - mean.z) * UAL_BOB_XZ_SCALE
			v.y = mean.y + (v.y - mean.y) * UAL_BOB_Y_SCALE
			anim.track_set_key_value(t, k, v)
	_compress_rotation(anim, UAL_STRIDE_BONES, UAL_STRIDE_SCALE)
	_compress_rotation(anim, UAL_SWAY_BONES, UAL_SWAY_SCALE)
	_compress_rotation(anim, UAL_ARM_BONES, UAL_ARM_SCALE)
	_compress_rotation(anim, UAL_HEAD_BONES, UAL_HEAD_SCALE)


# Bake the UAL posture correction into a clip: premultiply a constant pitch
# onto every spine-chain rotation key. Same math as the PostureAdjust
# modifier (Quaternion(RIGHT, rad) * pose), and left-multiplication commutes
# with blending, so mixes against unbaked clips fade the correction smoothly.
func _apply_posture_bias(anim: Animation) -> void:
	var bias := {
		"Spine": POSTURE_SPINE_PITCH,
		"Chest": POSTURE_CHEST_PITCH,
		"UpperChest": POSTURE_UPPER_CHEST_PITCH,
	}
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(anim.track_get_path(t)).get_slice(":", 1)
		if not bias.has(bone):
			continue
		var q := Quaternion(Vector3.RIGHT, deg_to_rad(bias[bone]))
		for k in anim.track_get_key_count(t):
			var rot: Quaternion = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, q * rot)


# Scale a rotation track's swing around its own mean orientation: for each
# key, slerp from the track mean toward the key by `scale`. 1.0 = untouched,
# 0.0 = frozen at the mean. The mean of nearby unit quaternions is the
# normalised component average (valid because a gait cycle stays well within
# one hemisphere).
func _compress_rotation(anim: Animation, bones: Array, scale: float) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(anim.track_get_path(t)).get_slice(":", 1)
		if not bone in bones:
			continue
		var n := anim.track_get_key_count(t)
		if n < 2:
			continue
		var first: Quaternion = anim.track_get_key_value(t, 0)
		var acc := Vector4.ZERO
		for k in n:
			var q: Quaternion = anim.track_get_key_value(t, k)
			if q.dot(first) < 0.0:
				q = -q
			acc += Vector4(q.x, q.y, q.z, q.w)
		var mean := Quaternion(acc.x, acc.y, acc.z, acc.w).normalized()
		for k in n:
			var q2: Quaternion = anim.track_get_key_value(t, k)
			if q2.dot(mean) < 0.0:
				q2 = -q2
			anim.track_set_key_value(t, k, mean.slerp(q2, scale))


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

	# Attach the retargeted MoCap clips. This only works because both rigs were
	# imported through BoneMaps, so the clips' track paths (%GeneralSkeleton:
	# LeftUpperArm ...) resolve against the Synty skeleton. Nothing is
	# retargeted at runtime.
	var anim_count := _attach_animations(root, skel)

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
	print("CHARACTER  animations=", anim_count)
	print("CHARACTER  saved=", OUT_CHAR, " err=", err)
	return err == OK


# Pulls every clip out of the imported animation FBXs into one AnimationPlayer
# on the character. DEFAULT_ANIM autoplays so the scene shows a real pose
# instead of the bind-pose T-pose.
func _attach_animations(root: Node, skel: Skeleton3D) -> int:
	# Track paths are authored against a uniquely-named skeleton node.
	skel.name = "GeneralSkeleton"
	skel.unique_name_in_owner = true

	# Characters.fbx ships its OWN AnimationPlayer holding a junk "Take 001"
	# clip. Leaving it in place means our player collides on name and gets
	# silently renamed to @AnimationPlayer@2, so anything looking up
	# "AnimationPlayer" finds the FBX's empty one instead of ours.
	for c in root.get_children():
		if c is AnimationPlayer:
			root.remove_child(c)
			c.queue_free()

	# Synty fingers have 4 joints; SkeletonProfileHumanoid defines only 3, so
	# the tips are never mapped and freeze in bind pose while the rest of the
	# finger curls. This modifier drives them from their parent joint.
	var tips := SkeletonModifier3D.new()
	tips.name = "FingerTips"
	tips.set_script(load(FINGER_TIP_SCRIPT))
	skel.add_child(tips)

	_attach_weapon(skel)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	var lib := AnimationLibrary.new()

	var count := 0
	for entry: Dictionary in ANIM_DIRS:
		var anim_dir: String = entry["dir"]
		var allow: Array = entry.get("allow", [])
		var prefix: String = entry.get("prefix", "")
		var d := DirAccess.open(anim_dir)
		if d == null:
			push_error("missing animation dir " + anim_dir)
			continue
		var files := d.get_files()
		files.sort()
		for f in files:
			if not f.get_extension().to_lower() in ["fbx", "glb"]:
				continue
			var ps: PackedScene = load(anim_dir.path_join(f))
			if ps == null:
				continue
			var inst: Node = ps.instantiate()
			var src := _find_anim_player(inst)
			if src == null:
				continue
			var clip_names: Array[String] = []
			for clip_name in src.get_animation_list():
				# "Take 001" is the junk bind-pose take skinned FBX exports
				# carry (same disease as Characters.fbx's own AnimationPlayer).
				if clip_name == "RESET" or clip_name == "Take 001":
					continue
				if not allow.is_empty() and not clip_name in allow:
					continue
				clip_names.append(clip_name)
			for clip_name in clip_names:
				var anim: Animation = src.get_animation(clip_name).duplicate(true)
				# Mixamo FBXs name their single take "mixamo.com"; key single-clip
				# files by filename so the library speaks our naming, not theirs.
				var key := clip_name
				if clip_names.size() == 1:
					key = f.get_basename()
				key = prefix + key
				if _should_loop(key):
					anim.loop_mode = Animation.LOOP_LINEAR
				if key.begins_with("W2_"):
					_fix_w2_positions(anim)
				_collapse_root_into_hips(anim)
				if key in UAL_BOB_CLIPS:
					_reduce_bob(anim)
				if key.begins_with("UAL_"):
					_apply_posture_bias(anim)
				if lib.has_animation(key):
					push_error("duplicate clip name " + key + " from " + f)
					continue
				lib.add_animation(key, anim)
				count += 1
			inst.queue_free()

	player.add_animation_library("", lib)
	if lib.has_animation(DEFAULT_ANIM):
		player.autoplay = DEFAULT_ANIM
	root.add_child(player)
	return count


func _fix_w2_positions(anim: Animation) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var is_hips := String(anim.track_get_path(t)).ends_with(":Hips")
		for k in anim.track_get_key_count(t):
			var v: Vector3 = anim.track_get_key_value(t, k) * W2_POSITION_SCALE
			if is_hips:
				v.y += W2_HIPS_Y_OFFSET
			anim.track_set_key_value(t, k, v)


# Some sources key the Root bone (the demo-pack W2 clips hold it at a constant
# -37 deg X; W1's D90/U90/Fire also carry Root tracks). A clip that keys Root
# POISONS every clip played after it that does not: AnimationPlayer leaves the
# bone at its last pose, so the whole character stays tilted — this produced
# the "everything after a rifle clip faces the sky" review round. In-place
# clips must not key Root at all, so compose Root's motion into the Hips
# tracks (global_hips = root * hips) and drop the Root tracks entirely.
func _collapse_root_into_hips(anim: Animation) -> void:
	var root_rot := -1
	var root_pos := -1
	var hips_rot := -1
	var hips_pos := -1
	for t in anim.get_track_count():
		var tp := String(anim.track_get_path(t))
		if tp.ends_with(":Root"):
			if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				root_rot = t
			elif anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				root_pos = t
		elif tp.ends_with(":Hips"):
			if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				hips_rot = t
			elif anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				hips_pos = t
	if root_rot == -1 and root_pos == -1:
		return
	if hips_rot != -1:
		for k in anim.track_get_key_count(hips_rot):
			var tm := anim.track_get_key_time(hips_rot, k)
			var rq := Quaternion.IDENTITY
			if root_rot != -1:
				rq = anim.rotation_track_interpolate(root_rot, tm)
			var hq: Quaternion = anim.track_get_key_value(hips_rot, k)
			anim.track_set_key_value(hips_rot, k, rq * hq)
	if hips_pos != -1:
		for k in anim.track_get_key_count(hips_pos):
			var tm := anim.track_get_key_time(hips_pos, k)
			var rq := Quaternion.IDENTITY
			if root_rot != -1:
				rq = anim.rotation_track_interpolate(root_rot, tm)
			var rp := Vector3.ZERO
			if root_pos != -1:
				rp = anim.position_track_interpolate(root_pos, tm)
			var hp: Vector3 = anim.track_get_key_value(hips_pos, k)
			anim.track_set_key_value(hips_pos, k, rq * hp + rp)
	for t in range(anim.get_track_count() - 1, -1, -1):
		if String(anim.track_get_path(t)).ends_with(":Root"):
			anim.remove_track(t)


# Stances and locomotion cycle; one-shots (fire, reload, draw/holster,
# transitions) do not. Filename-convention based, applied at build time.
func _should_loop(clip_key: String) -> bool:
	if clip_key.ends_with("_Loop_IPC") or clip_key.ends_with("_Idle_IPC"):
		return true
	for token: String in ["_Idle", "_Walk", "_Strafe", "_Jog", "_Loop", "_Sprint"]:
		if clip_key.contains(token):
			return true
	return false


# Engine-native weapon attachment: BoneAttachment3D -> calibrated socket ->
# weapon. No IK, no palm-socket math, no per-clip correction. The socket
# transform is calibrated ONCE for this weapon and is valid for every clip,
# because import-time Overwrite Axis normalised the bone rest axes.
#
# override_pose stays OFF: the docs warn it interferes with the
# SkeletonModifier3D system, which we rely on for the fingertips (and will
# rely on for LookAt/TwoBoneIK in Phase 2).
#
# The socket basis was measured in the running game against the aim pose, not
# guessed. NOTE: build the Basis from vectors here rather than copying a
# Transform3D literal out of a .tscn — the text format lists those 9 floats
# COLUMN-wise, so a naive row-wise copy silently loads transposed.
func _attach_weapon(skel: Skeleton3D) -> void:
	var att := BoneAttachment3D.new()
	att.name = "RightHandAttach"
	skel.add_child(att)
	att.bone_name = "RightHand"
	att.override_pose = false

	var socket := Node3D.new()
	socket.name = "WeaponSocket"
	att.add_child(socket)
	socket.transform = Transform3D(
		Basis(
			Vector3(0.113889, 0.012759, 0.993412),
			Vector3(0.969717, 0.216020, -0.113947),
			Vector3(-0.216051, 0.976306, 0.012230)
		),
		Vector3.ZERO
	)

	# Where the support palm belongs, riding with the gun so it stays valid in
	# every clip. Retargeting cannot fix limb-PROPORTION differences, so the
	# support hand lands ~19 cm from the grip on this rig; TwoBoneIK3D closes
	# that gap. Reach is 61 cm against ~50 cm needed, so it is never straining.
	# Position placed by the user on the gizmo, not computed.
	var support := Node3D.new()
	support.name = "SupportGrip"
	socket.add_child(support)
	support.position = Vector3(0.120312, 0.003870, 0.025649)

	# Posture override, live tuning ONLY — all pitches ship zeroed. The real
	# posture correction is baked per clip family (_apply_posture_bias on the
	# UAL_* clips); running it here skeleton-wide pitched the level U_Idle
	# carry skyward. The sliders remain so a tuning session can bias the spine
	# chain in the Remote tree without a rebuild.
	var posture := SkeletonModifier3D.new()
	posture.name = "PostureAdjust"
	posture.set_script(load("res://scripts/rig/posture_adjust.gd"))
	skel.add_child(posture)
	posture.set("spine_pitch_deg", 0.0)
	posture.set("chest_pitch_deg", 0.0)
	posture.set("upper_chest_pitch_deg", 0.0)
	posture.set("right_arm_out_deg", POSTURE_RIGHT_ARM_OUT)

	# Torso/head aim (Phase 2 M2). MUST run BEFORE LeftArmIK in child order so
	# the IK solves against the already-rotated torso (docs/rig-tuning.md).
	# forward_axis +Z is MEASURED: after Overwrite Axis every bone's global
	# rest basis is world-aligned and the character faces +Z. AimTarget is a
	# plain Node3D sibling of the skeleton; player.gd points it at the camera
	# ray while aiming and eases the modifiers' influence up/down.
	var aim_target := Node3D.new()
	aim_target.name = "AimTarget"
	skel.get_parent().add_child(aim_target)
	aim_target.position = Vector3(0, 1.4, 10.0)

	var torso_look := LookAtModifier3D.new()
	torso_look.name = "TorsoLookAt"
	skel.add_child(torso_look)
	torso_look.bone_name = "UpperChest"
	torso_look.target_node = NodePath("../../AimTarget")
	torso_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	torso_look.primary_rotation_axis = Vector3.AXIS_Y
	torso_look.use_secondary_rotation = true
	torso_look.duration = 0.15
	torso_look.influence = 0.6

	var head_look := LookAtModifier3D.new()
	head_look.name = "HeadLookAt"
	skel.add_child(head_look)
	head_look.bone_name = "Head"
	head_look.target_node = NodePath("../../AimTarget")
	head_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	head_look.primary_rotation_axis = Vector3.AXIS_Y
	head_look.use_secondary_rotation = true
	head_look.duration = 0.15
	head_look.influence = 0.35

	var ik := TwoBoneIK3D.new()
	ik.name = "LeftArmIK"
	skel.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "LeftUpperArm")
	ik.set_middle_bone_name(0, "LeftLowerArm")
	ik.set_end_bone_name(0, "LeftHand")
	ik.set_target_node(0, NodePath("../RightHandAttach/WeaponSocket/SupportGrip"))
	# Without a pole the elbow flips between valid solutions mid-animation.
	ik.set_pole_direction_vector(0, Vector3(0.0, -1.0, -0.35))
	ik.influence = 1.0

	# A draggable pole beats a hard-coded vector: the elbow can be aimed by
	# hand in the viewport instead of by editing numbers.
	var pole := Node3D.new()
	pole.name = "LeftElbowPole"
	skel.add_child(pole)
	pole.position = Vector3(0.915536, 1.0, 0.15)
	ik.set_pole_node(0, NodePath("../LeftElbowPole"))

	# Wrist + finger corrections for the support hand. MUST be added AFTER the
	# IK: modifiers run top-to-bottom, so the IK places the arm and this
	# refines it. Ships all-zero, i.e. a no-op, so the pose is pure mocap
	# until someone authors a correction in the Inspector.
	var tuner := SkeletonModifier3D.new()
	tuner.name = "SupportHandTuner"
	tuner.set_script(load(SUPPORT_TUNER_SCRIPT))
	skel.add_child(tuner)
	# Authored by the user in the Inspector against the live game. These are
	# corrections ON TOP of the mocap, in degrees, so they read as "how wrong
	# the clip was on this rig": the index finger was fully over-curled for a
	# revolver trigger guard (-90), the thumb needed to wrap much further
	# (+57.5), and the wrist wanted a few degrees of roll.
	tuner.wrist_offset_deg = Vector3(2.82, -3.78, 0.09)
	tuner.thumb_curl = 57.5
	tuner.index_curl = -90.0
	tuner.middle_curl = -20.0
	tuner.curl_axis = Vector3(1.62, -2.36, -0.9)
	tuner.thumb_axis = Vector3(0.578, 0.0, 0.685)

	var ps: PackedScene = load(REVOLVER)
	if ps == null:
		push_warning("weapon scene missing: " + REVOLVER)
		return
	var gun: Node3D = ps.instantiate()
	gun.name = "Revolver"
	# The revolver's ORIGIN is mid-body, not at the grip. This offset is the
	# NEGATED centroid of the 130 grip vertices (y < -0.035, z < 0.04),
	# measured off the real mesh, then hand-finished by the user dragging the
	# WeaponSocket gizmo in the editor until the grip sat right in the fist.
	gun.position = Vector3(0.012529, 0.095424, 0.096369)
	socket.add_child(gun)

	var gm := _find_mesh(gun)
	if gm != null:
		var gmat := StandardMaterial3D.new()
		gmat.albedo_texture = load(ATLAS)
		gmat.roughness = 0.8
		gmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		gm.material_override = gmat


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


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
		# Phase 2 owns the main scene (scenes/levels/test_range.tscn). Only
		# claim it if the project has none — a rebuild must never silently
		# repoint the game at the rig-calibration scene.
		var current: String = ProjectSettings.get_setting("application/run/main_scene", "")
		if current == "":
			ProjectSettings.set_setting("application/run/main_scene", OUT_TEST)
			var perr := ProjectSettings.save()
			print("TESTLEVEL  main_scene claimed, save err=", perr)
			return perr == OK
		print("TESTLEVEL  main_scene left as ", current)
		return true
	return false


# Nodes built in code have no owner, and PackedScene.pack() silently drops
# unowned children. Every node must be owned by the scene root.
#
# But do NOT recurse into an instanced sub-scene. A node with a
# scene_file_path is the root of its own packed scene; re-owning its children
# to OUR root makes pack() write them out a second time, so the scene ends up
# containing the character twice — the instanced copy plus a flattened,
# un-animated duplicate rendered on top of it. That looked exactly like the
# retarget having silently failed.
func _own_all(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		if c.scene_file_path.is_empty():
			_own_all(c, owner_node)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
