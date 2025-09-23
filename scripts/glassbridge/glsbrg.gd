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
var platform_manager: PlatformManager
var game_manager: GameManager

func _ready() -> void:
	print("===== GAME SETUP STARTING =====")
	print("Player node: ", (player.name as String) if player else "NULL")
	
	# Load and setup pause screen
	setup_pause_screen()
	
	# Initialize managers
	platform_manager = PlatformManager.new(self, player)
	game_manager = GameManager.new(self, player, goaltimer)
	
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
	
	print("===== GAME SETUP COMPLETE =====")


# Signal handlers for game manager
func _on_player_won():
	print("Main script: Player won!")

func _on_player_died():
	print("Main script: Player died!")

func _on_game_state_changed(new_state):
	print("Main script: Game state changed to ", GameManager.State.keys()[new_state])

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

func setup_pause_screen():
	"""Load and setup the pause screen"""
	var pause_scene = preload("res://scenes/glassbridge/pause_screen.tscn")
	pause_screen = pause_scene.instantiate()
	add_child(pause_screen)
	
	# Make sure pause screen processes during pause
	pause_screen.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	# Pass player reference to pause screen
	pause_screen.player = player
	
	# Initially hide the pause screen
	pause_screen.visible = false

func _unhandled_input(event: InputEvent):
	"""Handle pause input"""
	if event.is_action_pressed("ui_cancel"):  # ESC key
		if get_tree().paused:
			pause_screen.resume_game()
		else:
			pause_screen.show_pause()
	
	
