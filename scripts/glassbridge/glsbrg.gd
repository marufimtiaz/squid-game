extends Node3D

@onready var player: CharacterBody3D = $Player
@onready var platforms: Node3D = $Platforms
@onready var goaltimer: Timer = $Platforms/FinishPlatform/Goal/Timer
@onready var layer3: Node = $Platforms/Layer3
@onready var layer4: Node = $Platforms/Layer4

# Managers
var platform_manager: PlatformManager
var game_manager: GameManager

func _ready() -> void:
	print("===== GAME SETUP STARTING =====")
	print("Player node: ", (player.name as String) if player else "NULL")
	
	# Initialize managers
	platform_manager = PlatformManager.new(self, player)
	game_manager = GameManager.new(self, player, goaltimer)
	
	# Connect game manager signals
	game_manager.player_won.connect(_on_player_won)
	game_manager.player_died.connect(_on_player_died)
	game_manager.state_changed.connect(_on_game_state_changed)
	
	# Setup platforms using the platform manager
	platform_manager.setup_platforms(layer3, layer4)
	
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
	
	
