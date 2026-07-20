extends SceneTree
func _init():
	var want := ["move_forward","move_back","move_left","move_right","fire","aim","sprint",
		"roll","reload","interact","melee","shoulder_swap","respawn","pause",
		"weapon_wheel","weapon_1","weapon_2","weapon_3","weapon_next","weapon_prev"]
	var bad := 0
	for a in want:
		if not InputMap.has_action(a):
			print("MISSING ACTION: ", a); bad += 1
	print("ACTIONS_OK=", want.size() - bad, "/", want.size())
	print("aim events=", InputMap.action_get_events("aim").size())
	var layers := ["static","player","enemy","ragdoll","vehicle","projectile","camera"]
	for i in layers.size():
		var got: String = ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % (i+1), "")
		if got != layers[i]:
			print("LAYER MISMATCH ", i+1, " got=", got); bad += 1
	print("LAYERS_OK=", layers.size())
	print("physics_engine=", ProjectSettings.get_setting("physics/3d/physics_engine",""))
	quit(1 if bad > 0 else 0)
