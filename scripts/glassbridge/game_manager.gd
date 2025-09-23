class_name GameManager
extends RefCounted

enum State { PLAYING, DEAD, WON }

var state: State = State.PLAYING
var player: CharacterBody3D
var goal_timer: Timer
var game_node: Node3D

# Signals to communicate with main game
signal player_won
signal player_died
signal state_changed(new_state: State)

func _init(game_node: Node3D, player: CharacterBody3D, goal_timer: Timer):
	self.game_node = game_node
	self.player = player
	self.goal_timer = goal_timer
	
	# Connect goal timer signal
	if goal_timer:
		goal_timer.timeout.connect(_on_goal_timer_timeout)

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
	if body == player and state == State.PLAYING:
		print("Player reached the goal!")
		set_state(State.WON)

func handle_player_death():
	if state == State.PLAYING:
		print("Player died!")
		set_state(State.DEAD)

func _handle_player_won():
	print("Handling player win...")
	player.slow()
	player.release_mouse()
	if goal_timer:
		goal_timer.start()
	player_won.emit()

func _handle_player_died():
	print("Handling player death...")
	# Add any death-specific logic here
	player_died.emit()

func _on_goal_timer_timeout():
	print("Goal timer expired, transitioning to end screen...")
	player.freeze()
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