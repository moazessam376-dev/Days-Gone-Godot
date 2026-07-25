"""Export the authored clip as a Godot-ready glTF.

    /Applications/Blender.app/Contents/MacOS/Blender --background rig.blend \
        --python tools/blender/export_clip.py -- --name R_Fire_Authored

Writes assets/animations/authored/<name>.glb.

Targets Blender 4.5.12 LTS. Every property set below was checked against the
live RNA on that build (docs/blender-env.md) -- a silent rename between Blender
versions is the usual way an export script starts producing subtly wrong files.

glTF, not FBX, deliberately: it sidesteps the ufbx quirks entirely, including
godot#90314 (empty Node3D imports at 100x scale with wrong rotation), which
bites weapon sockets specifically.
"""

import argparse
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synty_rig  # noqa: E402

OUT_DIR = "assets/animations/authored"


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser(prog="export_clip.py")
    p.add_argument("--name", required=True, help="clip name; becomes the filename")
    p.add_argument("--out-dir", default="")
    return p.parse_args(argv)


def main() -> int:
    args = parse_args()
    repo = synty_rig.repo_root()
    out_dir = args.out_dir or os.path.join(repo, OUT_DIR)
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{args.name}.glb")

    arm = synty_rig.find_armature()

    # Select the armature and its meshes only. The control empties
    # (WeaponControl, WristTarget_*, ElbowPole_*) are authoring scaffolding --
    # exporting them would add tracks the Godot skeleton has no bones for, and
    # they are exactly the empties godot#90314 mis-scales.
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
        export_yup=True,               # Godot's convention
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_bake_animation=True,    # sampled keys are what Godot reads reliably
        export_force_sampling=True,
        export_def_bones=True,         # deform bones only -- no control scaffolding
        export_leaf_bone=False,
        export_anim_slide_to_zero=True,
        export_apply=False,            # modifiers on an animated rig must not be applied
    )

    size = os.path.getsize(out_path)
    print(f"EXPORT  {args.name} -> {out_path} ({size} bytes)")
    print("EXPORT  NEXT: validate before trusting it --")
    print(f"EXPORT    Blender --background --python tools/blender/check_clip.py -- {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
