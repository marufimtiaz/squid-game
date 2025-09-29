extends Area3D

@onready var player: CharacterBody3D = $"../Player"

# Reference to managers for proper state handling
var game_manager: GameManager
var player_manager: PlayerManager

func _ready():
	# Connect to player signals for better communication (with new signatures)
	if player:
		player.player_hit_killzone.connect(_on_player_hit_killzone)
		player.fallimpact_finished.connect(_on_player_fallimpact_finished)
	
	# Get reference to game manager from parent scene
	var main_scene = get_parent()
	if main_scene and main_scene.has_method("get") and main_scene.get("game_manager"):
		game_manager = main_scene.game_manager
	if main_scene and main_scene.has_method("get") and main_scene.get("player_manager"):
		player_manager = main_scene.player_manager

func _on_body_entered(body: Node3D) -> void:
	# Check if the body is a managed player using PlayerManager
	if player_manager and player_manager.is_valid_player(body):
		var entered_player = body as CharacterBody3D
		var player_id = player_manager.get_player_id(entered_player)
		var player_name = "Player " + str(player_id)
		
		print("KILLZONE: Player ", player_id, " (", player_name, ") entered killzone at position: ", entered_player.global_position)
		print("KILLZONE: Triggering fallimpact for player ", player_id)
		
		# Trigger fallimpact animation and freeze player
		entered_player.play_fallimpact()
		
		# Only release mouse if Player 1 dies (single-player compatibility)
		if player_id == 1:
			player_manager.release_mouse()
			print("KILLZONE: Player 1 died - mouse released")
		
		# Notify game manager about SPECIFIC player death
		if game_manager:
			print("KILLZONE: Notifying game manager about player ", player_id, " death")
			# Set the dying player ID before calling handle_player_death
			game_manager.current_dying_player = player_id
			game_manager.handle_player_death()
	elif body == player:
		# Fallback to direct player comparison for compatibility
		print("Player entered killzone - triggering fallimpact")
		# Trigger fallimpact animation and freeze player
		player.play_fallimpact()
		
		# Only release mouse if Player 1 dies (single-player compatibility) 
		var player_id = player_manager.get_player_id(player)
		if player_id == 1:
			player_manager.release_mouse()
			print("Player 1 died - mouse released")
		
		# Notify game manager about player death
		if game_manager:
			game_manager.handle_player_death()

func _on_player_hit_killzone(player_id: int):
	# This gets called when the player plays the fallimpact animation
	print("Player ", player_id, " hit killzone - fallimpact animation triggered")

func _on_player_fallimpact_finished(player_id: int):
	# This gets called when the fallimpact animation finishes
	print("Player ", player_id, " fallimpact animation finished")
	# Step 6: Now check if all players are done (after death animation)
	if game_manager:
		game_manager.call_deferred("check_and_handle_game_end")
