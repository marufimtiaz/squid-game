class_name SpawnManager
extends RefCounted

# Step 9: Dynamic Player Management - Spawn Points System

var spawn_points: Array[Vector3] = []
var used_spawn_points: Dictionary = {}  # player_id -> spawn_point_index
var game_node: Node3D

func _init(init_game_node: Node3D):
	self.game_node = init_game_node

func add_spawn_point(position: Vector3):
	"""Add a spawn point to the available list"""
	spawn_points.append(position)
	print("Spawn point added at: ", position)

func setup_default_spawn_points():
	"""Setup default spawn points for the glass bridge level"""
	# Starting area spawn points (forward/back line on starting platform)
	add_spawn_point(Vector3(2, 2, 20))    # Primary start (safest, most forward)
	add_spawn_point(Vector3(2, 2, 18))    # Behind player 1
	add_spawn_point(Vector3(2, 2, 22))    # Ahead of player 1  
	add_spawn_point(Vector3(2, 2, 16))   # Left side
	add_spawn_point(Vector3(2, 2, 24))    # Right side
	
	# Mid-level spawn points (in case of mid-game joining)
	add_spawn_point(Vector3(2, 2, 17))    # Mid bridge
	add_spawn_point(Vector3(2, 2, 15))   # Mid left
	add_spawn_point(Vector3(2, 2, 13))    # Mid right
	
	print("Default spawn points setup complete: ", spawn_points.size(), " points available")

func get_available_spawn_point(exclude_player_id: int = -1) -> Vector3:
	"""Get the next available spawn point, avoiding occupied ones"""
	
	# If no spawn points, return default position
	if spawn_points.is_empty():
		print("WARNING: No spawn points available, using default position")
		return Vector3(0, 2, 15)
	
	# Try to find an unused spawn point
	for i in range(spawn_points.size()):
		var is_used = false
		for player_id in used_spawn_points:
			if used_spawn_points[player_id] == i and player_id != exclude_player_id:
				is_used = true
				break
		
		if not is_used:
			print("Assigned spawn point ", i, " at position: ", spawn_points[i])
			return spawn_points[i]
	
	# If all are used, return the first one (players can overlap)
	print("All spawn points used, returning first spawn point")
	return spawn_points[0]

func assign_spawn_point(player_id: int) -> Vector3:
	"""Assign a spawn point to a specific player"""
	var spawn_position = get_available_spawn_point()
	
	# Find the index of this position
	for i in range(spawn_points.size()):
		if spawn_points[i] == spawn_position:
			used_spawn_points[player_id] = i
			break
	
	print("Player ", player_id, " assigned spawn point at: ", spawn_position)
	return spawn_position

func release_spawn_point(player_id: int):
	"""Release a spawn point when a player leaves"""
	if player_id in used_spawn_points:
		var spawn_index = used_spawn_points[player_id]
		used_spawn_points.erase(player_id)
		print("Released spawn point ", spawn_index, " for player ", player_id)

func get_spawn_point_count() -> int:
	"""Get total number of available spawn points"""
	return spawn_points.size()

func get_used_spawn_point_count() -> int:
	"""Get number of currently used spawn points"""
	return used_spawn_points.size()

func is_position_safe(_position: Vector3, _exclude_player_id: int = -1) -> bool:
	"""Check if a spawn position is safe (not inside other players)"""
	# This is a placeholder - in a real implementation, we'd check collision with other players
	# For now, we'll assume all spawn points are safe
	return true

func get_nearest_spawn_point(target_position: Vector3) -> Vector3:
	"""Get the spawn point nearest to a target position"""
	if spawn_points.is_empty():
		return Vector3(0, 2, 15)
	
	var nearest_point = spawn_points[0]
	var nearest_distance = target_position.distance_to(nearest_point)
	
	for spawn_point in spawn_points:
		var distance = target_position.distance_to(spawn_point)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_point = spawn_point
	
	return nearest_point

func cleanup():
	"""Clean up spawn manager resources"""
	spawn_points.clear()
	used_spawn_points.clear()
	print("SpawnManager cleanup complete")