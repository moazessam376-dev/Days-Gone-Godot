# Days Gone (Godot)

A Days Gone-inspired third-person open-world zombie shooter. Low-poly stylized (Synty POLYGON),
single-player, keyboard + mouse. **Desktop only: macOS + Windows. No web export.**
**Game feel is the project's #1 priority** — movement, aiming, and combat feedback quality outrank
feature count.

This project is a migration from `~/Projects/Days-Gone-Clone` (Vite + TypeScript + Three.js +
Rapier, still live and untouched). That repo is **reference only** — no code ports.

**READ `ROADMAP.md` FIRST in every session.** It holds the agreed phase plan, marks the current
phase, and records the design-before-code rule. Detailed specs live in `docs/`. Do not start feature
work outside the current phase.

---

## The lesson that caused this migration — read before touching weapons or audio

The old project spent **14 numbered fix rounds** on how the player holds a gun, and every round
failed the playtest. The root cause was not the math. It was that **POLYGON Apocalypse ships 1816
models and zero animations**, so there was no correct gun pose to play — and the response was to
synthesize one with procedural IK, palm sockets and finger-curl code.

The same mistake produced the bad audio: `AudioEngine.ts` synthesized every gunshot from noise
bursts and sine waves. There were zero audio files in the repo.

**The rule this project runs on: source real assets; do not synthesize content.**
A rifle-idle clip *is* the correct hand pose — fingers wrapped, trigger discipline, both hands
placed. If something looks or sounds wrong, the first question is "what asset is missing?", not
"what transform can I add?".

---

## Commands

Godot lives at `/Applications/Godot.app/Contents/MacOS/Godot` (4.7.1.stable).
It **must not** be run from `~/Downloads` — macOS AppTranslocation gives it a randomized read-only
path that breaks all automation.

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot

$GODOT --path .                       # open the editor
$GODOT --headless --path . --check-only --script <file.gd>   # typecheck a script
$GODOT --headless --path . --script <file.gd>                # run a SceneTree script

export PATH="$HOME/Library/Python/3.9/bin:$PATH"
gdlint  <path>                        # lint GDScript
gdformat <path>                       # format GDScript
```

Verified working: headless script execution returns normally. Two CLI facts that matter:
- **Headless rendering is impossible.** `--headless` forces the dummy rasterizer, whose
  `texture_2d_update` is a no-op — there are no pixels to read, and macOS has no `xvfb-run`
  equivalent. **You cannot screenshot the game from the CLI.**
- **Exit codes lie.** Only `--check-only` and export failures set a real exit code. Script errors
  must be caught by grepping stderr. `--quit-after N` counts *frames*, not seconds.

## Stack

Godot **4.7**, **GDScript**, Forward+, **Jolt Physics**. No C#, no web export.
Assets: user-licensed Synty POLYGON Apocalypse + City Zombies; MoCap Online weapon animations.

## Architecture map

_(Grows as phases land. Keep this section honest — it is the map future sessions navigate by.)_

- `addons/godot_mcp/` — the Godot MCP addon (tooling, not game code). Do not edit.
- `assets/` — imported, game-ready assets, committed via **Git LFS**.
- `assets/_raw/` — gitignored staging area for source packs.

## Conventions that must hold

- **Weapons attach via `BoneAttachment3D`, never procedural IK.** One `BoneAttachment3D` on the
  right hand bone with `override_pose = OFF` (it conflicts with the `SkeletonModifier3D` system),
  one child `Node3D` socket carrying a per-weapon `Transform3D` on the weapon's resource. That
  transform is calibrated **once per weapon** — never per clip, per stance, or per pose. If a
  weapon looks right in one animation and wrong in another, the bug is a missing **Rest Fixer →
  Overwrite Axis** on import, not a new offset.
- **Skeleton modifier order matters.** `LookAtModifier3D` (torso aim) runs *before* `TwoBoneIK3D`
  (support hand on the foregrip), so the IK solves against the already-rotated torso.
- **All tuning constants live in one place**, grouped by system, and are exposed for live tuning.
  Never hardcode a feel constant at a call site.
- **Data-driven weapons** — stats, sockets and IK targets on a `WeaponResource`, not in code.
- Perf target 60 fps. The dev machine is an **Apple M1 with 8 GB RAM** — respect it in asset budgets
  and import settings.

## The Synty rig trap — costs a day if you miss it

Godot's humanoid auto-mapper gets Synty's arm bones **backwards**:

| Godot humanoid slot | Synty bone |
|---|---|
| `LeftShoulder` | `Clavicle_L` |
| `LeftUpperArm` | **`Shoulder_L`** ← not the shoulder |
| `LeftLowerArm` | `Elbow_L` |
| `LeftHand` | `Hand_L` |

Synty's `Shoulder_L` is the **upper arm**; `Clavicle_L` is the **shoulder**. Auto-mapping produces
twisted arms. **Fix the BoneMap by hand and save it as a reusable `.tres`.**

Also: Synty hands have only **3 fingers** (Middle/Little slots stay empty), the spine is **3
segments**, right-side bones import with a trailing `" 1"` suffix, and bone names differ per pack —
budget a fresh BoneMap per pack. Import characters **one at a time**; batched FBX breaks retargeting.

Other known traps:
- Open ufbx bug [godot#90314](https://github.com/godotengine/godot/issues/90314): empty `Node3D`s
  import at **100× scale with wrong rotation** — bites weapon sockets specifically.
- The Unity material atlas does **not** survive a naive FBX import.
- Synty ships **native Godot projects** for POLYGON Apocalypse — check the Synty account before
  hand-converting anything.

## Verification (MANDATORY)

The old project's hardest-won rule, kept verbatim in spirit: *headless checks passed all six R2 fix
rounds while the user reported "nothing is fixed."*

- **The user's playtest gates anything visual.** Pose, grip, aim, stance, ground contact — never
  claim one of these is fixed without the user seeing it in their own build.
- **Use the Godot MCP to iterate between playtests.** It can freeze and step the game clock,
  `step_until <condition>`, inject real input, and read live game state as JSON. Since headless
  rendering is impossible on macOS, this is the only automated window into the running game. It
  requires the **editor to be open with the plugin enabled**.
- **Measured numbers over eyeballing.** Never tune a transform by guessing across screenshots — read
  the delta, set it once. This rule held up in the old project; keep it.
- **`gdlint` + `--check-only` are a regression net only**, never proof of a visual fix.

## Workflow

- **Everything goes through PRs.** Claude branches, commits, pushes and opens the PR. **Claude never
  merges and never pushes to `main`.** The user reviews and merges.
- **No assumptions.** Design decisions are made with the user before implementation, not bolted on
  feature-by-feature. When something is ambiguous, ask.
- Each phase ends with the game **runnable and actually played**.
- The repo is **private**, which is what allows licensed Synty assets to be committed at all. Keep
  it private; their licence forbids public redistribution.
