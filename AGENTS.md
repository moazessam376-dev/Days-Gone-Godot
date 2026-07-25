# AGENTS.md

Days Gone-inspired third-person zombie shooter. Godot 4.7, GDScript, Forward+, Jolt.
Desktop only (macOS + Windows), no web export. Private repo — licensed Synty and
MoCap Online assets are committed via Git LFS, so it stays private.

## Read these, in this order

1. **`CLAUDE.md` — the single source of truth.** Commands, stack, architecture map,
   conventions, the rig traps, and the verification rules. Everything else defers to it.
2. **`ROADMAP.md`** — the agreed phase plan and which phase is current. Do not start
   feature work outside it.
3. The `docs/` spec for whatever you are touching.

Do not duplicate content from `CLAUDE.md` into this file. Two sources of truth drift.

## Skills — read the matching one before the task

| Skill | Read before |
|---|---|
| `godot-scene-safety` | editing any `.tscn` / `.tres` / `project.godot`, or running a generator |
| `godot-rig-retargeting` | importing a character/animation FBX, editing a BoneMap, adding a `SkeletonModifier3D`, attaching a weapon to a bone |
| `godot-animation-pipeline` | choosing clips, editing `build_character.gd` / `build_anim_tree.gd`, diagnosing a wrong pose or gait |
| `godot-human-in-the-loop` | anything judged by eye — pose, grip, camera, feel |
| `blender-authoring` | authoring or exporting a clip in Blender |

## Three hard rules

- **Everything goes through PRs.** Branch, commit, push, open. **Never push directly to
  `main`**, and **never merge unless the user has authorised it**. Asking "these are green,
  want me to merge?" is encouraged; merging unasked is not.
- **The user places, Claude plumbs.** Anything needing "move it, look, move it again" is
  the user's, in the editor, with a gizmo. Claude builds the control, verifies its axis,
  reads the values back and bakes them. Never tune a pose by screenshot.
- **Source real assets; do not synthesize content.** No procedural gun poses, no
  synthesized audio. If something looks or sounds wrong, ask what asset is missing.

## Two things that will waste your time if you forget them

- **Headless rendering is impossible on macOS** — `--headless` forces the dummy
  rasterizer. You cannot screenshot the game from the CLI. Use the Godot MCP with the
  editor open.
- **Exit codes lie.** Only `--check-only` and export failures set a real one. Catch
  script errors by grepping stderr.
