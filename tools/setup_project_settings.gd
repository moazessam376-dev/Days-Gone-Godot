extends SceneTree

# Writes the project's input map and physics layer names into project.godot.
#
# Run with the Godot EDITOR CLOSED, otherwise the editor's stale in-memory
# ProjectSettings will overwrite this on quit:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
#       --script tools/setup_project_settings.gd
#
# Sources of truth:
#   - input map      -> docs/r1-player-handling.md ("Complete control map")
#   - physics layers -> docs/collision-matrix.md ("Layers")
# If either doc changes, change it here too. Do not hand-edit project.godot.

# Layer bit -> name. Mirrors docs/collision-matrix.md exactly.
const LAYERS := {
	1: "static",      # terrain, buildings, trees, crates
	2: "player",      # the player's character body
	3: "enemy",       # zombie capsules + head balls
	4: "ragdoll",     # corpse bodies
	5: "vehicle",     # car + bike chassis
	6: "projectile",  # grenades/molotovs + hitscan rays
	7: "camera",      # camera occlusion cast (query only)
}


func _init() -> void:
	_set_layers()
	_set_input_map()
	_set_misc()

	var err := ProjectSettings.save()
	print("SAVE_ERR=", err)
	if err != OK:
		quit(1)
		return
	_report()
	quit(0)


func _set_layers() -> void:
	for bit: int in LAYERS:
		ProjectSettings.set_setting("layer_names/3d_physics/layer_%d" % bit, LAYERS[bit])


func _set_input_map() -> void:
	# Movement is on PHYSICAL keycodes so WASD stays WASD on non-QWERTY layouts.
	_action("move_forward", [_key(KEY_W)])
	_action("move_back", [_key(KEY_S)])
	_action("move_left", [_key(KEY_A)])
	_action("move_right", [_key(KEY_D)])

	# Aim-to-shoot: fire only resolves while aiming (enforced in gameplay code,
	# not here). F is an aim alias -- a trackpad cannot hold a two-finger press
	# and click at the same time. Both from the r1 spec.
	_action("fire", [_mb(MOUSE_BUTTON_LEFT)])
	_action("aim", [_mb(MOUSE_BUTTON_RIGHT), _key(KEY_F)])

	_action("sprint", [_key(KEY_SHIFT)])
	_action("roll", [_key(KEY_SPACE)])
	_action("reload", [_key(KEY_R)])
	_action("interact", [_key(KEY_E)])
	_action("melee", [_key(KEY_V)])
	_action("shoulder_swap", [_key(KEY_Q)])
	_action("respawn", [_key(KEY_ENTER)])
	_action("pause", [_key(KEY_ESCAPE)])

	# Weapon wheel is a HELD action; releasing it equips the highlighted sector.
	_action("weapon_wheel", [_key(KEY_TAB)])
	_action("weapon_1", [_key(KEY_1)])
	_action("weapon_2", [_key(KEY_2)])
	_action("weapon_3", [_key(KEY_3)])
	_action("weapon_next", [_mb(MOUSE_BUTTON_WHEEL_DOWN)])
	_action("weapon_prev", [_mb(MOUSE_BUTTON_WHEEL_UP)])


func _set_misc() -> void:
	ProjectSettings.set_setting("display/window/size/viewport_width", 1600)
	ProjectSettings.set_setting("display/window/size/viewport_height", 900)
	# The game is mouse-look driven; gameplay code captures the mouse itself.
	ProjectSettings.set_setting("input_devices/pointing/emulate_touch_from_mouse", false)


func _action(name: String, events: Array) -> void:
	var d := {"deadzone": 0.2, "events": events}
	ProjectSettings.set_setting("input/" + name, d)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mb(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _report() -> void:
	print("--- physics layers ---")
	for bit: int in LAYERS:
		var k := "layer_names/3d_physics/layer_%d" % bit
		print("  %d  %s" % [bit, ProjectSettings.get_setting(k)])

	print("--- input actions ---")
	var names: Array[String] = []
	for p in ProjectSettings.get_property_list():
		var n: String = p.name
		if n.begins_with("input/"):
			names.append(n.substr(6))
	names.sort()
	for n in names:
		var evs: Array = ProjectSettings.get_setting("input/" + n)["events"]
		var parts: Array[String] = []
		for e in evs:
			if e is InputEventKey:
				parts.append(OS.get_keycode_string((e as InputEventKey).physical_keycode))
			elif e is InputEventMouseButton:
				parts.append("Mouse%d" % (e as InputEventMouseButton).button_index)
		print("  %-16s %s" % [n, ", ".join(parts)])
	print("ACTION_COUNT=", names.size())
