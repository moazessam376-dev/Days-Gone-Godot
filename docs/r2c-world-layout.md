# Phase 6 — World Layout Spec: "The Slice"  (was R2c)

Decisions locked with the user on 2026-07-22 (design Q&A during the Phase 4/6 prep session,
run in parallel with the Phase 2 animation work). Every asset named below is
**inventory-verified** against the user's POLYGON Apocalypse v1.09 extraction
(`~/Projects/Days-Gone-Clone/assets/raw/synty/`, 1,816 models) — nothing here is wished for.

This spec defines the layout so the Phase 6 build session can start placing. It does **not**
green-light building now: Phase 6 still waits behind Phases 2–5 per ROADMAP order.

## Concept — user's direction

Not a single walled arena. A **Days Gone-style slice**: a rural two-lane road through pine
forest, linking three destinations — the player's **home base** (spawn), a **fuel station**
stop, and the **barricaded town**. A radio tower on high ground orients from anywhere; a
destroyed elevated motorway and quarantine barricades close the world.

## Decisions

| # | Decision | Choice |
|---|---|---|
| DW1 | Topology | **Forest road spine with 3 nodes** (base → fuel station → town). User-directed; supersedes the town-only options — the barricaded main street survives as the town node |
| DW2 | Town setpieces | **All four**: Diner (interior kit), Motel + pool + sign, AutoRepair garage, Church — plus the fuel station as its own road node |
| DW3 | World edges | **Quarantine barricades + wrecks** seal the playable space; **destroyed motorway** pieces + background cards as non-playable skyline backdrop |
| DW4 | Landmark | **RadioTower** on a rise behind the town's far barricade — visible down the whole road spine, and a future-objective tease |
| DW5 | More Synty packs? | **None needed for this slice.** The pack has pines, gas pumps, and a full camp kit (verified below). Optional later: POLYGON Nature for forest variety only. First: check the Synty account for the **native Godot Apocalypse project** (Phase 1 note) — it may ship ready materials/FX |

## The map

```
        ~ ~ destroyed motorway skyline (Motorway_*_Destroyed + BackgroundCard) ~ ~
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │      p i n e   f o r e s t   (bounds the road corridor)         [RADIO]     │
  │  ┌───────────┐                                                  [TOWER]     │
  │  │ HOME BASE │                ┌──────────┐                         ▲        │
  │  │ tents+gate│═══ road ═══════│   FUEL   │═══ road ══════╗   ══════╩══════  │
  │  │  (spawn)  │  forest curves │ STATION  │  wreck pockets║    TOWN         │
  │  └───────────┘  + wrecks     └──────────┘               ▼    main street   │
  │                                                    [TOWN GATE] Diner·Motel │
  │      p i n e   f o r e s t                                     AutoRepair  │
  │                                                                Church      │
  └─────────────────────────────────────────────────[far BARRICADE]────────────┘
```

Rough scale for the M1 budget: **road spine 500–700 m**, town main street **150–200 m**.
Forest is a *corridor*, not an open field — it bounds sightlines and perf at the same time.

## Zones

### Z1 — Home base (spawn, safe zone)
A survivor camp in a forest clearing just off the road's near end.
`SM_Bld_Military_Tent`, `SM_Bld_Quarantine_Tent` (+ corridor/dome variants),
`SM_Prop_Tent_Dome`, `SM_Prop_Sleeping_Bag`, `SM_Prop_Camp_Chair`, `SM_Prop_Generator`,
`SM_Prop_Barrel_01` as a fire barrel (flame = GPUParticles on the prop),
`SM_Prop_Wall_Quarantine_Gate` as the entrance, corrugated barricades for the perimeter.
Future hooks (not Phase 6): the bike parks here (Phase 8); stash/sleep/save (Phase 10).

### Z2 — Road spine + forest
`SM_Env_Road_01..04` straights, `Road_Crossing_01..03`, `Road_Corner_End_02`,
`Road_Dirt_Straight_01` transitions, `RoadPiece_Damaged_*` for decay, patches/speed bumps for
texture. Forest fill: `SM_Env_Tree_Pine_Tall` (3 variants) + `Tree_Pine_Cluster` (cheap mass),
`Tree_Dead`, rocks and logs. Wrecked vehicles (`SM_Veh_*` + `Veh_Attach_*` bumpers/framing) as
sparse cover pockets along the way.
⚠ **Corner variety is thin** (one true corner piece) — road bends may need dirt-road
transitions or angled straights; verify in the build session before committing the path.

### Z3 — Fuel station (first combat pocket)
Composable — there is no monolithic gas-station building:
`SM_Prop_Gaspump_01/02` + `Gaspump_Base_01` + `Gaspump_Cover_01` (canopy), burnt variants for
one damaged bay, `SM_Bld_Shop_Small` as the kiosk, `SM_Env_Road_Parking_*` apron,
`SM_Prop_GasCan_01` set dressing.

### Z4 — Town (the dungeon of the slice)
The barricaded main street from the original concept, sealed at both ends
(`SM_Prop_Barricade*`, container walls, wrecks). Anchors: **Diner** (own interior kit: booths,
stools, tables, signage), **Motel** + `Motel_Sign` + `SM_Bld_Pool`, **AutoRepair**, **Church**.
Fill: `Shop_Small/Medium/Large`, `Commercial_*`, `Apartment`, `House`/`House_Burnt`;
`SM_Env_Path_*` for alleys and door approaches; junk shelters + market stalls for street life.

### Z5 — Landmark + skyline
`SM_Bld_RadioTower_01` on a rise behind the town's far barricade.
Backdrop ring: `SM_Env_Motorway_*_Destroyed` + `Motorway_Support` + `SM_Env_BackgroundCard`.

## Gameplay intent per zone (informs later phases, nothing built now)

Base **safe** → road **sparse wanderers** → fuel station **small pocket** → town **dense,
horde-capable** (Phase 7). A difficulty gradient you can read off the map.

## Perf posture (M1 / 8 GB, 60 fps target)

- One Synty atlas material across everything → minimal draw calls; keep it that way on import.
- Trees via **MultiMesh/instanced scenes**; prefer `Pine_Cluster` meshes over many singles;
  visibility ranges on forest bands.
- Sightlines are structurally short (forest corridor, street canyon) — that is the occlusion
  strategy, keep it when placing.
- Motorway backdrop = a handful of large meshes + cards, no gameplay collision.

## Open items for the Phase 6 build session

1. Terrain approach: flat ground + `Dirt_Slope` pieces vs. a real heightmap (the radio-tower
   rise needs *some* elevation).
2. Road bend solution given the thin corner inventory (Z2 note).
3. Exact town parcel map — per the project workflow, **the user places** (gizmo pass on a
   blocked-out street), Claude plumbs the generator/scene plumbing afterwards.
4. NavMesh baking strategy once zombie phases approach.
