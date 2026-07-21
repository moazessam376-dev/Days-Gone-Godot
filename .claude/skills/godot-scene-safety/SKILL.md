---
name: godot-scene-safety
description: Read BEFORE editing any .tscn, .tres or project.godot file in this project, or before running a tool that regenerates a scene. Covers the four ways scene edits silently vanish or load wrong - editor overwrite, Transform3D transposition, instanced-scene duplication, and generator overwrite. Every one of these has already cost this project real time.
---

# Editing Godot scene files without losing work

Four failure modes, all of which have already bitten this project. None of them
produce an error message. All of them look like something else went wrong.

## 1. The editor overwrites external edits

**Godot holds an open scene in memory and writes its own copy on save.** If you
edit the `.tscn` on disk while the editor has it open, your edits are silently
discarded the moment anything triggers a save.

This destroyed the left-arm IK, the elbow pole and the support-hand tuner in one
go. The next run came up with **no character at all**, which reads like a
totally different bug.

Same hazard applies to `project.godot`: the editor rewrites it on quit, so
settings written externally while it runs are lost.

**Rules:**
- Prefer `godot_node_edit` / `godot_scene save` via the MCP — the editor is then
  the only writer.
- If you must edit scene text directly while the editor runs, call
  `godot_scene reload` **immediately** afterwards so the editor re-reads disk.
- For `project.godot`, edit with the editor **closed**, or use
  `godot_project check_stale` + restart.
- To add or remove NODES you must edit the `.tscn` text (the MCP can only update
  existing node properties) — so this rule matters constantly.

**Symptom:** a node you just added is missing, or a value reverted, or the scene
loads with entire branches absent.

## 2. Transform3D serialises COLUMN-wise

In `.tscn` text, `Transform3D(a,b,c, d,e,f, g,h,i, ox,oy,oz)` maps to
**columns**, not to `basis.x`, `basis.y`, `basis.z`.

Writing `b.x.x, b.x.y, b.x.z, b.y.x, ...` loads **transposed**, which silently
rotates the object. A weapon calibrated correctly in code appeared 90 degrees
out once baked, and looked like a bad calibration rather than a bad write.

Correct text order is `(x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z, ...)`.

**Rule:** never hand-serialise a Transform3D. In GDScript build a
`Basis(x_vec, y_vec, z_vec)` from vectors. If you must write scene text, verify
by reading the value back out of the running game and comparing to what you
intended.

## 3. Re-owning children of an instanced scene duplicates them

A node with a non-empty `scene_file_path` is the root of its own packed scene.
Recursing into it and reassigning `owner` makes `PackedScene.pack()` write its
children out a **second** time — you get the instance plus a flattened copy on
top of it.

The flattened copy has no animation library, so the character renders in bind
pose. This is what produced the "T-pose that would not go away" while every
headless check passed.

**Rule:** when walking a tree to assign owners, stop at any node with a
`scene_file_path`.

```gdscript
func _own_all(node: Node, owner_node: Node) -> void:
    for c in node.get_children():
        c.owner = owner_node
        if c.scene_file_path.is_empty():   # do not descend into instances
            _own_all(c, owner_node)
```

**Symptom:** a scene file far larger than it should be. `test_character.tscn`
was 4682 lines with the whole mesh inlined; correct is 46 lines referencing the
character.

## 4. Generated scenes overwrite hand-tuning

`tools/build_character.gd` **regenerates** `scenes/characters/hunter.tscn` and
`scenes/test_character.tscn` wholesale.

Anything tuned by hand in the editor is lost on the next rebuild unless it has
been baked back into the generator's constants.

**Rule:** after the user tunes anything in the editor, read the values out of the
`.tscn` and write them into `tools/build_character.gd`, then record them with
their *reason* in `docs/rig-tuning.md`. See the pose-tuning workflow in
`CLAUDE.md`.

## Also worth knowing

- **`.import` files must be committed.** They carry each asset's resource UID;
  without them a fresh clone re-imports and generates new UIDs, breaking every
  scene reference.
- **Re-running a config tool that patches `.import` files appends a second
  options block**, and the stale one wins. Delete and regenerate the `.import`
  files rather than patching twice.
- **Godot normalising a scene is not a clobber.** Adding `uid=`, `unique_id=`,
  or resolving bone names to indices is the editor agreeing with you. Check what
  changed before assuming damage.
