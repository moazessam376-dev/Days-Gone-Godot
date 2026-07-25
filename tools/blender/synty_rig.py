"""Shared helpers for the Synty authoring rig.

Targets Blender 4.5.12 LTS / Python 3.11.11 (see docs/blender-env.md). Do not
port this to another Blender version without re-running the probe.

The one job that matters here: get Blender's bone names to match what the GODOT
skeleton calls them, so an exported clip's tracks resolve with no BoneMap and no
retarget. Read .claude/skills/blender-authoring/ before touching any of it.
"""

import os
import re

import bpy

# The Godot BoneMap is the single source of truth for Synty -> humanoid names.
# Parsed, never retyped: a hardcoded copy here is a second source of truth that
# drifts from the map the game actually imports through.
BONEMAP_TRES = "resources/rigs/synty_apocalypse_bonemap.tres"

# Synty's index and merged-finger chains have FOUR joints; SkeletonProfileHumanoid
# defines three. The 4th is unmapped, keeps its Synty name on the Godot skeleton,
# and is driven at runtime by scripts/rig/finger_tip_modifier.gd. Authored clips
# must not key these -- a track here either misses or fights the modifier.
#
# Godot's ufbx importer disambiguates the right-side duplicates with "_2".
UNMAPPED_TIP_BONES = {
    "IndexFinger_04": "IndexFinger_04",
    "Finger_04": "Finger_04",
}

# Godot's ufbx importer disambiguates Synty's duplicate finger bone names with
# this suffix; Blender's FBX importer uses ".001". Bridging the two is the whole
# job of resolve_synty_names(). See .claude/skills/blender-authoring/.
RIGHT_DUP_SUFFIX = "_2"

# Never keyed, though it IS a mapped bone. Clips that key Root poison every later
# clip that does not (the character holds the stale root pose) -- which is why
# Godot's build runs _collapse_root_into_hips(). In-place clips move Hips only.
ROOT_BONE = "Root"

# MEASURED against Characters.fbx on Blender 4.5.12, not taken from the docs:
# ignore_leaf_bones=True drops 8 REAL bones, including Thumb_03 / Thumb_03.001 --
# which are MAPPED (Left/RightThumbDistal). It also drops Finger_04 and
# IndexFinger_04. Importing with True yields 42 bones and a rig that cannot key
# the thumb tip; False yields 50 and the complete skeleton. Always import False.
FBX_IMPORT_KWARGS = {
    "use_anim": False,
    "ignore_leaf_bones": False,
    "automatic_bone_orientation": True,
}

_BONEMAP_LINE = re.compile(r'^bone_map/(\w+)\s*=\s*&"([^"]*)"', re.MULTILINE)


def repo_root() -> str:
    """The days-gone checkout root, derived from this file's location."""
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def load_bone_map(repo: str | None = None) -> dict[str, str]:
    """Parse the Godot BoneMap into {synty_bone_name: humanoid_slot_name}.

    Skips unmapped slots (empty string values), e.g. Synty's absent Ring and
    Little finger chains -- the hand has only three fingers.
    """
    repo = repo or repo_root()
    path = os.path.join(repo, BONEMAP_TRES)
    if not os.path.isfile(path):
        raise FileNotFoundError(f"BoneMap not found: {path}")
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()

    mapping: dict[str, str] = {}
    for slot, synty_name in _BONEMAP_LINE.findall(text):
        if not synty_name:
            continue
        if synty_name in mapping:
            raise ValueError(
                f"BoneMap maps '{synty_name}' to both '{mapping[synty_name]}' and "
                f"'{slot}' -- the map is ambiguous, fix the .tres"
            )
        mapping[synty_name] = slot
    if not mapping:
        raise ValueError(f"parsed no bone_map entries out of {path}")
    return mapping


def humanoid_bone_names(repo: str | None = None) -> set[str]:
    """Every humanoid slot name an authored clip is allowed to key."""
    return set(load_bone_map(repo).values())


def _side_of(bone: bpy.types.Bone) -> str | None:
    """Walk up the parent chain until a side-unambiguous ancestor names a side.

    Import ORDER is not a contract, so `.001` alone never decides which side a
    duplicate bone is. The hierarchy does: Synty's arm, hand and spine bones are
    uniquely named, so the first ancestor ending in _L / _R is authoritative.
    """
    node = bone
    while node is not None:
        stem = node.name.split(".")[0]
        if stem.endswith("_L"):
            return "L"
        if stem.endswith("_R"):
            return "R"
        node = node.parent
    return None


def resolve_synty_names(armature: bpy.types.Object) -> dict[str, str]:
    """Map each Blender bone to its canonical Godot name.

    Blender's FBX importer disambiguates duplicate bone names with `.001`;
    Godot's ufbx importer uses `_2`. Neither matches the other, so a naive
    round-trip silently drops every finger track. This resolves the collisions
    by hierarchy and returns {blender_bone_name: godot_bone_name}.

    Mapped bones become their humanoid slot name (LeftThumbMetacarpal), which is
    unique by construction. Unmapped finger tips keep Synty names, with the right
    side taking Godot's `_2` suffix.
    """
    bone_map = load_bone_map()
    out: dict[str, str] = {}
    seen: dict[str, str] = {}

    for bone in armature.data.bones:
        stem = bone.name.split(".")[0]
        dup_stem = stem + RIGHT_DUP_SUFFIX

        if stem in bone_map or stem in UNMAPPED_TIP_BONES:
            # A stem that ALSO exists with the _2 suffix is one of Synty's
            # duplicate finger bones, so this bone is either the left or the
            # right one and only the hierarchy can say which. Everything else
            # (Hand_R, Clavicle_R...) already carries its side in the name.
            is_duplicated = dup_stem in bone_map or stem in UNMAPPED_TIP_BONES
            side = _side_of(bone) if is_duplicated else None
            if is_duplicated and side is None:
                raise ValueError(
                    f"cannot determine the side of '{bone.name}': no ancestor "
                    f"names _L or _R. Refusing to guess."
                )

            if stem in bone_map:
                target = bone_map[dup_stem] if side == "R" and dup_stem in bone_map else bone_map[stem]
            else:
                target = UNMAPPED_TIP_BONES[stem]
                if side == "R":
                    target += RIGHT_DUP_SUFFIX
        else:
            # Leave anything unrecognised alone rather than inventing a name
            # (Eyes, Eyebrows, the Toes_* leaf children of Ball_*).
            # check_clip.py rejects them loudly if they reach an export.
            continue

        if target in seen:
            raise ValueError(
                f"two bones resolve to '{target}': '{seen[target]}' and "
                f"'{bone.name}'. The duplicate-name resolution is wrong -- do "
                f"not rename past this, it would silently merge tracks."
            )
        seen[target] = bone.name
        out[bone.name] = target

    return out


def rename_to_humanoid(armature: bpy.types.Object) -> dict[str, str]:
    """Rename the armature's bones in place to their Godot names.

    Two-pass via temporary names: renaming A->B while a bone named B still
    exists makes Blender silently append `.001` to one of them, which is the
    exact class of bug this whole module exists to prevent.
    """
    resolved = resolve_synty_names(armature)

    missing = humanoid_bone_names() - set(resolved.values())
    if missing:
        raise ValueError(
            "these humanoid slots found no bone on the armature: "
            + ", ".join(sorted(missing))
        )

    for index, (blender_name, _) in enumerate(resolved.items()):
        armature.data.bones[blender_name].name = f"__tmp_{index}__"
    for index, (_, godot_name) in enumerate(resolved.items()):
        armature.data.bones[f"__tmp_{index}__"].name = godot_name

    return resolved


def find_armature(context: bpy.types.Context | None = None) -> bpy.types.Object:
    """The one armature in the scene. Errors if there is not exactly one."""
    scene = (context or bpy.context).scene
    rigs = [o for o in scene.objects if o.type == "ARMATURE"]
    if len(rigs) != 1:
        raise ValueError(f"expected exactly 1 armature in the scene, found {len(rigs)}")
    return rigs[0]


def reset_scene() -> None:
    """Empty the scene. Blender's default cube is not a neutral starting point."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
