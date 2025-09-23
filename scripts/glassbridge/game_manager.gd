class_name GameManager
extends RefCounted

enum State { PLAYING, DEAD, WON }

var state: State = State.PLAYING
var player_manager: PlayerManager
var goal_timer: Timer
var game_node: Node3D

# Signals to communicate with main game
signal player_won
signal player_died
signal state_changed(new_state: State)

func _init(_game_node: Node3D, _player_manager: PlayerManager, _goal_timer: Timer):
	self.game_node = _game_node
	self.player_manager = _player_manager
	self.goal_timer = _goal_timer
	
	# Connect goal timer signal (for backup timing)
	if _goal_timer:
		_goal_timer.timeout.connect(_on_goal_timer_timeout)
	
	# Connect player signals for primary player (with new signature)
	var primary_player = _player_manager.get_primary_player()
	if primary_player:
		primary_player.player_victory_started.connect(_on_player_victory_started)
		primary_player.victory_finished.connect(_on_player_victory_finished)

func get_current_state() -> State:
	return state

func set_state(new_state: State):
	if state != new_state:
		var old_state = state
		state = new_state
		print("Game state changed from ", State.keys()[old_state], " to ", State.keys()[new_state])
		state_changed.emit(new_state)
		
		match new_state:
			State.WON:
				_handle_player_won()
			State.DEAD:
				_handle_player_died()

func handle_goal_reached(body: Node3D):
	if player_manager.is_valid_player(body) and state == State.PLAYING:
		print("Player reached the goal!")
		set_state(State.WON)

func handle_player_death():
	if state == State.PLAYING:
		print("Player died!")
		set_state(State.DEAD)
	else:
		print("Player death ignored - game state is already: ", State.keys()[state])

func _handle_player_won():
	print("Handling player win...")
	var primary_player = player_manager.get_primary_player()
	# Use the new goal reached handler that waits for landing
	if primary_player:
		primary_player.handle_goal_reached()
		primary_player.release_mouse()
	# Start goal timer as backup, but victory_finished signal will be primary trigger
	if goal_timer:
		goal_timer.start()
	player_won.emit()

func _handle_player_died():
	print("Handling player death...")
	# Death is now handled by killzone waiting for fallimpact_finished
	player_died.emit()

func _on_player_victory_started(player_id: int):
	print("Player ", player_id, " victory animation started")

func _on_player_victory_finished(player_id: int):
	print("Player ", player_id, " victory animation finished - transitioning to end screen")
	player_manager.freeze_all_players()
	game_node.get_tree().change_scene_to_file("res://scenes/glassbridge/end_screen.tscn")

func _on_goal_timer_timeout():
	print("Goal timer backup timeout - transitioning to end screen...")
	# This is now a backup - the primary trigger should be victory_finished
	if state == State.WON:
		player_manager.freeze_all_players()
		game_node.get_tree().change_scene_to_file("res://scenes/glassbridge/end_screen.tscn")

func is_playing() -> bool:
	return state == State.PLAYING

func is_won() -> bool:
	return state == State.WON

func is_dead() -> bool:
	return state == State.DEAD

func reset_game():
	set_state(State.PLAYING)
	if goal_timer:
		goal_timer.stop()
