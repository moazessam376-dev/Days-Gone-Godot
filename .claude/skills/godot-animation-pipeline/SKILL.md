---
name: godot-animation-pipeline
description: Read BEFORE choosing or downloading animation clips, adding a clip source to build_character.gd, editing build_anim_tree.gd or AnimationTree blends, or diagnosing a wrong pose/gait in the running game. Covers clip selection by measurement, build-time clip corrections (root collapse, per-family posture), tree-level composition with filtered blends, and the mixer conflicts that look like broken animation.
---

# Sourcing, correcting and mixing animation clips in this project

Phase 2 built this pipeline through seven user-review rounds. Every rule here
replaced a round that failed the playtest.

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
