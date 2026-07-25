"""Build the Synty authoring rig: character + weapon + IK controllers.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/blender/build_control_rig.py -- --weapon AssaultRifle --out rig.blend

Run without --background to build it in front of you, or open the saved .blend.

Targets Blender 4.5.12 LTS (docs/blender-env.md). Read
.claude/skills/blender-authoring/ first.

WHAT YOU POSE
    WeaponControl   the gun. Move/rotate this for recoil -- both hands follow.
    ElbowPole_L/R   which way each elbow points.
    WristTarget_L/R where each palm sits on the gun (parented to WeaponControl,
                    so they ride it).

That is the whole interface: four to five controllers instead of 50 bones.

WHY IT MIRRORS hunter.tscn
    Godot solves LeftArmIK (TwoBoneIK3D) onto SupportGrip, which rides the
    weapon socket on the RightHand bone. Authoring against the same topology
    means what you pose here is what the engine reproduces. The right arm is
    IK'd here too -- Godot does not IK it, it parents the weapon TO the hand,
    so keying the right hand to the weapon control round-trips correctly: the
    hand lands where you put the gun, and in game the gun follows the hand.

RUN seed_pose.py NEXT -- THE BARE RIG IS NOT POSEABLE
    A freshly imported Synty character is in a T-POSE, where both arms are
    already fully extended. That is a DEGENERATE configuration for IK: there is
    no elbow bend to rotate, so the poles do nothing and dragging a wrist target
    outward barely moves the hand. Measured on this rig, pushing WristTarget_L
    0.25 m from the T-pose moved the hand 0.014 m and the elbow pole moved the
    elbow 0.0004 m -- which reads exactly like broken plumbing and is not.

    The IK is fine. Verified by placing the target at absolute points inside the
    reach envelope:

        arm reach (LeftUpperArm -> LeftHand)      0.609 m
        hand-to-target error, 55% extension       0.0004 m
        hand-to-target error, 95% extension       0.0004 m
        elbow travel from the pole, arm bent      0.104 m

    (0.609 m also cross-checks the Godot side, where docs/rig-tuning.md records
    the same arm as ~61 cm of reach -- the two rigs have matching proportions.)

    So always seed the calibrated aim pose before posing. That is what
    seed_pose.py is for, and it is why authored clips start from the pose the
    weapon socket is calibrated against.
"""

import argparse
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synty_rig  # noqa: E402

CHARACTER_FBX = "assets/characters/Characters.fbx"
KEEP_MESH = "SM_Chr_Hunter_Male_01"

# Weapon id -> source FBX, matching resources/weapons/*.tres.
WEAPONS = {
    "AssaultRifle": "assets/weapons/SM_Wep_AssaultRifle_01.fbx",
    "Revolver": "assets/weapons/SM_Wep_Revolver_01.fbx",
}

IK_CHAINS = [
    {"side": "L", "lower": "LeftLowerArm", "hand": "LeftHand"},
    {"side": "R", "lower": "RightLowerArm", "hand": "RightHand"},
]


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser(prog="build_control_rig.py")
    p.add_argument("--weapon", default="AssaultRifle", choices=sorted(WEAPONS))
    p.add_argument("--out", default="", help="save the .blend here (optional)")
    return p.parse_args(argv)


def import_character(repo: str) -> bpy.types.Object:
    """Import Characters.fbx, drop the 30 unused meshes, normalise bone names."""
    path = os.path.join(repo, CHARACTER_FBX)
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    bpy.ops.import_scene.fbx(filepath=path, **synty_rig.FBX_IMPORT_KWARGS)

    # Characters.fbx packs 31 character meshes onto ONE skeleton. Same reasoning
    # as tools/build_character.gd: keep Hunter, drop the rest. This only removes
    # mesh objects; the rig is untouched.
    removed = 0
    for obj in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
        if obj.name != KEEP_MESH:
            bpy.data.objects.remove(obj, do_unlink=True)
            removed += 1

    arm = synty_rig.find_armature()
    synty_rig.rename_to_humanoid(arm)
    print(f"RIG  character bones={len(arm.data.bones)} dropped_meshes={removed}")
    return arm


def import_weapon(repo: str, weapon_id: str) -> bpy.types.Object:
    path = os.path.join(repo, WEAPONS[weapon_id])
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=path, use_anim=False, ignore_leaf_bones=False)
    new = [o for o in set(bpy.context.scene.objects) - before if o.type == "MESH"]
    if not new:
        raise ValueError(f"no mesh imported from {path}")
    gun = new[0]
    gun.name = weapon_id
    for extra in new[1:]:
        bpy.data.objects.remove(extra, do_unlink=True)
    print(f"RIG  weapon={weapon_id}")
    return gun


def make_empty(name: str, location: Vector, size: float, kind: str) -> bpy.types.Object:
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = kind
    empty.empty_display_size = size
    empty.location = location
    bpy.context.scene.collection.objects.link(empty)
    return empty


def bone_head_world(arm: bpy.types.Object, bone_name: str) -> Vector:
    return arm.matrix_world @ arm.data.bones[bone_name].head_local


def bone_tail_world(arm: bpy.types.Object, bone_name: str) -> Vector:
    return arm.matrix_world @ arm.data.bones[bone_name].tail_local


def build_controls(arm: bpy.types.Object, gun: bpy.types.Object) -> dict:
    """Weapon control + wrist targets + elbow poles, then the IK constraints."""
    right_hand = bone_head_world(arm, "RightHand")

    # The weapon control starts at the right hand: that is where the gun is held,
    # and it makes "move this for recoil" the obvious gesture.
    weapon_control = make_empty("WeaponControl", right_hand, 0.15, "ARROWS")
    gun.parent = weapon_control
    gun.matrix_parent_inverse = weapon_control.matrix_world.inverted()

    controls = {"WeaponControl": weapon_control}

    for chain in IK_CHAINS:
        side = chain["side"]
        hand_head = bone_head_world(arm, chain["hand"])

        # Wrist targets ride the weapon control, so moving the gun carries both
        # hands with it -- the single gesture a recoil clip is made of.
        wrist = make_empty(f"WristTarget_{side}", hand_head, 0.05, "SPHERE")
        wrist.parent = weapon_control
        wrist.matrix_parent_inverse = weapon_control.matrix_world.inverted()

        # Pole sits behind the elbow so the arm keeps a natural break. A pole is
        # MANDATORY: without one the elbow flips between valid IK solutions
        # mid-animation (same reason hunter.tscn ships LeftElbowPole).
        elbow = bone_head_world(arm, chain["lower"])
        pole = make_empty(f"ElbowPole_{side}", elbow + Vector((0.0, 0.35, 0.0)), 0.07, "PLAIN_AXES")

        pose_bone = arm.pose.bones[chain["lower"]]
        ik = pose_bone.constraints.new("IK")
        ik.target = wrist
        ik.pole_target = pole
        ik.chain_count = 2  # lower arm + upper arm, matching TwoBoneIK3D
        ik.use_tail = True

        controls[wrist.name] = wrist
        controls[pole.name] = pole
        print(f"RIG  IK {side}: {chain['lower']} -> {wrist.name} pole={pole.name}")

    return controls


def main() -> int:
    args = parse_args()
    repo = synty_rig.repo_root()

    synty_rig.reset_scene()
    arm = import_character(repo)
    gun = import_weapon(repo, args.weapon)
    controls = build_controls(arm, gun)

    print("RIG  controls=" + ", ".join(sorted(controls)))
    print(f"RIG  OK weapon={args.weapon}")
    print(
        "RIG  NEXT: run seed_pose.py. The T-pose is a degenerate IK "
        "configuration -- the poles will appear dead and the wrist targets "
        "weak until a bent-arm pose is seeded. See this file's docstring."
    )

    if args.out:
        out = os.path.abspath(args.out)
        bpy.ops.wm.save_as_mainfile(filepath=out)
        print(f"RIG  saved={out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
