class_name GameManager
extends RefCounted

enum State { PLAYING, DEAD, WON }

# Per-player state tracking (multiplayer-ready)
var player_states: Dictionary = {}  # player_id -> State
var player_manager: PlayerManager
var goal_timer: Timer
var game_node: Node3D

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
	# For now, handle primary player death (Step 6 will make this per-player)
	var primary_player = player_manager.get_primary_player()
	if primary_player:
		var player_id = player_manager.get_player_id(primary_player)
		var current_state = get_player_state(player_id)
		if current_state == State.PLAYING:
			print("Player ", player_id, " died!")
			set_player_state(player_id, State.DEAD)
		else:
			print("Player ", player_id, " death ignored - already in state: ", State.keys()[current_state])

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

func _handle_player_died(player_id: int):
	print("Handling player ", player_id, " death...")
	# Death is now handled by killzone waiting for fallimpact_finished
	player_died.emit(player_id)

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
	for player in player_manager.get_all_players():
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
	if is_game_finished():
		print("All players finished - transitioning based on result...")
		player_manager.freeze_all_players()
		var result = get_game_result()
		match result:
			"win":
				# Use call_deferred to avoid physics callback issues
				game_node.get_tree().call_deferred("change_scene_to_file", "res://scenes/glassbridge/end_screen.tscn")
			"lose":
				# Use call_deferred to avoid physics callback issues
				game_node.get_tree().call_deferred("change_scene_to_file", "res://scenes/glassbridge/lose_screen.tscn")

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
