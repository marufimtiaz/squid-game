class_name PlayerManager
extends RefCounted

enum UIState { PLAYING, MENU_OPEN, SPECTATING }

# For now, we maintain single player compatibility while preparing for multiplayer
var _primary_player: CharacterBody3D
var _players: Array[CharacterBody3D] = []
var _next_player_id: int = 1

# Step 7: Per-player UI state tracking (multiplayer-ready)
var _player_ui_states: Dictionary = {}  # player_id -> UIState

func _init(primary_player: CharacterBody3D):
	self._primary_player = primary_player
	if primary_player:
		# Assign player ID if not already set
		if primary_player.has_method("get") and primary_player.get("player_id") == 0:
			primary_player.player_id = _next_player_id
			primary_player.player_name = "Player " + str(_next_player_id)
			_next_player_id += 1
		_players.append(primary_player)
		# Initialize player to PLAYING UI state
		_player_ui_states[primary_player.player_id] = UIState.PLAYING

# Primary interface for single-player compatibility
func get_primary_player() -> CharacterBody3D:
	return _primary_player

# Future-proofing: methods for multiplayer support
func get_all_players() -> Array[CharacterBody3D]:
	return _players.duplicate()

func get_player_count() -> int:
	return _players.size()

func has_player(player: CharacterBody3D) -> bool:
	return player in _players

func is_valid_player(body: Node3D) -> bool:
	"""Check if a body is one of our managed players"""
	return body is CharacterBody3D and has_player(body as CharacterBody3D)

# Utility methods for common operations
func freeze_all_players():
	"""Freeze all managed players"""
	for player in _players:
		if player and player.has_method("freeze"):
			player.freeze()

# Mouse handling methods (centralized for multiplayer support)
func capture_mouse():
	"""Capture mouse for the game"""
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func release_mouse():
	"""Release mouse capture"""
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# Step 7: Per-player UI state management
func get_player_ui_state(player_id: int) -> UIState:
	"""Get the current UI state for a player"""
	return _player_ui_states.get(player_id, UIState.PLAYING)

func set_player_ui_state(player_id: int, state: UIState):
	"""Set the UI state for a player"""
	_player_ui_states[player_id] = state
	print("Player ", player_id, " UI state changed to ", UIState.keys()[state])
	
	# Step 8: Log sync data when UI state changes
	var sync_data = create_player_sync_data(player_id)
	if sync_data:
		print("SYNC Player: Player ", player_id, " Pos=", sync_data.position, " UIState=", UIState.keys()[sync_data.ui_state])

func is_player_playing(player_id: int) -> bool:
	"""Check if player is in PLAYING state (can receive game input)"""
	return get_player_ui_state(player_id) == UIState.PLAYING

func get_playing_players() -> Array[CharacterBody3D]:
	"""Get all players currently in PLAYING state"""
	var playing_players: Array[CharacterBody3D] = []
	for player in _players:
		var player_id = get_player_id(player)
		if is_player_playing(player_id):
			playing_players.append(player)
	return playing_players

# Future methods for multiplayer (currently just work with primary player)
func add_player(player: CharacterBody3D) -> bool:
	"""Add a new player (prepared for future multiplayer)"""
	if player and not has_player(player):
		# Assign player ID if not already set
		if player.has_method("get") and player.get("player_id") == 0:
			player.player_id = _next_player_id
			player.player_name = "Player " + str(_next_player_id)
			_next_player_id += 1
		_players.append(player)
		# Initialize player to PLAYING UI state
		_player_ui_states[player.player_id] = UIState.PLAYING
		return true
	return false

func get_player_by_id(player_id: int) -> CharacterBody3D:
	"""Get player by their ID"""
	for player in _players:
		if player.has_method("get") and player.get("player_id") == player_id:
			return player
	return null

func get_player_id(player: CharacterBody3D) -> int:
	"""Get the ID of a player"""
	if player and player.has_method("get"):
		return player.get("player_id")
	return 0

func remove_player(player: CharacterBody3D) -> bool:
	"""Remove a player (prepared for future multiplayer)"""
	if has_player(player):
		_players.erase(player)
		# Don't remove primary player reference for now
		if player != _primary_player:
			return true
	return false

func cleanup():
	"""Clean up player references"""
	_players.clear()
	_primary_player = null

# Step 8: Network Sync Methods
func create_player_sync_data(player_id: int) -> SyncData.PlayerSyncData:
	"""Create sync data for a specific player"""
	var player = get_player_by_id(player_id)
	if not player:
		return null
	
	var animation_state = ""
	if player.has_method("get_current_animation"):
		animation_state = player.get_current_animation()
	
	return SyncData.PlayerSyncData.new(
		player_id,
		player.global_position,
		player.rotation,
		animation_state,
		get_player_ui_state(player_id),
		GameManager.State.PLAYING  # Will be overridden by GameManager
	)

func apply_player_sync_data(sync_data: SyncData.PlayerSyncData):
	"""Apply sync data to a specific player"""
	var player = get_player_by_id(sync_data.player_id)
	if not player:
		return
	
	# Only sync position/rotation if player is not local (for future multiplayer)
	# For now, this prepares the structure
	player.global_position = sync_data.position
	player.rotation = sync_data.rotation
	
	# Apply animation state if player supports it
	if sync_data.animation_state != "" and player.has_method("set_animation"):
		player.set_animation(sync_data.animation_state)
	
	# Apply UI state
	set_player_ui_state(sync_data.player_id, sync_data.ui_state)

func get_all_players_sync_data() -> Dictionary:
	"""Get sync data for all players"""
	var sync_data = {}
	for player in _players:
		var player_id = get_player_id(player)
		sync_data[player_id] = create_player_sync_data(player_id)
	return sync_data

func apply_all_players_sync_data(players_sync_data: Dictionary):
	"""Apply sync data to all players"""
	for player_id in players_sync_data:
		if players_sync_data[player_id]:
			apply_player_sync_data(players_sync_data[player_id])
