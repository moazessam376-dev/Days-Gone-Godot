"""Self-test for check_clip.py: prove it rejects each defect class, and passes clean.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/blender/selftest_check_clip.py

Exit 0 = the validator discriminates, 1 = it does not.

A VALIDATOR THAT HAS NEVER FAILED HAS NOT BEEN TESTED. And exit codes alone are
not enough: a validator that fails EVERYTHING also "fails the broken clip". So
this asserts both directions -- the clean clip passes, and each broken clip is
rejected for ITS OWN defect and nothing else.

Two real bugs this caught in check_clip.py itself, both worth keeping in mind
before adding a check:

  * Presence is not motion. export_bake_animation + export_force_sampling emit a
    full location/rotation/scale track for EVERY bone (a 9-frame clip exports
    ~500 fcurves over 50 bones), so checking whether a track EXISTS failed every
    clip, good ones included.
  * A glTF round-trip reconstructs the armature rest differently, leaving frozen
    bones at a large CONSTANT pose offset -- RightLowerArm reads -0.376 m with a
    range of 0.000000. Measuring |value| called that "translation". Motion is the
    RANGE across keys, not the deviation from an assumed zero rest.
"""

import os
import sys
import tempfile

import bpy
from mathutils import Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_control_rig  # noqa: E402
import check_clip  # noqa: E402
import synty_rig  # noqa: E402

# mode -> substring that MUST appear in the rejection, or None for the clean clip
CASES = {
    "good": None,
    "scale": "SCALED away from 1.0",
    "drift": "drift",
    "root": "Root is animated",
    "tips": "finger tip",
    "dotname": "duplicate suffix",
}


def build_clip(mode: str, out_path: str) -> None:
    repo = synty_rig.repo_root()
    synty_rig.reset_scene()
    arm = build_control_rig.import_character(repo)
    gun = build_control_rig.import_weapon(repo, "AssaultRifle")
    build_control_rig.build_controls(arm, gun)

    # Mute IK so the ONLY variable between cases is the injected defect. With IK
    # live and no seed pose, WristTarget_L still sits at the right hand and the
    # solver drags the left arm 152 deg across the body -- a real defect, but not
    # the one under test.
    for pose_bone in arm.pose.bones:
        for constraint in pose_bone.constraints:
            constraint.mute = True

    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in arm.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"

    def key(bone, frame, quat=None, loc=None, scale=None):
        pose_bone = arm.pose.bones[bone]
        if quat is not None:
            pose_bone.rotation_quaternion = quat
            pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
        if loc is not None:
            pose_bone.location = loc
            pose_bone.keyframe_insert("location", frame=frame)
        if scale is not None:
            pose_bone.scale = scale
            pose_bone.keyframe_insert("scale", frame=frame)

    # A small, legitimate upper-body motion plus a little vertical Hips bob.
    for frame, angle in ((1, 0.0), (9, 0.08)):
        key("RightUpperArm", frame, quat=Quaternion((1, 0, 0), angle))
        key("Chest", frame, quat=Quaternion((1, 0, 0), angle * 0.5))
        key("Hips", frame, loc=Vector((0.0, angle * 0.01, 0.0)))

    if mode == "scale":
        key("RightHand", 1, scale=Vector((1, 1, 1)))
        key("RightHand", 9, scale=Vector((1.4, 1, 1)))
    elif mode == "drift":
        key("Hips", 1, loc=Vector((0, 0, 0)))
        key("Hips", 9, loc=Vector((0.9, 0, 0)))
    elif mode == "root":
        key(synty_rig.ROOT_BONE, 1, quat=Quaternion((1, 0, 0), 0.0))
        key(synty_rig.ROOT_BONE, 9, quat=Quaternion((1, 0, 0), 0.3))
    elif mode == "tips":
        key("IndexFinger_04", 1, quat=Quaternion((1, 0, 0), 0.0))
        key("IndexFinger_04", 9, quat=Quaternion((1, 0, 0), 0.4))
    elif mode == "dotname":
        bpy.ops.object.mode_set(mode="OBJECT")
        arm.data.bones["LeftHand"].name = "LeftHand.001"
        bpy.ops.object.mode_set(mode="POSE")

    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and obj.find_armature() is arm:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_bake_animation=True,
        export_force_sampling=True,
        export_def_bones=True,
        export_leaf_bone=False,
        export_anim_slide_to_zero=True,
        export_apply=False,
    )


def validate(path: str) -> list[str]:
    arm, action = check_clip.load_clip(path)
    errors: list[str] = []
    check_clip.check_bone_names(arm, errors)
    check_clip.check_tracks(action, errors)
    check_clip.check_hips_drift(action, errors)
    return errors


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="selftest_clips_")
    failures = 0

    paths = {}
    for mode in CASES:
        paths[mode] = os.path.join(tmp, f"clip_{mode}.glb")
        build_clip(mode, paths[mode])

    print("=" * 68)
    for mode, expect in CASES.items():
        errors = validate(paths[mode])

        if expect is None:
            ok = not errors
            print(f"SELFTEST {mode:<8} clean clip -> {'PASS' if ok else 'FAIL'}")
            if not ok:
                failures += 1
                for err in errors:
                    print(f"SELFTEST   unexpected: {err}")
        else:
            matched = [e for e in errors if expect in e]
            # Exactly one problem, and it is the injected one: proves the check
            # is specific, not just noisy.
            ok = len(errors) == 1 and len(matched) == 1
            print(
                f"SELFTEST {mode:<8} rejected={bool(errors)} "
                f"problems={len(errors)} matched={bool(matched)} -> "
                f"{'PASS' if ok else 'FAIL'}"
            )
            if not ok:
                failures += 1
                for err in errors:
                    print(f"SELFTEST   got: {err[:100]}")

    print("=" * 68)
    print(f"SELFTEST {'ALL PASS' if failures == 0 else f'{failures} CASE(S) FAILED'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
