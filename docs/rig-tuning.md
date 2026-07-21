# Rig tuning — who adjusts what

The division of labour agreed with the user on 2026-07-21, after Claude burned
several rounds on adjust → screenshot → adjust for weapon placement.

**The user does the placing. Claude does the plumbing.**

Anything that needs "move it, look at it, move it again" is the user's job, in
the editor, with a gizmo. Claude's job is to make sure a control *exists* for
every part of the pose, to read the values back out, and to bake them into
`tools/build_character.gd` so a rebuild cannot lose them.

Claude should not tune poses by screenshot. That loop is exactly what cost the
Three.js project 14 rounds, and it is slower and worse than the user doing it
by eye in a viewport.

## The controls

Open `scenes/characters/hunter.tscn`. Everything below is live — press **F5**
and adjust while it runs; no restart, no rebuild.

| To change | Select this node | How |
|---|---|---|
| Where the **weapon** sits in the right hand | `GeneralSkeleton/RightHandAttach/WeaponSocket` | Drag / rotate gizmo |
| Where the **support (left) hand** goes | `…/WeaponSocket/SupportGrip` | Drag gizmo |
| Which way the **left elbow** points | `GeneralSkeleton/LeftElbowPole` | Drag gizmo |
| **Left wrist** rotation | `GeneralSkeleton/SupportHandTuner` → `wrist_offset_deg` | Inspector |
| **Left finger** curl | `SupportHandTuner` → `thumb_curl` / `index_curl` / `middle_curl` | Inspector sliders |
| **Fingertip** curl, both hands | `GeneralSkeleton/FingerTips` → `follow` | Inspector |

`SupportGrip` and the weapon socket are parented **to the gun**, so a value set
once stays correct in every animation — walk, jog, crouch, fire. This is not
per-clip tuning.

The tuner ships all-zero, which is a deliberate no-op: with every slider at 0
the pose is pure mocap. Only author a correction where the mocap is actually
wrong on this rig.

### Camera, while you work

`scripts/dev/orbit_camera.gd` is on the test scene's camera:
left-drag orbit · right-drag pan · scroll zoom · **R** reset ·
**1** hands · **2** upper body · **3** full body.

## The rule that keeps this from breaking

**Never hand-edit a `.tscn` the editor has open.** Godot holds the scene in
memory and writes its copy on save, silently discarding external edits. This
already destroyed the left-arm IK once.

If Claude must edit scene text while the editor is running, it has to call
`godot_scene reload` immediately afterwards so the editor re-reads from disk.
Otherwise: close the editor, edit, reopen.

Same hazard applies to `project.godot`.

## Verifying a skeleton modifier

**Do not use `get_bone_global_pose()`.** It returns the pose from *before* the
modifier stack runs, so a perfectly working modifier reads as an exact no-op —
indistinguishable from a broken one. This cost an hour and produced a wrong
conclusion that had to be corrected in a later commit.

Check a modifier is live by counting its `modification_processed` signal, and
judge the result **on screen**.

## Modifier order

Children of `Skeleton3D` run top to bottom. Current order, which matters:

```
SM_Chr_Hunter_Male_01   (mesh)
FingerTips              fourth finger joint, both hands
RightHandAttach         weapon socket
LeftArmIK               support hand onto the gun
LeftElbowPole           (target node, not a modifier)
SupportHandTuner        wrist + finger corrections — must run AFTER the IK
```

Phase 2 adds `LookAtModifier3D` (torso aim) and it must sit **before**
`LeftArmIK`, so the IK solves against the already-rotated torso.

## Current authored values (pistol / revolver, aim idle)

Placed by the user in the editor on 2026-07-21 and baked into
`tools/build_character.gd`. Recorded here so the intent survives, not just the
numbers.

| Control | Value | What it was correcting |
|---|---|---|
| `WeaponSocket` | basis measured, origin 0 | Aligns the gun level and forward in the aim pose |
| `Revolver` position | `(0.0125, 0.0954, 0.0964)` | Seats the grip in the fist — the model's origin is mid-body |
| `SupportGrip` position | `(0.1203, 0.0039, 0.0256)` | Where the left palm meets the gun |
| `LeftElbowPole` position | `(0.9155, 1.0, 0.15)` | Pushes the left elbow out so the arm reads naturally |
| `wrist_offset_deg` | `(2.82, -3.78, 0.09)` | A few degrees of roll onto the grip |
| `thumb_curl` | `+57.5` | Mocap barely wrapped the thumb on this hand |
| `index_curl` | `-90.0` | Mocap fully curled it; the revolver's trigger guard needs it open |
| `middle_curl` | `-20.0` | Slightly relaxed |

The curls are large because they are corrections against a MotusMan hand
posed for a 1911, transferred to a three-fingered Synty hand holding a
revolver. That is the residual retargeting cannot fix, and it is exactly what
this layer exists for.
