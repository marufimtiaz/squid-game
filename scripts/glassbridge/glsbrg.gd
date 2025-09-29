extends Node3D

@onready var player: CharacterBody3D = $Player
@onready var platforms: Node3D = $Platforms
@onready var goaltimer: Timer = $Platforms/FinishPlatform/Goal/Timer
@onready var layer3: Node = $Platforms/Layer3
@onready var layer4: Node = $Platforms/Layer4
@onready var killzone: Area3D = $Killzone

# Pause screen
@onready var pause_screen: Control

# Managers
var player_manager: PlayerManager
var platform_manager: PlatformManager
var game_manager: GameManager

func _ready() -> void:
	print("===== GAME SETUP STARTING =====")
	print("Player node: ", (player.name as String) if player else "NULL")
	
	# Initialize player manager first
	player_manager = PlayerManager.new(player)
	
	# Step 7: Set PlayerManager reference in player for UI state checking
	if player:
		player.player_manager = player_manager
	
	# Load and setup pause screen
	setup_pause_screen()
	
	# Initialize managers with player manager
	platform_manager = PlatformManager.new(self, player_manager)
	game_manager = GameManager.new(self, player_manager, goaltimer)
	
	# Connect game manager signals
	game_manager.player_won.connect(_on_player_won)
	game_manager.player_died.connect(_on_player_died)
	game_manager.state_changed.connect(_on_game_state_changed)
	
	# Setup platforms using the platform manager
	platform_manager.setup_platforms(layer3, layer4)
	
	# Setup killzone reference to game manager
	#var killzone = $KillZone

	if killzone and killzone.has_method("set"):
		killzone.game_manager = game_manager
		killzone.player_manager = player_manager
	
	# Auto-capture mouse when game starts (centralized input handling)
	player_manager.capture_mouse()
	
	print("===== GAME SETUP COMPLETE =====")


# Signal handlers for game manager
func _on_player_won(player_id: int):
	print("Main script: Player ", player_id, " won!")

func _on_player_died(player_id: int):
	print("Main script: Player ", player_id, " died!")

func _on_game_state_changed(player_id: int, new_state):
	print("Main script: Player ", player_id, " state changed to ", GameManager.State.keys()[new_state])

# Goal detection
func _on_goal_body_entered(body: Node3D) -> void:
	game_manager.handle_goal_reached(body)

func _on_timer_timeout() -> void:
	# This is now handled by the GameManager
	pass

func _exit_tree():
	# Clean up managers
	if platform_manager:
		platform_manager.cleanup()
	if player_manager:
		player_manager.cleanup()

func setup_pause_screen():
	"""Load and setup the player menu screen (Step 7: no global pause)"""
	var pause_scene = preload("res://scenes/glassbridge/pause_screen.tscn")
	pause_screen = pause_scene.instantiate()
	add_child(pause_screen)
	
	# Step 7: Menu overlay processes normally (game never pauses)
	pause_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Pass references to menu screen
	pause_screen.player_manager = player_manager
	pause_screen.main_scene = self
	
	# Initially hide the menu screen
	pause_screen.visible = false

# Step 7: Per-player menu management
func open_player_menu(player_id: int):
	"""Open menu for a specific player (game continues running)"""
	print("Opening menu for Player ", player_id)
	player_manager.set_player_ui_state(player_id, PlayerManager.UIState.MENU_OPEN)
	
	# Show menu overlay (convert old pause screen to player menu)
	pause_screen.visible = true
	player_manager.release_mouse()

func close_player_menu(player_id: int):
	"""Close menu for a specific player"""
	print("Closing menu for Player ", player_id)
	player_manager.set_player_ui_state(player_id, PlayerManager.UIState.PLAYING)
	
	# Hide menu overlay
	pause_screen.visible = false
	player_manager.capture_mouse()

func _unhandled_input(event: InputEvent):
	"""Handle player menu input and centralized mouse control"""
	# Step 7: Per-player menu handling (no global pause)
	if event.is_action_pressed("ui_cancel"):  # ESC key
		var menu_player = player_manager.get_primary_player()
		if menu_player:
			var player_id = player_manager.get_player_id(menu_player)
			var ui_state = player_manager.get_player_ui_state(player_id)
			if ui_state == PlayerManager.UIState.MENU_OPEN:
				close_player_menu(player_id)
			else:
				open_player_menu(player_id)
	
	# Centralized mouse handling (Step 5: moved from player script)
	# Only process game input for players in PLAYING state
	var input_player = player_manager.get_primary_player()
	if input_player:
		var player_id = player_manager.get_player_id(input_player)
		if not player_manager.is_player_playing(player_id):
			return  # Player has menu open, ignore game input
		
	# Capture mouse with left click
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		player_manager.capture_mouse()
		
	# Release mouse with ALT key
	if event is InputEventKey and event.keycode == KEY_ALT and event.pressed:
		player_manager.release_mouse()
	
	
