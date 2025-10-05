extends Node3D

# Multiplayer setup - no hardcoded player reference
@onready var platforms: Node3D = $Platforms
@onready var goaltimer: Timer = $Platforms/FinishPlatform/Goal/Timer
@onready var layer3: Node = $Platforms/Layer3
@onready var layer4: Node = $Platforms/Layer4
@onready var killzone: Area3D = $Killzone

# Multiplayer spawning
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
const PLAYER_SCENE = preload("res://scenes/glassbridge/player_glass.tscn")

# Pause screen
@onready var pause_screen: Control

# Managers
var player_manager: PlayerManager
var platform_manager: PlatformManager
var game_manager: GameManager
var spawn_manager: SpawnManager

func _ready() -> void:
	print("===== MULTIPLAYER GAME SETUP STARTING =====")
	
	# Initialize player manager without hardcoded player
	player_manager = PlayerManager.new(null)
	print("SETUP: PlayerManager initialized")
	
	# Setup multiplayer spawning first
	print("SETUP: Calling setup_multiplayer_spawning...")
	setup_multiplayer_spawning()
	
	# Load and setup pause screen
	setup_pause_screen()
	
	# Step 9: Initialize spawn manager
	spawn_manager = SpawnManager.new(self)
	spawn_manager.setup_default_spawn_points()
	
	# Set spawn manager reference in player manager
	player_manager.set_spawn_manager(spawn_manager)
	
	# Players will be spawned automatically via MultiplayerSpawner
	# No need to move hardcoded player
	
	# Set player scene for spawning (load from current player)
	var player_scene_path = "res://scenes/glassbridge/player_glass.tscn"  # Assuming this is the player scene
	var player_scene_resource = load(player_scene_path) as PackedScene
	if player_scene_resource:
		player_manager.set_player_scene(player_scene_resource)
	
	# Initialize managers with player manager
	platform_manager = PlatformManager.new(self, player_manager)
	game_manager = GameManager.new(self, player_manager, goaltimer)
	
	# Connect game manager signals
	game_manager.player_won.connect(_on_player_won)
	game_manager.player_died.connect(_on_player_died)
	game_manager.state_changed.connect(_on_game_state_changed)
	
	# MULTIPLAYER FIX: Both host and clients create platforms, but only host determines configuration
	if multiplayer.is_server():
		print("HOST: Generating platforms (will sync configuration to clients as they join)...")
		platform_manager.setup_platforms(layer3, layer4)
	else:
		print("CLIENT: Creating platforms and waiting for host configuration...")
		# Clients need to create the platforms first, then configuration will be applied
		platform_manager.create_empty_platforms(layer3, layer4)
	
	# Setup killzone reference to game manager
	#var killzone = $KillZone

	if killzone and killzone.has_method("set"):
		killzone.game_manager = game_manager
		killzone.player_manager = player_manager
	
	# Auto-capture mouse when game starts (centralized input handling)
	player_manager.capture_mouse()
	
	# Step 8: Setup periodic sync logging
	setup_sync_logging()
	
	print("===== GAME SETUP COMPLETE =====")

func setup_multiplayer_spawning():
	"""Setup MultiplayerSpawner with automatic spawning"""
	print("Setting up multiplayer spawning...")
	
	# Restore peer_connected signal for manual remote player spawning
	if multiplayer.peer_connected.is_connected(_on_player_joined):
		multiplayer.peer_connected.disconnect(_on_player_joined)
	if multiplayer.peer_disconnected.is_connected(_on_player_left):
		multiplayer.peer_disconnected.disconnect(_on_player_left)
	
	multiplayer.peer_connected.connect(_on_player_joined)
	multiplayer.peer_disconnected.connect(_on_player_left)
	
	# DISABLE MultiplayerSpawner to avoid conflicts with manual spawning
	if multiplayer_spawner:
		# Disable automatic spawning by removing spawnable scenes
		multiplayer_spawner._spawnable_scenes = PackedStringArray()
		multiplayer_spawner.spawn_limit = 0
		
		# Revert to manual spawning - it was working better
		if multiplayer.has_multiplayer_peer():
			call_deferred("spawn_local_player_manual")
		else:
			call_deferred("spawn_single_player_fallback")



# REMOVED: spawn_all_connected_players - reverting to manual spawning approach

func spawn_local_player_manual():
	"""Manually spawn only the local player - using unified RPC positioning"""
	print("SPAWN: Spawning local player manually...")
	
	var local_peer_id = multiplayer.get_unique_id()
	
	if multiplayer.is_server():
		# HOST: Spawn locally and coordinate with others
		print("SPAWN: HOST spawning local player for peer: ", local_peer_id)
		spawn_local_player_as_host(local_peer_id)
	else:
		# CLIENT: Request spawn from host via RPC
		print("SPAWN: CLIENT requesting spawn from host for peer: ", local_peer_id)
		rpc_request_spawn_from_host.rpc_id(1, local_peer_id)

func spawn_local_player_as_host(peer_id: int):
	"""Host spawns local player with proper positioning"""
	print("SPAWN: Creating local host player for peer: ", peer_id)
	
	# Calculate position using the same logic as remote players
	var spawn_position = calculate_deterministic_spawn_position(peer_id)
	
	# Spawn at the calculated position
	spawn_player_at_position(peer_id, spawn_position, true)

@rpc("any_peer", "call_local", "reliable")
func rpc_request_spawn_from_host(peer_id: int):
	"""RPC call from client to host requesting to be spawned"""

	
	# Only host should handle spawn requests
	if not multiplayer.is_server():
		print("RPC: Not host, ignoring spawn request")
		return
	
	# Calculate spawn position for the requesting client
	var spawn_position = calculate_deterministic_spawn_position(peer_id)
	
	# Tell the specific client where to spawn themselves
	rpc_spawn_local_at_position.rpc_id(peer_id, peer_id, spawn_position)
	
	# Tell all OTHER clients about this new player (not the requesting client)
	rpc_spawn_player_for_clients.rpc(peer_id, spawn_position)

@rpc("any_peer", "call_local", "reliable")
func rpc_spawn_local_at_position(peer_id: int, spawn_position: Vector3):
	"""RPC call from host to client telling them where to spawn themselves"""

	
	# Spawn locally at the position specified by host
	spawn_player_at_position(peer_id, spawn_position, true)

func spawn_player_at_position(peer_id: int, spawn_position: Vector3, is_local: bool):
	"""Unified function to spawn a player (local or remote) at a specific position"""
	var player_type = "LOCAL" if is_local else "REMOTE"
	print("SPAWN: Creating ", player_type, " player for peer: ", peer_id, " at: ", spawn_position)
	
	# Load the player scene
	var player_scene = load("res://scenes/glassbridge/player_glass.tscn") as PackedScene
	if not player_scene:
		print("SPAWN ERROR: Could not load player scene!")
		return
	
	# Instantiate player
	var new_player = player_scene.instantiate() as CharacterBody3D
	if not new_player:
		print("SPAWN ERROR: Failed to instantiate player for peer: ", peer_id)
		return
	
	# Add to scene tree FIRST to ensure proper initialization
	var unique_name = "Player_" + str(peer_id)
	new_player.name = unique_name
	add_child(new_player, true)  # true = force_readable_name
	
	# Set multiplayer authority AFTER adding to scene tree
	new_player.set_multiplayer_authority(peer_id)
	
	# Also set authority for MultiplayerSynchronizer AFTER scene tree addition
	var synchronizer = new_player.get_node_or_null("MultiplayerSynchronizer")
	if synchronizer:
		synchronizer.set_multiplayer_authority(peer_id)
		print("SPAWN: MultiplayerSynchronizer setup - Authority: ", peer_id, " Current: ", synchronizer.get_multiplayer_authority(), " Local: ", multiplayer.get_unique_id())
	else:
		print("SPAWN ERROR: MultiplayerSynchronizer not found in player!")
	
	print("SPAWN: Player added to scene - Name: ", new_player.name, " Path: ", new_player.get_path())
	
	# Position the player at the specified location
	new_player.global_position = spawn_position
	
	# Configure player properties manually
	new_player.player_id = peer_id
	new_player.player_name = "Player " + str(peer_id)
	new_player.player_manager = player_manager
	new_player.game_manager = game_manager
	
	# Setup camera based on whether this is local or remote
	var camera = new_player.get_node_or_null("Head/Camera3D")
	if camera:
		if is_local:
			# For local player: disable ALL other cameras first, then enable this one
			var all_cameras_in_scene = []
			_find_all_cameras(get_tree().current_scene, all_cameras_in_scene)
			
			for other_camera in all_cameras_in_scene:
				if other_camera != camera and other_camera.current:
					other_camera.current = false
			
			# Now set this camera as current
			camera.current = true
			print("Local camera enabled for peer: ", peer_id)
		else:
			# For remote players: make sure camera is disabled
			camera.current = false
	
	# Add to managers
	if player_manager:
		player_manager.add_player(new_player)
		if is_local:
			# Set as primary player if local (direct access since no setter exists)
			player_manager._primary_player = new_player
	
	if game_manager:
		game_manager.add_player_to_game(peer_id)
	
	# Connect fallimpact signal to killzone for game completion check
	if new_player.has_signal("fallimpact_finished"):
		if not new_player.fallimpact_finished.is_connected(killzone._on_player_fallimpact_finished):
			new_player.fallimpact_finished.connect(killzone._on_player_fallimpact_finished)
			print("SPAWN: Connected fallimpact_finished signal for player ", peer_id)
	
	print("SPAWN: Player configured for peer ", peer_id, " at position: ", spawn_position)

func _on_player_joined(peer_id: int):
	"""Handle when a new player joins during gameplay - HOST MANAGES ALL SPAWNING"""
	print("Player ", peer_id, " joined the game")
	print("SPAWN: Current multiplayer ID: ", multiplayer.get_unique_id())
	print("SPAWN: Am I host?: ", multiplayer.is_server())
	print("SPAWN: Current scene children: ", get_children().map(func(child): return child.name))
	
	# ONLY the host manages all spawning coordination
	if not multiplayer.is_server():
		print("SPAWN: Not host, ignoring player join coordination")
		return
	
	# HOST: Send platform configuration to the new client
	print("HOST: Sending platform configuration to new client: ", peer_id)
	var config_data = platform_manager.get_platform_configuration_data()
	sync_platform_configuration_to_clients.rpc_id(peer_id, config_data)
	
	# HOST: Collect list of all existing players with their positions (except the new one)
	var existing_players_data = []
	for child in get_children():
		if child.name.begins_with("Player_"):
			var existing_peer_id = child.name.get_slice("_", 1).to_int()
			if existing_peer_id != peer_id:
				existing_players_data.append([existing_peer_id, child.global_position])
	
	# HOST: Tell the new client about all existing players
	if existing_players_data.size() > 0:
		print("SPAWN: Telling new player ", peer_id, " about existing players: ", existing_players_data)
		rpc_sync_existing_players.rpc_id(peer_id, existing_players_data)
	
	# HOST: Calculate deterministic spawn position for the new player
	var spawn_position = calculate_deterministic_spawn_position(peer_id)
	
	# HOST: Tell all existing clients about the new player with their position
	print("SPAWN: Telling all clients about new player: ", peer_id, " at position: ", spawn_position)
	rpc_spawn_player_for_clients.rpc(peer_id, spawn_position)

func configure_spawned_player(new_player: CharacterBody3D):
	"""Configure a manually spawned player (position, camera, etc.)"""
	var peer_id = new_player.get_multiplayer_authority()
	print("SPAWN: Configuring spawned player for peer: ", peer_id)
	
	# Configure the spawned player
	new_player.player_id = peer_id
	new_player.player_name = "Player " + str(peer_id)
	
	# Get spawn position - use deterministic assignment based on peer order
	var spawn_position = Vector3(0, 2, 20)  # Default position
	if spawn_manager:
		# Get sorted list of all connected peers (including host and self)
		var all_peers = multiplayer.get_peers()
		# Always add host (peer 1) to the list if not already there
		if not all_peers.has(1):
			all_peers.append(1)
		# Always add self to the list if not already there
		var my_id = multiplayer.get_unique_id()
		if not all_peers.has(my_id):
			all_peers.append(my_id)
		all_peers.sort()
		
		print("SPAWN: DEBUG - All peers: ", all_peers, " Target peer: ", peer_id)
		
		# Find this peer's index in the sorted list
		var peer_index = all_peers.find(peer_id)
		print("SPAWN: DEBUG - Peer index: ", peer_index, " Spawn point count: ", spawn_manager.get_spawn_point_count())
		
		if peer_index >= 0 and peer_index < spawn_manager.get_spawn_point_count():
			# Assign spawn point based on connection order
			spawn_position = spawn_manager.spawn_points[peer_index]
			print("SPAWN: Deterministic spawn - Peer ", peer_id, " gets index ", peer_index, " at ", spawn_position)
		else:
			# Fallback to old method
			spawn_position = spawn_manager.assign_spawn_point(peer_id)
	
	# Position the player
	new_player.global_position = spawn_position
	
	# Camera management: Only enable camera for local player
	var is_local_in_configure = peer_id == multiplayer.get_unique_id()
	var camera = new_player.get_node_or_null("Head/Camera3D")
	if camera:
		print("SPAWN: Camera setup - Peer: ", peer_id, " Local: ", is_local_in_configure, " MyID: ", multiplayer.get_unique_id())
		
		if is_local_in_configure:
			# For local player: disable ALL other cameras first, then enable this one
			print("SPAWN: Setting up LOCAL player camera for peer: ", peer_id)
			
			# Find and disable all existing Camera3D nodes in the scene
			var all_cameras_in_scene = []
			_find_all_cameras(get_tree().current_scene, all_cameras_in_scene)
			
			for other_camera in all_cameras_in_scene:
				if other_camera != camera and other_camera.current:
					other_camera.current = false
					print("SPAWN: Disabled existing camera: ", other_camera.get_path())
			
			# Now set this camera as current
			camera.current = true
			print("SPAWN: LOCAL camera set as current: ", camera.current)
		else:
			# For remote players: make sure camera is disabled
			camera.current = false
			print("SPAWN: REMOTE player camera disabled for peer: ", peer_id)
		
		print("SPAWN: Final camera state - Peer: ", peer_id, " Current: ", camera.current, " Path: ", camera.get_path())
	
	# Add to PlayerManager
	var added_to_manager = player_manager.add_player(new_player)
	print("SPAWN: Added to PlayerManager: ", added_to_manager)
	print("SPAWN: PlayerManager now has ", player_manager.get_player_count(), " players")
	
	if is_local_player:
		# Set as primary player if local (direct access since no setter exists)
		player_manager._primary_player = new_player
		print("SPAWN: Set as primary player (local)")
	
	print("SPAWN: Primary player is now: ", player_manager.get_primary_player())
	
	# Set player manager reference in player
	new_player.player_manager = player_manager
	
	# Add player to GameManager
	game_manager.add_player_to_game(peer_id)
	print("SPAWN: Added to GameManager for peer: ", peer_id)
	
	print("SPAWN: Player configured for peer ", peer_id, " at position: ", spawn_position)
	print("SPAWN: Total players now: ", game_manager.get_active_player_count())

func spawn_remote_player(peer_id: int):
	"""Spawn a remote player for a peer that joined"""
	print("SPAWN: Creating remote player for peer: ", peer_id)
	
	# Load the player scene
	var player_scene = load("res://scenes/glassbridge/player_glass.tscn") as PackedScene
	if not player_scene:
		print("SPAWN ERROR: Could not load player scene for remote player!")
		return
	
	# Instantiate remote player
	var remote_player = player_scene.instantiate() as CharacterBody3D
	if not remote_player:
		print("SPAWN ERROR: Failed to instantiate remote player for peer: ", peer_id)
		return
	
	# Add to scene tree FIRST before setting authority
	var unique_name = "Player_" + str(peer_id)
	remote_player.name = unique_name
	add_child(remote_player, true)
	
	# Set multiplayer authority AFTER adding to scene tree
	remote_player.set_multiplayer_authority(peer_id)
	
	# Also set authority for MultiplayerSynchronizer AFTER scene tree addition
	var synchronizer = remote_player.get_node_or_null("MultiplayerSynchronizer")
	if synchronizer:
		synchronizer.set_multiplayer_authority(peer_id)
		print("SPAWN: Remote MultiplayerSynchronizer setup - Authority: ", peer_id)
	else:
		print("SPAWN ERROR: MultiplayerSynchronizer not found in remote player!")
	
	print("SPAWN: Remote player added - Name: ", remote_player.name, " Path: ", remote_player.get_path())
	
	# Configure the remote player manually (no MultiplayerSpawner)
	configure_spawned_player(remote_player)

@rpc("any_peer", "call_local", "reliable")
func rpc_sync_existing_players(existing_players_data: Array):
	"""RPC call from host to new client to spawn all existing players with positions"""

	
	for player_data in existing_players_data:
		var peer_id = player_data[0]
		var spawn_position = player_data[1]
		
		# Skip if player already exists
		var player_name = "Player_" + str(peer_id)
		if has_node(player_name):
			print("RPC: Player ", peer_id, " already exists, skipping")
			continue
		
		# Spawn the remote player locally at the specified position

		spawn_remote_player_at_position(peer_id, spawn_position)

@rpc("any_peer", "call_local", "reliable")
func rpc_spawn_player_for_clients(peer_id: int, spawn_position: Vector3):
	"""RPC call from host to all clients to spawn a remote player at specific position"""

	
	# Skip if this is the local player (they spawn themselves)
	if peer_id == multiplayer.get_unique_id():

		return
	
	# Skip if player already exists
	var player_name = "Player_" + str(peer_id)
	if has_node(player_name):
		print("RPC: Player ", peer_id, " already exists, skipping")
		return
	
	# Spawn the remote player locally at the specified position

	spawn_remote_player_at_position(peer_id, spawn_position)

func calculate_deterministic_spawn_position(peer_id: int) -> Vector3:
	"""Calculate deterministic spawn position for a peer - HOST ONLY"""
	var spawn_position = Vector3(0, 2, 20)  # Default position
	
	if not spawn_manager:
		return spawn_position
	
	# Get current list of all existing players (from scene, not multiplayer.get_peers())
	var existing_peers = []
	for child in get_children():
		if child.name.begins_with("Player_"):
			var existing_peer_id = child.name.get_slice("_", 1).to_int()
			existing_peers.append(existing_peer_id)
	
	# The new peer gets the next available spawn index (don't add to list, just count)
	var next_spawn_index = existing_peers.size()
	
	print("HOST: Calculating spawn for peer ", peer_id, " - existing players: ", existing_peers, " next index: ", next_spawn_index)
	
	if next_spawn_index < spawn_manager.get_spawn_point_count():
		spawn_position = spawn_manager.spawn_points[next_spawn_index]
		print("HOST: Deterministic spawn - Peer ", peer_id, " gets next available index ", next_spawn_index, " at ", spawn_position)
	else:
		# Fallback to old method
		spawn_position = spawn_manager.assign_spawn_point(peer_id)
		print("HOST: Using fallback spawn for peer ", peer_id, " at ", spawn_position)
	
	return spawn_position

func spawn_remote_player_at_position(peer_id: int, spawn_position: Vector3):
	"""Spawn a remote player at a specific position"""
	print("SPAWN: Creating remote player for peer: ", peer_id, " at position: ", spawn_position)
	
	# Load the player scene
	var player_scene = load("res://scenes/glassbridge/player_glass.tscn") as PackedScene
	if not player_scene:
		print("SPAWN ERROR: Could not load player scene for remote player!")
		return
	
	# Instantiate remote player
	var remote_player = player_scene.instantiate() as CharacterBody3D
	if not remote_player:
		print("SPAWN ERROR: Failed to instantiate remote player for peer: ", peer_id)
		return
	
	# Add to scene tree FIRST before setting authority
	var unique_name = "Player_" + str(peer_id)
	remote_player.name = unique_name
	add_child(remote_player, true)
	
	# Set multiplayer authority AFTER adding to scene tree
	remote_player.set_multiplayer_authority(peer_id)
	
	# Also set authority for MultiplayerSynchronizer AFTER scene tree addition
	var synchronizer = remote_player.get_node_or_null("MultiplayerSynchronizer")
	if synchronizer:
		synchronizer.set_multiplayer_authority(peer_id)
		print("SPAWN: Remote MultiplayerSynchronizer setup - Authority: ", peer_id)
	else:
		print("SPAWN ERROR: MultiplayerSynchronizer not found in remote player!")
	
	print("SPAWN: Remote player added - Name: ", remote_player.name, " Path: ", remote_player.get_path())
	
	# Position the player at the specified location
	remote_player.global_position = spawn_position
	
	# Configure player properties
	remote_player.player_id = peer_id
	remote_player.player_name = "Player " + str(peer_id)
	
	# Set player manager reference in player
	remote_player.player_manager = player_manager
	
	# Setup camera (disabled for remote players)  
	var camera = remote_player.get_node_or_null("Head/Camera3D")
	if camera:
		print("SPAWN: Camera setup - Peer: ", peer_id, " Local: false MyID: ", multiplayer.get_unique_id())
		camera.current = false
		print("SPAWN: REMOTE player camera disabled for peer: ", peer_id)
		print("SPAWN: Final camera state - Peer: ", peer_id, " Current: ", camera.current, " Path: ", camera.get_path())
	
	# Add to managers
	if player_manager:
		var added_to_manager = player_manager.add_player(remote_player)
		print("SPAWN: Added to PlayerManager: ", added_to_manager)
		print("SPAWN: PlayerManager now has ", player_manager.get_player_count(), " players")
		
		# Don't set as primary - keep existing primary
		var current_primary = player_manager.get_primary_player()
		if current_primary:
			print("SPAWN: Primary player is now: ", current_primary.name, ":", current_primary)
	
	if game_manager:
		game_manager.add_player_to_game(peer_id)
		print("SPAWN: Added to GameManager for peer: ", peer_id)
	
	print("SPAWN: Player configured for peer ", peer_id, " at position: ", spawn_position)

func _on_player_spawned(node: Node):
	"""Handle when MultiplayerSpawner spawns a new player"""
	print("SPAWN: Player node spawned: ", node)
	var new_player = node as CharacterBody3D
	if not new_player:
		print("SPAWN ERROR: Spawned node is not CharacterBody3D!")
		return
		
	var peer_id = new_player.get_multiplayer_authority()
	print("SPAWN: MultiplayerSpawner spawned player for peer: ", peer_id)
	
	# Configure the spawned player
	new_player.player_id = peer_id
	new_player.player_name = "Player " + str(peer_id)
	
	# Get spawn position - use deterministic assignment based on peer order
	var spawn_position = Vector3(0, 2, 20)  # Default position
	if spawn_manager:
		# Get sorted list of all connected peers (including host and self)
		var all_peers = multiplayer.get_peers()
		# Always add host (peer 1) to the list if not already there
		if not all_peers.has(1):
			all_peers.append(1)
		# Always add self to the list if not already there
		var my_id = multiplayer.get_unique_id()
		if not all_peers.has(my_id):
			all_peers.append(my_id)
		all_peers.sort()
		
		print("SPAWN: DEBUG - All peers: ", all_peers, " Target peer: ", peer_id)
		
		# Find this peer's index in the sorted list
		var peer_index = all_peers.find(peer_id)
		print("SPAWN: DEBUG - Peer index: ", peer_index, " Spawn point count: ", spawn_manager.get_spawn_point_count())
		
		if peer_index >= 0 and peer_index < spawn_manager.get_spawn_point_count():
			# Assign spawn point based on connection order
			spawn_position = spawn_manager.spawn_points[peer_index]
			print("SPAWN: Deterministic spawn - Peer ", peer_id, " gets index ", peer_index, " at ", spawn_position)
		else:
			# Fallback to old method
			spawn_position = spawn_manager.assign_spawn_point(peer_id)
	
	# Position the player
	new_player.global_position = spawn_position
	
	# Camera management: Only enable camera for local player
	var is_local_in_spawned = peer_id == multiplayer.get_unique_id()
	var camera = new_player.get_node_or_null("Head/Camera3D")
	if camera:
		print("SPAWN: Camera setup - Peer: ", peer_id, " Local: ", is_local_in_spawned, " MyID: ", multiplayer.get_unique_id())
		
		if is_local_in_spawned:
			# For local player: disable ALL other cameras first, then enable this one
			print("SPAWN: Setting up LOCAL player camera for peer: ", peer_id)
			
			# Find and disable all existing Camera3D nodes in the scene
			var all_cameras_in_scene = []
			_find_all_cameras(get_tree().current_scene, all_cameras_in_scene)
			
			for other_camera in all_cameras_in_scene:
				if other_camera != camera and other_camera.current:
					other_camera.current = false
					print("SPAWN: Disabled existing camera: ", other_camera.get_path())
			
			# Now set this camera as current
			camera.current = true
			print("SPAWN: LOCAL camera set as current: ", camera.current)
		else:
			# For remote player: never set as current
			camera.current = false
			print("SPAWN: REMOTE player camera disabled for peer: ", peer_id)
		
		print("SPAWN: Final camera state - Peer: ", peer_id, " Current: ", camera.current, " Path: ", camera.get_path())
	else:
		print("SPAWN ERROR: No camera found in player for peer: ", peer_id)

	
	# Add to player manager
	var add_success = player_manager.add_player(new_player)
	print("SPAWN: Added to PlayerManager: ", add_success)
	print("SPAWN: PlayerManager now has ", player_manager.get_player_count(), " players")
	
	# Set as primary player if this is the local player
	if is_local_player:
		player_manager._primary_player = new_player
		print("SPAWN: Set as primary player (local)")
	
	print("SPAWN: Primary player is now: ", player_manager.get_primary_player())
	
	# Set player manager reference in player
	new_player.player_manager = player_manager
	
	# Add to game manager
	if game_manager:
		game_manager.add_player_to_game(peer_id)
		print("SPAWN: Added to GameManager for peer: ", peer_id)
	
	print("SPAWN: Player configured for peer ", peer_id, " at position: ", spawn_position)
	print("SPAWN: Total players now: ", player_manager.get_player_count())

# Helper function to find all cameras in scene tree
func _find_all_cameras(node: Node, camera_list: Array):
	if node is Camera3D:
		camera_list.append(node)
	
	for child in node.get_children():
		_find_all_cameras(child, camera_list)

func spawn_single_player_fallback():
	"""Manually spawn a single player when not in multiplayer mode"""
	print("SPAWN: Creating single player manually...")
	
	# Create player instance
	var new_player = PLAYER_SCENE.instantiate()
	
	# Set as local player
	new_player.player_id = 1
	new_player.player_name = "Player 1"
	
	# Add to scene
	add_child(new_player)
	
	# Get spawn position and set it
	var spawn_position = Vector3(0, 2, 20)
	if spawn_manager:
		spawn_position = spawn_manager.assign_spawn_point(1)
	
	new_player.global_position = spawn_position
	
	# Enable camera for single player
	var camera = new_player.get_node_or_null("Head/Camera3D")
	if camera:
		camera.current = true
		print("SPAWN: Camera enabled for single player")
	
	# Add to managers
	player_manager.add_player(new_player)
	new_player.player_manager = player_manager
	
	# Set as primary player for single-player mode
	player_manager._primary_player = new_player
	print("SPAWN: Set as primary player (single-player)")
	
	if game_manager:
		game_manager.add_player_to_game(1)
	
	print("SPAWN: Single player created at position: ", spawn_position)
	print("SPAWN: Total players now: ", player_manager.get_player_count())

func _on_player_left(peer_id: int):
	"""Handle when a player leaves during gameplay"""
	print("DISCONNECT: Player ", peer_id, " left the game")
	print("DISCONNECT: I am server: ", multiplayer.is_server())
	print("DISCONNECT: My peer ID: ", multiplayer.get_unique_id())
	
	# Check if HOST disconnected (peer_id 1 is always the host)
	if peer_id == 1 and not multiplayer.is_server():
		print("HOST DISCONNECTED! Handling graceful client transition...")
		handle_host_disconnection()
		return
	
	# Regular player left - remove them
	var leaving_player = player_manager.get_player_by_id(peer_id)
	if leaving_player:
		player_manager.remove_player(leaving_player)
		if game_manager:
			game_manager.remove_player_from_game(peer_id)
		leaving_player.queue_free()

func handle_host_disconnection():
	"""Handle when host leaves - transition client based on their state"""
	print("DISCONNECTION: Host left, determining my result...")
	
	# Get my state before multiplayer becomes invalid
	var my_state = GameManager.State.PLAYING  # Default fallback
	
	if game_manager:
		my_state = game_manager.get_local_player_state()
		print("DISCONNECTION: My state is: ", GameManager.State.keys()[my_state])
	
	# Clean up multiplayer properly
	cleanup_multiplayer_session()
	
	# Transition based on my result (your perfect logic!)
	match my_state:
		GameManager.State.WON:
			print("DISCONNECTION: I won! Going to end screen...")
			get_tree().call_deferred("change_scene_to_file", "res://scenes/glassbridge/end_screen.tscn")
		GameManager.State.DEAD:
			print("DISCONNECTION: I died! Going to lose screen...")
			get_tree().call_deferred("change_scene_to_file", "res://scenes/glassbridge/lose_screen.tscn")
		_:  # State.PLAYING or any other state
			print("DISCONNECTION: I was still playing! Going back to multiplayer screen...")
			get_tree().call_deferred("change_scene_to_file", "res://scenes/glassbridge/multiplayer_screen.tscn")

func cleanup_multiplayer_session():
	"""Clean up multiplayer session to avoid issues joining next game"""
	print("CLEANUP: Cleaning up multiplayer session...")
	
	# Disconnect all multiplayer signals
	if multiplayer.peer_connected.is_connected(_on_player_joined):
		multiplayer.peer_connected.disconnect(_on_player_joined)
	if multiplayer.peer_disconnected.is_connected(_on_player_left):
		multiplayer.peer_disconnected.disconnect(_on_player_left)
	
	# Clear the multiplayer peer to fully disconnect
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
		print("CLEANUP: Multiplayer peer cleared")
	
	# Release mouse if it was captured
	if player_manager:
		player_manager.release_mouse()
	
	print("CLEANUP: Session cleanup complete - ready for next game!")


# Signal handlers for game manager
func _on_player_won(player_id: int):
	print("Main script: Player ", player_id, " won!")

func _on_player_died(player_id: int):
	print("Main script: Player ", player_id, " died!")

func is_local_player(player_id: int) -> bool:
	"""Check if the given player ID is the local player on this instance"""
	if not multiplayer.has_multiplayer_peer():
		# Single player mode - assume player 1 is local
		return player_id == 1
	else:
		# Multiplayer mode - check against local multiplayer ID
		return player_id == multiplayer.get_unique_id()

func _on_game_state_changed(player_id: int, new_state):
	print("Main script: Player ", player_id, " state changed to ", GameManager.State.keys()[new_state])

# Goal detection
func _on_goal_body_entered(body: Node3D) -> void:
	# AUTHORITY CHECK: Only host processes game state changes
	if multiplayer.is_server():
		game_manager.handle_goal_reached(body)

func _on_timer_timeout() -> void:
	# This is now handled by the GameManager
	pass

func _exit_tree():
	# Clean up multiplayer session first
	cleanup_multiplayer_session()
	
	# Clean up managers
	if platform_manager:
		platform_manager.cleanup()
	if player_manager:
		player_manager.cleanup()

func setup_pause_screen():
	"""Load and setup the player menu screen (Step 7: no global pause)"""
	var pause_scene = preload("res://scenes/glassbridge/pause_screen.tscn")
	pause_screen = pause_scene.instantiate()
	add_child(pause_screen)
	
	# Step 7: Menu overlay processes normally (game never pauses)
	pause_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Pass references to menu screen
	pause_screen.player_manager = player_manager
	pause_screen.main_scene = self
	
	# Initially hide the menu screen
	pause_screen.visible = false

# Step 7: Per-player menu management
func open_player_menu(player_id: int):
	"""Open menu for a specific player (game continues running)"""
	print("Opening menu for Player ", player_id)
	player_manager.set_player_ui_state(player_id, PlayerManager.UIState.MENU_OPEN)
	
	# Show menu overlay (convert old pause screen to player menu)
	pause_screen.visible = true
	player_manager.release_mouse()

func close_player_menu(player_id: int):
	"""Close menu for a specific player"""
	print("Closing menu for Player ", player_id)
	player_manager.set_player_ui_state(player_id, PlayerManager.UIState.PLAYING)
	
	# Hide menu overlay
	pause_screen.visible = false
	player_manager.capture_mouse()

func _unhandled_input(event: InputEvent):
	"""Handle player menu input and centralized mouse control"""
	# Step 7: Per-player menu handling (no global pause)
	if event.is_action_pressed("ui_cancel"):  # ESC key
		print("ESC pressed! Player count: ", player_manager.get_player_count())
		var menu_player = player_manager.get_primary_player()
		print("Primary player: ", menu_player)
		if menu_player:
			var player_id = player_manager.get_player_id(menu_player)
			var ui_state = player_manager.get_player_ui_state(player_id)
			if ui_state == PlayerManager.UIState.MENU_OPEN:
				close_player_menu(player_id)
			else:
				open_player_menu(player_id)
		else:
			print("ESC ERROR: No primary player found - can't open menu!")
			# Maybe try to get any local player instead
			var local_peer_id = multiplayer.get_unique_id()
			var local_player = player_manager.get_player_by_id(local_peer_id)
			if local_player:
				print("ESC: Found local player by ID, opening menu...")
				open_player_menu(local_peer_id)
			else:
				print("ESC ERROR: No local player found at all!")
	
	# Centralized mouse handling (Step 5: moved from player script)
	# Only process game input for players in PLAYING state
	var input_player = player_manager.get_primary_player()
	if input_player:
		var player_id = player_manager.get_player_id(input_player)
		if not player_manager.is_player_playing(player_id):
			return  # Player has menu open, ignore game input
		
	# Capture mouse with left click
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		player_manager.capture_mouse()
		
	# Release mouse with ALT key
	if event is InputEventKey and event.keycode == KEY_ALT and event.pressed:
		player_manager.release_mouse()
	


# Step 8: Network Sync Methods
func capture_player_input(player_id: int) -> SyncData.InputSyncData:
	"""Capture current input state for a specific player"""
	var input_sync = SyncData.InputSyncData.new(player_id)
	
	# Capture movement input
	input_sync.movement_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# Capture jump input
	input_sync.jump_pressed = Input.is_action_just_pressed("ui_accept")  # Space
	
	# Capture menu toggle input
	input_sync.menu_toggled = Input.is_action_just_pressed("ui_cancel")  # ESC
	
	# Mouse look delta would be captured in player script, not here
	# This is preparatory - in real multiplayer, mouse input might be handled differently
	
	return input_sync

func apply_player_input(input_sync: SyncData.InputSyncData):
	"""Apply input sync data to a specific player"""
	var target_player = player_manager.get_player_by_id(input_sync.player_id)
	if not target_player:
		return
	
	# This is preparatory - in real multiplayer we would apply the input state
	# For now, just log what we would do
	print("Would apply input to player ", input_sync.player_id, ": movement=", input_sync.movement_vector, " jump=", input_sync.jump_pressed)

func create_complete_sync_snapshot() -> SyncData.GameSyncData:
	"""Create a complete sync snapshot of current game state"""
	var sync_data = game_manager.create_game_sync_data()
	
	# Add platform data from platform manager
	sync_data.platforms = platform_manager.get_all_platforms_sync_data()
	
	return sync_data

func apply_complete_sync_snapshot(sync_data: SyncData.GameSyncData):
	"""Apply a complete sync snapshot to update game state"""
	if not sync_data:
		return
	
	# Apply platform sync data
	platform_manager.apply_all_platforms_sync_data(sync_data.platforms)
	
	# Apply game sync data (includes player data)
	game_manager.apply_game_sync_data(sync_data)

func get_sync_state_summary() -> String:
	"""Get a human-readable summary of current sync state (for debugging)"""
	var summary = []
	
	# Player states
	for game_player in player_manager.get_all_players():
		var player_id = player_manager.get_player_id(game_player)
		var game_state = game_manager.get_player_state(player_id)
		var ui_state = player_manager.get_player_ui_state(player_id)
		summary.append("Player %d: Game=%s UI=%s" % [player_id, GameManager.State.keys()[game_state], PlayerManager.UIState.keys()[ui_state]])
	
	# Platform states  
	var platform_data = platform_manager.get_all_platforms_sync_data()
	summary.append("Active platforms: %d" % platform_data.size())
	
	# Game completion
	if game_manager.is_game_finished():
		summary.append("Game finished: %s" % game_manager.get_game_result())
	
	return "Sync State: " + " | ".join(summary)

# Step 8: Simple sync logging setup
func setup_sync_logging():
	"""Setup periodic sync state logging"""
	var sync_timer = Timer.new()
	sync_timer.wait_time = 10.0  # Log sync state every 10 seconds
	sync_timer.timeout.connect(_on_sync_timer)
	add_child(sync_timer)
	sync_timer.start()
	print("SYNC Logging enabled - summary every 10 seconds")

func _on_sync_timer():
	"""Log current sync state summary"""
	var summary = get_sync_state_summary()
	print("SYNC ", summary)

@rpc("authority", "call_local", "reliable")
func sync_platform_configuration_to_clients(config_data: Array):
	"""RPC: Host sends platform configuration to all clients"""
	if not multiplayer.is_server():
		print("CLIENT: Received platform configuration from host with ", config_data.size(), " platforms")
		platform_manager.apply_platform_configuration(config_data, layer3, layer4)
	else:
		print("HOST: Synced platform configuration to all clients")

@rpc("authority", "call_local", "reliable")
func sync_game_state_rpc(game_state_data: Dictionary):
	"""RPC: Host sends game state updates to all clients"""
	if not multiplayer.is_server():
		print("CLIENT: Received game state update from host: ", game_state_data.keys())
		if game_manager:
			game_manager.apply_essential_sync_data(game_state_data)
	else:
		print("HOST: Synced game state to all clients: ", game_state_data.keys())

@rpc("authority", "call_local", "reliable") 
func sync_platform_break_rpc(platform_path: String):
	"""RPC: Host notifies all clients when a platform breaks"""
	print("RPC: Platform break sync - Path: ", platform_path, " IsServer: ", multiplayer.is_server())
	
	if not multiplayer.is_server():
		# Client side - find and remove the platform
		var platform_node = get_node_or_null(NodePath(platform_path))
		if platform_node and platform_node is CSGBox3D:
			print("CLIENT: Breaking platform via RPC: ", platform_node.name)
			platform_manager.platform_states[platform_path] = PlatformManager.Glass.BROKEN
			platform_manager.platform_objects[platform_path] = null
			platform_node.queue_free()
			platform_manager.call_deferred("_cleanup_single_platform", platform_path)
		else:
			print("CLIENT: Warning - Platform not found for breaking: ", platform_path)
	else:
		print("HOST: Platform break RPC sent to all clients: ", platform_path)

func sync_platform_break_to_clients(platform_path: String):
	"""Public method called by platform_manager to trigger RPC"""
	if multiplayer.is_server():
		print("HOST: Calling platform break RPC for: ", platform_path) 
		sync_platform_break_rpc.rpc(platform_path)
	else:
		print("CLIENT: Ignoring platform break call - not host")

@rpc("authority", "call_local", "reliable")
func sync_platform_breaking_rpc(platform_path: String):
	"""RPC: Host notifies all clients when a platform starts breaking"""
	print("RPC: Platform breaking sync - Path: ", platform_path, " IsServer: ", multiplayer.is_server())
	
	if not multiplayer.is_server():
		# Client side - find and set platform to breaking state
		var platform_node = get_node_or_null(NodePath(platform_path))
		if platform_node and platform_node is CSGBox3D:
			print("CLIENT: Setting platform to breaking via RPC: ", platform_node.name)
			platform_manager.platform_states[platform_node] = PlatformManager.Glass.BREAKING
			platform_manager.change_platform_color(platform_node, Color.YELLOW)
		else:
			print("CLIENT: Warning - Platform not found for breaking state: ", platform_path)
	else:
		print("HOST: Platform breaking RPC sent to all clients: ", platform_path)

func sync_platform_breaking_to_clients(platform_path: String):
	"""Public method called by platform_manager to trigger breaking RPC"""
	if multiplayer.is_server():
		print("HOST: Calling platform breaking RPC for: ", platform_path) 
		sync_platform_breaking_rpc.rpc(platform_path)
	else:
		print("CLIENT: Ignoring platform breaking call - not host")
