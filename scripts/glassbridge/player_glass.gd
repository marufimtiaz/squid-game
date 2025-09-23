# ProtoController v1.0 by Brackeys
# CC0 License
# Intended for rapid prototyping of first-person games.
# Happy prototyping!

extends CharacterBody3D
@onready var animation_player: AnimationPlayer = $Remy/AnimationPlayer

## Can we move around?
@export var can_move : bool = true
## Are we affected by gravity?
@export var has_gravity : bool = true
## Can we press to jump?
@export var can_jump : bool = true
## Can we hold to run?
@export var can_sprint : bool = false
## Can we press to enter freefly mode (noclip)?
@export var can_freefly : bool = false

@export_group("Speeds")
## Look around rotation speed.
@export var look_speed : float = 0.002
## Normal speed.
@export var base_speed : float = 5.0
## Speed of jump.
@export var jump_velocity : float = 4
## How fast do we run?
@export var sprint_speed : float = 10.0
## How fast do we freefly?
@export var freefly_speed : float = 25.0

@export_group("Input Actions")
## Name of Input Action to move Left.
@export var input_cancel : String = "ui_cancel"
## Name of Input Action to move Left.
@export var input_left : String = "ui_left"
## Name of Input Action to move Right.
@export var input_right : String = "ui_right"
## Name of Input Action to move Forward.
@export var input_forward : String = "ui_up"
## Name of Input Action to move Backward.
@export var input_back : String = "ui_down"
## Name of Input Action to Jump.
@export var input_jump : String = "ui_accept"
## Name of Input Action to Sprint.
@export var input_sprint : String = "sprint"
## Name of Input Action to toggle freefly mode.
@export var input_freefly : String = "freefly"

var mouse_captured : bool = false
var look_rotation : Vector2
var move_speed : float = 0.0
var freeflying : bool = false
var jump_start_time : float = 0.0
var is_jump_starting : bool = false

var idle_anim = "Remyanims/Idle"
var walk_anim = "Remyanims/Walk"
var jump_anim = "Remyanims/Jump"
var fall_anim = "Remyanims/Falling"
var fallimpact_anim = "Remyanims/FallingFlatImpact"
var victory_anim = "Remyanims/Victory"

# Animation state tracking
enum PlayerState { IDLE, WALKING, JUMPING, FALLING, IMPACT, VICTORY }
var current_state: PlayerState = PlayerState.IDLE
var was_on_floor: bool = true
var jump_time: float = 0.0
var falling_time: float = 0.0

# Signals for better communication
signal player_hit_killzone
signal player_victory_started
signal fallimpact_finished
signal victory_finished
	


## IMPORTANT REFERENCES
@onready var head: Node3D = $Head
@onready var collider: CollisionShape3D = $Collider

func freeze():
	can_move = false
	velocity.x = 0
	velocity.y = 0
	
func slow():
	move_speed = base_speed/3

func play_fallimpact():
	"""Play the fallimpact animation and emit signal for killzone handling"""
	if current_state == PlayerState.IMPACT:
		print("Already in IMPACT state - ignoring fallimpact request")
		return
		
	print("Playing Fallimpact Animation.")
	set_player_state(PlayerState.IMPACT)
	animation_player.play(fallimpact_anim)
	animation_player.seek(0.4, true)
	player_hit_killzone.emit()
	# Freeze player after impact
	call_deferred("freeze")

func play_victory():
	"""Play the victory animation"""
	if current_state == PlayerState.VICTORY:
		print("Already in VICTORY state - ignoring victory request")
		return
		
	print("Playing Victory Animation.")
	set_player_state(PlayerState.VICTORY)
	# can_move = false
	animation_player.play(victory_anim)
	player_victory_started.emit()

func set_player_state(new_state: PlayerState):
	"""Centralized state management with logging"""
	if current_state != new_state:
		print("Player state: ", PlayerState.keys()[current_state], " -> ", PlayerState.keys()[new_state])
		current_state = new_state

func play_idle():
	if current_state != PlayerState.IDLE:
		set_player_state(PlayerState.IDLE)
		animation_player.speed_scale = 1.0
		animation_player.play(idle_anim)

func play_walk():
	if current_state != PlayerState.WALKING:
		set_player_state(PlayerState.WALKING)
		animation_player.speed_scale = 1.0
		animation_player.play(walk_anim)
	# Keep the walk animation looping while in walking state
	elif animation_player.current_animation != walk_anim:
		animation_player.speed_scale = 1.0
		animation_player.play(walk_anim)
	
func play_jump():
	print("Playing Jump Animation")
	set_player_state(PlayerState.JUMPING)
	animation_player.play(jump_anim)
	animation_player.speed_scale = 0.9
	animation_player.seek(0.4, true)
	
func play_falling():
	if current_state != PlayerState.FALLING:
		print("Playing Falling Animation")
		set_player_state(PlayerState.FALLING)
		animation_player.speed_scale = 1.0
		animation_player.play(fall_anim)
	
func _ready() -> void:
	check_input_mappings()
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	
	# Connect animation finished signal
	animation_player.animation_finished.connect(_on_animation_finished)
	
	animation_player.play(idle_anim)

func _on_animation_finished(animation_name: StringName):
	"""Handle animation completion events"""
	print("Animation finished: ", animation_name)
	match animation_name:
		fallimpact_anim:
			fallimpact_finished.emit()
		victory_anim:
			victory_finished.emit()
		walk_anim:
			# Don't auto-transition from walk - let _update_animation_state handle it
			pass
		jump_anim:
			# Don't auto-transition from jump - let _update_animation_state handle it
			pass
		fall_anim:
			# Don't auto-transition from fall - let _update_animation_state handle it
			pass
		idle_anim:
			# Don't auto-transition from idle - let _update_animation_state handle it
			pass

func _unhandled_input(event: InputEvent) -> void:
	# Mouse capturing
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		capture_mouse()
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()
	
	# Look around
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)
	
	# Toggle freefly mode
	if can_freefly and Input.is_action_just_pressed(input_freefly):
		if not freeflying:
			enable_freefly()
		else:
			disable_freefly()

func _physics_process(delta: float) -> void:
	# Track floor state for fall detection
	var current_on_floor = is_on_floor()
	
	# If freeflying, handle freefly and nothing else
	if can_freefly and freeflying:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var motion := (head.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		motion *= freefly_speed * delta
		move_and_collide(motion)
		return
	
	# Don't process movement if in special states
	if current_state == PlayerState.IMPACT or current_state == PlayerState.VICTORY:
		move_and_slide()
		return
	
	# Apply gravity to velocity
	if has_gravity:
		if not current_on_floor:
			velocity += get_gravity() * delta

	# Track timing for animation transitions
	if not current_on_floor and velocity.y < 0:
		falling_time += delta
	else:
		falling_time = 0.0

	# Track jump time for fall transition
	if current_state == PlayerState.JUMPING and not current_on_floor:
		jump_time += delta

	# Modify speed based on sprinting
	if can_sprint and Input.is_action_pressed(input_sprint):
			move_speed = sprint_speed
	else:
		move_speed = base_speed

	# Apply desired movement to velocity
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if move_dir:
			velocity.x = move_dir.x * move_speed
			velocity.z = move_dir.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
	else:
		velocity.x = 0
		velocity.y = 0
	
	# Handle animation state transitions based on current state and conditions
	var movement_input := Input.get_vector(input_left, input_right, input_forward, input_back)
	var has_movement_input = movement_input.length() > 0
	var jump_pressed = can_jump and Input.is_action_just_pressed(input_jump)
	_update_animation_state(current_on_floor, has_movement_input, jump_pressed, delta)
	
	# Store previous floor state
	was_on_floor = current_on_floor
	
	# Use velocity to actually move
	move_and_slide()

func _update_animation_state(on_floor: bool, has_movement_input: bool, jump_pressed: bool, _delta: float):
	"""Centralized animation state logic"""
	
	# Handle jump input - highest priority
	if jump_pressed and on_floor:
		velocity.y = jump_velocity
		jump_time = 0.0
		play_jump()
		return
	
	match current_state:
		PlayerState.IDLE, PlayerState.WALKING:
			if not on_floor:
				# Started falling (walked off or platform disappeared)
				if velocity.y < -1.0:
					play_falling()
			elif on_floor and can_move:
				if has_movement_input:
					play_walk()
				else:
					play_idle()
		
		PlayerState.JUMPING:
			# Stay in jumping state until we transition to falling or land
			if jump_time > 0.4 and velocity.y < -4.5:
				# Transition from jump to fall
				play_falling()
			elif on_floor:
				# Landed - check if moving or idle
				if can_move and has_movement_input:
					play_walk()
				else:
					play_idle()
			# If still jumping (on_floor=false, jump_time<=0.3, velocity.y>=-1.0), stay in JUMPING
		
		PlayerState.FALLING:
			if on_floor:
				# Landed - check if moving or idle
				if can_move and has_movement_input:
					play_walk()
				else:
					play_idle()
		
		PlayerState.IMPACT, PlayerState.VICTORY:
			# These states are terminal - don't transition automatically
			pass


## Rotate us to look around.
## Base of controller rotates around y (left/right). Head rotates around x (up/down).
## Modifies look_rotation based on rot_input, then resets basis and rotates by look_rotation.
func rotate_look(rot_input : Vector2):
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
	look_rotation.y -= rot_input.x * look_speed
	transform.basis = Basis()
	rotate_y(look_rotation.y)
	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)


func enable_freefly():
	collider.disabled = true
	freeflying = true
	velocity = Vector3.ZERO

func disable_freefly():
	collider.disabled = false
	freeflying = false


func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


## Checks if some Input Actions haven't been created.
## Disables functionality accordingly.
func check_input_mappings():
	if can_move and not InputMap.has_action(input_left):
		push_error("Movement disabled. No InputAction found for input_left: " + input_left)
		can_move = false
	if can_move and not InputMap.has_action(input_right):
		push_error("Movement disabled. No InputAction found for input_right: " + input_right)
		can_move = false
	if can_move and not InputMap.has_action(input_forward):
		push_error("Movement disabled. No InputAction found for input_forward: " + input_forward)
		can_move = false
	if can_move and not InputMap.has_action(input_back):
		push_error("Movement disabled. No InputAction found for input_back: " + input_back)
		can_move = false
	if can_jump and not InputMap.has_action(input_jump):
		push_error("Jumping disabled. No InputAction found for input_jump: " + input_jump)
		can_jump = false
	if can_sprint and not InputMap.has_action(input_sprint):
		push_error("Sprinting disabled. No InputAction found for input_sprint: " + input_sprint)
		can_sprint = false
	if can_freefly and not InputMap.has_action(input_freefly):
		push_error("Freefly disabled. No InputAction found for input_freefly: " + input_freefly)
		can_freefly = false
