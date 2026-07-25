---
name: godot-animation-pipeline
description: Read BEFORE choosing or downloading animation clips, adding a clip source to build_character.gd, editing build_anim_tree.gd or AnimationTree blends, or diagnosing a wrong pose/gait in the running game. Covers the single-rig invariant (no blend space may mix source rigs) and how to verify a clip's rig, clip selection by measurement, build-time clip corrections (root collapse, per-family posture) and why authored clips get none, tree-level composition with filtered blends, and the mixer conflicts that look like broken animation.
---

# Sourcing, correcting and mixing animation clips in this project

Phase 2 built this pipeline through seven user-review rounds. Every rule here
replaced a round that failed the playtest.

## The single-rig invariant — read this first

> **No blend space and no held blend may mix clips from two source rigs.**
> A brief *transition* crossfade between two single-rig states is permitted.
> A resting state is not.

This is a hard invariant, not a preference. It was adopted after a measurement
round (2026-07-25) found the project's animation library fed by **four** source
rigs — MotusMan (MoCap Online), Mixamo X Bot, Quaternius UAL, all retargeted
onto Synty — and blend spaces mixing them freely.

**What it cost before it was a rule.** The rifle's `fire_clip` was `R_Fire`
(Mixamo) while the weapon socket was calibrated against `W2_Stand_Aim_Idle_v2`
(MotusMan). `FireShot` is a `OneShot` filtered on the whole `Spine` subtree —
both arms, both hands — so every trigger pull swapped the calibrated hand for a
different rig's. Measured delta at frame 0:

| Bone | `W2_Stand_Aim_Idle_v2` → `R_Fire` |
|---|---|
| `RightShoulder` | **48.9°** |
| `RightUpperArm` | **38.9°** |

Fixed clip, fixed offset → the rifle flew the same direction on every shot.
That was reported and chased as a recoil/physics bug for multiple sessions. It
was data.

**`build_anim_tree.gd` asserts this.** It holds a clip → rig provenance table
and fails the build if one blend space contains two rigs. Do not weaken the
assert to land a clip; drop the clip or author a replacement.

**The one accepted exception**, recorded so it is a decision and not a leak:
`HolsterBlend` crossfades the weapon composite (MotusMan) to `Unarmed`
(Quaternius). It is a transition, it is brief, and authoring a whole unarmed
locomotion set to close it is not currently worth it. Revisit at Gate D.

**Corollary — filtered composites do not launder a mixed blend space.** A
`Blend2` filter narrows *which bones* cross rigs; it does not make the blend
single-rig. `RifleCarry` filtered both clavicle subtrees onto a MotusMan idle
and left the spine on Mixamo gaits — the junction just moved to the clavicle,
where it read as a hunched chest and an arching back.

## Choose clips by measurement, never by name

`UAL_Pistol_Idle` is not a pistol idle — it is a two-handed READY pose with
the hand half a metre above the hips. Trusting the name cost a full playtest
round; a 30-second headless sweep would have rejected it instantly.

Before wiring any clip into the tree, measure the pose mid-clip and compare
against what the pose must be. Useful metrics (see
`scratchpad/sweep_carry_pose.gd` pattern):

- upper-arm tilt from straight-down (0 deg = hanging by the side)
- elbow angle (180 deg = straight arm)
- wrist height relative to Hips (negative = below hip line)
- wrist forward offset (character faces +Z after retarget)

Also sweep several timestamps across the clip — Mixamo idles sometimes hide
mid-loop fidgets that a single sample misses.

**A clip named for an action may not contain the action.** `R_Fire` is the
rifle "fire" clip. Measured across its full 0.267 s: `RightShoulder` moves
**1.3°** and `RightHand` **1.5°**. It is a near-static pose with no recoil in
it at all — so it contributed zero shot feel while also teleporting the arm
~49°. Worst of both. Add "does this clip actually move?" to the sweep:
max angular deviation from frame 0, per bone.

## A clip's filename is not its rig — verify, it takes one second

`assets/animations/pistol_extra/` is named `W1_*`, which is MoCap Online's
convention, and the code comments called it Mixamo. Both could not be right.
The files are **Mixamo clips renamed to MCO's convention**. The wrong belief
sat in a comment for days and made `PISTOL_AIM` look single-rig when it split
2 MotusMan / 3 Mixamo.

The check, on the raw FBX, before any import:

```bash
strings -a <file.fbx> | grep -c mixamorig      # >0 = Mixamo, 0 = not
strings -a <file.fbx> | grep -oE '^(Hips|Spine[0-9]*|LeftArm|pelvis|upperarm_l)$' | sort -u
```

Mixamo bones carry a literal `mixamorig:` prefix. MotusMan uses bare
`Hips`/`Spine1`/`LeftArm`. Quaternius/UE uses `pelvis`/`spine_01`/`upperarm_l`.
Record the answer where the clips live, not in a comment that can drift from
the bytes.

### Current provenance (2026-07-25)

| Directory | Rig | Clips |
|---|---|---|
| `animations/pistol` | MotusMan (MCO free demo) | 10 — incl. `W1_Stand_Fire_Single` |
| `animations/rifle_mco` | MotusMan (MCO free demo) | 5 |
| `animations/rifle` | Mixamo X Bot | 12 |
| `animations/pistol_extra` | Mixamo X Bot | 4 — **despite `W1_` names** |
| `animations/unarmed` | Mixamo X Bot | 3 |
| `animations/ual` | Quaternius UAL (UE mannequin) | 11 used of ~43 |
| `animations/authored` | **Synty-native, authored in Blender** | — |

**The MotusMan rifle path is 5 clips**: `W2_Stand_Aim_Idle_v2`,
`W2_Walk_Aim_F_Loop_IPC`, `W2_Jog_Aim_F_Loop_IPC`,
`W2_Stand_Relaxed_Idle_v2`, `W2_Stand_Aim_To_Relaxed`. There is **no** rifle
fire, reload, draw or holster on that rig. That gap is the Blender authoring
workload — see `blender-authoring`.

**Measuring technique:** one fresh scene instance per clip, then
`ap.play(clip)` → `ap.advance(t)` → `skel.force_update_all_bone_transforms()`.
Seeking one shared instance across clips does not re-evaluate reliably
(measured). `get_bone_global_pose()` is correct here because raw clips play
with no modifiers.

## Downloading from Mixamo

- **Always download With Skin.** A skinless FBX carries no true bind pose;
  poses far from rest import skewed (leaning, aiming skyward). This broke 17
  clips once.
- Skinned FBXs ship a junk `Take 001` — the build filters it, keep it that way.
- Single-clip files are keyed by filename, so the filename IS the clip name.

## Corrections are per clip family, baked at build time

Different sources carry different systematic defects. Each family's fix lives
in `tools/build_character.gd` keyed off the clip prefix, applied to the clip
keys at build time:

- `W2_*`: broken bind pose → measured position scale + hips Y offset.
- Root-keying clips poison later clips that leave Root unkeyed (the player
  holds the stale pose) → `_collapse_root_into_hips()` on every clip.
- `UAL_*`: source rig hunches forward (head ~30 deg down, measured) →
  `_apply_posture_bias()` premultiplies the spine-chain correction onto the
  keys.
- `UAL_*` locomotion: bob/stride/sway/head-sway amplitude compression
  (position deviation scaling, quaternion slerp-toward-mean).

**Never apply a family's correction as a skeleton-wide runtime modifier.**
The posture fix shipped first as a `PostureAdjust` modifier running on every
clip; the moment a clean clip (`U_Idle`, level head) entered the graph it got
the same +11 deg backward push and the character stood facing the sky.
Left-multiplying a constant quaternion onto keys commutes with blending, so
baked corrections mix correctly against unbaked clips — the correction fades
in exactly as the clip does.

Amplitude compression and constant-offset baking of sourced mocap is NOT the
forbidden pose synthesis: every input stays real mocap. Synthesis means
inventing a pose from nothing (palm sockets, finger-curl code, procedural IK
holds) — that is still banned.

**Authored clips get no correction, ever.** A clip keyed in Blender on the
Synty skeleton has no source rig, no BoneMap, no rest-pose delta and therefore
no residual to correct. `assets/animations/authored/` must never appear in
`configure_imports.gd` and must never match a correction predicate in
`build_character.gd`. `tools/rig/import_authored.gd` asserts both. Every
correction in this file exists to undo a retarget; applying one to a clip that
was never retargeted only introduces the defect it was written to remove.

**A correction whose clip family is gone is dead code — delete it.**
`STRAFE_HIPS_PITCH` existed solely to patch the Mixamo aim strafes' hips.
When the single-rig invariant dropped those strafes, leaving the constant
behind would have meant a tuned number with no referent, which the next
session has to reverse-engineer.

## Composing clips in the AnimationTree

The tree is GENERATED (`tools/build_anim_tree.gd`) so filter lists stay
reproducible — never hand-edit `player_anim_tree.tres`.

- A filtered `Blend2` composites two real clips: unfiltered tracks play
  input 0, filtered tracks blend toward input 1. This gives body-from-walk +
  gun-arm-from-idle (filter = RightShoulder subtree) and grip-fingers-over-
  open-hand (filter = RightHand subtree minus the wrist).
- Filter lists are MEASURED from the skeleton (`_subtree_paths`), never typed.
- Pinned blend amounts (e.g. the finger mix at 1.0) must be written by
  player.gd every frame — a Blend2's amount is a runtime parameter, not a
  resource default, and it starts at 0.

## Mixer conflicts that look like broken animation

- **Dual mixers:** an autoplaying `AnimationPlayer` plus an active
  `AnimationTree` both write the skeleton; last writer wins. On screen:
  clips look frozen while the body moves. Stop AND deactivate the player when
  the tree owns the skeleton (player.gd `_ready`).
- A pose that is wrong ONLY in game (correct in the raw clip) is a modifier
  or blend problem — attribute it with the live A/B method in
  `godot-rig-retargeting` (BoneAttachment3D probes + toggling modifiers)
  before touching any clip.
