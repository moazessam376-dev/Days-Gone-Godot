# Phase 4 — Audio Source Research & Selection Proposal

Research done 2026-07-22 (parallel to the Phase 2 animation session; docs-only branch).
This is the input to the **short decision session** ROADMAP Phase 4 calls for. Nothing is
purchased or imported yet — the tables below end in three decisions for the user.

**Why this doc exists:** the old project synthesized every gunshot from noise bursts and sine
waves in `AudioEngine.ts` and shipped **zero audio files**. The rule this project runs on —
*source real assets; do not synthesize content* — applies to audio exactly as it applies to
animation. Every sound in the game must come from a real recording with a real license.

## What Phase 4 needs (from ROADMAP + weapon decisions D3)

| # | Category | Contents needed |
|---|---|---|
| A1 | Gunshots | Fire + tail per weapon: Revolver_01, AssaultRifle_01 (semi/auto), Shotgun_01, Hybrid_02 sawn-off. Handling foley: reload stages, dry-fire, holster/draw |
| A2 | Impacts | Bullet hits by surface (concrete, metal, wood, dirt, glass) + flesh hits for zombies |
| A3 | Explosions & fire | Grenade blast, Molotov glass-break + ignite + burning loop |
| A4 | Footsteps | Player + zombie steps keyed by surface (concrete, dirt, grass, metal, wood minimum) |
| A5 | Zombie vocals | Idle groans, alert, attack/bite, hurt, death; horde layer for later phases |
| A6 | Ambience | Abandoned-town day/night beds, wind, interior room tones |
| A7 | UI | Weapon wheel open/close + tick, pickup, menu clicks |

## Candidate sources

### The one purchase that covers most of the table

**Gamemaster Audio — Pro Sound Collection**, $47 direct
([gamemasteraudio.com](https://www.gamemasteraudio.com/product/pro-sound-collection/), also on
the [Godot Assets Marketplace](https://godotmarketplace.com/shop/pro-sound-collection/)).
8,076 game-ready SFX (96 kHz/24-bit source), bundling their entire catalog: **Gun Sound Pack,
Silenced Gun Sounds, Bullet Impact Sounds, Explosion Sound Pack, Warfare Sounds, Footstep and
Foley Sounds, Human Vocalizations**, fire/electricity/water, buttons/collectibles/powerups (UI),
punches, and more. Royalty-free for commercial games.

- Covers: **A1, A2, A3, A4 (backup), A7** in one purchase, plus player hurt/effort vocals.
- Any purchase channel is fine, **including the Unity Asset Store**: Unity's own support FAQ
  confirms Asset Store assets may be used in other engines under the standard EULA
  (non-restricted assets — which standard third-party packs like this are), provided they ship
  embedded in the game, never redistributed raw. *(Corrected 2026-07-23 — an earlier draft of
  this doc claimed a Unity-only tie.)* Delivery may be a `.unitypackage`: same tar.gz format as
  the Synty packs, extracted in `assets/_raw/` staging the same way during the Phase 4 build.
- Not confirmed to contain zombie vocals (the bundled packs list has none) → A5 is sourced
  separately below.
- Risk: 8k sounds averaging ~1.4 s each — these are game one-shots, not cinematic layers. If a
  gun doesn't pass the feel bar in playtest, upgrade path below.

### Free backbone — Sonniss GDC Game Audio Bundles

[Sonniss GameAudioGDC](https://sonniss.com/gameaudiogdc/) — the yearly free bundles
([2026 edition](https://gdc.sonniss.com/)), tens of GB of **professional** libraries
(contributors include BOOM Library and Krotos). Royalty-free, commercial use, **no attribution**,
unlimited projects; raw-file redistribution prohibited (same posture as Synty — fine in this
private LFS repo); AI/ML training use prohibited (irrelevant to us).

- Covers: **A1 tails/layers, A2, A3, A6** — this is where pro-grade gun tails, explosion weight
  and ambience beds come from for free.
- Cost is curation time, not money: multi-GB downloads to sift. Treat it as the *backfill*
  source when a specific sound is missing or weak, not the primary workflow.

### Category specialists

| Category | Pick | License / price | Notes |
|---|---|---|---|
| A4 Footsteps | **Nox_Sound — Footsteps Essentials** ([itch.io](https://nox-sound-design.itch.io/essentials-series-sfx-nox-sound)) | **CC0, free** | 397 mono WAVs, 48 kHz/24-bit, **13 surfaces** (dirt, grass, gravel, leaves, metal, mud, rock, sand, snow×2, tile, water, wood). Purpose-built for a surface-keyed footstep system |
| A5 Zombies (now) | **Cafofo — Zombie Sound Pack, Free version** ([GameDev Market](https://www.gamedevmarket.net/asset/zombie-sound-pack-free-version)) | Royalty-free, free | 40+ sounds, 2 voice sets (idle/attack/hurt) — enough for Phase 2–5 prototyping |
| A5 Zombies (Phase 7) | **Cafofo — Zombie Sound Pack, Pro version** ([GameDev Market](https://www.gamedevmarket.net/asset/zombie-sound-pack-pro-version), also on [Godot marketplace](https://godotmarketplace.com/shop/zombie-sound-pack-pro-version/)) | Royalty-free, ~$20–30 | 600+ sounds: **8 voice sets** (male/female/kid × idle/attack/hurt/die) matching our 12-civilian zombie cast, headshot sounds, zombie footsteps on 4 surfaces, blood/bodyfalls. Buy when Phase 7 starts, price it then |
| A6 Ambience | Sonniss GDC beds + [Pixabay](https://pixabay.com/sound-effects/search/apocalypse/) / Freesound CC0 wind & urban decay | Free | Loop-ready post-apocalyptic beds also on itch (e.g. Juhani Junkala's wasteland ambience, free). Final beds chosen by ear during the Phase 4 build |
| A7 UI | **Kenney — Interface Sounds** ([kenney.nl](https://kenney.nl/assets/interface-sounds)) | CC0, free | Clean neutral clicks/ticks for wheel + menus; Pro Sound Collection buttons as alternates |

### Gun upgrade path (only if playtest demands it)

If a weapon still sounds weak after mixing Pro Sound Collection shots with Sonniss tails:
[BOOM Library GUNS](https://www.boomlibrary.com/sound-effects/gun-sounds/) construction kit
(2,600+ source recordings, 12-mic rig — the industry reference, but €150+ and overkill for 4
weapons) or a single per-weapon library from
[Sonniss's gun category](https://sonniss.com/category/sound-libraries/guns/). **Decision
deferred until a real playtest fails** — same discipline as D4's bike fallback.

## Licensing posture (mirrors the Synty rule)

All picks are royalty-free for commercial games. CC0 sources (Nox_Sound, Kenney) need nothing.
Sonniss/Gamemaster/Cafofo forbid **redistributing the raw files** — satisfied the same way as
Synty: private repo, Git LFS, no public mirror. `CREDITS.md` gets a "Licensed (not
redistributed)" section for audio when files land.

## Godot-side notes (for the Phase 4 build session, not decided here)

- One-shots (guns, impacts, UI): **WAV** import; loops/beds (ambience, fire): **Ogg Vorbis**.
- Buses per ROADMAP: Master → SFX / Ambience / UI (+ Music later), reverb send on SFX for
  interiors; `AudioStreamPlayer3D` for world sounds. Bus + attenuation design is its own session.
- `AudioStreamRandomizer` for footstep/impact round-robin + pitch jitter — the engine-native way
  to avoid the machine-gun-repetition tell.
- M1 8 GB budget: keep sources 44.1 kHz/16-bit in-game; the 96/24 masters stay in `assets/_raw`.

## Decisions — locked with the user 2026-07-23

| # | Decision | Outcome |
|---|---|---|
| DA1 | The one purchase | ✅ **Pro Sound Collection purchased** (delivered as `.unitypackage`; stays zipped in `assets/_raw/audio/` until the Phase 4 build session) |
| DA2 | Guns | ✅ Default accepted: Pro Sound Collection shots + free Sonniss layers first; BOOM-tier upgrade **only after a failed playtest** |
| DA3 | Zombies | ✅ Default accepted: Cafofo **Free now**, **Pro (~$25) deferred to Phase 7** |

Total spent: **$47**. Everything else in the plan is free.
