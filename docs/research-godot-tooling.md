# Godot MCP servers for Claude Code — comparison & recommendation

Research date: 2026-07-21. All star counts / dates pulled live from the GitHub API.

**Your project context (verified):** `/Users/moazessam/Projects/Godot/days-gone/project.godot`
declares `config/features=PackedStringArray("4.7", "Forward Plus")`, Jolt Physics, no `addons/`
directory yet, no existing `.mcp.json`. Godot is **not on PATH**; the only install found is
`/Users/moazessam/Downloads/Godot.app`. This matters: **you are on Godot 4.7**, which rules out
several of the stale servers below.

---

## 1. Correction on the repos you named

| Named repo | Status |
|---|---|
| `Coding-Solo/godot-mcp` | Exists. 4,816 stars. |
| `ee0pdt/Godot-MCP` | Exists. 597 stars, but abandoned since 2025-03. |
| `bradypp/godot-mcp` | Exists. 87 stars, abandoned since 2025-05. |
| `Chetan-Nagalikar/godot-mcp` | **Does not exist.** The *user* `Chetan-Nagalikar` 404s. |
| `tomvanantwerp/godot-mcp` | **Does not exist.** The *user* `tomvanantwerp` 404s. |

The last two are not deleted repos under a live account — the accounts themselves return 404.
Treat those two names as bad data.

---

## 2. Coding-Solo/godot-mcp — the most-starred one

- Repo: https://github.com/Coding-Solo/godot-mcp
- **4,816 stars, 432 forks**, MIT, JavaScript/TypeScript
- Created 2025-02-26, **last commit 2026-04-16** (~3 months stale), 62 open issues
- npm: `@coding-solo/godot-mcp` — **v0.1.1, published 2026-02-03, only one version ever published**
- ~11,216 npm downloads/month

### Exact tool list (14 tools, read from `src/index.ts` on `main`)

`launch_editor`, `run_project`, `get_debug_output`, `stop_project`, `get_godot_version`,
`list_projects`, `get_project_info`, `create_scene`, `add_node`, `load_sprite`,
`export_mesh_library`, `save_scene`, `get_uid`, `update_project_uids`

### Answering your specific questions

- **Runs the editor?** Yes — `launch_editor` spawns `godot -e --path <project>`.
- **Runs the project?** Yes — `run_project` spawns `godot -d --path <project>` and pipes stdio.
- **Reads debug output?** Yes, but only as **buffered stdout/stderr of the process it spawned**
  (`get_debug_output`). There is no debugger-protocol introspection, no live game state.
- **Edits scenes/nodes?** Partially. It can *create* scenes and *add* nodes by shelling out to a
  bundled `godot_operations.gd` run under `--headless`. There is **no read-back**: no
  `get_scene_tree`, no node property inspection, no delete/reparent/modify-node.
- **Needs the editor running?** **No.** This is the architecture's main advantage — it drives the
  Godot binary via CLI subprocesses. Nothing to install into your project.
- **Godot version:** No hard floor for basic tools; `get_uid`/`update_project_uids` gate on 4.4+
  via an `isGodot44OrLater()` check. Works with 4.7 in principle, but **untested/unclaimed**.
- **Install:** `claude mcp add godot -- npx @coding-solo/godot-mcp`

### ⚠️ Security finding — the recommended install ships an unpatched RCE

This repo has had **two** separate code-execution issues:

1. **CVE-2026-25546 / GHSA-8jx2-rhfh-q928** — "Command Injection via unsanitized projectPath",
   severity **high**, published 2026-02-04. Patched in `0.1.1`. ✅ Fixed on npm.
2. **Issue #95 → PR #99** — "Remote Code Execution via Arbitrary GDScript Instantiation in
   `add_node`", merged **2026-04-16**. A `nodeType` like `res://evil.gd` was passed to
   `load()` inside `godot_operations.gd`, running the script's `_init()` in the Godot process.
   Fixed by an identifier regex `^[A-Za-z_][A-Za-z0-9_]*$` plus removing the `load()` fallback.
   **No advisory was filed for this one.**

I downloaded and unpacked the published tarball
(`registry.npmjs.org/@coding-solo/godot-mcp/-/godot-mcp-0.1.1.tgz`) and verified directly:

- the validation regex is **absent** from `build/index.js`
- `build/scripts/godot_operations.gd` **still contains** the vulnerable
  `ResourceLoader.exists(name_of_class, "Script")` / `load(name_of_class)` fallback (lines 97–100)

So the README's own headline command — `npx @coding-solo/godot-mcp` — installs the **February
build, which predates the April RCE fix**. To get patched code today you must build from source:

```bash
git clone https://github.com/Coding-Solo/godot-mcp && cd godot-mcp && npm install && npm run build
```

This is a low-practical-risk bug for a solo dev (you'd have to ask the agent to add a node named
after a malicious script in your own repo), but it's a real signal about release hygiene.

**Verdict:** the star count is a 2025 artifact. It's a thin CLI wrapper, it can't read scene state
back, and its published package is behind its own security fix. Not the best pick in 2026.

---

## 3. ee0pdt/Godot-MCP — the GDScript-plugin one

- Repo: https://github.com/ee0pdt/Godot-MCP
- 597 stars, MIT, GDScript + Node server
- **Last commit 2025-03-19 — abandoned for ~16 months**
- Its bundled `project.godot` declares `config/features=PackedStringArray("4.4", ...)`

### Node/scene manipulation offered

Resources: `godot://script/current`, `godot://scene/current`, `godot://project/info`

Commands: `get-scene-tree`, `get-node-properties`, `create-node`, `delete-node`, `modify-node`,
`list-project-scripts`, `read-script`, `modify-script`, `create-script`, `analyze-script`,
`list-project-scenes`, `read-scene`, `create-scene`, `save-scene`, `get-project-settings`,
`list-project-resources`, `get-editor-state`, `run-project`, `stop-project`

This is a genuinely richer *editing* surface than Coding-Solo — it has the read-back
(`get-scene-tree`, `get-node-properties`) that Coding-Solo lacks.

- **Needs the editor running?** **Yes** — it's an `addons/godot_mcp` editor plugin; the Node server
  talks to the live editor.
- **Install:** clone, `cd server && npm install && npm run build`, point Claude at
  `server/dist/index.js`, copy `addons/godot_mcp` into your project, enable in Plugins.

**Verdict:** good idea, dead project. 16 months of Godot releases (4.5, 4.6, 4.7) have shipped
since the last commit. Don't install this on a 4.7 project.

---

## 4. bradypp/godot-mcp and other forks

**bradypp/godot-mcp** — https://github.com/bradypp/godot-mcp — 87 stars, TypeScript, MIT,
**last commit 2025-05-31 (abandoned)**. It is a direct fork/reskin of Coding-Solo (same badges,
same architecture). Adds `edit_node`, `remove_node`, and a `--read-only` mode. Claims Godot 3.5+/4.0+.
Requires clone + `npm run build`. Being a pre-June-2025 fork, it **predates both** Coding-Solo
security fixes. Avoid.

**tugcantopaloglu/godot-mcp** — https://github.com/tugcantopaloglu/godot-mcp — 348 stars, MIT,
**last commit 2026-07-13**, explicitly credits Coding-Solo as its base. **157 tools**, "Requires
Godot 4.4 or later; tested and working with the latest Godot **4.7**". Keeps the CLI/headless
architecture (no editor addon) but adds a TCP runtime-interaction server for live game control:
`game_eval` (arbitrary GDScript in the running game), `game_get_property`/`game_set_property`,
`game_call_method`, `game_get_node_info`, `game_instantiate_scene`, `game_change_scene`,
`game_reparent_node`, `game_connect_signal`, plus `validate_script`/`validate_scripts` for static
GDScript diagnostics and C#/.NET scaffolding. Install is clone + `npm install && npm run build`
(its npm package `@tugcantopaloglu/godot-mcp` is stale at 1.0.0 while the repo is at 3.1.0 — build
from source). This is the best *maintained descendant* of the Coding-Solo lineage.

### The wider 2026 field (none of which were in your list)

| Repo | Stars | Last push | Lang | Notes |
|---|---|---|---|---|
| [hi-godot/godot-ai](https://github.com/hi-godot/godot-ai) | 1,094 | 2026-07-20 | GDScript + Python | ~43 tools / 120+ ops. Godot 4.5+, 4.7 recommended. On Asset Library + Asset Store. Needs `uv`. Editor plugin. |
| [youichi-uda/godot-mcp-pro](https://github.com/youichi-uda/godot-mcp-pro) | 519 | 2026-07-19 | GDScript | 162 tools. **Paid, $15 one-time.** Non-OSI license. |
| [DaxianLee/godot-mcp](https://github.com/DaxianLee/godot-mcp) | 494 | 2026-01-14 | GDScript | Chinese-language, non-OSI license, 6 months stale. |
| [yurineko73/Godot-MCP-Native](https://github.com/yurineko73/Godot-MCP-Native) | 432 | 2026-07-03 | GDScript | MIT. Native GDScript HTTP MCP server, **zero deps — no Node/Python**. |
| [tomyud1/godot-mcp](https://github.com/tomyud1/godot-mcp) | 395 | 2026-04-21 | GDScript | 42 tools, `npx godot-mcp-server`, AssetLib install. |
| [tugcantopaloglu/godot-mcp](https://github.com/tugcantopaloglu/godot-mcp) | 348 | 2026-07-13 | JS/TS | 157 tools, Coding-Solo fork, 4.7-tested. |
| [HaD0Yun/Doyunha-Gopeak](https://github.com/HaD0Yun/Doyunha-Gopeak) | 234 | 2026-07-13 | TypeScript | 95+ tools, requires **Bun**. Tool-profile gating to keep context small. |
| [Glade-tool/glade-mcp](https://github.com/Glade-tool/glade-mcp) | 179 | 2026-07-20 | C# | 235+ tools, Unity **and** Godot. |
| [IvanMurzak/Godot-MCP](https://github.com/IvanMurzak/Godot-MCP) | 178 | 2026-07-20 | C# | Apache-2.0, cloud connection to ai-game.dev. |
| **[satelliteoflove/godot-mcp](https://github.com/satelliteoflove/godot-mcp)** | 126 | 2026-07-17 | GDScript + TS | **21 tools / 86 actions.** Godot 4.5+. Built around agent self-verification. |
| [3ddelano/gdai-mcp-plugin-godot](https://github.com/3ddelano/gdai-mcp-plugin-godot) | 94 | 2026-03-30 | GDScript | No license file. |
| [ryanmazzolini/minimal-godot-mcp](https://github.com/ryanmazzolini/minimal-godot-mcp) | 38 | 2026-07-19 | TypeScript | Tiny: bridges Godot's **LSP** for GDScript validation + DAP console. Complementary. |

---

## 5. Official / Godot-Foundation MCP

**There is none.** Godot 4.7 ("Lights, Camera, Action!",
https://godotengine.org/releases/4.7/) ships no built-in AI assistant or MCP integration.

The thing that *looks* official is the Asset Library / new Asset Store listings —
e.g. Godot AI at https://godotengine.org/asset-library/asset/5050 and
https://store.godotengine.org/asset/dlight/godot-ai/. These are **community submissions to a
hosted catalog, not Foundation endorsements**. Being on AssetLib means it passed submission
review, nothing more. No Foundation-authored or Foundation-blessed MCP server exists as of
2026-07.

---

## 6. Recommendation

**Primary: [satelliteoflove/godot-mcp](https://github.com/satelliteoflove/godot-mcp)**

Reasoning, specific to you:

- **It targets the actual problem.** Every other server is a scene/node CRUD API. This one is built
  around "let the agent verify its own work": freeze the game clock, step exact slices of game time,
  step *until a condition holds*, inject real input (analog stick deflection, key combos, mouse-look),
  then read live entity state back as structured JSON rather than burning vision tokens on screenshots.
  Nothing else in the field has deterministic time-stepping.
- **Godot 4.5+**, actively released (v4.1.0 on 2026-06-20, commits through 2026-07-17), 79 npm
  versions published — real release hygiene, unlike Coding-Solo's single 5-month-old tarball.
- **Read/write split** (`godot_*_read` vs `godot_*_edit`) so you can auto-allow the read tools in
  Claude Code permissions while writes stay gated. 21 tools instead of 157 keeps your context clean.
- Deliberately does **not** duplicate what Claude Code already does well — it doesn't wrap file
  creation, since Claude can write `.tscn` and `.gd` directly. It covers only what files can't:
  editor state, the running game, and binary-encoded TileMap/GridMap cell data.
- Your project is 3D with Jolt Physics; `godot_scene3d` (engine-computed transforms, bounding boxes,
  visibility) and `godot_validate_meshes` are directly relevant.

Install:

```bash
claude mcp add godot-mcp -- npx -y @satelliteoflove/godot-mcp
npx @satelliteoflove/godot-mcp --install-addon /Users/moazessam/Projects/Godot/days-gone
```

Then enable **Project > Project Settings > Plugins > Godot MCP** in the editor.
Requires Node 20+. **Needs the Godot editor open** — the server talks to the addon over a
localhost WebSocket (:6550), and the addon reaches the running game over Godot's debugger protocol.
One editor serves one client at a time.

**Pair it with [ryanmazzolini/minimal-godot-mcp](https://github.com/ryanmazzolini/minimal-godot-mcp)**
(`npx -y @ryanmazzolini/minimal-godot-mcp`) — the two authors explicitly designed them not to
overlap. minimal covers fast static GDScript validation via Godot's LSP and the game console via
DAP; satelliteoflove covers everything needing the editor bridge.

**If you refuse to keep the editor open:** use
[tugcantopaloglu/godot-mcp](https://github.com/tugcantopaloglu/godot-mcp) instead — it's the only
actively-maintained, 4.7-tested server that keeps the pure-CLI architecture (no addon in your
project). Build from source; its npm package is stale.

**Do not install** Coding-Solo (unpatched npm build, no scene read-back, 3 months stale),
ee0pdt (16 months dead, 4.4-era), or bradypp (14 months dead, predates both security fixes) —
despite them being the three you were pointed at.

Also worth noting: your project has no `addons/` directory and Godot isn't on PATH. Any
addon-based server needs the first; every CLI-based server needs the second (set `GODOT_PATH` to
`/Users/moazessam/Downloads/Godot.app/Contents/MacOS/Godot`, or move the app to `/Applications`).

---

## 7. Godot 4.x headless/CLI capabilities (no MCP required)

Sourced from the 4.7 docs + `godotengine/godot` source, then **cross-checked against your own
`/Users/moazessam/Downloads/Godot.app/Contents/MacOS/Godot --help` (4.7.1.stable.official)**.

### What an agent can actually verify from the CLI

| Capability | Verified? | Trustworthy signal |
|---|---|---|
| Run standalone GDScript (`--headless -s res://tool.gd`) | ✅ | your own `print()` / `quit(code)`. Script **must** `extends SceneTree` or `MainLoop` |
| Single-script parse/typecheck (`--check-only -s <file>`) | ✅ | **exit 0/1 is reliable** (`main.cpp:4270`) |
| Project-wide parse errors (`--import`) | ✅ printed | **stderr text only** |
| Project-wide parse errors via exit code | ❌ **impossible** | `main.cpp` has only 3 `set_exit_code(EXIT_FAILURE)` sites, none script-related → **must grep stderr** for `SCRIPT ERROR` / `Parse Error:` |
| Export success/failure (`--export-release`) | ✅ since **Godot 4.3** (PR #89234) | exit code reliable for *export* failure |
| Export failing on script errors | ⚠️ unverified | don't use export as a typechecker |
| GUT tests headless | ✅ | **exit 0 = pass, 1 = fail**; `-gjunit_xml_file` for JUnit XML |
| gdUnit4 tests | ✅ | **0 = pass, 100 = failures, 101 = warnings** (not 1!) |
| gdUnit4 under `--headless` | ⚠️ not the supported path — its own CI uses `xvfb-run` + real OpenGL |
| Frame-bounded run (`--quit-after N`) | ✅ | **N = frames/iterations, NOT seconds** |
| **Screenshot under `--headless`** | ❌ **architecturally impossible** | headless display server advertises only the `"dummy"` rendering driver — confirmed verbatim in your local `--help`: `--display-driver ... "headless" ("dummy")`. The dummy rasterizer's `texture_2d_update` is a no-op, so `get_viewport().get_texture().get_image()` has no pixels |
| Native `--offscreen` rendering | ❌ not shipped | proposal #5790 open, PR #94530 unmerged, milestone `4.x` |
| Screenshot on **Linux** | ⚠️ works via `xvfb-run ... --display-driver x11 --rendering-driver opengl3` | |
| **Screenshot on macOS headlessly** | ❌ **no option exists** | no xvfb equivalent; needs a real window |
| `--write-movie out.avi` | ✅ syntax (OGV/AVI/PNG) | but **needs real rendering**, so same dead-end headlessly. Never SIGINT it — you get a corrupt AVI. `--fixed-fps` is forced; `--quit-after` = frame count |

Confirmed verbatim in your local 4.7.1 help: `--headless` is exactly
`--display-driver headless --audio-driver Dummy`; `-s/--script` and `--check-only` are tagged
**template-unsafe** (editor builds only); all `--export-*` flags are **editor-only**.

### The three things an agent must not assume

1. **Exit code ≠ script health.** Only `--check-only` and export failure give trustworthy codes.
2. **`--headless` can never render.** Not a flag away — it's the dummy rasterizer.
3. **`--quit-after N` is frames, not seconds.** Pair with `--fixed-fps 60` for determinism.

### Baseline loop you get for free, no MCP (works on your Mac)

```bash
G=/Users/moazessam/Downloads/Godot.app/Contents/MacOS/Godot
P=/Users/moazessam/Projects/Godot/days-gone

# import + surface parse errors (grep, don't trust $?)
$G --headless --path "$P" --import 2> /tmp/import.err || true
grep -qE "SCRIPT ERROR|Parse Error:|ERROR:" /tmp/import.err && cat /tmp/import.err

# per-file typecheck ($? IS trustworthy here)
$G --headless --path "$P" --check-only -s res://scripts/player.gd; echo $?

# frame-bounded smoke run
$G --headless --path "$P" --quit-after 300 --fixed-fps 60
```

**Why this matters for the MCP choice:** on macOS you have **no headless visual verification path
at all**. Static checks and tests you get free from the CLI. What you *cannot* get from the CLI on
this machine is a rendered frame, live game state, or input injection — which is precisely the gap
`satelliteoflove/godot-mcp` fills (`godot_editor_read screenshot_game`, `godot_runtime_state`,
`godot_input`, `godot_game_time`). That's the strongest argument for the recommendation in §6:
buy the MCP for the things the CLI structurally cannot do, and keep using the CLI for tests and
typechecking.

Sources: [Command line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) ·
[Creating movies](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html) ·
[main.cpp](https://github.com/godotengine/godot/blob/master/main/main.cpp) ·
[display_server_headless.h](https://github.com/godotengine/godot/blob/master/servers/display/display_server_headless.h) ·
[Proposal #5790](https://github.com/godotengine/godot-proposals/issues/5790) ·
[PR #94530](https://github.com/godotengine/godot/pull/94530) ·
[bitwes/Gut](https://github.com/bitwes/Gut) ·
[GUT CLI docs](https://gut.readthedocs.io/en/latest/Command-Line.html) ·
[godot-gdunit-labs/gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) (note: moved from `MikeSchulze/gdUnit4`)
