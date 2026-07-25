extends SceneTree

# Generates resources/weapons/revolver.tres + assault_rifle.tres — the
# WeaponResource files consumed by tools/build_character.gd (scene build) and
# scripts/player/weapon_manager.gd (runtime switching).
#
# Run BEFORE build_character.gd, with the editor CLOSED:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
#       --script tools/build_weapons.gd
#
# THIS IS THE BAKE TARGET for weapon calibration. When the user finishes a
# placement session (socket, grips, curls, stow), read the values out of the
# scene, write them into the functions below WITH THEIR REASON, then re-run
# this tool and build_character.gd. The .tres files are generated artefacts —
# hand-edits to them are lost on the next run.
#
# Stats are the Phase 2 plan's proposed numbers; the user sanity-checks them
# live at the M4 gate.

# Preloaded (not the global class name): a headless --script run does not
# rebuild the global class cache, so a fresh checkout would fail to resolve
# the class_name here.
const WeaponResource := preload("res://scripts/weapons/weapon_resource.gd")

const OUT_DIR := "res://resources/weapons"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var ok := _save(_revolver(), OUT_DIR + "/revolver.tres")
	ok = _save(_assault_rifle(), OUT_DIR + "/assault_rifle.tres") and ok
	quit(0 if ok else 1)


# Calibration authored by the user in the editor on 2026-07-21 and previously
# baked into build_character.gd; migrated here unchanged (M3). Reasons per
# value: docs/rig-tuning.md ("Current authored values").
func _revolver() -> WeaponResource:
	var w := WeaponResource.new()
	w.id = &"Revolver"
	w.anim_set = 0
	w.mesh_scene = load("res://assets/weapons/SM_Wep_Revolver_01.fbx")

	# Socket basis MEASURED in the running game against the aim pose, not
	# guessed. Aligns the gun level and forward in the fist.
	w.socket_basis_x = Vector3(0.113889, 0.012759, 0.993412)
	w.socket_basis_y = Vector3(0.969717, 0.216020, -0.113947)
	w.socket_basis_z = Vector3(-0.216051, 0.976306, 0.012230)
	w.socket_origin = Vector3.ZERO
	# NEGATED centroid of the 130 grip vertices (y < -0.035, z < 0.04) measured
	# off the mesh, then hand-finished by the user on the WeaponSocket gizmo
	# until the grip sat right in the fist (the FBX origin is mid-body).
	w.mesh_offset = Vector3(0.012529, 0.095424, 0.096369)
	# Where the left palm meets the gun; placed by the user on the gizmo.
	# Carry point identical: the pistol's support IK is aim-only, so the
	# carry position never drives the arm.
	w.support_grip_pos = Vector3(0.120312, 0.003870, 0.025649)
	w.carry_support_grip_pos = Vector3(0.120312, 0.003870, 0.025649)
	# Pushes the left elbow out so the arm reads naturally.
	w.elbow_pole_pos = Vector3(0.915536, 1.0, 0.15)

	# Corrections against a MotusMan hand posed for a 1911, transferred to a
	# three-fingered Synty hand holding a revolver: thumb barely wrapped
	# (+57.5), index fully curled where the trigger guard needs it open (-90).
	w.wrist_offset_deg = Vector3(2.82, -3.78, 0.09)
	w.thumb_curl = 57.5
	w.index_curl = -90.0
	w.middle_curl = -20.0
	w.curl_axis = Vector3(1.62, -2.36, -0.9)
	w.thumb_axis = Vector3(0.578, 0.0, 0.685)

	# Days Gone hip carry, iterated against screenshots (2026-07-23): the
	# first seed sat deep in the thigh (user: "visibly going on the leg").
	# Hips-bone space (world-aligned at rest, character faces +Z): right hip
	# is -X. Moved outboard and up, tilted the barrel a few degrees back so
	# the animated hips pose doesn't rake it forward into the leg.
	w.stow_socket = "hip"
	w.stow_position = Vector3(-0.26, 0.03, -0.09)
	w.stow_rotation_deg = Vector3(72, 0, 8)

	w.fire_clip = &"W1_Stand_Fire_Single"
	w.reload_clip = &"W1_Reload"

	w.damage = 65.0
	w.rpm = 130.0
	w.auto_fire = false
	w.mag_size = 6
	w.reserve = 24
	w.reload_time = 2.6
	w.spread_deg = 0.5
	w.recoil_pitch_deg = 1.4
	w.ads_fov = 42.0
	w.hitscan_range = 60.0
	# Centroid of the 178 barrel-front vertices (z > 0.30), mesh space.
	w.muzzle_offset = Vector3(0.0, 0.0714, 0.318)
	return w


# ALL calibration below is a measured SEED awaiting the user's rifle
# calibration session (socket, grips, curls, stow) — the values only need to
# put the rifle recognisably in the hands so the gizmos start somewhere sane.
func _assault_rifle() -> WeaponResource:
	var w := WeaponResource.new()
	w.id = &"AssaultRifle"
	w.anim_set = 1
	w.mesh_scene = load("res://assets/weapons/SM_Wep_AssaultRifle_01.fbx")

	# The revolver's measured basis rotated 27.45 deg about the gun's lateral
	# axis, in two probed rounds: +19.8 (a rifle-grip wrist holds the gun
	# muzzle-skyward vs the pistol-calibrated basis) then +7.65 more when the
	# rifle's ADS torso lock rose to 0.9 (the socket is calibrated THROUGH
	# the LookAt chain, so an influence change re-pitches the gun — see
	# LOOKAT_ADS_RIFLE in player.gd). ADS probes level; carry rakes ~-49, a
	# steep-but-fine low carry.
	# Hand-placed by the user 2026-07-26 — the FIRST time this socket was set by
	# eye rather than by the measured screenshot loop, and the change that fixed
	# the gun sitting wrong in the right fist. Note socket_origin is no longer
	# zero: the gun needed moving ~10.6 cm out of the wrist as well as rotating.
	# Read out of the saved hunter.tscn, not reconstructed from Euler.
	w.socket_basis_x = Vector3(0.121227, -0.003536, 0.992619)
	w.socket_basis_y = Vector3(0.768003, 0.633871, -0.091538)
	w.socket_basis_z = Vector3(-0.628868, 0.773431, 0.079558)
	w.socket_origin = Vector3(0.105734, 0.037378, 0.048830)
	# Negated grip centroid (112 verts, y < -0.02, -0.12 < z < 0.02, measured
	# 2026-07-23: (-0.0012, -0.0611, -0.0183)) PLUS the revolver's hand-finish
	# delta (+0.013, +0.0215, +0.078) — the fist-vs-centroid correction the
	# user's revolver placement encodes, weapon-agnostic to first order.
	w.mesh_offset = Vector3(0.014, 0.083, 0.096)
	# AIM grip: under the handguard (underside measured y=0.019 mesh, i.e.
	# 0.102 socket; centre z=0.28), wrist left of and below the surface.
	# Iterated against screenshots: pulled back to the guard's rear third (a
	# far-forward target straightened the elbow — user), then raised toward
	# the underside ("the left palm is on the air").
	# Hand-placed by the user on the gizmo, 2026-07-25, in hunter.tscn with the
	# AnimationPlayer previewing W2_Stand_Aim_Idle_v2 ("happy with this").
	# Replaces the screenshot-loop seed (0.06, 0.075, 0.33): further forward
	# along the handguard and slightly inboard.
	w.support_grip_pos = Vector3(0.0967697, 0.005177, 0.2837636)
	# CARRY grip: just ahead of the mag well, close to the right hand — the
	# handguard point over-reached the arm in the low carry ("left arm is
	# still over/hyper extended ... normalize the space between two hands on
	# relaxed" — user). player.gd lerps between the two with stance.
	# Low-carry grip, hand-placed by the user 2026-07-26 previewing
	# W2_Stand_Relaxed_Idle_v2. player.gd lerps SupportGrip between this and
	# support_grip_pos by the stance blend, so these two points cover every
	# rifle state -- there is no per-clip grip tuning.
	# Note it sits only ~8 mm behind the ADS point (z 0.2755 vs 0.2838) but
	# 4 cm higher: the carry differs mostly in hand HEIGHT, not reach.
	w.carry_support_grip_pos = Vector3(0.067523, 0.055392, 0.283459)
	w.elbow_pole_pos = Vector3(0.915536, 1.0, 0.15)

	# Authored by the user live in the running game (calibration_freeze
	# session, 2026-07-23) — in-progress values banked from their Inspector
	# screenshots so a crash or restart cannot lose them; the session is
	# still refining.
	# Support (left) hand, hand-finished by the user 2026-07-25 on the WristTarget
	# gizmo + tuner sliders, previewing W2_Stand_Aim_Idle_v2 in hunter.tscn.
	# The wrist is a big correction because the MotusMan clip's left hand is
	# posed for its own foregrip, not the Synty AK's; thumb_curl swings fully
	# negative to OPEN the thumb over the handguard instead of closing it.
	# Axes are stored unnormalised on purpose — the tuner normalises, so only
	# their direction matters and these are the values as dialled.
	w.wrist_offset_deg = Vector3(-10.580438, 112.45559, 26.64803)
	w.thumb_curl = -90.0
	w.index_curl = -90.0
	w.middle_curl = -73.5
	w.curl_axis = Vector3(4.39, -27.36, -28.03)
	w.thumb_axis = Vector3(-5.94, 4.35, -7.94)

	# Days Gone diagonal back carry. SEED ONLY. UpperChest-bone space: grip
	# lands at the lower back right (-X right, -Y down, -Z behind); the
	# rotation is Rz(-40)*Rx(-90) expressed in YXZ euler — barrel (mesh +Z,
	# 1.03 m long) up and leaned 40 deg toward the left shoulder, measured
	# barrel_dir (0.64, 0.77, 0) in the running scene.
	w.stow_socket = "back"
	w.stow_position = Vector3(-0.18, -0.30, -0.16)
	w.stow_rotation_deg = Vector3(-50, 90, -90)

	w.fire_clip = &"R_Fire"
	w.reload_clip = &"R_Reload"

	w.damage = 18.0
	w.rpm = 600.0
	w.auto_fire = true
	w.mag_size = 30
	w.reserve = 90
	w.reload_time = 2.2
	w.spread_deg = 1.4
	w.recoil_pitch_deg = 0.35
	w.ads_fov = 42.0
	w.hitscan_range = 150.0
	# Centroid of the 281 barrel-front vertices (z > 0.65), mesh space.
	w.muzzle_offset = Vector3(0.0, 0.112, 0.696)
	return w


func _save(w: WeaponResource, path: String) -> bool:
	if w.mesh_scene == null:
		push_error("mesh scene missing for " + String(w.id))
		return false
	var err := ResourceSaver.save(w, path)
	print("WEAPON  ", w.id, "  saved=", path, " err=", err)
	return err == OK
