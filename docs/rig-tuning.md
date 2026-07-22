# Rig tuning — who adjusts what

The division of labour agreed with the user on 2026-07-21, after Claude burned
several rounds on adjust → screenshot → adjust for weapon placement.

**The user does the placing. Claude does the plumbing.**

Anything that needs "move it, look at it, move it again" is the user's job, in
the editor, with a gizmo. Claude's job is to make sure a control *exists* for
every part of the pose, to read the values back out, and to bake them into the
right generator so a rebuild cannot lose them. Since M3 the bake target is
split: **weapon values** (socket basis, mesh offset, grips, curls, stow
placement, stats) go into `tools/build_weapons.gd` →
`resources/weapons/*.tres`; everything else stays in
`tools/build_character.gd`. Rebuild order: `build_weapons.gd` first, then
`build_character.gd`.

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
| Where the **rifle stows on the back** | `GeneralSkeleton/BackSocket/BackStow` | Drag / rotate gizmo |
| Where the **revolver stows on the hip** | `GeneralSkeleton/HipSocket/HipStow` | Drag / rotate gizmo |

The hand controls (socket, grips, curls) are **per weapon** — the values live
on each weapon's resource and the WeaponManager re-applies them on every
equip. When calibrating a weapon, make sure ITS values are on the shared
nodes first (they are whatever the scene last shipped or the manager last
applied). Eye-icon visibility toggles during a calibration session are safe:
the WeaponManager re-asserts hand/stow visibility on every run.

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

Placed by the user in the editor on 2026-07-21, originally baked into
`tools/build_character.gd`, migrated unchanged to `tools/build_weapons.gd` →
`resources/weapons/revolver.tres` in M3. Recorded here so the intent
survives, not just the numbers.

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

## Posture correction — per clip family, never skeleton-wide (2026-07-23)

The Quaternius UAL clips carry a forward hunch in the source rig (head
pitched ~30° down, measured). The correction — spine −3°, chest −4°,
upper-chest −4° — is **baked into the `UAL_*` clips' rotation keys** by
`_apply_posture_bias()` in `tools/build_character.gd`.

It was first shipped as a runtime `PostureAdjust` modifier applied to every
clip, which broke the moment a *clean* clip entered the graph: `U_Idle`
(level head, upright spine) got the same +11° backward push and the
character stood facing the sky. Attribution was a post-modifier
`BoneAttachment3D` probe A/B in the running game: modifier on = head +10.8°,
off = −0.9°; the LookAt residuals measured under 1°.

`PostureAdjust` stays in the scene with **all pitches zeroed** as a
live-tuning override only. If a future clip family hunches, bake its own
correction at build time — do not turn the global sliders back on.

## Assault rifle — measured seeds, awaiting the calibration session (2026-07-23)

Everything on `resources/weapons/assault_rifle.tres` is a **seed**, not a
calibration: enough to put the rifle recognisably in the hands and on the
back so the gizmos start somewhere sane.

| Value | Seed | How it was derived |
|---|---|---|
| socket basis | revolver's measured basis | Overwrite Axis normalised the hand bone, so one pistol-grip orientation transfers to first order |
| `mesh_offset` | `(0.014, 0.083, 0.096)` | negated grip centroid (112 verts, y < −0.02, −0.12 < z < 0.02) + the revolver's hand-finish delta |
| `support_grip_pos` | `(0.064, 0.043, 0.376)` | under the handguard (underside y 0.019, centre z 0.28), wrist left of and below the surface |
| stow (BackStow) | pos `(-0.18, -0.30, -0.16)`, rot `(-50, 90, -90)` | grip at the lower back right, barrel up-left diagonal — measured barrel_dir (0.64, 0.77, 0) in the running scene |
| curls / wrist | all zero | rifle clips are genuinely two-handed; pure mocap until the user sees it |

The user's calibration session covers: rifle socket + grip + curls, and
back/hip stow placement. Bake results into `tools/build_weapons.gd` (with
reasons here), re-run it and `build_character.gd`, diff-check nothing
reverts.
