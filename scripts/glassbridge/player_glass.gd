# ProtoController v1.0 by Brackeys
# CC0 License
# Intended for rapid prototyping of first-person games.
# Happy prototyping!

extends CharacterBody3D
@onready var animation_player: AnimationPlayer = $Remy/AnimationPlayer

# Player identification for multiplayer support
@export var player_id: int = 1
@export var player_name: String = "Player 1"

# Step 7: Reference to PlayerManager for UI state checking
var player_manager: PlayerManager

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

# mouse_captured is no longer used (Step 5: moved to scene level)
# var mouse_captured : bool = false
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
enum PlayerState { IDLE, WALKING, JUMPING, FALLING, IMPACT, VICTORY, WON_WAITING }
@export var current_state: PlayerState = PlayerState.IDLE
var was_on_floor: bool = true
var jump_time: float = 0.0
var falling_time: float = 0.0

# Signals for better communication (now include player_id for multiplayer)
signal player_hit_killzone(player_id: int)
signal player_victory_started(player_id: int)
signal fallimpact_finished(player_id: int)
signal victory_finished(player_id: int)
	


## IMPORTANT REFERENCES
@onready var head: Node3D = $Head
@onready var collider: CollisionShape3D = $Collider

# Helper function for consistent player logging
func log_player(message: String):
	print("[Player ", player_id, " - ", player_name, "] ", message)

func freeze():
	can_move = false
	velocity.x = 0
	velocity.y = 0
	log_player("Player frozen")
	
func slow():
	move_speed = base_speed/3
	log_player("Player movement slowed")

func play_fallimpact():
	"""Play the fallimpact animation and emit signal for killzone handling"""
	if current_state == PlayerState.IMPACT:
		log_player("Already in IMPACT state - ignoring fallimpact request")
		return
		
	log_player("Playing Fallimpact Animation")
	set_player_state(PlayerState.IMPACT)
	animation_player.play(fallimpact_anim)
	animation_player.seek(0.2, true)
	player_hit_killzone.emit(player_id)
	# Freeze player after impact
	call_deferred("freeze")

func play_victory():
	"""Play the victory animation"""
	if current_state == PlayerState.VICTORY:
		log_player("Already in VICTORY state - ignoring victory request")
		return
		
	log_player("Playing Victory Animation")
	set_player_state(PlayerState.VICTORY)
	can_move = false
	velocity = Vector3.ZERO  # Stop all movement immediately
	animation_player.play(victory_anim)
	player_victory_started.emit(player_id)

func handle_goal_reached():
	"""Handle when player reaches goal - set won state but wait for landing before victory animation"""
	if current_state == PlayerState.VICTORY or current_state == PlayerState.WON_WAITING:
		log_player("Already won - ignoring goal reached")
		return
	
	log_player("Player reached goal! Setting won state...")
	# Stop movement immediately
	can_move = false
	velocity.x = 0
	velocity.z = 0
	
	# If player is on ground, play victory immediately
	if is_on_floor():
		play_victory()
	else:
		# If in air, wait for landing
		set_player_state(PlayerState.WON_WAITING)
		log_player("Player in air - waiting for landing before victory animation")

func set_player_state(new_state: PlayerState):
	"""Centralized state management with logging"""
	if current_state != new_state:
		log_player("State: " + PlayerState.keys()[current_state] + " -> " + PlayerState.keys()[new_state])
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
	log_player("Playing Jump Animation")
	set_player_state(PlayerState.JUMPING)
	animation_player.play(jump_anim)
	animation_player.speed_scale = 0.9
	animation_player.seek(0.4, true)
	
func play_falling():
	if current_state != PlayerState.FALLING:
		log_player("Playing Falling Animation")
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
	
	# Mouse capture is now handled by main scene (Step 5)
	
	# Setup animation sync for remote players
	if not is_multiplayer_authority():
		# For remote players, monitor state changes and sync animations
		# Use a timer to periodically check for state changes
		var sync_timer = Timer.new()
		sync_timer.wait_time = 0.1
		sync_timer.timeout.connect(_sync_remote_animation)
		sync_timer.autostart = true
		add_child(sync_timer)

func _on_animation_finished(animation_name: StringName):
	"""Handle animation completion events"""
	log_player("Animation finished: " + str(animation_name))
	match animation_name:
		fallimpact_anim:
			fallimpact_finished.emit(player_id)
		victory_anim:
			victory_finished.emit(player_id)
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

var last_synced_state: PlayerState = PlayerState.IDLE

func _sync_remote_animation():
	"""Sync animation for remote players based on synchronized current_state"""
	if is_multiplayer_authority():
		return  # Only remote players need to sync
	
	if current_state != last_synced_state:
		log_player("Syncing animation for remote player - state: " + PlayerState.keys()[current_state])
		last_synced_state = current_state
		
		# Play the appropriate animation based on synced state
		match current_state:
			PlayerState.IDLE:
				animation_player.play(idle_anim)
			PlayerState.WALKING:
				animation_player.play(walk_anim)
			PlayerState.JUMPING:
				animation_player.play(jump_anim)
			PlayerState.FALLING:
				animation_player.play(fall_anim)
			PlayerState.IMPACT:
				animation_player.play(fallimpact_anim)
			PlayerState.VICTORY, PlayerState.WON_WAITING:
				animation_player.play(victory_anim)

func _unhandled_input(event: InputEvent) -> void:
	# Don't process input if game is paused
	if get_tree().paused:
		return
	
	# Step 9: Only local authority player gets input (multiplayer compatible)
	if not is_multiplayer_authority():
		return
	
	# Step 7: Don't process input if player has menu open
	if player_manager and not player_manager.is_player_playing(player_id):
		return
		
	# Look around (mouse capture is now handled by main scene)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		rotate_look(event.relative)
	
	# Toggle freefly mode
	if can_freefly and Input.is_action_just_pressed(input_freefly):
		if not freeflying:
			enable_freefly()
		else:
			disable_freefly()

func _physics_process(delta: float) -> void:
	# Don't process physics if game is paused
	if get_tree().paused:
		return
	
	# Step 9: Only local authority player gets input (multiplayer compatible)
	if not is_multiplayer_authority():
		# Other players still need physics (gravity, etc) but no input
		if has_gravity and not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return
	
	# Step 7: Don't process input if player has menu open
	if player_manager and not player_manager.is_player_playing(player_id):
		return
		
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
	
	# Handle won waiting state - allow gravity but no horizontal movement
	if current_state == PlayerState.WON_WAITING:
		# Apply gravity to let player land
		if has_gravity and not current_on_floor:
			velocity += get_gravity() * delta
		# No horizontal movement
		velocity.x = 0
		velocity.z = 0
		# Handle animation transitions for won waiting
		_update_animation_state(current_on_floor, false, false, delta)
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
		
		PlayerState.WON_WAITING:
			# Player has won but needs to land first
			if on_floor:
				log_player("Player landed after winning - playing victory animation")
				play_victory()
			# Continue falling animation while waiting to land
			elif velocity.y < -1.0 and animation_player.current_animation != fall_anim:
				play_falling()
		
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

# Mouse handling moved to scene level (Step 5)
# func capture_mouse():
# 	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
# 	mouse_captured = true

# func release_mouse():
# 	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
# 	mouse_captured = false

# func resume_from_pause():
# 	"""Called when resuming from pause to re-capture mouse"""
# 	capture_mouse()


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
