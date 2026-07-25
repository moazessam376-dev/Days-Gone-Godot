# Blender environment

Blender is the authoring tool for **new animation clips**, keyed by the user directly on
the Synty skeleton. Clips authored here get **no BoneMap, no Rest Fixer and no build-time
correction** — there is no second rig, so there is no retarget residual to undo. That
deletes the entire bug class documented in `.claude/skills/godot-rig-retargeting/`.

Decided 2026-07-25, alongside the single-rig invariant (see
`.claude/skills/godot-animation-pipeline/`).

---

## Version: Blender 4.5 LTS

> ⚠️ **Every generated `bpy` script in `tools/blender/` targets the version recorded
> below.** Do not upgrade Blender without re-running the probe and updating this file —
> `bpy` API churn between releases is the single most common way generated scripts break,
> and it is free to prevent.

**Why 4.5 LTS and not latest:**

- LTS, supported into mid-2027 — the scripts do not get invalidated by a minor release
- the glTF 2.0 exporter is stable here and its Godot-facing quirks are well documented
- comfortable on the dev machine (Apple M1, 8 GB RAM) for rig and keyframe work

### Install (macOS, Apple Silicon)

1. Download the **macOS Apple Silicon `.dmg`** for the latest **4.5 LTS** patch from
   <https://www.blender.org/download/lts/>
2. Open the `.dmg` and drag `Blender.app` to **`/Applications`**.

   > ⚠️ **Not `~/Downloads`, not the Desktop.** macOS AppTranslocation gives an app run
   > from a quarantined location a randomized read-only path, which breaks every
   > `--background` invocation. This exact trap already cost this project time with Godot
   > (see `CLAUDE.md`), and it fails the same way here.

3. First launch: **right-click `Blender.app` → Open** (not a double-click) and confirm, to
   clear the quarantine flag.

### The version probe — required before any script is written

Open Blender → **Scripting** workspace → paste into the console and run:

```python
import bpy, sys
print(bpy.app.version_string)
print(sys.version)
```

Paste the output back so it lands here verbatim.

```
<!-- PENDING: paste bpy.app.version_string and sys.version output here -->
```

| | Recorded value |
|---|---|
| `bpy.app.version_string` | _pending_ |
| `sys.version` (bundled Python) | _pending_ — expect 3.11.x on the 4.5 series; **verify, do not assume** |

### CLI

```bash
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender

$BLENDER --version
$BLENDER --background --python tools/blender/check_clip.py -- <clip.glb>
```

`--background` is Blender's headless mode. Unlike Godot's `--headless`, it **can** run the
full dependency graph and evaluate armatures, which is why `check_clip.py` can validate a
clip without a GUI. It cannot render a viewport preview — visual judgement of a clip stays
a job for the user in the Blender viewport, per
`.claude/skills/godot-human-in-the-loop/`.

---

## Blender MCP: deferred, deliberately

**Decision: not yet.** Script-first for now — readable `.py` files run from the Scripting
workspace, which the user can read before running and undo with Ctrl+Z.

**Why, beyond preference.** The Godot MCP works well because the Godot editor is a
persistent server the addon plugs into. A Blender MCP instead drives a *live* Blender
instance, so a bad call mutates the scene with no diff to inspect. While the rig scripts
are still being got right, a file that can be read, run, and undone is both safer and far
easier to debug than an opaque live connection.

**Candidate when it is time:** `ahujasid/blender-mcp` (the de-facto one).

**Trigger to revisit:** after the first authored clip ships through
`seed_pose.py → export_clip.py → check_clip.py → import_authored.gd` and passes a user
playtest. At that point the pipeline is known-good and a live connection is accelerating a
working loop rather than debugging a broken one.

Adding it will need a session restart to be picked up.

---

## The authored-clip pipeline

| Step | Tool | Venue |
|---|---|---|
| 1. build the posing rig | `tools/blender/build_control_rig.py` | Blender, Scripting |
| 2. seed the start pose | `tools/blender/seed_pose.py` | Blender, Scripting |
| 3. **key the animation** | — | **Blender viewport, the user** |
| 4. export | `tools/blender/export_clip.py` | Blender, Scripting |
| 5. validate | `tools/blender/check_clip.py` | `--background`, CI-able |
| 6. register in Godot | `tools/rig/import_authored.gd` | Godot, headless |

Step 3 is the user's. Steps 1, 2, 4, 5, 6 are Claude's — that is the same
"user places, Claude plumbs" split as the Godot-side rig work, moved into Blender.

### Why clips are seeded, not authored from scratch

`seed_pose.py` loads **frame 0 of the calibrated aim clip** — `W2_Stand_Aim_Idle_v2`
(rifle) or `W1_Stand_Aim_Idle_IPC` (pistol) — as the Blender starting pose. Those are the
exact clips each weapon's socket is calibrated against.

So an authored fire or reload clip *begins* precisely where the aim pose ends, and the
cross-fade discontinuity that caused the rifle-fire bug becomes impossible by
construction rather than something to tune away. `check_clip.py` asserts it
(frame 0 must match the declared seed within tolerance).

The clip itself is still authored Synty-native: the seed is a pose baked once onto the
Synty skeleton, not a retarget at play time.
