"""Validate an authored clip before it is allowed near the game.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/blender/check_clip.py -- <clip.glb> [--frames N] [--seed pose.json]

Exit 0 = pass, 1 = fail. The Blender-side twin of tools/rig/verify_pose.gd, and
CI-able because Blender's --background evaluates armatures for real (unlike
Godot's --headless, which cannot render at all).

Every check here corresponds to a failure this project has already shipped, or
to a documented trap in .claude/skills/blender-authoring/. A validator that has
never failed has not been tested -- see the self-test at the bottom of that
skill, and run it against a deliberately broken clip before trusting a pass.
"""

import argparse
import json
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synty_rig  # noqa: E402

# A clip is in-place: Godot's build collapses Root into Hips and the locomotion
# system owns world movement. Hips may bob, but must not walk away.
HIPS_DRIFT_TOLERANCE_M = 0.02
SEED_TOLERANCE_DEG = 1.0


class Failure(Exception):
    pass


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser(prog="check_clip.py")
    p.add_argument("clip")
    p.add_argument("--frames", type=int, default=0, help="expected frame count")
    p.add_argument("--seed", default="", help="seed pose JSON that frame 0 must match")
    return p.parse_args(argv)


def load_clip(path: str) -> tuple[bpy.types.Object, bpy.types.Action]:
    if not os.path.isfile(path):
        raise Failure(f"no such file: {path}")
    synty_rig.reset_scene()
    bpy.ops.import_scene.gltf(filepath=path)

    rigs = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    if len(rigs) != 1:
        raise Failure(f"expected exactly 1 armature in the clip, found {len(rigs)}")
    arm = rigs[0]

    if not (arm.animation_data and arm.animation_data.action):
        raise Failure("the armature carries no action -- the clip has no animation")
    return arm, arm.animation_data.action


def bone_of(fcurve: bpy.types.FCurve) -> str | None:
    path = fcurve.data_path
    if not path.startswith('pose.bones["'):
        return None
    return path.split('"')[1]


def channel_of(fcurve: bpy.types.FCurve) -> str:
    return fcurve.data_path.rsplit(".", 1)[-1]


def check_bone_names(arm: bpy.types.Object, errors: list[str]) -> None:
    """Names must match the GODOT skeleton, or every track silently misses."""
    names = {b.name for b in arm.data.bones}

    # Blender's duplicate-name suffix. If one of these survives to an export the
    # track resolves against nothing on the Godot skeleton -- no error, no
    # warning, a finger that simply never moves.
    dotted = sorted(n for n in names if "." in n)
    if dotted:
        errors.append(
            f"{len(dotted)} bone(s) carry Blender's duplicate suffix, which Godot "
            f"cannot resolve: {dotted[:6]}. Run rename_to_humanoid() (synty_rig.py)."
        )


# Deviation from REST at which a channel counts as animated. Pose-space rest is
# identity, so these are absolute.
#
# These thresholds exist because the glTF exporter, with export_bake_animation +
# export_force_sampling (which we WANT -- sampled keys are what Godot reads
# reliably), emits a full location/rotation/scale track for EVERY bone, Root and
# unmapped bones included. Measured: a clean 9-frame clip exports 500 fcurves
# across 50 bones. So the presence of a track proves nothing; only motion does.
# An earlier version of this file checked presence and failed every clip it was
# given, including known-good ones -- a validator that cannot tell good from bad.
SCALE_EPS = 1e-3     # deviation from 1.0
LOCATION_EPS = 1e-3  # metres from rest

# MEASURED, not guessed. A glTF round-trip of a clean clip leaves ~0.73 deg of
# residual rotation across a whole hand chain (RightMiddleDistal, RightIndexDistal
# and the unmapped tips all read 0.73 deg on a clip that never keyed them) --
# sampling plus quantisation, not authored motion. 0.5 deg flagged that noise as
# a defect; 2.0 clears it while staying far below anything an animator would
# author on a bone that is supposed to be frozen.
ROTATION_EPS_DEG = 2.0


def _channel_motion(action: bpy.types.Action) -> dict[tuple[str, str], float]:
    """How much each (bone, channel) MOVES across the clip.

    Location and rotation are measured as the RANGE (max - min) over the keys,
    NOT as deviation from an assumed zero rest.

    MEASURED reason: a glTF export/re-import reconstructs the armature rest
    differently, so a bone that never moves still reads a large CONSTANT
    pose-space offset. On a clean clip, RightLowerArm sits at -0.376 m with a
    range of 0.000000, and LeftLowerArm at +0.372 m with a range of 0.000006 --
    while the authored Hips bob has a range of 0.000795. Measuring |value|
    called those two frozen bones "translating" and failed every good clip;
    measuring the range separates rest reconstruction from real motion.

    Scale stays a deviation from 1.0: a CONSTANT 1.4x scale is itself the defect
    (it tears the mesh), and the round-trip's own scale artifact measures ~1e-6.
    """
    import math

    worst: dict[tuple[str, str], float] = {}
    quats: dict[str, dict[int, list[float]]] = {}

    for fcurve in action.fcurves:
        bone = bone_of(fcurve)
        if bone is None:
            continue
        channel = channel_of(fcurve)
        values = [k.co[1] for k in fcurve.keyframe_points]
        if not values:
            continue

        if channel == "scale":
            dev = max(abs(v - 1.0) for v in values)
        elif channel == "location":
            dev = max(values) - min(values)
        elif channel == "rotation_quaternion":
            quats.setdefault(bone, {})[fcurve.array_index] = values
            continue
        else:
            continue

        key = (bone, channel)
        worst[key] = max(worst.get(key, 0.0), dev)

    # Rotation is only meaningful across all four components together, and the
    # same rest-reconstruction caveat applies -- so take the SPREAD of the
    # per-key angle, not its peak.
    for bone, comps in quats.items():
        if 0 not in comps:
            continue
        count = min(len(v) for v in comps.values())
        angles = []
        for i in range(count):
            w = max(-1.0, min(1.0, abs(comps[0][i])))
            angles.append(math.degrees(2.0 * math.acos(w)))
        if angles:
            worst[(bone, "rotation_quaternion")] = max(angles) - min(angles)

    return worst


def check_tracks(action: bpy.types.Action, errors: list[str]) -> None:
    """Reject bones that MOVE when they must not. Presence alone is fine."""
    motion = _channel_motion(action)

    tips = set()
    for tip in synty_rig.UNMAPPED_TIP_BONES.values():
        tips.add(tip)
        tips.add(tip + synty_rig.RIGHT_DUP_SUFFIX)
    frozen = tips | synty_rig.UNMAPPED_SKELETON_BONES | {synty_rig.ROOT_BONE}

    scaled = sorted(
        b for (b, c), d in motion.items() if c == "scale" and d > SCALE_EPS
    )
    translated = sorted(
        b
        for (b, c), d in motion.items()
        if c == "location" and b != synty_rig.TRANSLATING_BONE and d > LOCATION_EPS
    )
    moved_frozen = sorted(
        {
            b
            for (b, c), d in motion.items()
            if b in frozen
            and d > (ROTATION_EPS_DEG if c == "rotation_quaternion" else LOCATION_EPS)
        }
    )

    if scaled:
        errors.append(
            f"{len(scaled)} bone(s) are SCALED away from 1.0: {scaled[:6]}. "
            f"Differing limb proportions plus scale keys tears the mesh."
        )
    if translated:
        errors.append(
            f"{len(translated)} non-Hips bone(s) TRANSLATE: {translated[:6]}. "
            f"Translation belongs on Hips only; everything else is pure rotation."
        )
    for bone in moved_frozen:
        if bone == synty_rig.ROOT_BONE:
            errors.append(
                "Root is animated. A clip that moves Root poisons every clip "
                "played after it that does not -- the character holds the stale "
                "root pose. Godot's _collapse_root_into_hips() exists for this."
            )
        elif bone in tips:
            errors.append(
                f"unmapped finger tip '{bone}' is animated. Tips are driven at "
                f"runtime by finger_tip_modifier.gd; a moving track fights it."
            )
        else:
            errors.append(
                f"unmapped bone '{bone}' is animated. It has no humanoid slot, so "
                f"the track lands on nothing useful in Godot."
            )


def check_hips_drift(action: bpy.types.Action, errors: list[str]) -> None:
    per_axis = {}
    for fcurve in action.fcurves:
        if bone_of(fcurve) == "Hips" and channel_of(fcurve) == "location":
            keys = [k.co[1] for k in fcurve.keyframe_points]
            if keys:
                per_axis[fcurve.array_index] = abs(keys[-1] - keys[0])
    if not per_axis:
        return
    # Vertical bob is legitimate; walking away from the origin is not. glTF is
    # Y-up, so index 1 is vertical.
    horizontal = max((v for i, v in per_axis.items() if i != 1), default=0.0)
    if horizontal > HIPS_DRIFT_TOLERANCE_M:
        errors.append(
            f"Hips drift {horizontal:.3f} m horizontally over the clip "
            f"(tolerance {HIPS_DRIFT_TOLERANCE_M}). In-place clips must not travel."
        )


def check_frames(action: bpy.types.Action, expected: int, errors: list[str]) -> None:
    start, end = (int(round(v)) for v in action.frame_range)
    actual = end - start + 1
    if expected and actual != expected:
        errors.append(f"frame count is {actual}, expected {expected}")


def check_seed(arm: bpy.types.Object, seed_path: str, errors: list[str]) -> None:
    """Frame 0 must match the pose the weapon socket is calibrated against.

    This is the load-bearing assert. Clips are seeded from the calibrated aim
    pose precisely so an authored fire or reload BEGINS where the aim pose ends.
    If frame 0 drifts, the cross-fade discontinuity that threw the rifle 49 deg
    sideways on every shot comes straight back.
    """
    from mathutils import Quaternion

    with open(seed_path, "r", encoding="utf-8") as handle:
        seed = json.load(handle)

    bpy.context.scene.frame_set(int(round(arm.animation_data.action.frame_range[0])))
    bpy.context.view_layer.update()

    worst_bone, worst_deg = "", 0.0
    missing = []
    for bone_name, quat in seed.items():
        pose_bone = arm.pose.bones.get(bone_name)
        if pose_bone is None:
            missing.append(bone_name)
            continue
        want = Quaternion((quat["w"], quat["x"], quat["y"], quat["z"]))
        got = pose_bone.rotation_quaternion
        dot = min(1.0, abs(want.dot(got)))
        import math

        deg = math.degrees(2.0 * math.acos(dot))
        if deg > worst_deg:
            worst_bone, worst_deg = bone_name, deg

    if missing:
        errors.append(f"seed names bones the clip does not have: {missing[:6]}")
    if worst_deg > SEED_TOLERANCE_DEG:
        errors.append(
            f"frame 0 does not match the seed pose: {worst_bone} is off by "
            f"{worst_deg:.2f} deg (tolerance {SEED_TOLERANCE_DEG}). The authored "
            f"clip must begin exactly where the calibrated aim pose sits."
        )
    else:
        print(f"CHECK   seed match: worst bone {worst_bone or '-'} {worst_deg:.3f} deg")


def main() -> int:
    args = parse_args()
    errors: list[str] = []

    try:
        arm, action = load_clip(args.clip)
    except Failure as exc:
        print(f"CHECK   FAIL  {exc}")
        return 1

    print(f"CHECK   clip={os.path.basename(args.clip)} action={action.name}")
    print(f"CHECK   bones={len(arm.data.bones)} fcurves={len(action.fcurves)}")

    check_bone_names(arm, errors)
    check_tracks(action, errors)
    check_hips_drift(action, errors)
    check_frames(action, args.frames, errors)
    if args.seed:
        try:
            check_seed(arm, args.seed, errors)
        except Failure as exc:
            errors.append(str(exc))

    if errors:
        print(f"CHECK   FAIL ({len(errors)} problem(s))")
        for err in errors:
            print(f"CHECK     - {err}")
        return 1

    print("CHECK   PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
