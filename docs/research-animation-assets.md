# TPS Weapon-Handling Animations for a Godot 4 Synty POLYGON Game — Research Report

## 1. Synty's own animation line — Synty sells NO shooter animations

Synty sells exactly **6** animation packs. Verified three ways (collection page,
`collections/all?q=animation`, and the ANIMATION Collection Bundle contents).
None involve firearms.

| Pack | List | Sale seen | Clips |
|---|---|---|---|
| ANIMATION - Base Locomotion | $69.99 | $21.00 | 247 |
| ANIMATION - Idles | $49.99 | $15.00 | 330 |
| ANIMATION - Sword Combat | $59.99 | $18.00 | 105 |
| ANIMATION - Bow Combat | $99.99 | $30.00 | 190 |
| ANIMATION - Emotes and Taunts | $59.99 | $18.00 | 140 |
| ANIMATION - Goblin Locomotion | $69.99 | $21.00 | 398 |

- Delivery: Unity 2022.3+ package **plus a separate "Animation FBX Zip File"**.
- Root-motion AND in-place variants shipped.
- Authored directly on the POLYGON/Sidekick rig -> drop-in, no retarget for POLYGON chars.
- Officially supported rigs: POLYGON + Sidekick only. No official UE or Godot support.
- Combat packs use a **prop bone** (extra bone in the hand) for the weapon.
- No public roadmap. Shooter anims requested in reviews; nothing announced.

Bow Combat is structurally the closest (aim drawn/undrawn, stances, strafe, hits,
deaths) but the arm poses are bow-specific and unusable for a rifle.

Base Locomotion DOES ship a full 8-way strafe set (Back Strafe B/BL/BR/FL/L,
Forward Strafe F/FL/FR/R/BR, plus crouch/run variants) — unarmed, but exactly the
lower-body layer an aim-strafe system needs.

## 2. Rig + Godot support

- Synty FAQ: "we currently only provide official support for Unity and Unreal Engine."
- For UE, Synty uses "our own Skeleton that requires animation retargeting" — NOT the
  UE mannequin, NOT the Mixamo skeleton.
- Most POLYGON packs share one skeleton, so characters mix freely; the skeleton
  *asset name* differs per pack (e.g. SK_Character_City_Rig).
- **Synty now ships native Godot projects** for 22 POLYGON packs. POLYGON Apocalypse
  is listed "Compatible with Godot 4.6.2+ / Godot 4.6.2 Project". Military Pack too.
  City Zombies is NOT in the Godot collection.
- Godot forum thread documents real pain retargeting Mixamo onto Synty: missing bones
  in BoneMap, `Shoulder` vs `Clavicle` naming mismatch, twisted shoulders, and
  uploading a Synty char to Mixamo yields empty animation tracks.
- Mixamo auto-rigger upload of Synty chars fails ~75% of the time (Versluis).

### ACTUAL SYNTY BONE NAMES (Godot humanoid slot -> Synty bone)
Extracted from a working community BoneMap:
https://raw.githubusercontent.com/tctimmeh/synty-in-godot/main/godot/synty_bone_map.tres

```
Root->Root  Hips->Hips  Spine->Spine_01  Chest->Spine_02  UpperChest->Spine_03
Neck->Neck  Head->Head  Jaw->Jaw
LeftShoulder->Clavicle_L   LeftUpperArm->Shoulder_L   LeftLowerArm->Elbow_L   LeftHand->Hand_L
RightShoulder->Clavicle_R  RightUpperArm->Shoulder_R  RightLowerArm->Elbow_R  RightHand->Hand_R
LeftUpperLeg->UpperLeg_L   LeftLowerLeg->LowerLeg_L   LeftFoot->Ankle_L   LeftToes->Ball_L
RightUpperLeg->UpperLeg_R  RightLowerLeg->LowerLeg_R  RightFoot->Ankle_R  RightToes->Ball_R
Fingers: Thumb_01/02/03, IndexFinger_01/02/03, Finger_01/02/03  (right side suffixed " 1")
```

THE TRAP: Synty's `Shoulder_L` is the **upper arm**; `Clavicle_L` is the **shoulder**.
Godot's auto-mapper guesses this backwards -> twisted arms. This is the root cause of
the forum reports. Swap them manually.

Other quirks:
- **Only 3 fingers.** Middle/Little slots empty; ring slot filled by generic `Finger_0x`.
  Quaternius/Mixamo 5-finger tracks will simply drop (invisible at Synty poly counts).
- Spine is 3 segments, not 5.
- Right-side bones import with a trailing `" 1"` suffix (collision disambiguation),
  so the BoneMap is import-specific.
- Bone names differ per pack ("each pack has their own naming conventions" - Versluis).
  The BoneMap above was authored against Dungeon/Fantasy Kingdom. NOT verified against
  Apocalypse or City Zombies. Budget ~10 min per pack to build one.
- City Zombies' UNREAL build was converted to the UE4 mannequin rig (v1.7.0); the FBX
  source files are still on the Synty rig.
- Import characters ONE AT A TIME — batch/combined FBX breaks retargeting.

## 3. Godot 4 import specifics

- Godot 4.3+ uses built-in **ufbx**; FBX2glTF no longer needed. New project on 4.7
  gets ufbx by default. (Projects upgraded from 4.1/4.2 keep FBX2glTF — different
  node hierarchies.)
- Retargeting = import "As Scene" -> Skeleton3D -> Bones -> Set Profile -> Humanoid ->
  assign BoneMap. Rest Fixer options: Overwrite Axis (the critical one),
  Fix Silhouette (A-pose -> T-pose), Normalize Position Tracks (stride slip).
- Known gotchas: rest-pose mismatch causes rotation errors; root scale / Apply Root
  Transform for 90-degree rotation; foot sliding if root motion isn't wired to
  CharacterBody3D; 120fps mocap should be downsampled to 30.
- Open ufbx bug: **empty/Node3D nodes import at 100x scale with wrong rotation** —
  godotengine/godot#90314, still open. Matters if you rely on Synty attachment-point
  empties (weapon sockets!).
- Switching importers (FBX2glTF <-> ufbx) breaks NodePath refs AND changes skeleton
  rest poses. Pick one at project start; you're on 4.7 so ufbx is correct.
- Community tooling, two options:
  - `DeniedWorks/synty-godot-converter` (v2.4, Feb 2026) — best starting point. Reads
    .unitypackage directly (no Unity install), parses Unity .mat -> Godot ShaderMaterial
    .tres, ships 7 shaders replicating Synty Polygon/Foliage/Crystal/Water/Clouds/
    Particles/Skydome. `--mesh-scale` flag.
  - `tctimmeh/synty-in-godot` — Unity round-trip. Requires a Unity install. Documents
    two extra traps: `.tif` textures must be converted to `.png`, and any node whose
    name ends in "Wheel" must be renamed or Godot turns it into a wheel physics object.
- godotshaders.com/shader-tag/synty — 8 standalone drop-in shader ports.
- Mixamo Animation Retargeter plugin (godotengine.org/asset-library/asset/3429)
  requires the skeleton be named `Skeleton`, NOT `GeneralSkeleton` — conflicts with
  Godot's own bone-renaming step, which renames it to `GeneralSkeleton`.
- The atlas does NOT survive naive import: the FBX references Unity material names,
  so Godot generates one untextured material per slot. Hence the converters above.

## 4. Commercial gun-animation options

### MoCap Online — dedicated FBX SKUs, best technical fit
| Product | Price | Anims |
|---|---|---|
| Rifle Pro (FBX) | $149.99 | 390 |
| Pistol Pro (FBX) | $149.99 | 372 |
| Hipfire Shooter | $49.99 | 140 |
| Rifle Basic / Pistol Basic | $44.99 ea | 88 / 86 |
| Rifle Starter / Pistol Starter | $5.99 / $4.99 | 11 / 16 |
| **Shooter MoCap Bundle** | **$299** | rifle+pistol+hipfire |
| Free Pistol Starter (itch.io) | $0 | 20+ |

Skeleton MotusMan_v55; weapon parents to `RightHandMiddle1`. Ships root-motion AND
in-place; Pro adds "IPC" in-place-with-curves (speed/rotation as animation curves —
useful for driving a Godot controller). Licence: royalty-free perpetual up to
1M users / $1M revenue; AI training needs a separate permit. itch.io starter licence
is narrower (one commercial project).

### Kubold — Mixamo-identical HumanIK skeleton
Fab: Rifle Animset Pro $59.99, Pistol Animset Pro $49.99, Movement Animset Pro $64.99,
Cover Animset Pro $49.99. Unity AS: Rifle $50, Pistol $50, Movement $65.
FBX source shipped in `SourceFiles.zip` inside the UE project.
**Buy on Fab, not Unity** — Fab Standard Licence is explicitly not engine-restricted.
Unverified anecdote that Kubold's Unity-side FBX imports poorly into Godot.

### Free / CC0

**Quaternius Universal Animation Library** — CC0 1.0 (verified from shipped
License.txt). Standard free (45-46 anims), Pro $9.99+, Source $14.99+ on itch.
NOTE: quaternius.com marketing implies Pro is free; itch lists $9.99+. Discrepancy
unresolved. Rig is **Blender Rigify deform**, 53 joints, 5 fingers. Ships a
dedicated Godot GLB (`AnimationLibrary_Godot_Standard.glb`).

GUN COVERAGE IS 6 CLIPS, ALL PISTOL — enumerated from the source package:
`Pistol_Idle`, `Pistol_Shoot`, `Pistol_Reload`, `Pistol_Aim_Up/Neutral/Down`.
**Zero rifle. Zero aim-while-moving. Zero holster/draw.** All 8-way locomotion
is unarmed. All 6 pistol clips ARE in the free tier.
BUT: **UAL2 has a full CC0 zombie set** — Zombie_Idle/Bite/Scratch/Spawn plus
8-way Zombie_Walk_* and Zombie_Run_*. Directly relevant to this project.

**Mixamo** — online and free, verified live (HTTP 200, public API responds
unauthenticated). Adobe FAQ last updated Sep 2021; no shutdown announced but the
service is frozen (no feature updates in years, auto-rigger biped-only, multi-day
outages Jun+Sep 2025). Plan for it disappearing. Licence: royalty-free personal/
commercial incl. video games, no attribution; the one hard rule is you may not
redistribute the raw FBX as the product (no asset packs/templates). Baked into a
shipped game is fine.

GUN COVERAGE IS ACTUALLY GOOD — enumerated from Mixamo's API:
- **Pro Rifle Pack / Rifle 8-Way Locomotion Pack** (~49 clips): idle, idle aiming,
  idle crouching aiming; walk/run/sprint x 8 directions; crouch-walk x 8; turn 90
  L/R standing+crouching; jump up/loop/down; 6 deaths incl. headshots. A COMPLETE
  8-way aim-locomotion set.
- Pistol/Handgun Locomotion Pack (20), Basic Shooter Pack (16), Slim Shooter (7)
- Fire: Firing Rifle (standing/walking/running/crouch-walking), Prone Firing Rifle
- Reload: standing, walking, crouch, running, prone
- Holster/draw: Rifle Pull Out/Put Away, Grab Rifle From Back/Behind Shoulder/Side,
  Drawing Gun, Pistol Aim To Holster Idle
- Strafe-while-aiming: Strafe L/R While Aiming Rifle, Rifle Walk Strafe L/R,
  Crouch Walk Strafe L/R, Pistol Strafe L/R
- Raw counts: 227 "rifle", 211 "gun", 97 "aim", 56 "shoot", 38 "pistol", 12 "reload"

Quality caveats (real): no recoil layering, no aim offsets (upper-body aim must come
from your own IK/skeleton modification), hand-on-weapon placement often off
(recurring "left hand twisted" reports), inconsistent style between clips from
different mocap sessions, generic rifle grip won't match specific weapon models.
- `Jayb3e-PGS/Godot-third-person-Shooter-Template` — CC0, Godot 4.3, unarmed/pistol/rifle,
  but 2 commits and 0 stars.
- `gdquest-demos/godot-4-3d-third-person-controller` — open source, aim/shoot/grenade.

### Dead ends
- GameDev.tv: no TPS shooter animation pack (only resells Kinemation FPS Animation Pro).
- Infima Low Poly Shooter Pack: first-person Unity template, not an animation library.
- GDH All Animation Bundle ($104.99, 4789 anims, Mixamo+UE rigs): zero firearms.
- Most Fab shooter listings are UE .uasset only (AnimBP/BlendSpace/AimOffset are
  worthless in Godot). E.g. "Shooter Rifle Animations" $8.99 — skip.
- ArtStation: nothing meaningful in this category.

## 5. Reference: what a TPS actually needs
MoCap Online's own guide: **80-150 clips per weapon type** — locomotion (idle/walk/
run/strafe/crouch), aim/reload/fire/swap/hipfire, 9-pose aim-offset grid, cover
entry/exit/lean/blind-fire, melee bash, grenade. Also notes FPS animations are
"rarely usable in TPS without significant editing."

## 6. Recommended purchase path

**Step 0 (do this before spending anything, ~half a day).**
Grab the MoCap Online free pistol starter (itch, $0) AND a Mixamo Pro Rifle Pack clip.
Build the Synty BoneMap from the .tres above, fix the Shoulder/Clavicle swap, and
retarget onto an Apocalypse character. If this works, everything below works. If it
doesn't, no purchase fixes it.

**Free path — genuinely viable now.**
Mixamo alone assembles a complete TPS set: Pro Rifle Pack (8-way aim locomotion) +
individual Firing Rifle / Reloading / Rifle Pull Out / Strafe While Aiming clips.
Plus Quaternius UAL2 zombie set (CC0) for the horde. Cost: $0.
Trade-off: hand-on-weapon cleanup in Blender, no recoil layer, build your own aim
offset via upper-body bone rotation.

**Paid path — buys polish and consistency, not coverage.**
- $299 MoCap Online Shooter Bundle (rifle + pistol + hipfire, FBX, MotusMan_v55)
  or $149.99 Rifle Pro alone
- OR $109.98 Kubold Rifle + Pistol Animset Pro on Fab (HumanIK rig, closer to Mixamo,
  easier BoneMap)
- + $21 Synty Base Locomotion for unarmed traversal, zero retargeting

Realistic totals: **$0** (Mixamo + Quaternius), **~$131** (Kubold + Synty locomotion),
**~$320** (MoCap Online bundle + Synty locomotion).

## 7. Corrections to my first pass
- I understated Mixamo. Its rifle coverage is complete, not thin — 227 rifle-tagged
  clips and a full 8-way aim-locomotion pack. The weakness is polish, not breadth.
- I overstated Quaternius. Marketing says "combat and gun"; the actual pack has
  6 pistol clips and no rifle at all.
- Quaternius Pro is $9.99+ on itch, not free as quaternius.com implies.

## Caveats / not verified
- Synty product pages render "Sold out" on EVERY product via fetch (including
  in-stock art packs), so it is a rendering artifact — but I could not confirm
  actual purchasability of the animation packs at the sale prices.
- Sale prices are time-limited; list prices are the safe planning number.
- Kubold Unity-edition animation counts (Fab says 120+ rifle / 150 pistol).
- Whether Synty's Godot project exports include the animation packs (they are not
  in the Godot collection — assume FBX zip + manual retarget).
