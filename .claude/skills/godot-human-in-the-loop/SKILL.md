---
name: godot-human-in-the-loop
description: Read BEFORE any task whose success is judged by eye — weapon placement, grip, hand or finger position, elbow direction, wrist rotation, stance, camera framing, ground contact, weapon-on-back placement, recoil feel, or "does this look right". Also read before telling the user to adjust something, before baking hand-tuned values back into a generator, and whenever tempted to nudge a transform and take a screenshot. Defines the mandatory handoff format, the read-back-and-bake loop, and which decisions are never Claude's.
---

# The handoff protocol — the user places, Claude plumbs

This rule already existed in `CLAUDE.md` and `docs/rig-tuning.md` as prose,
with no trigger. It **silently degraded**: `support_hand_tuner.gd` shipped
`wrist_offset_deg` as a `Vector3` field and three float sliders, which put the
user back to typing numbers and squinting — the exact loop those documents were
written to prevent. Prose without a trigger decays. This skill is the trigger.

## Why this exists

The predecessor project (`~/Projects/Days-Gone-Clone`, Three.js) spent **14
numbered fix rounds** on how the player holds a gun. Every round was
adjust → screenshot → adjust. Every round failed the playtest. The loop is not
slow because Claude is bad at it; it is slow because judging a pose needs eyes
on a live viewport with a gizmo in hand, and a screenshot is a still frame from
one angle with no depth cue.

The user is faster at this than any screenshot loop, wants to do it, and has
said so. **Handing work over is the fast path, not the fallback.**

## The trigger

Stop and hand over the moment a task's success criterion is *visual*:

- weapon placement in the hand, grip, mesh offset
- support-hand position, finger curl, wrist rotation
- elbow direction / pole placement
- stance, posture, lean, ground contact
- weapon stow placement on back or hip
- camera framing, shoulder offset, FOV feel
- recoil, kick, impact feel
- any sentence that ends "…does that look right?"

Also stop if you catch yourself about to: sweep a value across screenshots,
pick a number because it "looks closer", or write "adjusted X to Y, should be
better now" without eyes on it.

## Claude's four jobs

Everything around the placing, and nothing in it.

1. **Make sure a control exists** for every part of the pose. If the user asks
   "how do I adjust X" and there is no control, that is a Claude bug, not a
   user question.
2. **Verify the control works** — right axis, right direction, right magnitude
   — *before* handing it over. This is plumbing, not tuning, and it is
   mandatory. Handing over a control that moves the wrong axis wastes a
   session and reads as the user's mistake.
3. **Read the values back out** after the user saves, and **bake them into the
   generator** with their reason.
4. **Never let a rebuild silently revert hand-tuned work.** A value that lives
   only in a `.tscn` is a value that a generator run will delete.

## Prefer a gizmo to a number field

**Every rotational and positional control must be a draggable `Node3D`**, not
an `@export var Vector3`. A gizmo gives direct manipulation, live feedback and
depth; a Euler triple in the Inspector gives none of those and silently invites
the screenshot loop back.

Pattern: a target node the modifier *reads* — e.g. a `WristTarget` parented
under `SupportGrip` whose `quaternion` the tuner consumes. Keep the numeric
`@export` as a **read-back display** so the value can still be baked, but the
gizmo is the interface.

**The honest exception: bone-level posing cannot happen in Godot.** Godot 4 has
no in-viewport bone rotation gizmo (open proposals godot-proposals#887 and
#2891). So per-joint work — finger curl especially — has no gizmo to offer. It
stays a slider *only* until Blender authoring can carry it, at which point that
posing moves to Blender entirely. Say this out loud when handing over a slider;
do not present it as the intended interface.

## The handoff format — all five fields, every time

An incomplete handoff is a guessing game with extra steps. Never send fewer
than these:

1. **Which node to select** — full path from the scene root, and say whether
   it is the **Scene** dock or the **Remote** dock (Remote only exists while
   the game runs)
2. **What to do to it** — drag with move gizmo (**W**) / rotate gizmo (**E**) /
   type in this Inspector field
3. **What "correct" looks like** — in words the eye can check, not numbers.
   "the palm wraps the handguard with the thumb over the top" beats
   "position ≈ (0.06, 0.075, 0.33)"
4. **How they know they are done** — the specific thing to look for, and from
   which camera angle
5. **What to do after saving** — Ctrl/Cmd+S, then tell Claude, so the values
   get read out and baked

Plus any **preconditions** the control needs to respond at all. For live
tuning that means `WeaponManager.calibration_freeze` — without it every value
is rewritten each frame and dragging appears to do nothing. Omitting a
precondition makes a working control look broken.

### Worked example

> **Select** `Player/Hunter/GeneralSkeleton/RightHandAttach/WeaponSocket/SupportGrip`
> in the **Remote** dock (press F5 first; tick
> `Player/WeaponManager → calibration_freeze` before touching anything, or
> your drags get overwritten every frame).
>
> **Drag** it with the move gizmo (**W**).
>
> **Correct** looks like: the left palm sits on the underside of the handguard,
> fingers wrapping up around it, the wrist not bent back, and the two hands a
> natural shoulder-width apart — not stretched, not crossed.
>
> **You're done** when it reads right from the over-the-shoulder camera *and*
> from a front orbit (press **1** for the hands view). A grip that looks right
> from one angle only is the classic false positive.
>
> **After:** note the numbers, tell me, and I bake them into
> `tools/build_weapons.gd` — Remote-tree values are gone when the game closes.

## Camera, while the user works

`scripts/dev/orbit_camera.gd` is on the test scene camera:
left-drag orbit · right-drag pan · scroll zoom · **R** reset ·
**1** hands · **2** upper body · **3** full body.

Offer the relevant preset in the handoff.

## The bake-back loop

After the user saves:

1. Read the values **out of the `.tscn`** (or out of the running Remote tree
   values they report) — do not re-derive them
2. Bake into the right generator. Since M3 the target is split: **weapon**
   values (socket basis, mesh offset, grips, curls, stow) →
   `tools/build_weapons.gd` → `resources/weapons/*.tres`; everything else →
   `tools/build_character.gd`. Rebuild order: weapons first, then character.
3. Record in `docs/rig-tuning.md` **with the reason**, not just the number.
   "why" survives; a bare number gets reverse-engineered next session.
4. Never hand-edit a `.tscn` the editor has open — Godot holds it in memory and
   overwrites on save. Call `godot_scene reload` immediately, or close the
   editor first. See `godot-scene-safety`.

## What Claude may still decide alone

Handing over visual judgement does not mean handing over everything. Claude
still owns: which clip to use (by measurement), graph structure, filter lists,
whether a control is wired to the right axis, and every number that is
*measured* rather than *judged* — a grip centroid, a bone delta, a muzzle
offset read off the mesh.

**Measured numbers over eyeballing** still holds. Read the delta and set it
once; that is not the banned loop. The banned loop is *sweeping* values and
picking by appearance.

## When stuck, ask — and make asking cheap

If something needs eyes or hands, stop and ask. Give the five fields. The user
has said explicitly they are happy to do manual work and that it is faster than
a screenshot loop. An honest "this needs your eyes, here is exactly what to do"
is a better deliverable than a confident guess.

What they do not want is Claude guessing numbers.
