class_name SyncData
extends RefCounted

# Step 8: Network Sync Data Structures
# These classes define what data needs to be synchronized between clients

class PlayerSyncData extends RefCounted:
	var player_id: int
	var position: Vector3
	var rotation: Vector3
	var animation_state: String
	var ui_state: PlayerManager.UIState
	var game_state: GameManager.State
	
	func _init(p_player_id: int = 0, p_position: Vector3 = Vector3.ZERO, p_rotation: Vector3 = Vector3.ZERO, p_animation_state: String = "", p_ui_state: PlayerManager.UIState = PlayerManager.UIState.PLAYING, p_game_state: GameManager.State = GameManager.State.PLAYING):
		player_id = p_player_id
		position = p_position
		rotation = p_rotation
		animation_state = p_animation_state
		ui_state = p_ui_state
		game_state = p_game_state
	
	func to_dict() -> Dictionary:
		return {
			"player_id": player_id,
			"position": {"x": position.x, "y": position.y, "z": position.z},
			"rotation": {"x": rotation.x, "y": rotation.y, "z": rotation.z},
			"animation_state": animation_state,
			"ui_state": ui_state,
			"game_state": game_state
		}
	
	func from_dict(data: Dictionary):
		player_id = data.get("player_id", 0)
		position = Vector3(data.get("position", {}).get("x", 0), data.get("position", {}).get("y", 0), data.get("position", {}).get("z", 0))
		rotation = Vector3(data.get("rotation", {}).get("x", 0), data.get("rotation", {}).get("y", 0), data.get("rotation", {}).get("z", 0))
		animation_state = data.get("animation_state", "")
		ui_state = data.get("ui_state", PlayerManager.UIState.PLAYING)
		game_state = data.get("game_state", GameManager.State.PLAYING)

class PlatformSyncData extends RefCounted:
	var platform_id: String
	var state: PlatformManager.Glass
	var timer_remaining: float
	var affected_players: Array[int]
	
	func _init(p_platform_id: String = "", p_state: PlatformManager.Glass = PlatformManager.Glass.SOLID, p_timer_remaining: float = 0.0, p_affected_players: Array[int] = []):
		platform_id = p_platform_id
		state = p_state
		timer_remaining = p_timer_remaining
		affected_players = p_affected_players
	
	func to_dict() -> Dictionary:
		return {
			"platform_id": platform_id,
			"state": state,
			"timer_remaining": timer_remaining,
			"affected_players": affected_players
		}
	
	func from_dict(data: Dictionary):
		platform_id = data.get("platform_id", "")
		state = data.get("state", PlatformManager.Glass.SOLID)
		timer_remaining = data.get("timer_remaining", 0.0)
		affected_players = data.get("affected_players", [])

class GameSyncData extends RefCounted:
	var platforms: Dictionary  # platform_id -> PlatformSyncData
	var players: Dictionary    # player_id -> PlayerSyncData
	var game_finished: bool
	var game_result: String
	
	func _init():
		platforms = {}
		players = {}
		game_finished = false
		game_result = ""
	
	func to_dict() -> Dictionary:
		var platforms_dict = {}
		for platform_id in platforms:
			platforms_dict[platform_id] = platforms[platform_id].to_dict()
		
		var players_dict = {}
		for player_id in players:
			players_dict[player_id] = players[player_id].to_dict()
		
		return {
			"platforms": platforms_dict,
			"players": players_dict,
			"game_finished": game_finished,
			"game_result": game_result
		}
	
	func from_dict(data: Dictionary):
		platforms = {}
		var platforms_data = data.get("platforms", {})
		for platform_id in platforms_data:
			var platform_sync = PlatformSyncData.new()
			platform_sync.from_dict(platforms_data[platform_id])
			platforms[platform_id] = platform_sync
		
		players = {}
		var players_data = data.get("players", {})
		for player_id in players_data:
			var player_sync = PlayerSyncData.new()
			player_sync.from_dict(players_data[player_id])
			players[player_id] = player_sync
		
		game_finished = data.get("game_finished", false)
		game_result = data.get("game_result", "")

class InputSyncData extends RefCounted:
	var player_id: int
	var movement_vector: Vector2
	var look_delta: Vector2
	var jump_pressed: bool
	var menu_toggled: bool
	
	func _init(p_player_id: int = 0, p_movement_vector: Vector2 = Vector2.ZERO, p_look_delta: Vector2 = Vector2.ZERO, p_jump_pressed: bool = false, p_menu_toggled: bool = false):
		player_id = p_player_id
		movement_vector = p_movement_vector
		look_delta = p_look_delta
		jump_pressed = p_jump_pressed
		menu_toggled = p_menu_toggled
	
	func to_dict() -> Dictionary:
		return {
			"player_id": player_id,
			"movement_vector": {"x": movement_vector.x, "y": movement_vector.y},
			"look_delta": {"x": look_delta.x, "y": look_delta.y},
			"jump_pressed": jump_pressed,
			"menu_toggled": menu_toggled
		}
	
	func from_dict(data: Dictionary):
		player_id = data.get("player_id", 0)
		movement_vector = Vector2(data.get("movement_vector", {}).get("x", 0), data.get("movement_vector", {}).get("y", 0))
		look_delta = Vector2(data.get("look_delta", {}).get("x", 0), data.get("look_delta", {}).get("y", 0))
		jump_pressed = data.get("jump_pressed", false)
		menu_toggled = data.get("menu_toggled", false)
