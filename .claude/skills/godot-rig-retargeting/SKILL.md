---
name: godot-rig-retargeting
description: Read BEFORE importing a character or animation FBX, editing a BoneMap, adding a SkeletonModifier3D (TwoBoneIK3D, LookAtModifier3D), attaching a weapon to a bone, or diagnosing a pose that is wrong in game but clean in the raw clip. Covers the working retarget pipeline for Synty + MoCap Online rigs, why a BoneMap holds no rest poses and what to measure instead, the probe A/B method for attributing a bad pose to its modifier, and the verification traps that produce confidently wrong conclusions. Use when importing a new pack or character, and to know when a clip needs no retarget at all.
---

# Retargeting and skeleton modifiers in this project

The pipeline works and is proven (see `docs/rig-tuning.md`). This is how to
extend it without re-learning the traps.

## When NOT to retarget at all

A clip **authored in Blender on the Synty skeleton** needs none of this page.
No BoneMap, no Rest Fixer, no `fix_silhouette`, no `overwrite_axis`, no
build-time correction — there is no second rig, so there is no residual to
normalise. Running an authored clip through `configure_imports.gd` *introduces*
the defects the rest of this document exists to undo.

Everything below applies to **sourced** clips only. See `blender-authoring`
for the authored path, and `tools/rig/import_authored.gd`, which asserts the
authored directory never acquires a BoneMap.

## The pipeline in one paragraph

Import BOTH the character and the animation FBXs with a `BoneMap` against
`SkeletonProfileHumanoid`. Godot then **renames each skeleton's bones to the
profile's names at import time**, so two structurally different rigs (Synty: 50
bones, `Shoulder_L`; MotusMan: 80 bones, `LeftArm`) both end up speaking
`LeftUpperArm` — and the clips simply play on the character. Nothing is
retargeted at runtime. `tools/rig/configure_imports.gd` wires this up;
`tools/rig/verify_retarget.gd` checks it.

## Import settings that matter

- **`retarget/rest_fixer/overwrite_axis = true`** — the single most important
  option. Unifies bone rest AXES across rigs. Without it, a weapon socket
  calibrated on one clip reads visibly twisted on the next, which is what forces
  people into per-clip correction tables.
- **`retarget/rest_fixer/fix_silhouette/enable = true`** — MotusMan is authored
  in an A-pose, Synty in a T-pose.
- **`retarget/bone_renamer/rename_bones = true`** and `unique_node/make_unique`
  — the latter renames the skeleton to `GeneralSkeleton` and marks it unique, so
  clip track paths (`%GeneralSkeleton:LeftUpperArm`) resolve.
- **DO NOT set `retarget/remove_tracks/*`.** Measured: they cut a clip from 57
  tracks / 24 animated to 20 / 2, stripping spine, neck, head, forearm and hand
  — i.e. the actual motion. The docs recommend them for shared AnimationLibraries;
  here they gut the clip.

## Rig-specific traps

**Synty (`resources/rigs/synty_apocalypse_bonemap.tres`)**
- `Shoulder_L` is the **upper arm**; `Clavicle_L` is the **shoulder**. Godot's
  auto-mapper guesses this backwards and produces twisted arms. Verified from the
  hierarchy: `Spine_03 -> Clavicle_L -> Shoulder_L -> Elbow_L -> Hand_L`.
- Only **three finger chains** (thumb, index, and one merged `Finger_0x` covering
  middle+ring+little). The merged chain maps to **Middle**.
- Fingers have **four joints**; the humanoid profile has three, so the 4th is
  never mapped and freezes in bind pose. `scripts/rig/finger_tip_modifier.gd`
  drives it from its parent.
- Right-side duplicated finger bones are suffixed **`_2`** under ufbx (NOT `" 1"`
  as community docs claim). This is import-specific — re-verify after any
  importer change.
- `Characters.fbx` packs 31 characters on one skeleton AND ships its **own
  `AnimationPlayer`** holding a junk `Take 001`. Remove it, or your player
  collides on name and is silently renamed `@AnimationPlayer@2`.

**MoCap Online (`resources/rigs/motusman_v55_bonemap.tres`)**
- MotusMan_v55, 80 bones, HumanIK/Biped naming — effectively Mixamo's convention
  without the prefix. That is why Mixamo is a viable fallback: swapping animation
  source costs one BoneMap, not a re-rig.
- Its `hand_r_wep` / `hand_l_wep` socket bones are **not usable as a calibration
  source.** They are unmapped, so they skip Overwrite Axis while `RightHand` gets
  it — a relative transform between them mixes a normalised parent with an
  unnormalised child. The position comes out roughly right and the rotation is
  garbage, which looks plausible from one camera angle.

**General rule:** any bone the BoneMap does not map is NOT axis-normalised. Do
not compute relative transforms between mapped and unmapped bones.

## A BoneMap holds no rest poses — do not try to diff them

A `BoneMap` `.tres` is a `SkeletonProfileHumanoid` plus ~55
`bone_map/<Slot> = &"<source bone name>"` string pairs. **That is all it is.**
There is no `Spine` rotation, no rest transform, no per-bone delta in the file.

This matters because "print the rest-pose rotation of Spine/Chest/UpperChest
from each BoneMap and show the deltas" is a natural-sounding request that has
no answer, and producing a table for it means inventing numbers — the exact
*confident measurement of the wrong thing* this project has shipped three times.

**What to measure instead.** The thing that reaches the screen is the pose
delta between clips *after* retarget, on the target skeleton. Read it off the
baked library:

```
mcp__godot-mcp__godot_animation_read  get_details    → track index for a bone
mcp__godot-mcp__godot_animation_read  get_keyframes  → quaternion keys
```

against `Hunter/AnimationPlayer` in the open scene, then
`angle = 2·acos(|q1·q2|)`. This is **read-only, needs no running game, and no
script file** — the editor already has the library loaded. It is the cheapest
honest measurement in the toolbox and it is how the 48.9° `RightShoulder`
delta behind the rifle-fire bug was found (see `godot-animation-pipeline`).

Caveat that keeps it honest: these are **local** bone rotations. A large local
delta on a chain is strong evidence, not proof of where the hand lands —
downstream bones can partially compensate. For where the hand actually ends up,
use the post-modifier `BoneAttachment3D` probe below.

## Weapons

`BoneAttachment3D` (bone = `RightHand`, **`override_pose = OFF`**) -> a child
`Node3D` socket carrying ONE calibrated `Transform3D` -> the weapon scene.

`override_pose` must stay off: the docs warn it interferes with the
`SkeletonModifier3D` system, which this project relies on.

Calibrate the socket **once per weapon**, never per clip or per stance. Useful
measurements: read the weapon's local axes off its mesh AABB, and get the grip
position from the centroid of the grip vertices rather than eyeballing.

## Skeleton modifiers

Children of `Skeleton3D` run **top to bottom**. Current order:

```
FingerTips          4th finger joint, both hands
RightHandAttach     weapon socket
LeftArmIK           TwoBoneIK3D, support hand onto the gun
LeftElbowPole       (target node, not a modifier)
SupportHandTuner    wrist + finger corrections — AFTER the IK
```

`LookAtModifier3D` (torso aim) must go **before** `LeftArmIK`, so the IK solves
against the already-rotated torso.

`TwoBoneIK3D` API is **indexed** — `set_root_bone_name(0, ...)` etc., with
`setting_count` controlling how many chains. A pole target is **mandatory**;
without one the elbow flips between valid solutions mid-animation.

Retargeting normalises names and axes but **cannot fix limb proportions** — the
support hand landed 19 cm from the grip on this rig. That gap is what IK is for.

## Verifying a modifier — read this before concluding one is broken

**`Skeleton3D.get_bone_global_pose()` returns the pose from BEFORE the modifier
stack runs.** A perfectly working modifier therefore reads as an exact no-op,
which is indistinguishable from a broken one.

This produced a confidently wrong conclusion that Godot's modifier callbacks
"don't dispatch on 4.7", a workaround built on that false premise, and a commit
that had to be corrected. Counting the signal showed it firing **1892 times**.

**Do instead:**
- Confirm a modifier is live by counting its `modification_processed` signal.
- Judge the RESULT on screen, via MCP `screenshot_game`.
- To sanity-check the maths in isolation, call the modifier's method by hand and
  compare before/after — that path does reflect writes.

## Attributing a wrong pose to its modifier — the probe A/B method

When the pose is wrong in game but the raw clip measures clean, find the
guilty modifier in minutes instead of guessing:

1. **`BoneAttachment3D` follows the POST-modifier pose** (it is how weapons
   attach — proven). Via `godot_exec`, attach probe nodes on the suspect
   bones in the running game and read pitch/direction off their global basis.
   This is the only cheap numeric read of what the player actually sees.
2. Toggle ONE modifier's `active` off per step (`godot_exec`), re-read the
   probes, and screenshot from the SAME camera. The numbers attribute the
   fault; the paired screenshots prove it visually.
3. Note: player.gd re-writes some modifier `influence`s every frame — toggle
   `active`, not `influence`, or your override is erased within a frame.

This method pinned an 11-degree head/chest pitch on `PostureAdjust` in two
toggles (LookAt residuals measured under 1 degree and were exonerated). Bone
numbers and screen can disagree — a level head BONE can still read chin-up on
the MESH — so always pair the probe numbers with a same-camera screenshot
before and after.

## Verify the thing that actually runs

A headless check that loads `hunter.tscn` directly proves nothing about a game
that loads `test_character.tscn`. That exact mismatch let a broken scene pass
every automated check while the user saw a T-pose.

Reproduce the user's path: load the **main scene**, run it, and look.
