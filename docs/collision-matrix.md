# Collision Matrix (Godot / Jolt)

The single source of truth for these decisions in code is
`scripts/physics/physics_layers.gd` (created when Phase 5 opens) — a
`class_name PhysicsLayers` file of named layer bits and composite query masks.
Every physics **query** in code (raycast, shape cast, run-over sweep) uses a
constant from that file; **never** write a mask literal at a call site. Scene
files carry `collision_layer` / `collision_mask` as raw integers in the
inspector — this document is the review checklist those values are checked
against.

> **Status (2026-07-22):** Phase 5 prep, written before Phase 5 opens
> (design-before-code). No scene or `project.godot` changes land with this
> doc. The values already in `scenes/player/player.tscn` (player layer,
> static-only masks) comply. First Phase 5 actions: add
> `layer_8="hitbox"` to `project.godot`, create `physics_layers.gd`, run the
> verification scenarios below.

This doc was ported from the Three.js/Rapier original (still in
`~/Projects/Days-Gone-Clone`). The *decisions* — who blocks whom, and why —
carry over unchanged. The *mechanisms* do not, because the filtering model is
different, and several Rapier-era hacks are Godot's default behavior.

## How Godot filtering differs from the Rapier original

Rapier's test was **two-way**: A and B interact iff
`(A.memberships & B.filter) && (B.memberships & A.filter)`. Godot's test is
**one-way, per object** — from the `CollisionObject3D` class reference:

> "Object A can detect a contact with object B only if object B is in any of
> the layers that object A scans."

Three consequences shape everything below:

1. **Queries never consult the target's mask.** A raycast or shape cast
   carries its own mask and hits anything whose *layer* matches. The Rapier
   trip-wires of the form "the enemy filter must keep PROJECTILE or hitscan
   stops seeing enemies" are gone — targets only need to *be on* a layer.
2. **Asymmetric masks are a feature, not dirt.** If A scans B but B does not
   scan A, only A responds. Several rows below use this deliberately. Do not
   "clean up" a mask to mirror its partner — the docs' mask==layer rule of
   thumb does **not** apply to this project.
3. **`CharacterBody3D.move_and_slide()` imparts no impulse to rigid bodies.**
   Bodies in its mask are walls; pushing a `RigidBody3D` requires explicit
   code. The old project's "flying car" guard
   (`applyImpulsesToDynamicBodies=false` plus a hand-split body-filter/
   query-filter) is simply how Godot behaves. The guard here is to **never
   write** that push code.

The official *Using Jolt Physics* page documents no deviation from these
layer/mask semantics. One Jolt behavior is unproven for us — whether an
**asymmetric pair of two dynamic bodies** resolves one-way as documented —
and scenario 1 below settles it before anything depends on it.

## Layers

Layers say where a thing **is**. Only queries and scanners need masks.
Names for layers 1–7 are already in `project.godot`.

| layer | # | bit | who |
|---|---|---|---|
| static | 1 | 1 | terrain, buildings, trees, props, wrecks, breakable boards |
| player | 2 | 2 | the player's `CharacterBody3D` capsule |
| enemy | 3 | 4 | zombie `CharacterBody3D` movement capsules (Phase 7) |
| ragdoll | 4 | 8 | corpse rigid bodies (Phase 9) |
| vehicle | 5 | 16 | car + bike chassis, `RigidBody3D`/`VehicleBody3D` (Phase 8) |
| projectile | 6 | 32 | thrown grenade/molotov bodies — hitscan is a query and needs no layer |
| camera | 7 | 64 | **vestigial — nothing lives here.** Rapier queries needed a membership bit; Godot queries don't. Keep it named, keep it empty. |
| hitbox | 8 | 128 | bone-attached hit zones on characters (decided 2026-07-22) |

**Why `hitbox` is separate from `enemy`:** movement and being-shot are
different systems. Capsules block movement; bullets read bone-attached hitbox
shapes (head/body, later limbs). The old project overlaid both on ENEMY and
would have had to unpick them for headshots. Zombies carry at least one
whole-body hitbox shape on layer 8 **from their first Phase 7 build**, so
hitscan never needs the `enemy` layer even temporarily.

## Per-node settings

| node | layer | mask |
|---|---|---|
| world geometry (`StaticBody3D`) | static | — (static bodies scan nothing) |
| player (`CharacterBody3D`) | player | static \| enemy \| vehicle |
| zombie (`CharacterBody3D`) | enemy | static \| player \| enemy \| vehicle |
| corpse (`RigidBody3D`) | ragdoll | static \| ragdoll \| vehicle |
| vehicle chassis | vehicle | static \| vehicle |
| grenade / molotov (`RigidBody3D`) | projectile | static \| vehicle |
| character hitboxes | hitbox | — (passive; only queries hit them) |

| query | mask |
|---|---|
| hitscan ray (`MASK_HITSCAN`) | static \| hitbox \| vehicle |
| camera `SpringArm3D` | static |
| vehicle run-over sweep (`ShapeCast3D`, Phase 8) | enemy |
| wheel/suspension casts | static \| vehicle — `VehicleBody3D` wheel casts filter by the **chassis mask**, which is why enemy/ragdoll must stay out of it (scenario 4 verifies before Phase 8 relies on it) |

## Pair table

| pair | behavior | mechanism / rationale |
|---|---|---|
| player ↔ static | wall | `move_and_slide()` slide; already live in `player.tscn` |
| player ↔ enemy | wall | both scan each other so neither walks through; two character bodies never exchange impulses |
| player ↔ vehicle | **wall, zero impulse** | player scans vehicle; **vehicle does not scan player**. The chassis is a wall to `move_and_slide()`, which imparts no impulse — the Rapier body-filter/query-filter split is native behavior here. Never add push code to the player. |
| player ↔ corpse | pass through | neither scans the other; corpses would trip the player constantly |
| player ↔ throwable | pass through | never collide with your own grenade |
| enemy ↔ static | wall | real physics replaces the old `enemyBlockAt` steering field. The navmesh does routing; the mask is the hard guarantee. |
| enemy ↔ enemy | wall (baseline) | natural spacing in hordes. This is a Phase 7 **perf lever**: if horde counts chug the M1, drop `enemy` from the zombie mask and use `NavigationAgent3D` avoidance instead. |
| enemy ↔ vehicle | **one-way wall** | zombie scans vehicle → parked cars block zombies natively (replaces `vehicleBlockAt`); **vehicle never scans enemy** → a kinematic capsule can never stonewall the chassis. Run-over kills are a `ShapeCast3D` on the vehicle (a query — no solver pair), speed-thresholded in Phase 8. |
| enemy ↔ corpse / throwable | ignore | — |
| corpse ↔ static / corpse | collide | bodies rest on ground, stack |
| corpse ↔ vehicle | **knock-aside, one-way** | corpse scans vehicle (gets shoved); vehicle doesn't scan ragdoll (the car is never deflected, and suspension never rides a corpse). Corpse `linear_velocity` clamped each tick (Phase 9) so a solver kick can't moon-launch one. Subject to scenario 1. |
| vehicle ↔ static / vehicle | collide | normal driving |
| throwable ↔ static / vehicle | bounce, one-way vs vehicle | grenades roll off cars; a car is never nudged by a grenade. They sail past bodies — AoE handles damage. Subject to scenario 1. |
| hitscan → static, hitbox, vehicle | hit | query mask only; target masks are irrelevant in Godot. Bullets spark on cars, hit characters through their hitboxes, and ignore corpses (Phase 9 may add `ragdoll` to the ray for impact feedback). |
| camera → static only | push-in | `SpringArm3D.collision_mask = static`, already live in `player.tscn`. Bodies would make the camera pop constantly. |

## Trip wires (do not break)

- **Vehicle mask stays `static | vehicle`.** Adding `player` re-creates
  nothing useful; adding `enemy` lets capsules stonewall the chassis; adding
  `ragdoll` puts the suspension on corpses.
- **No push code in the player.** The capsule must never apply impulses to
  rigid bodies — the flying-car bug is impossible only while this holds.
- **`SpringArm3D` mask stays `static` only.**
- **Asymmetric masks are intentional.** Don't mirror them "for tidiness";
  one-way response is the mechanism (see the class-reference quote above).
- **Query masks come from `PhysicsLayers` constants**, never literals.
- **Never renumber or reorder layers.** `.tscn` files store raw integers;
  renaming `layer_N` entries in `project.godot` does not update scenes.
  Append only.

## Verification scenarios (the Phase 5 gate)

The old repo backed this matrix with `scripts/physics-tests.mts`. The Godot
equivalent is a set of MCP-driven scenes — freeze the clock, step, read state
as JSON — run when Phase 5 opens and after any matrix change. Per
`CLAUDE.md`: load the scene the game actually loads, not a lookalike.

1. **Asymmetric dynamic pair under Jolt** — drop a grenade-mass body
   (scans vehicle) onto a car-mass body (does not scan projectile): grenade
   bounces, car velocity stays ~0. This is the one place Godot's documented
   one-way rule is unproven for two *dynamic* bodies under Jolt. If Jolt
   resolves the pair symmetrically, record it here and switch the
   corpse↔vehicle and throwable↔vehicle rows to symmetric masks — mass
   ratios already do the real work there.
2. **Player cannot shove the car** — walk the capsule into a parked chassis
   for 60 frames: car velocity ~0, player walled.
3. **Zombie vs car, both directions** — zombie blocked by a parked car; a
   driving car's velocity unchanged while overlapping a zombie capsule.
4. **Suspension never rides bodies** — park the car over a corpse and a
   zombie: no chassis catapult; confirms wheel casts filter by chassis mask.
5. **Hitscan discipline** — one ray with `MASK_HITSCAN` through a lineup of
   zombie capsule + hitbox + corpse + car: hits hitbox and car, never the
   movement capsule or the corpse.
6. **Camera ignores bodies** — spring arm does not shorten when a zombie
   stands between camera and player; does shorten against a wall.

## Adding a layer

1. Add the bit to `PhysicsLayers` in `scripts/physics/physics_layers.gd` and
   the name under `[layer_names]` in `project.godot` (append — never
   renumber).
2. Decide its row against every existing layer; update the per-node and
   query tables.
3. Update the pair table here with rationale.
4. Add an MCP verification scenario covering the new interaction's failure
   mode.
