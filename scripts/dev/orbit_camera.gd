extends Camera3D

## Dev inspection camera: orbit, zoom and pan around a fixed point.
##
## Exists so pose and grip work can be judged by eye without editing the scene
## or asking anyone to fly a camera by hand. Every phase from here on is gated
## on "does this look right", so looking has to be cheap.
##
## Controls
##   Left-drag ............ orbit
##   Right-drag / Shift ... pan the focus point
##   Scroll ............... zoom
##   R .................... reset to the default framing
##   1 / 2 / 3 ............ snap to hands / upper body / full body
##
## Not gameplay code. Phase 2's real player camera is a separate SpringArm3D
## rig; this one is only ever attached to test scenes.

# focus, distance, yaw, pitch, fov — what the number keys snap to.
# A narrow FOV up close keeps the grip readable; a wide one at this distance
# fisheyes the hands and makes the pose impossible to judge.
const VIEWS := {
	KEY_1: [Vector3(-0.02, 1.40, 0.42), 0.70, 38.0, -4.0, 32.0],  # hands / grip
	KEY_2: [Vector3(0.0, 1.30, 0.20), 2.10, 24.0, -5.0, 45.0],    # upper body
	KEY_3: [Vector3(0.0, 0.95, 0.00), 4.20, 14.0, -4.0, 50.0],    # full body
}

@export var focus: Vector3 = Vector3(0.0, 1.30, 0.20)
@export var distance: float = 2.1
@export var yaw_deg: float = 24.0
@export var pitch_deg: float = -5.0
@export var fov_deg: float = 45.0

@export var orbit_sensitivity: float = 0.35
@export var pan_sensitivity: float = 0.0022
@export var zoom_step: float = 0.12
@export var min_distance: float = 0.25
@export var max_distance: float = 12.0

var _default: Array = []
var _orbiting := false
var _panning := false


func _ready() -> void:
	_default = [focus, distance, yaw_deg, pitch_deg, fov_deg]
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(-zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(zoom_step)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning or (_orbiting and mm.shift_pressed):
			# Pan in the camera's own plane so dragging feels screen-relative.
			var scale := pan_sensitivity * distance
			focus -= global_transform.basis.x * mm.relative.x * scale
			focus += global_transform.basis.y * mm.relative.y * scale
			_apply()
		elif _orbiting:
			yaw_deg -= mm.relative.x * orbit_sensitivity
			pitch_deg = clampf(pitch_deg - mm.relative.y * orbit_sensitivity, -89.0, 89.0)
			_apply()

	elif event is InputEventKey and (event as InputEventKey).pressed:
		var key := (event as InputEventKey).keycode
		if key == KEY_R:
			focus = _default[0]
			distance = _default[1]
			yaw_deg = _default[2]
			pitch_deg = _default[3]
			fov_deg = _default[4]
			_apply()
		elif VIEWS.has(key):
			var v: Array = VIEWS[key]
			focus = v[0]
			distance = v[1]
			yaw_deg = v[2]
			pitch_deg = v[3]
			fov_deg = v[4]
			_apply()


func _zoom(amount: float) -> void:
	# Proportional zoom, so it stays controllable both up close and far out.
	distance = clampf(distance * (1.0 + amount), min_distance, max_distance)
	_apply()


func _apply() -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		-sin(pitch),
		cos(yaw) * cos(pitch)
	) * distance
	global_position = focus + offset
	look_at(focus, Vector3.UP)
	fov = fov_deg
