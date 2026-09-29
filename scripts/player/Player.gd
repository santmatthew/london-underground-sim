class_name Player
extends CharacterBody3D
## First-person commuter. Layers: 1 = world, 2 = people, 3 = platform-edge guard (blocks the player only).

signal interact_pressed
signal fell(from_pos: Vector3, safe: Vector3)     # emitted just before the fall-safety respawn (diagnostics)

const WALK_SPEED := 1.55        # m/s, ordinary commuter pace
const HURRY_SPEED := 2.6        # brisk walk (Shift), drains stamina
const RUN_SPEED := 3.6          # jog/run while stamina lasts (Shift + Ctrl)
const EYE_HEIGHT := 1.66
const GRAVITY := 18.0

var cam: Camera3D
var head: Node3D
var mouse_sens := 0.0022
var stamina := 1.0
var speed_mult := 1.0           # set by crowd drag
var frozen := false             # e.g. while seated / cutscene
var enabled := true
var _bob := 0.0
var _yaw := 0.0
var _pitch := 0.0
var look_target := Vector3.ZERO
var last_speed := 0.0
var hurrying := false
var safe_pos := Vector3.ZERO
var respawn_provider := Callable()      # (safe_pos) -> Vector3: where to put the player after a fall (the game knows what floor still exists)
var _safe_t := 0.0
var sway := 0.0                  # carriage sway amount (0 = off), set while riding
var _sway_t := 0.0
var step_accum := 0.0
var surface := "concrete"
var footsteps_enabled := true
var bot_active := false          # autopilot drives movement
var bot_move := Vector2.ZERO     # x strafe, y forward(-)/back(+)
var bot_hurry := false
var bot_yaw_target := 0.0
var bot_pitch_target := 0.0


func _ready() -> void:
	collision_layer = 1 << 3            # layer 4: player body (NPCs avoid)
	collision_mask = 1 | (1 << 1) | (1 << 2)
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50)
	safe_margin = 0.01
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.27
	cap.height = 1.76
	cs.shape = cap
	cs.position.y = 0.88
	add_child(cs)
	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 78.0
	cam.near = 0.05
	cam.far = 400.0
	head.add_child(cam)
	cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sens
		_pitch = clampf(_pitch - event.relative.y * mouse_sens, deg_to_rad(-85), deg_to_rad(85))
		rotation.y = _yaw
		head.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			interact_pressed.emit()


func face(dir: Vector3) -> void:
	_yaw = atan2(-dir.x, -dir.z)
	rotation.y = _yaw
	_pitch = 0.0
	head.rotation.x = 0.0


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var input := Vector2.ZERO
	if bot_active:
		input = bot_move
		_yaw = lerp_angle(_yaw, bot_yaw_target, clampf(delta * 3.2, 0.0, 1.0))
		rotation.y = _yaw
		_pitch = lerpf(_pitch, bot_pitch_target, clampf(delta * 2.5, 0.0, 1.0))
		head.rotation.x = _pitch
	elif not frozen:
		input = _read_keys()
	var dir := (global_transform.basis * Vector3(input.x, 0, input.y)).normalized() if input.length() > 0.01 else Vector3.ZERO
	var speed := WALK_SPEED
	hurrying = false
	if (Input.is_key_pressed(KEY_SHIFT) or bot_hurry) and stamina > 0.05 and input.length() > 0.1:
		speed = RUN_SPEED if Input.is_key_pressed(KEY_CTRL) else HURRY_SPEED
		stamina = maxf(0.0, stamina - delta * (0.11 if speed == HURRY_SPEED else 0.22))
		hurrying = true
	else:
		stamina = minf(1.0, stamina + delta * 0.09)
	speed *= speed_mult
	if input.y > 0.1:
		speed *= 0.6     # backpedalling is slow
	var target := dir * speed
	var accel := 14.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = maxf(velocity.y, -0.5)
	move_and_slide()
	# safety net: if we ever fall out of the world, go back to the last solid ground
	if is_on_floor():
		_safe_t -= delta
		if _safe_t <= 0.0:
			_safe_t = 0.4
			safe_pos = global_position
	elif safe_pos != Vector3.ZERO and global_position.y < safe_pos.y - 30.0:
		fell.emit(global_position, safe_pos)
		global_position = respawn_provider.call(safe_pos) if respawn_provider.is_valid() else safe_pos + Vector3(0, 0.3, 0)
		velocity = Vector3.ZERO
		push_warning("Player fell out of the world at %s (safe %s) - respawned" % [str(global_position.snapped(Vector3(0.01, 0.01, 0.01))), str(safe_pos.snapped(Vector3(0.01, 0.01, 0.01)))])
	last_speed = Vector2(get_real_velocity().x, get_real_velocity().z).length()
	# footsteps
	if is_on_floor() and last_speed > 0.4 and footsteps_enabled:
		step_accum += last_speed * delta
		if step_accum > 0.78:
			step_accum = 0.0
			Sfx.footstep(surface, -3.0 if last_speed < 2.0 else 0.0)
	# carriage sway while riding
	_sway_t += delta
	if sway > 0.001:
		head.rotation.z = sin(_sway_t * 1.7) * 0.0025 * sway + sin(_sway_t * 5.3 + 1.0) * 0.0012 * sway
	else:
		head.rotation.z = lerpf(head.rotation.z, 0.0, delta * 4.0)
	# head bob
	if is_on_floor() and last_speed > 0.2:
		_bob += delta * last_speed * 4.4
		head.position.y = EYE_HEIGHT + sin(_bob * 2.0) * 0.022 * clampf(last_speed / 2.0, 0.3, 1.5)
		head.position.x = cos(_bob) * 0.012
	else:
		head.position.y = lerpf(head.position.y, EYE_HEIGHT, delta * 8.0)
		head.position.x = lerpf(head.position.x, 0.0, delta * 8.0)


func _read_keys() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	return v.limit_length(1.0)


func eye_pos() -> Vector3:
	return head.global_position


func forward() -> Vector3:
	return -cam.global_transform.basis.z
