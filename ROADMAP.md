# Roadmap — Days Gone (Godot)

The agreed phase plan for the Godot rebuild, decided with the user on 2026-07-21.
**Each phase gets its own planning session with the user before any code**, and every phase ends
with the game runnable, verified, and actually played. Sessions: read this file plus `CLAUDE.md`
and the relevant `docs/` spec before starting work. The current phase is marked below.

**Guiding principle (user's words): "I want to create a good game, not slop."**
Design decisions are made explicitly with the user BEFORE implementation. Details matter more than
feature count.

**The project's operating rule: source real assets; do not synthesize content.**
See the top of `CLAUDE.md` for why — it is the reason this migration exists.

## Where this came from

The Three.js original (`~/Projects/Days-Gone-Clone`, still live and untouched) completed R0 and R1
and most of R2, then stalled for three days across **14 fix rounds** on one problem: how the player
holds a pistol or long gun. Root cause, confirmed on disk: POLYGON Apocalypse ships **1816 models
and zero animations**, so no correct gun pose existed to play, and the response was to synthesize
one procedurally. Godot supplies the engine half of the fix (`BoneAttachment3D`, `TwoBoneIK3D`,
import-time retargeting, `AnimationTree` bone filters, `LookAtModifier3D`); **real purchased
animations supply the other half.** Neither alone is sufficient.

The original roadmap's phases are kept, **reordered to start at R2** (assets/character/weapons),
because that is where the project is actually blocked.

## Phases

### Phase 0 — Foundation & workflow  ◀ CURRENT
Environment, repo, tooling, docs. No gameplay.
- Godot moved to `/Applications` and de-quarantined (it was running under AppTranslocation, which
  breaks all automation); headless CLI verified working.
- Git repo + **Git LFS** for binary assets; private repo `moazessam376-dev/Days-Gone-Godot`.
- Godot MCP (`satelliteoflove/godot-mcp`) + `gdtoolkit` (`gdformat` / `gdlint`).
- `CLAUDE.md`, this file, and the ported `docs/` specs.
- Export templates (macOS + Windows), input map, physics layers, CI.

**Gate:** repo cloneable, opens in Godot, CI green, MCP responds.

### Phase 1 — Asset pipeline & character import  (was R2a)
- Check the Synty account for the **native Godot POLYGON Apocalypse project** first — it would skip
  most of this phase.
- Import Hunter_Male_01 alone with a hand-corrected BoneMap (see the Synty rig trap in `CLAUDE.md`)
  and **Rest Fixer → Overwrite Axis**. Save the BoneMap as a reusable `.tres`.
- Import the 4 guns + 2 throwables; fix Synty's 100× scale and forward axis at import.

**Gate:** character stands at 1.8 m with correct textures, bone map green, guns at correct scale.

### Phase 1.5 — Retarget validation
Retarget the **free MoCap Online Pistol Starter** onto the Synty character through the Phase 1
BoneMap. Proves the animation pipeline before the paid packs are needed. If it fails here, no
purchase fixes it — fall back to Kubold (Mixamo-identical rig), then Mixamo.

**Gate:** a MoCap Online pistol idle plays on the Synty character with un-twisted arms.

### Phase 2 — Weapon handling vertical slice  (was R2b) — **the point of the migration**
Minimal `CharacterBody3D` + `SpringArm3D` camera, flat test level, one character, two weapons.
Nothing else. Full node architecture in the approved plan; summary:
`BoneAttachment3D` socket → `AnimationTree` with a `Blend2` bone filter splitting upper/lower body →
`LookAtModifier3D` torso aim → `TwoBoneIK3D` support hand on the foregrip.

**Gate — the one that matters:** the user plays it and signs off on how the character holds,
carries, aims, fires, reloads and holsters both weapons. **Nothing else is built until this passes.**

### Phase 3 — Player handling model  (was R1)
Straight implementation of `docs/r1-player-handling.md`, already user-approved and needing no
redesign: three-layer state model, action priority `ROLL ≻ WHEEL ≻ THROW ≻ RELOAD ≻ SWAP ≻ FIRE`,
the movement × weapon matrix, stamina, per-state camera table, weapon wheel + slow-mo, throwables
with arc trace, reticle-only-in-ADS.

### Phase 4 — Audio
Real sourced SFX — gunshots per weapon, impacts, footsteps by surface, zombie vocals, ambience, UI.
Godot audio buses with reverb and `AudioStreamPlayer3D` positioning. The old game synthesized every
sound in WebAudio and shipped zero audio files; that is not repeated. Source selection gets its own
short decision session.

### Phase 5 — Physics & collision  (was R0)
Port `docs/collision-matrix.md` onto Jolt layers as the single source of truth. Godot handles
natively most of what R0 hand-built.

### Phase 6 — World  (was R2c)
Synty town (barricaded main street), roads, props, wrecks, nature. Layout spec'd with the user first.

### Phase 7 — Enemy AI depth  (was R4)
Perception (sight/sound, not omniscient), idle/wander/aggro states, horde pathing, hit reactions,
attack variety. Quaternius UAL2 ships a **CC0 zombie set** (idle/bite/scratch/spawn + 8-way walk and
run) that covers the horde for free.

### Phase 8 — Vehicles  (was R3)
Enter/exit animations, visible rider, per-vehicle handling, engine audio, damage, per-vehicle camera.

### Phase 9 — Combat feel & fire polish  (was R5)
Per-weapon recoil identity, impact feedback, fire/explosion visuals, ragdolls.

### Phase 10 — Game structure  (was R6)
Spawning/difficulty pacing, day/night, objectives, save. Only after moment-to-moment feel is right.

## Asset decisions (carried over from `docs/r2-asset-round.md`, no re-deciding needed)

| # | Decision | Choice |
|---|---|---|
| D1 | Player | Hunter_Male_01 |
| D2 | Zombies | Civilian set of 12 × 12 colorways |
| D3 | Guns | Revolver_01, AssaultRifle_01, Shotgun_01, Hybrid_02 (sawn-off) + Molotov_01, Grenade_01 |
| D4 | Bike | User's `Bike.glb`, Synty Motorbike_01 as fallback |
| D5 | Car | Muscle_01 + apocalypse attachments |
| D6 | World | Full Synty replacement |
| D7 | **Animations** | **MoCap Online Rifle Pro + Pistol Pro** (2026-07-21). Fallbacks: Kubold on Fab (~$110, Mixamo-identical rig), then Mixamo + Quaternius (free) |
