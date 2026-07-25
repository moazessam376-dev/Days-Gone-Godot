---
name: blender-authoring
description: Read BEFORE writing or editing any bpy script, importing the Synty character into Blender, building or changing the control rig, exporting a clip for Godot, or adding a clip to assets/animations/authored/. Covers the pinned Blender/Python version, the duplicate-bone-name trap that breaks naive FBX round-trips, the humanoid-name convention authored clips must speak, known-good glTF export settings, the IK control rig, and the rule that authored clips get no retarget and no correction.
---

# Authoring animation in Blender for this project

New clips are **keyed by the user in Blender on the Synty skeleton**. Nothing
authored here is retargeted. That is the point: no BoneMap, no rest-pose delta,
no `fix_silhouette`, no `overwrite_axis`, no build-time correction pass — and
therefore none of the bug class in `godot-rig-retargeting`, which exists
entirely to undo retargeting artefacts.

Version, install and the pipeline table live in **`docs/blender-env.md`**.
Read that first; this file is the *how*, that one is the *what and where*.

## Pin the version, always

Every script in `tools/blender/` targets the Blender + Python version recorded
in `docs/blender-env.md`. **Do not write `bpy` from memory of another version.**
`bpy` API churn between releases is the most common way generated scripts break,
and generating 2.9x-era calls that fail on 4.x is free to prevent and expensive
to debug.

If `docs/blender-env.md` still says _pending_, the probe has not been run.
Stop and ask for it rather than guessing.

## The trap that will cost you a day: duplicate bone names

**The raw `Characters.fbx` contains two bones literally named `Thumb_01`.**
Same for `IndexFinger_01/02/03/04` and `Finger_01/02/03/04` — Synty ships the
left and right finger chains with *identical* names and no side suffix.
Verified on the bytes:

```bash
strings -a assets/characters/Characters.fbx | grep -cx Thumb_01     # → 2
strings -a assets/characters/Characters.fbx | grep -cx IndexFinger_01  # → 2
strings -a assets/characters/Characters.fbx | grep -cx Hand_L        # → 1
```

Arm, leg, spine and hand bones are unique. Only the finger chains collide.

Each importer disambiguates differently, and **neither matches the other**:

| Importer | Right-side result |
|---|---|
| Godot (ufbx) | `Thumb_01_2` |
| Blender (FBX) | `Thumb_01.001` |

So a clip authored in Blender and exported naively carries `Thumb_01.001`,
which resolves against nothing on the Godot skeleton. The track is silently
dropped — no error, no warning, a finger that simply never moves.

Two consequences:

- **Never trust import order to tell you which side a duplicate is.** Resolve
  it by walking the parent chain to `Hand_L` / `Hand_R`, and *assert* you found
  exactly one of each. Import order is not a contract.
- **Rename at rig-build time, not export time.** `build_control_rig.py`
  normalises names immediately after import, so everything downstream — the
  user's posing, the export, the validator — speaks one vocabulary.

## Authored clips speak HUMANOID names, not Synty names

This is the part that is easy to get subtly wrong.

Godot imports `Characters.fbx` *through* the Synty BoneMap, which **renames the
bones to `SkeletonProfileHumanoid` names at import time**. So the live skeleton,
and every track path in `hunter_anim_library.res`, speaks:

```
%GeneralSkeleton:Hips        %GeneralSkeleton:RightUpperArm
%GeneralSkeleton:Spine       %GeneralSkeleton:RightHand
%GeneralSkeleton:Chest       %GeneralSkeleton:RightThumbMetacarpal
```

**not** `Spine_01`, `Shoulder_R`, `Hand_R`, `Thumb_01_2`.

An authored clip has to land in that same library and play on that same
skeleton, so `build_control_rig.py` renames the Blender armature's bones to the
**humanoid profile names** up front. Benefits, all of them load-bearing:

- the exported glTF's track names already match the target skeleton, so Godot
  imports it with **no BoneMap at all**
- the duplicate-finger problem disappears by construction —
  `LeftThumbMetacarpal` and `RightThumbMetacarpal` cannot collide
- the user poses bones with the same names used everywhere else in the project

**Source the mapping from `resources/rigs/synty_apocalypse_bonemap.tres`, do not
retype it.** It is a plain text file; parse the
`bone_map/<Slot> = &"<synty name>"` lines. A hardcoded copy in a `.py` is a
second source of truth that will drift from the map the game actually imports
through.

### The bones with no humanoid slot

Synty's index and merged-finger chains have **four** joints; the humanoid
profile defines three. So `IndexFinger_04` and `Finger_04` (and their right-side
twins) are **unmapped** — they keep their Synty names on the Godot skeleton and
are driven at runtime by `scripts/rig/finger_tip_modifier.gd` from their parent.

**Authored clips must not key them.** A track for an unmapped bone either
misses or fights the modifier. `check_clip.py` asserts their absence.

`Thumb` has only three joints, so there is no `Thumb_04`. Do not add one.

Also unmapped and **never keyed**: `Root`. Godot's
`_collapse_root_into_hips()` exists because clips that key `Root` poison every
later clip that does not — the character holds the stale root pose. In-place
clips carry motion on `Hips` only.

## The control rig — pose 4 controllers, not 60 bones

`build_control_rig.py` mirrors the architecture already in `hunter.tscn`, so
what the user poses in Blender matches what the engine solves at runtime:

| Godot | Blender equivalent |
|---|---|
| `BoneAttachment3D` on `RightHand` → `WeaponSocket` | weapon parented to the `RightHand` bone |
| `TwoBoneIK3D` (`LeftUpperArm`→`LeftLowerArm`→`LeftHand`) | two-bone IK constraint on `LeftLowerArm` |
| `LeftElbowPole` `Node3D` | IK pole target empty |
| `SupportGrip` under the socket | hand IK target empty, parented to the weapon |

Controllers the user actually touches: **`WristTarget_L`, `WristTarget_R`,
`ElbowPole_L`, `ElbowPole_R`** — plus the weapon, which rides the right hand.

Keep it to that. The whole reason this rig exists is that posing 60 bones by
hand is what makes clip authoring feel impossible; the moment it needs more
than a handful of controllers, it has stopped being the tool it was built to be.

## glTF export settings (Godot 4.7)

Export **glTF 2.0 (`.glb`)**, not FBX — it avoids the ufbx quirks entirely,
including the [godot#90314](https://github.com/godotengine/godot/issues/90314)
empty-`Node3D` trap below.

- `+Y up` (Godot's convention)
- **animation sampled/baked**, not curve-exported — sampled keys are what
  Godot's importer reads reliably
- **deform bones only** — control empties and IK targets must NOT ship in the
  clip; they are authoring scaffolding, and exporting them adds tracks the
  skeleton has no bones for
- **no leaf bones**
- **no scale keys.** Differing limb proportions plus scale keys tears the mesh.
  `check_clip.py` treats any scale key as a hard failure.
- one clip per file, filename = clip name (matches the project's existing
  single-clip-file convention in `build_character.gd`)

## The ufbx 100× empty-scale trap

Open bug [godot#90314](https://github.com/godotengine/godot/issues/90314): empty
`Node3D`s import from FBX at **100× scale with wrong rotation**, and it bites
**weapon sockets specifically** — an empty is exactly what a socket is.

Two defences, use both:

- export **glTF, not FBX** (above), which sidesteps it
- never ship the control empties in the clip (deform-only export), so there is
  no empty to mis-scale in the first place

If a weapon socket ever arrives 100× out, this is the cause. Do not "fix" it
with a 0.01 scale factor at the call site.

## Validate before believing

`check_clip.py` runs headless and is the Blender-side twin of
`tools/rig/verify_pose.gd`:

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
    --background --python tools/blender/check_clip.py -- <clip.glb>
```

It asserts: bone names match the expected humanoid set (no `.001`, no leaf
bones, no unmapped bones, no `Root`), zero scale keys, expected frame count,
no hips drift on in-place clips, and — for a seeded clip — that **frame 0
matches the declared seed pose within tolerance**.

That last one is the load-bearing assert. Clips are seeded from the calibrated
aim pose (`docs/blender-env.md`) precisely so an authored fire or reload begins
where the aim pose ends. If frame 0 drifts, the cross-fade discontinuity that
caused the original rifle-fire bug comes straight back.

**A validator that has never failed has not been tested.** Run it against a
deliberately broken clip and watch it fail before trusting a pass.

## What stays the user's

Keyframing. All of it. Pose, timing, weight, follow-through.

Claude builds the rig, the seed, the export and the validator, and reads values
back — the same `godot-human-in-the-loop` split as the Godot-side rig work,
moved into Blender. Do not key a pose to "get it started".
