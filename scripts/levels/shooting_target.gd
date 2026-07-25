extends StaticBody3D

# Test-range target: flashes on a hit so the playtest can SEE shots land
# (impact decals/particles are Phase 9). The WeaponManager's hitscan calls
# on_shot() on any collider that has it.

const FLASH_TIME := 0.12

var _flash_left := 0.0
var _flash_mat := StandardMaterial3D.new()

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	_flash_mat.albedo_color = Color(1.0, 0.85, 0.4)
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(1.0, 0.7, 0.25)
	_flash_mat.emission_energy_multiplier = 1.6
	set_process(false)


func on_shot(_point: Vector3, _normal: Vector3, _damage: float) -> void:
	# material_override, not the shared mesh material — the three targets
	# share one sub-resource and must flash individually.
	_mesh.material_override = _flash_mat
	_flash_left = FLASH_TIME
	set_process(true)


func _process(delta: float) -> void:
	_flash_left -= delta
	if _flash_left <= 0.0:
		_mesh.material_override = null
		set_process(false)
