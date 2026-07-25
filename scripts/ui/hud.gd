extends CanvasLayer

# Minimal M4 HUD: mag/reserve counter plus a centre-dot reticle that only
# shows in ADS (docs/r1-player-handling.md: reticle-only-in-ADS). Deliberately
# bare — real UI assets (Kenney pack) arrive with Phase 4's build session.

@onready var _ammo: Label = $Ammo
@onready var _reticle: Control = $Reticle
@onready var _weapons: WeaponManager = $"../WeaponManager"
@onready var _camera_rig: Node3D = $"../CameraRig"


func _ready() -> void:
	_weapons.ammo_changed.connect(_on_ammo_changed)
	# The manager's _ready (and its first ammo_changed) ran before this node
	# existed in signal reach — pull the first frame's numbers directly.
	var a := _weapons.ammo()
	_on_ammo_changed(a.x, a.y)


func _process(_delta: float) -> void:
	_reticle.visible = _camera_rig.ads


func _on_ammo_changed(mag: int, reserve: int) -> void:
	_ammo.text = "%d / %d" % [mag, reserve]
