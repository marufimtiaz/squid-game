class_name PlayerManager
extends RefCounted

# For now, we maintain single player compatibility while preparing for multiplayer
var _primary_player: CharacterBody3D
var _players: Array[CharacterBody3D] = []
var _next_player_id: int = 1

func _init(primary_player: CharacterBody3D):
	self._primary_player = primary_player
	if primary_player:
		# Assign player ID if not already set
		if primary_player.has_method("get") and primary_player.get("player_id") == 0:
			primary_player.player_id = _next_player_id
			primary_player.player_name = "Player " + str(_next_player_id)
			_next_player_id += 1
		_players.append(primary_player)

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

func release_mouse_all_players():
	"""Legacy method - now just calls release_mouse()"""
	release_mouse()

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