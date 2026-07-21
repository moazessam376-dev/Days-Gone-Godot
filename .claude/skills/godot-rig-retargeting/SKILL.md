---
name: godot-rig-retargeting
description: Read BEFORE importing a character or animation FBX, editing a BoneMap, adding a SkeletonModifier3D (TwoBoneIK3D, LookAtModifier3D), or attaching a weapon to a bone. Covers the working retarget pipeline for Synty + MoCap Online rigs and the verification traps that produce confidently wrong conclusions. Use when importing the Rifle Pro pack, the zombie set, or any new character.
---

# Retargeting and skeleton modifiers in this project

The pipeline works and is proven (see `docs/rig-tuning.md`). This is how to
extend it without re-learning the traps.

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

## Verify the thing that actually runs

A headless check that loads `hunter.tscn` directly proves nothing about a game
that loads `test_character.tscn`. That exact mismatch let a broken scene pass
every automated check while the user saw a T-pose.

Reproduce the user's path: load the **main scene**, run it, and look.
