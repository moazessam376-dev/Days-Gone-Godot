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

## Assault rifle — calibrated by measurement + screenshots (2026-07-23)

Calibrated in a measured screenshot loop (`tools/rig/visual_shots.tscn` —
runs the real game windowed, injects input, captures every weapon state;
the MCP-free window into what the player sees). The user's playtest still
gates the feel; every value below has a live gizmo/slider for finishing.

| Value | Final | Why |
|---|---|---|
| socket basis | revolver basis × Rx(+19.8°) | the revolver basis raw held the rifle muzzle +19.8° skyward in ADS (probed in the running game); the rotation levels ADS at 0.0° measured, carry rakes −42° (fine for a low carry) |
| `mesh_offset` | `(0.014, 0.083, 0.096)` | negated grip centroid (112 verts) + the revolver's hand-finish delta |
| `support_grip_pos` (ADS) | `(0.06, 0.075, 0.33)` | rear third of the handguard, raised onto the underside ("the left palm is on the air"); a far-forward target straightened the elbow ("left arm is getting a bit extended") |
| `carry_support_grip_pos` | `(0.06, 0.06, 0.22)` | just ahead of the mag well — the handguard point over-reached the arm in the low carry ("normalize the space between two hands on relaxed"). player.gd lerps SupportGrip between the two points with the stance blend |
| curls | thumb 25 / index 30 / middle 35 | mocap held MotusMan's foregrip — fingers read flat on the Synty AK; coarse wrap, user fine-finishes |
| stow (BackStow) | pos `(-0.18, -0.30, -0.16)`, rot `(-50, 90, -90)` | grip lower back right, barrel up-left diagonal, hugging the back |

Revolver hip stow: pos `(-0.26, 0.03, -0.09)`, rot `(72, 0, 8)` — first
seed sat inside the thigh ("visibly going on the leg"); moved outboard, up,
and tilted back until the front view cleared the leg.

## Rifle animation fixes — measured, baked at build time (2026-07-23)

Both were diagnosed by the clip sweep (`godot-animation-pipeline` skill):

- **`R_Carry_Jog_F` is not a carry** — it jogs with the rifle raised to a
  high ready (left wrist +0.50 m above hips, upper arm 73°; user: "the
  weapon is aimed on jogging"). Fix is the SAME composite as the pistol
  carry: `RifleCarry` = Blend2, body/legs from the gait space, BOTH clavicle
  subtrees held on `W2_Stand_Relaxed_Idle_v2` (`rifle_carry_arm_lock`,
  default 1.0). The support-hand IK now stays ON during rifle carry (it is
  two-handed), welding the left palm to the handguard at every gait — the
  pistol keeps IK aim-only.
- **`R_Aim_Walk_B` is not an aim** — it backpedals in a low carry (left
  wrist +0.12 m, arm 20°; user: "the rifle is not on ADS" walking
  backwards), and the Mixamo aim strafes aim with a different wrist
  convention than the MotusMan pose the socket is calibrated against (gun
  off-axis; "not aiming straightforward"). Fix: `RifleAim` is a Blend2 with
  the UPPER-BODY filter — legs blend by direction in `RifleAimLegs`, the
  whole upper body holds `W2_Stand_Aim_Idle_v2` (the clip the socket is
  calibrated on), LookAt + IK on top. The strafes' remaining defect — hips
  pitched back ~21° vs the aim idle, leaking a constant +8.4° muzzle-up
  through the unfiltered hips — is baked down by `STRAFE_HIPS_PITCH` (+14°
  hips bias, upper legs counter-rotated by the exact conjugate so foot
  plants are untouched; residual ~3.5°, hidden by LookAt in motion).
- **`W2_Stand_Relaxed_Idle_v2` leans +5.2° vs the approved U_Idle −4.4°**
  ("leaning forward weirdly with the rifle") → `W2_POSTURE` bakes −14°
  across the spine chain (lands −2.9°; the lean responds at ~0.59× the
  baked total). The W2 **aim** clips are deliberately NOT corrected:
  leveling the aim spine rotates the gun up with it — a −16.5° bias read as
  the rifle aiming 35° skyward, screenshot-verified, and the aim stance's
  own forward lean reads as intent, not defect.
