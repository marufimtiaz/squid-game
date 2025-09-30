class_name GameManager
extends RefCounted

enum State { PLAYING, DEAD, WON }

# Per-player state tracking (multiplayer-ready)
var player_states: Dictionary = {}  # player_id -> State
var player_manager: PlayerManager
var goal_timer: Timer
var game_node: Node3D

# Track which player is dying (set by killzone)
var current_dying_player: int = 0

# Prevent multiple simultaneous game end transitions
var game_end_in_progress: bool = false

# Signals to communicate with main game (now include player_id)
signal player_won(player_id: int)
signal player_died(player_id: int)
signal state_changed(player_id: int, new_state: State)

func _init(_game_node: Node3D, _player_manager: PlayerManager, _goal_timer: Timer):
	self.game_node = _game_node
	self.player_manager = _player_manager
	self.goal_timer = _goal_timer
	
	# Initialize all players to PLAYING state
	for player in _player_manager.get_all_players():
		var player_id = _player_manager.get_player_id(player)
		player_states[player_id] = State.PLAYING
	
	# Connect goal timer signal (for backup timing)
	if _goal_timer:
		_goal_timer.timeout.connect(_on_goal_timer_timeout)
	
	# Connect player signals for primary player (with new signature)
	var primary_player = _player_manager.get_primary_player()
	if primary_player:
		primary_player.player_victory_started.connect(_on_player_victory_started)
		primary_player.victory_finished.connect(_on_player_victory_finished)

func get_current_state() -> State:
	# For compatibility, return primary player state
	var primary_player = player_manager.get_primary_player()
	if primary_player:
		var player_id = player_manager.get_player_id(primary_player)
		return player_states.get(player_id, State.PLAYING)
	return State.PLAYING

func get_player_state(player_id: int) -> State:
	return player_states.get(player_id, State.PLAYING)

func set_player_state(player_id: int, new_state: State):
	var current_state = player_states.get(player_id, State.PLAYING)
	if current_state != new_state:
		var old_state = current_state
		player_states[player_id] = new_state
		print("Player ", player_id, " state changed from ", State.keys()[old_state], " to ", State.keys()[new_state])
		
		# Step 8: Log essential sync data when game state changes
		var essential_sync = get_essential_sync_data()
		if not essential_sync.is_empty():
			print("SYNC Game: Essential data size=", essential_sync.size(), " keys=", essential_sync.keys())
		
		state_changed.emit(player_id, new_state)
		
		match new_state:
			State.WON:
				_handle_player_won(player_id)
			State.DEAD:
				_handle_player_died(player_id)
		
		# Step 6: Don't check game end immediately - wait for animations

func handle_goal_reached(body: Node3D):
	if player_manager.is_valid_player(body):
		var player_id = player_manager.get_player_id(body as CharacterBody3D)
		var current_state = get_player_state(player_id)
		if current_state == State.PLAYING:
			print("Player ", player_id, " reached the goal!")
			set_player_state(player_id, State.WON)

func handle_player_death():
	# Handle death for the specific player that entered the killzone
	if current_dying_player <= 0:
		print("GAME_MANAGER: Error - no dying player set!")
		return
		
	var player_id = current_dying_player
	var current_state = get_player_state(player_id)
	
	print("GAME_MANAGER: Processing death for player ", player_id, " (current state: ", State.keys()[current_state], ")")
	
	if current_state == State.PLAYING:
		print("GAME_MANAGER: Player ", player_id, " died!")
		set_player_state(player_id, State.DEAD)
	else:
		print("GAME_MANAGER: Player ", player_id, " death ignored - already in state: ", State.keys()[current_state])
	
	# Reset the dying player tracker
	current_dying_player = 0

func _handle_player_won(player_id: int):
	print("Handling player ", player_id, " win...")
	var player = player_manager.get_player_by_id(player_id)
	if player:
		player.handle_goal_reached()
	# Release mouse centrally when player wins
	player_manager.release_mouse()
	# Start goal timer as backup, but victory_finished signal will be primary trigger
	if goal_timer:
		goal_timer.start()
	player_won.emit(player_id)
	
	# FALLBACK: Also check if game should end when any player wins
	# This ensures all instances transition properly even if victory_finished RPC fails
	call_deferred("check_and_handle_game_end")

func _handle_player_died(player_id: int):
	print("Handling player ", player_id, " death...")
	# Step 7: Set dead player to spectator UI state
	player_manager.set_player_ui_state(player_id, PlayerManager.UIState.SPECTATING)
	# Death is now handled by killzone waiting for fallimpact_finished
	player_died.emit(player_id)
	
	# FALLBACK: Also check if game should end when any player dies
	# This ensures the host doesn't get stuck if a client disconnects before sending fallimpact RPC
	call_deferred("check_and_handle_game_end")

func _on_player_victory_started(player_id: int):
	print("Player ", player_id, " victory animation started")

func _on_player_victory_finished(player_id: int):
	print("Player ", player_id, " victory animation finished")
	# Step 6: Don't transition immediately - check if all players done
	call_deferred("check_and_handle_game_end")

func _on_goal_timer_timeout():
	print("Goal timer backup timeout")
	# Step 6: Check if all players done instead of immediate transition
	call_deferred("check_and_handle_game_end")

func is_playing() -> bool:
	# Check if primary player is playing (compatibility)
	var primary_player = player_manager.get_primary_player()
	if primary_player:
		var player_id = player_manager.get_player_id(primary_player)
		return get_player_state(player_id) == State.PLAYING
	return false

# Step 6: Multi-player scene transition logic
func is_game_finished() -> bool:
	"""Check if all players have finished (won or died)"""
	var all_players = player_manager.get_all_players()
	
	# If no players exist yet, game is not finished (still starting up)
	if all_players.is_empty():
		return false
		
	# Check if all players have finished
	for player in all_players:
		var player_id = player_manager.get_player_id(player)
		var state = get_player_state(player_id)
		if state == State.PLAYING:
			return false  # At least one player still playing
	return true

func get_game_result() -> String:
	"""Determine overall game result for scene transition"""
	var won_count = 0
	
	for player in player_manager.get_all_players():
		var player_id = player_manager.get_player_id(player)
		var state = get_player_state(player_id)
		if state == State.WON:
			won_count += 1
	
	if won_count > 0:
		return "win"  # At least one player won
	else:
		return "lose"  # All players died

func check_and_handle_game_end():
	"""Check if game is finished and transition to appropriate screen"""
	print("GAME_END: Checking if game is finished...")
	var mp = game_node.multiplayer
	if mp:
		print("GAME_END: I am server: ", mp.is_server())
		print("GAME_END: My peer ID: ", mp.get_unique_id())
	else:
		print("GAME_END: No multiplayer available")
	
	# Prevent multiple simultaneous game end transitions
	if game_end_in_progress:
		print("GAME_END: Game end already in progress, skipping...")
		return
	
	if is_game_finished():
		game_end_in_progress = true
		print("All players finished - transitioning based on individual result...")
		player_manager.freeze_all_players()
		
		# Show individual result for local player
		var local_player_state = get_local_player_state()
		print("GAME_END: My local player state is: ", State.keys()[local_player_state])
		
		# Add 2-second delay to let players see the final animation
		print("GAME_END: Waiting 2 seconds before transitioning to result screen...")
		await game_node.get_tree().create_timer(2.0).timeout
		
		match local_player_state:
			State.WON:
				# Local player won - show end screen
				game_node.get_tree().call_deferred("change_scene_to_file", "res://scenes/glassbridge/end_screen.tscn")
			State.DEAD:
				# Local player died - show lose screen
				game_node.get_tree().call_deferred("change_scene_to_file", "res://scenes/glassbridge/lose_screen.tscn")
			_:
				# Fallback - shouldn't happen but use overall result
				var result = get_game_result()
				match result:
					"win":
						game_node.get_tree().call_deferred("change_scene_to_file", "res://scenes/glassbridge/end_screen.tscn")
					"lose":
						game_node.get_tree().call_deferred("change_scene_to_file", "res://scenes/glassbridge/lose_screen.tscn")

func get_local_player_state() -> State:
	"""Get the state of the local player on this instance"""
	# Get the primary player (local player on this instance)
	var primary_player = player_manager.get_primary_player()
	if primary_player:
		var player_id = player_manager.get_player_id(primary_player)
		return get_player_state(player_id)
	
	# Fallback - if no primary player, assume single player mode
	return get_player_state(1)

func is_won() -> bool:
	# Check if primary player won (compatibility)
	var primary_player = player_manager.get_primary_player()
	if primary_player:
		var player_id = player_manager.get_player_id(primary_player)
		return get_player_state(player_id) == State.WON
	return false

func is_dead() -> bool:
	# Check if primary player is dead (compatibility)
	var primary_player = player_manager.get_primary_player()
	if primary_player:
		var player_id = player_manager.get_player_id(primary_player)
		return get_player_state(player_id) == State.DEAD
	return false

func reset_game():
	# Reset all players to PLAYING state
	for player_id in player_states.keys():
		player_states[player_id] = State.PLAYING
	if goal_timer:
		goal_timer.stop()

# Step 9: Dynamic Player Management Methods
func add_player_to_game(player_id: int, initial_state: State = State.PLAYING):
	"""Add a new player to the game state"""
	if player_id in player_states:
		print("Player ", player_id, " already exists in game state")
		return
	
	player_states[player_id] = initial_state
	print("Player ", player_id, " added to game with state: ", State.keys()[initial_state])
	
	# Connect player signals if it's a real player object
	var player = player_manager.get_player_by_id(player_id)
	if player and player.has_signal("player_victory_started") and player.has_signal("victory_finished"):
		if not player.player_victory_started.is_connected(_on_player_victory_started):
			player.player_victory_started.connect(_on_player_victory_started)
		if not player.victory_finished.is_connected(_on_player_victory_finished):
			player.victory_finished.connect(_on_player_victory_finished)
		print("Connected signals for player ", player_id)

func remove_player_from_game(player_id: int):
	"""Remove a player from the game state"""
	if player_id not in player_states:
		print("Player ", player_id, " not found in game state")
		return
	
	# Disconnect player signals if it's a real player object
	var player = player_manager.get_player_by_id(player_id)
	if player and player.has_signal("player_victory_started") and player.has_signal("victory_finished"):
		if player.player_victory_started.is_connected(_on_player_victory_started):
			player.player_victory_started.disconnect(_on_player_victory_started)
		if player.victory_finished.is_connected(_on_player_victory_finished):
			player.victory_finished.disconnect(_on_player_victory_finished)
		print("Disconnected signals for player ", player_id)
	
	player_states.erase(player_id)
	print("Player ", player_id, " removed from game state")

func get_active_player_count() -> int:
	"""Get count of players still actively playing (not dead or won)"""
	var active_count = 0
	for player_id in player_states:
		if player_states[player_id] == State.PLAYING:
			active_count += 1
	return active_count

func handle_mid_game_join(player_id: int):
	"""Handle a player joining an already running game"""
	if is_game_finished():
		# Game already finished, add as spectator
		add_player_to_game(player_id, State.DEAD)  # Use DEAD as spectator state
		print("Player ", player_id, " joined finished game as spectator")
	else:
		# Game still running, add as playing
		add_player_to_game(player_id, State.PLAYING)
		print("Player ", player_id, " joined ongoing game")

# Step 8: Network Sync Methods
func create_game_sync_data() -> SyncData.GameSyncData:
	"""Create complete game sync data"""
	var sync_data = SyncData.GameSyncData.new()
	
	# Get platform sync data from platform manager
	# Note: We don't have direct access to platform_manager here, so this would be called from main scene
	# sync_data.platforms = platform_manager.get_all_platforms_sync_data()
	
	# Get player sync data from player manager and update with game state
	sync_data.players = player_manager.get_all_players_sync_data()
	for player_id in sync_data.players:
		if sync_data.players[player_id]:
			sync_data.players[player_id].game_state = get_player_state(player_id)
	
	# Set game completion status
	sync_data.game_finished = is_game_finished()
	if sync_data.game_finished:
		sync_data.game_result = get_game_result()
	
	return sync_data

func apply_game_sync_data(sync_data: SyncData.GameSyncData):
	"""Apply complete game sync data"""
	if not sync_data:
		return
	
	# Apply player sync data
	player_manager.apply_all_players_sync_data(sync_data.players)
	
	# Update game states from sync data
	for player_id in sync_data.players:
		if sync_data.players[player_id]:
			var player_sync = sync_data.players[player_id]
			set_player_state(player_id, player_sync.game_state)
	
	# Handle game completion if sync indicates it's finished
	if sync_data.game_finished and not is_game_finished():
		# Game finished on remote but not locally - handle appropriately
		print("Game finished remotely with result: ", sync_data.game_result)

func get_essential_sync_data() -> Dictionary:
	"""Get minimal sync data for efficient networking"""
	var essential_data = {}
	
	# Only include changed/important state
	var changed_players = {}
	for player_id in player_states:
		var state = get_player_state(player_id)
		if state != State.PLAYING:  # Only sync non-default states
			changed_players[player_id] = {
				"game_state": state,
				"ui_state": player_manager.get_player_ui_state(player_id)
			}
	
	if not changed_players.is_empty():
		essential_data["players"] = changed_players
	
	if is_game_finished():
		essential_data["game_finished"] = true
		essential_data["game_result"] = get_game_result()
	
	return essential_data

func apply_essential_sync_data(essential_data: Dictionary):
	"""Apply minimal sync data efficiently"""
	if essential_data.has("players"):
		var players_data = essential_data["players"]
		for player_id in players_data:
			var player_data = players_data[player_id]
			if player_data.has("game_state"):
				set_player_state(player_id, player_data["game_state"])
			if player_data.has("ui_state"):
				player_manager.set_player_ui_state(player_id, player_data["ui_state"])
	
	if essential_data.get("game_finished", false):
		print("Essential sync: Game finished with result: ", essential_data.get("game_result", ""))
