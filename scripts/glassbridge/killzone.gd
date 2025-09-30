extends Area3D

# No hardcoded player reference - we'll work with PlayerManager instead

# Reference to managers for proper state handling
var game_manager: GameManager
var player_manager: PlayerManager

func _ready():
	# No hardcoded player connections - signals are connected dynamically by PlayerManager
	
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
		
		# Release mouse if local player dies (multiplayer compatible)
		var local_player_id = multiplayer.get_unique_id()
		if player_id == local_player_id:
			player_manager.release_mouse()
			print("KILLZONE: Local player died - mouse released")
		
		# Notify game manager about SPECIFIC player death
		if game_manager:
			print("KILLZONE: Notifying game manager about player ", player_id, " death")
			# Set the dying player ID before calling handle_player_death
			game_manager.current_dying_player = player_id
			game_manager.handle_player_death()

func _on_player_hit_killzone(player_id: int):
	# This gets called when the player plays the fallimpact animation
	print("Player ", player_id, " hit killzone - fallimpact animation triggered")

func _on_player_fallimpact_finished(player_id: int):
	# This gets called when the fallimpact animation finishes
	print("Player ", player_id, " fallimpact animation finished")
	print("FALLIMPACT: About to send RPC for player ", player_id)
	print("FALLIMPACT: I am server: ", multiplayer.is_server())
	print("FALLIMPACT: My peer ID: ", multiplayer.get_unique_id())
	# Step 6: Now check if all players are done (after death animation)
	# Use RPC to notify ALL instances that a player finished
	if game_manager:
		notify_all_player_finished.rpc(player_id)
		print("FALLIMPACT: RPC sent for player ", player_id)

@rpc("any_peer", "call_local", "reliable")
func notify_all_player_finished(player_id: int):
	"""RPC to notify all instances when a player finishes (dies or wins)"""
	print("RPC RECEIVED: Player ", player_id, " finished - checking game end on all instances")
	print("RPC RECEIVED: I am server: ", multiplayer.is_server())
	print("RPC RECEIVED: My peer ID: ", multiplayer.get_unique_id())
	if game_manager:
		print("RPC RECEIVED: Calling check_and_handle_game_end")
		game_manager.call_deferred("check_and_handle_game_end")
