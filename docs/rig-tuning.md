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
| **Left wrist** rotation | `…/WeaponSocket/SupportGrip/WristTarget` | **Rotate gizmo (E)** |
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

### The wrist is a gizmo now, not a number field (2026-07-25)

`wrist_offset_deg` was a `Vector3` Inspector field, so rolling the palm onto a
grip meant type-three-numbers → look → type again: the
adjust-screenshot-adjust loop this whole document exists to prevent, rebuilt
inside the tool meant to prevent it.

**Rotate `SupportGrip/WristTarget` with the E gizmo instead.**
`SupportHandTuner` reads that node's rotation and mirrors the Euler back into
`wrist_offset_deg`, so the number is still there to read off and hand over for
baking — it is a **read-back**, not an input. The WeaponManager writes the
per-weapon value to the node (writing the Euler instead would be overwritten
within a frame).

Verified before handover, in the **main** scene, through a post-modifier
`BoneAttachment3D` probe on `LeftHand` — all six directions:

| drive | measured |
|---|---|
| X ±20° | 20.00° about (±1, 0, 0) |
| Y ±20° | 20.00° about (0, ±1, 0) |
| Z ±20° | 20.00° about (0, 0, ±1) |

Exact axis, exact sign, exact magnitude. **Freeze the animation before any such
A/B** — the character autoplays a looping aim idle, and measuring across frames
without pausing read a 20° drive as **103°**, i.e. clip motion plus the gizmo.

**Finger curl stays sliders**, and that is a real limitation rather than an
oversight: Godot 4 has no in-viewport bone gizmo (godot-proposals#887, #2891),
so per-joint posing cannot happen in the editor at all. It moves to Blender
once authoring lands; see `docs/blender-env.md`.

### The rifle calibration session — two tools, two venues

**Palm / left hand (live, in the running game):**
1. Press **F5**. Press **2** to bring the rifle out; hold **RMB** to pose
   ADS, or release it for the carry cradle.
2. In the editor's Scene dock, click the **Remote** tab (appears while the
   game runs).
3. Select `Player/WeaponManager` and tick **`calibration_freeze`** in the
   Inspector — without this, every value below is rewritten each frame and
   dragging appears to do nothing.
4. Now adjust live, in the Inspector:
   - `Player/Hunter/GeneralSkeleton/SupportHandTuner` →
     `wrist_offset_deg`, `thumb_curl` / `index_curl` / `middle_curl`
     (palm rotation + finger wrap; this is the tool the pistol was
     finished with)
   - `Player/Hunter/GeneralSkeleton/RightHandAttach/WeaponSocket/SupportGrip`
     → `position` (where the palm sits on the gun; note whether you were
     in ADS or carry — they are separate baked points)
5. Screenshot or note the final numbers and hand them to Claude to bake
   into `tools/build_weapons.gd`. Values changed in the Remote tree are
   gone when the game closes — the bake is what makes them permanent.

**Stow placement (gizmo, in the editor, game closed):**
1. Open `scenes/characters/hunter.tscn`.
2. In the Scene dock select `GeneralSkeleton/BackSocket/BackStow` (rifle)
   or `GeneralSkeleton/HipSocket/HipStow` (revolver).
3. Drag with the move gizmo (**W**) and rotate with **E** until it sits
   right against the body. The stowed mesh is parented under the node, so
   it follows the gizmo.
4. **Ctrl/Cmd+S**, then tell Claude — the values get read out of the scene
   and baked into `tools/build_weapons.gd` (a rebuild would otherwise
   revert them, and the WeaponManager re-asserts the .tres values on every
   run).

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

### …but count it with a reference type, not an int (2026-07-25)

**GDScript lambdas capture locals BY VALUE.** So the obvious counter

```gdscript
var fired := 0
tuner.modification_processed.connect(func() -> void: fired += 1)   # always 0
```

increments a copy and reads **0** — which is exactly what a dead modifier looks
like. Measured side by side on the same run of a modifier that was demonstrably
working: `int-capture=0`, `array-capture=25`.

Use a reference type:

```gdscript
var fired: Array[int] = [0]
tuner.modification_processed.connect(func() -> void: fired[0] += 1)
```

This is the prescribed technique for *avoiding* a confidently wrong conclusion,
so the naive version fails in the most expensive possible place.

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

## Recoil must not double-count the player's compensation (2026-07-24)

The M4 firing playtest showed the camera sinking into the dirt over a rifle
burst and then, over-corrected, ending up in the sky. It was **not** the kick
size — with hands off the mouse, 26 shots move the pitch **+0.07°**, i.e.
nothing.

The bug was in the recovery. `camera_rig.gd` banked every kick as
`_recoil_debt` and drained it back to the baseline. But a player holding the
reticle on target pulls the mouse **down by the kick they just took** — and
the rig then handed that same correction back a second time. Measured against
the real script:

| player behaviour | pitch after 26 shots (before / after) |
|---|---|
| hands off the mouse | +0.07° / +0.07° |
| pulls down 1× kick (holding the reticle on target) | **−9.03°** / −0.00° |
| pulls down 2× kick | −9.10° / −9.10° (their own pull, nothing added) |

Fix: mouse-look pitch goes through `_add_pitch()`, and a **downward** input
pays off the outstanding debt instead of stacking with it. `add_recoil()` also
banks only what the pitch clamp actually let through — firing at the ceiling
used to bank debt that never moved the camera, then drag it down on drain.

Regression: `tools/verify_fire_reload.gd` → "recoil: compensated burst leaves
aim where the player put it". It reads **−14.00°** (10 × the revolver's 1.4°
kick — the whole recoil total) if the payoff is removed.

**The recoil kick size is still untuned.** +0.07° over a mag is invisible;
`recoil_pitch_deg` per weapon is the knob, and it wants a playtest now that
the model underneath it is honest.

## The support-hand IK reaches — a wrong grip is placement, not plumbing

Measured in the running main scene through a `BoneAttachment3D` on `LeftHand`
(post-modifier; `get_bone_global_pose()` would read a working IK as a no-op):
the palm lands **0.0 cm** from `SupportGrip` in both carry and ADS. So when the
rifle grip looks wrong, the target is in the wrong place — a gizmo job, per
"the user places, Claude plumbs" — and not a solver that is failing to reach.

Useful frame for that session: in socket space **+z runs along the barrel**,
the rifle spans **z −0.21 … +0.82 m** and **y −0.10 … +0.23 m**, the muzzle is
at z 0.696, and the current ADS grip point is `(0.06, 0.075, 0.33)`.

Regression: `tools/verify_weapon_switching.gd` → "support hand IK reaches the
grip target".
