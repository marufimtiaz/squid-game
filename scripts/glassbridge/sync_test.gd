# Step 8: Sync Data Testing Script
# This script demonstrates and tests the sync data structures

extends Node

func _ready():
	print("=== Step 8: Testing Sync Data Structures ===")
	test_player_sync_data()
	test_platform_sync_data()
	test_game_sync_data()
	test_input_sync_data()
	print("=== All Sync Data Tests Completed ===")

func test_player_sync_data():
	print("\n--- Testing PlayerSyncData ---")
	
	# Create sample player sync data
	var player_sync = SyncData.PlayerSyncData.new(
		1,  # player_id
		Vector3(10, 5, -3),  # position
		Vector3(0, 45, 0),   # rotation
		"running",           # animation_state
		PlayerManager.UIState.PLAYING,  # ui_state
		GameManager.State.PLAYING       # game_state
	)
	
	# Test serialization
	var dict_data = player_sync.to_dict()
	print("Player sync to dict: ", dict_data)
	
	# Test deserialization
	var new_sync = SyncData.PlayerSyncData.new()
	new_sync.from_dict(dict_data)
	print("Deserialized player_id: ", new_sync.player_id)
	print("Deserialized position: ", new_sync.position)

func test_platform_sync_data():
	print("\n--- Testing PlatformSyncData ---")
	
	# Create sample platform sync data
	var platform_sync = SyncData.PlatformSyncData.new(
		"Platform_Layer3_01",  # platform_id
		PlatformManager.Glass.BRITTLE,  # state
		0.75,  # timer_remaining
		[1, 2]  # affected_players
	)
	
	# Test serialization
	var dict_data = platform_sync.to_dict()
	print("Platform sync to dict: ", dict_data)
	
	# Test deserialization
	var new_sync = SyncData.PlatformSyncData.new()
	new_sync.from_dict(dict_data)
	print("Deserialized platform_id: ", new_sync.platform_id)
	print("Deserialized timer_remaining: ", new_sync.timer_remaining)
	print("Deserialized affected_players: ", new_sync.affected_players)

func test_game_sync_data():
	print("\n--- Testing GameSyncData ---")
	
	# Create sample game sync data
	var game_sync = SyncData.GameSyncData.new()
	
	# Add some player data
	var player1_sync = SyncData.PlayerSyncData.new(1, Vector3.ZERO, Vector3.ZERO, "idle", PlayerManager.UIState.PLAYING, GameManager.State.PLAYING)
	var player2_sync = SyncData.PlayerSyncData.new(2, Vector3(5, 0, 0), Vector3.ZERO, "running", PlayerManager.UIState.MENU_OPEN, GameManager.State.DEAD)
	game_sync.players[1] = player1_sync
	game_sync.players[2] = player2_sync
	
	# Add some platform data
	var platform1_sync = SyncData.PlatformSyncData.new("Platform_01", PlatformManager.Glass.SOLID, 0.0, [])
	var platform2_sync = SyncData.PlatformSyncData.new("Platform_02", PlatformManager.Glass.BRITTLE, 1.2, [1])
	game_sync.platforms["Platform_01"] = platform1_sync
	game_sync.platforms["Platform_02"] = platform2_sync
	
	game_sync.game_finished = false
	game_sync.game_result = ""
	
	# Test serialization
	var dict_data = game_sync.to_dict()
	print("Game sync data size: Players=", dict_data["players"].size(), " Platforms=", dict_data["platforms"].size())
	
	# Test deserialization
	var new_sync = SyncData.GameSyncData.new()
	new_sync.from_dict(dict_data)
	print("Deserialized players count: ", new_sync.players.size())
	print("Deserialized platforms count: ", new_sync.platforms.size())
	print("Player 2 game state: ", new_sync.players[2].game_state)

func test_input_sync_data():
	print("\n--- Testing InputSyncData ---")
	
	# Create sample input sync data
	var input_sync = SyncData.InputSyncData.new(
		1,  # player_id
		Vector2(0.5, -0.8),  # movement_vector
		Vector2(12.3, -5.7),  # look_delta
		true,  # jump_pressed
		false  # menu_toggled
	)
	
	# Test serialization
	var dict_data = input_sync.to_dict()
	print("Input sync to dict: ", dict_data)
	
	# Test deserialization
	var new_sync = SyncData.InputSyncData.new()
	new_sync.from_dict(dict_data)
	print("Deserialized player_id: ", new_sync.player_id)
	print("Deserialized movement_vector: ", new_sync.movement_vector)
	print("Deserialized jump_pressed: ", new_sync.jump_pressed)