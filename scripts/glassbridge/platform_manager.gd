class_name PlatformManager
extends RefCounted

enum Glass { SOLID, BRITTLE, BREAKING, BROKEN }

# Simplified storage: track everything by path string for consistency
var platform_states = {}  # path_string -> Glass state  
var platform_objects = {}  # path_string -> CSGBox3D (null for broken platforms)
# Dictionary to track timers for brittle platforms
var brittle_timers = {}
# Step 8: Track which players are on each platform for sync
var platform_affected_players = {}  # platform -> Array[int]

const BREAK_TIME: float = 1.0

var game_node: Node3D
var player_manager: PlayerManager

func _init(init_game_node: Node3D, init_player_manager: PlayerManager):
	self.game_node = init_game_node
	self.player_manager = init_player_manager

func setup_layer_platforms(layer: Node):
	"""Setup platforms for a single layer with dynamic distribution: ~3/8 brittle, ~3/8 broken, ~2/8 solid"""
	var glass_platforms = layer.get_children().filter(func(child): return child is CSGBox3D)
	glass_platforms.shuffle()
	
	var total_platforms = len(glass_platforms)
	
	# Dynamic distribution based on proportions (3:3:2 ratio)
	# Use floor to ensure we don't exceed total platforms
	var platforms_brittle = (total_platforms * 3.0 / 8.0) as int
	var platforms_broken = (total_platforms * 3.0 / 8.0) as int
	# Remaining platforms will be solid
	var platforms_solid = total_platforms - platforms_brittle - platforms_broken
	
	print("Layer ", layer.name, " distribution: ", platforms_brittle, " brittle, ", platforms_broken, " broken, ", platforms_solid, " solid (total: ", total_platforms, ")")
	
	for i in range(total_platforms):
		var platform = glass_platforms[i]
		if i < platforms_brittle:
			setup_platform(platform, Glass.BRITTLE)
		elif i < (platforms_brittle + platforms_broken):
			setup_platform(platform, Glass.BROKEN)
		else:
			setup_platform(platform, Glass.SOLID)

func setup_platforms(layers: Array[Node]):
	"""Setup platforms for multiple layers"""
	for layer in layers:
		setup_layer_platforms(layer)

func create_empty_platforms(layers: Array[Node]):
	"""Create platforms for clients without configuration - all solid initially"""
	print("CLIENT: Creating platforms as solid, waiting for host configuration...")
	
	# Get all platforms in all layers and set them all as solid
	var all_platforms = []
	for layer in layers:
		all_platforms.append_array(layer.get_children().filter(func(child): return child is CSGBox3D))
	
	for platform in all_platforms:
		setup_platform(platform, Glass.SOLID)
		print("CLIENT: Created platform ", platform.name, " as SOLID (awaiting configuration)")

func is_platform_valid(platform: CSGBox3D) -> bool:
	"""Check if a platform is valid and not freed"""
	return platform != null and is_instance_valid(platform)

func create_brittle_detector(platform: CSGBox3D):
	"""Create collision detection area for brittle platforms"""
	var area = Area3D.new()
	area.name = "BrittleDetector_" + platform.name
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	
	# Match the platform's size but make it slightly larger and positioned correctly
	box_shape.size = platform.size + Vector3(0.5, 0.5, 0.5)  # Slightly larger for better detection
	collision_shape.shape = box_shape
	
	# Position the area at the same location as the platform
	area.position = Vector3.ZERO  # Relative to platform
	collision_shape.position = Vector3.ZERO
	
	area.add_child(collision_shape)
	platform.add_child(area)
	
	print("Created Area3D for brittle platform: ", platform.name, " with size: ", box_shape.size)
	print("Platform global position: ", platform.global_position)
	print("Area3D local position: ", area.position)
	
	# Connect the collision signal with the correct signature
	area.body_entered.connect(_on_brittle_platform_entered.bind(platform))
	print("Connected body_entered signal for platform: ", platform.name)

func create_platform_timer(platform: CSGBox3D) -> Timer:
	"""Create and configure a timer for brittle platform breaking"""
	var timer = Timer.new()
	timer.wait_time = BREAK_TIME
	timer.one_shot = true
	timer.timeout.connect(_on_brittle_timer_timeout.bind(platform))
	game_node.add_child(timer)
	timer.start()
	
	print("Timer created and started for platform: ", platform.name, " - wait time: ", timer.wait_time)
	return timer

func has_active_timer(platform: CSGBox3D) -> bool:
	"""Check if platform has an active timer"""
	return platform in brittle_timers and brittle_timers[platform] != null

func cleanup_platform_timer(platform: CSGBox3D):
	"""Clean up timer and affected players for a platform"""
	if platform in brittle_timers:
		var timer = brittle_timers[platform]
		print("Cleaning up timer for platform: ", platform.name)
		timer.queue_free()
		brittle_timers.erase(platform)
	
	if platform in platform_affected_players:
		platform_affected_players.erase(platform)

func setup_platform(platform: CSGBox3D, glass_type: Glass):
	var platform_path = str(platform.get_path())
	platform_states[platform_path] = glass_type
	platform_objects[platform_path] = platform
	
	if glass_type == Glass.BRITTLE:
		change_platform_color(platform, Color.ORANGE)  # Orange for brittle
		print("Set platform as brittle: ", platform.name)
		create_brittle_detector(platform)
	elif glass_type == Glass.BROKEN:
		# Make platform invisible and disable collision for broken state
		platform.visible = false
		platform.set_collision_layer(0)
		platform.set_collision_mask(0)
		print("Set platform as broken (invisible): ", platform.name)
		# Set platform_objects to null since it's effectively removed
		platform_objects[platform_path] = null
	else: # Glass.SOLID
		change_platform_color(platform, Color.WHITE)    # White for solid
		print("Set platform as solid: ", platform.name)

func disable_platform(platform: CSGBox3D):
	print("Deleting platform: ", platform.name, " - Setting state to BROKEN and cleaning up")
	
	# Get platform path and update state
	var platform_path = str(platform.get_path())
	platform_states[platform_path] = Glass.BROKEN
	
	# Remove from active objects (but keep the state for late joiners)
	platform_objects[platform_path] = null
	
	# Trigger immediate sync to clients if we're the host
	if game_node.multiplayer.is_server():
		print("HOST: Triggering immediate platform sync for broken platform: ", platform.name)
		# Use the game_node to call sync method
		if game_node.has_method("sync_platform_break_to_clients"):
			game_node.sync_platform_break_to_clients(platform_path)
		else:
			print("HOST: Warning - sync method not found on game_node")
	
	# Delete the platform
	platform.queue_free()
	
	# Remove from state tracking after a short delay to allow one last sync
	call_deferred("_cleanup_single_platform", platform_path)

func _cleanup_platform_references(platform_path: String):
	"""Clean up all references to a specific platform by path"""
	# Don't remove broken platforms from platform_states - keep them for late-joining clients
	# Only clean up from platform_objects
	if platform_path in platform_objects:
		print("PLATFORM_CLEANUP: Removing platform object reference for path: ", platform_path)
		platform_objects.erase(platform_path)
	
	# Clean up timer references - need to update these to use paths too
	# For now, we'll leave brittle_timers and platform_affected_players as-is
	# since they may still be using object references
	
	print("PLATFORM_CLEANUP: Cleaned up object references for platform path: ", platform_path)

func _cleanup_single_platform(platform_path: String):
	"""Clean up a single platform's references after it's been freed"""
	_cleanup_platform_references(platform_path)

func _on_brittle_platform_entered(body: Node3D, platform: CSGBox3D):
	print("Body entered brittle platform area! Body: ", body.name, " Platform: ", platform.name)
	var current_state = get_platform_state(platform)
	print("Platform current state: ", current_state)
	
	# Only trigger if platform is still brittle (not breaking or broken)
	if current_state != Glass.BRITTLE:
		print("Platform ", platform.name, " is not brittle anymore (state: ", Glass.keys()[current_state], ") - ignoring collision")
		return
	
	# Check if it's any managed player (multiplayer-ready logic)
	if player_manager.is_valid_player(body):
		var player_id = player_manager.get_player_id(body as CharacterBody3D)
		print("CONFIRMED: Player ", player_id, " stepped on brittle platform: ", platform.name)
		start_brittle_timer(platform, player_id)
	else:
		print("Not a managed player - ignoring collision with: ", body.name)

func start_brittle_timer(platform: CSGBox3D, triggering_player_id: int = 0):
	# AUTHORITY CHECK: Only host processes platform timers
	if not game_node.multiplayer.is_server():
		return
		
	print("start_brittle_timer called for platform: ", platform.name, " by player: ", triggering_player_id)
	
	# Check platform state before starting timer
	var current_state = get_platform_state(platform)
	if current_state != Glass.BRITTLE:
		print("Platform ", platform.name, " is no longer brittle (state: ", current_state, ") - cannot start timer")
		return
	
	# Don't start timer if one is already running for this platform
	if has_active_timer(platform):
		print("Timer already running for platform: ", platform.name, " - skipping")
		return
		
	print("Starting ", BREAK_TIME, "-second timer for brittle platform: ", platform.name, " triggered by player: ", triggering_player_id)
	
	# Change state to BREAKING and update visual
	set_platform_state(platform, Glass.BREAKING)
	change_platform_color(platform, Color.YELLOW)  # Change to yellow when breaking starts
	
	# Trigger immediate sync to clients for BREAKING state if we're the host
	if game_node.multiplayer.is_server():
		print("HOST: Triggering immediate platform BREAKING sync for: ", platform.name)
		# Use the game_node to call sync method for breaking state
		if game_node.has_method("sync_platform_breaking_to_clients"):
			game_node.sync_platform_breaking_to_clients(platform.get_path())
		else:
			print("HOST: Warning - breaking sync method not found on game_node")
	
	# Step 8: Track affected player for sync
	var affected_players: Array[int] = []
	if triggering_player_id > 0:
		affected_players.append(triggering_player_id)
	platform_affected_players[platform] = affected_players
	
	# Create and start timer
	var timer = create_platform_timer(platform)
	brittle_timers[platform] = timer
	
	# Step 8: Log sync data for this platform
	var sync_data = create_platform_sync_data(platform)
	if sync_data:
		print("SYNC Platform: ", platform.name, " State=", PlatformManager.Glass.keys()[sync_data.state], " Timer=", "%.2f" % sync_data.timer_remaining, " AffectedPlayers=", sync_data.affected_players)

func _on_brittle_timer_timeout(platform: CSGBox3D):
	# AUTHORITY CHECK: Only host processes platform timeout
	if not game_node.multiplayer.is_server():
		return
		
	print("===== TIMER TIMEOUT =====")
	print("Brittle platform timer expired, disabling: ", platform.name)
	
	# Step 8: Log final sync state before breaking
	var sync_data = create_platform_sync_data(platform)
	if sync_data:
		print("SYNC Final Platform: ", platform.name, " State=", PlatformManager.Glass.keys()[sync_data.state], " AffectedPlayers=", sync_data.affected_players)
	
	disable_platform(platform)
	
	# Clean up timer and affected players
	cleanup_platform_timer(platform)
	print("==========================")

func change_platform_color(platform: CSGBox3D, new_color: Color):
	# Get the current material
	var material: StandardMaterial3D = platform.material
	
	# If the platform doesn't have a material, create a new one
	if material == null:
		material = StandardMaterial3D.new()
		platform.material = material
	
	# Duplicate the material to avoid affecting other instances
	material = material.duplicate()
	platform.material = material
	
	# Set the new albedo color while preserving alpha (transparency)
	var current_color = material.albedo_color
	material.albedo_color = Color(new_color.r, new_color.g, new_color.b, current_color.a)

func get_platform_state(platform: CSGBox3D) -> Glass:
	if not platform or not is_instance_valid(platform):
		return Glass.SOLID
	var platform_path = str(platform.get_path())
	return platform_states.get(platform_path, Glass.SOLID)

func set_platform_state(platform: CSGBox3D, state: Glass):
	if not platform or not is_instance_valid(platform):
		return
	var platform_path = str(platform.get_path())
	platform_states[platform_path] = state

func auto_discover_layers(platforms_parent: Node) -> Array[Node]:
	"""Automatically discover all layer nodes under a Platforms parent node"""
	var layers: Array[Node] = []
	
	for child in platforms_parent.get_children():
		if child.name.begins_with("Layer") or child.name.to_lower().contains("layer"):
			layers.append(child)
			print("AUTO-DISCOVERED: Found layer ", child.name)
	
	print("AUTO-DISCOVERED: Found ", layers.size(), " total layers")
	return layers

func setup_platforms_auto(platforms_parent: Node):
	"""Convenience method to automatically discover and setup all layers"""
	var layers = auto_discover_layers(platforms_parent)
	setup_platforms(layers)

func create_empty_platforms_auto(platforms_parent: Node):
	"""Convenience method to automatically discover and create empty platforms for all layers"""
	var layers = auto_discover_layers(platforms_parent)
	create_empty_platforms(layers)

func apply_platform_configuration_auto(config_data: Array, platforms_parent: Node):
	"""Convenience method to automatically discover layers and apply configuration"""
	var layers = auto_discover_layers(platforms_parent)
	apply_platform_configuration(config_data, layers)

func cleanup():
	# Clean up all timers
	for timer in brittle_timers.values():
		if timer and is_instance_valid(timer):
			timer.queue_free()
	brittle_timers.clear()
	platform_states.clear()
	platform_objects.clear()
	platform_affected_players.clear()

# Step 9: Dynamic Player Management Methods
func remove_player_from_platforms(player_id: int):
	"""Remove a player from all platform affected_players lists"""
	var platforms_to_update: Array[CSGBox3D] = []
	
	# Find all platforms that have this player in their affected_players list
	for platform in platform_affected_players:
		var affected_players: Array = platform_affected_players[platform]
		if player_id in affected_players:
			platforms_to_update.append(platform)
	
	# Remove the player from those platforms
	for platform in platforms_to_update:
		var affected_players: Array = platform_affected_players[platform]
		affected_players.erase(player_id)
		print("Removed player ", player_id, " from platform ", platform.name, " affected list")
		
		# If no more players are affected by this platform, we could optionally stop its timer
		# For now, we'll leave the timer running for consistency

func cleanup_player_platform_data(player_id: int):
	"""Clean up all platform-related data for a removed player"""
	remove_player_from_platforms(player_id)
	print("Platform cleanup completed for player ", player_id)

# Step 8: Network Sync Methods
func get_platform_id(platform: CSGBox3D) -> String:
	"""Generate unique ID for platform based on its path"""
	if platform and is_instance_valid(platform):
		return str(platform.get_path())
	else:
		return ""

func find_platform_by_id(platform_id: String) -> CSGBox3D:
	"""Find platform by its path ID"""
	var platform_node = game_node.get_node_or_null(NodePath(platform_id))
	if platform_node and platform_node is CSGBox3D:
		return platform_node
	return null

func create_platform_sync_data(platform: CSGBox3D) -> SyncData.PlatformSyncData:
	"""Create sync data for a specific platform"""
	if not is_platform_valid(platform):
		return null
	
	var platform_id = get_platform_id(platform)
	var state = get_platform_state(platform)
	var timer_remaining = 0.0
	var affected_players_raw = platform_affected_players.get(platform, [])
	var affected_players: Array[int] = []
	
	# Convert to typed array
	for player_id in affected_players_raw:
		affected_players.append(player_id)
	
	# Get remaining timer time if timer is active
	if platform in brittle_timers and brittle_timers[platform]:
		timer_remaining = brittle_timers[platform].time_left
	
	return SyncData.PlatformSyncData.new(
		platform_id,
		state,
		timer_remaining,
		affected_players
	)

func apply_platform_sync_data(sync_data: SyncData.PlatformSyncData):
	"""Apply sync data to a specific platform"""
	if not sync_data:
		return
	
	# Skip on host - host is the authority
	if game_node.multiplayer.is_server():
		return
	
	# Find the platform by ID
	var platform = find_platform_by_id(sync_data.platform_id)
	if not platform:
		print("CLIENT SYNC: Platform not found: ", sync_data.platform_id)
		return
	
	var current_state = get_platform_state(platform)
	
	# Apply state changes
	if sync_data.state != current_state:
		print("CLIENT SYNC: Updating platform ", platform.name, " from ", Glass.keys()[current_state], " to ", Glass.keys()[sync_data.state])
		
		if sync_data.state == Glass.BROKEN:
			# Platform should be broken - remove it
			print("CLIENT SYNC: Breaking platform ", platform.name)
			set_platform_state(platform, Glass.BROKEN)
			var platform_path = str(platform.get_path())
			platform_objects[platform_path] = null
			platform.queue_free()
			call_deferred("_cleanup_single_platform", platform_path)
		elif sync_data.state == Glass.BREAKING:
			# Platform is breaking - update color and state
			print("CLIENT SYNC: Platform ", platform.name, " is now breaking")
			set_platform_state(platform, Glass.BREAKING)
			change_platform_color(platform, Color.YELLOW)
		elif sync_data.state == Glass.BRITTLE and current_state == Glass.SOLID:
			# Platform changed to brittle - update color and state
			set_platform_state(platform, Glass.BRITTLE)
			change_platform_color(platform, Color.ORANGE)
		
	# Update affected players
	var path_for_players = str(platform.get_path()) 
	if path_for_players in platform_states and sync_data.affected_players.size() > 0:
		platform_affected_players[platform] = sync_data.affected_players.duplicate()
		
		# If there's a timer remaining and we don't have one, start visual countdown
		if sync_data.timer_remaining > 0.0 and not has_active_timer(platform):
			change_platform_color(platform, Color.YELLOW)  # Show countdown visual
			print("CLIENT SYNC: Platform ", platform.name, " should break in ", sync_data.timer_remaining, " seconds")

func get_all_platforms_sync_data() -> Dictionary:
	"""Get sync data for all platforms that have active state"""
	var sync_data = {}
	
	# Clean up freed platforms first
	cleanup_freed_platforms()
	
	# Include all platforms with non-default state or active timers
	for platform_path in platform_states.keys():
		var platform_obj = platform_objects.get(platform_path, null)
		var state = platform_states[platform_path]
		
		# Skip broken platforms for sync (they're handled differently)
		if state == Glass.BROKEN:
			continue
			
		# For active platforms, check if they have timers
		var has_timer = false
		if platform_obj and is_instance_valid(platform_obj):
			has_timer = has_active_timer(platform_obj)
		
		# Include platforms that are not solid (brittle/breaking) or have active timers
		if state != Glass.SOLID or has_timer:
			if platform_obj and is_instance_valid(platform_obj):
				var platform_id = get_platform_id(platform_obj)
				sync_data[platform_id] = create_platform_sync_data(platform_obj)
	
	return sync_data

func cleanup_freed_platforms():
	"""Remove references to freed platforms from tracking dictionaries"""
	var paths_to_remove = []
	
	# Find all freed platforms by checking platform_objects
	for platform_path in platform_objects:
		var platform_obj = platform_objects[platform_path]
		if platform_obj == null or not is_instance_valid(platform_obj):
			paths_to_remove.append(platform_path)
	
	# Remove them from platform_objects (but keep states for broken platforms)
	for platform_path in paths_to_remove:
		print("PLATFORM_CLEANUP: Removing freed platform object reference for ", platform_path)
		platform_objects.erase(platform_path)
		# Note: We keep states in platform_states for broken platforms to sync to late joiners

func apply_all_platforms_sync_data(platforms_sync_data: Dictionary):
	"""Apply sync data to all platforms"""
	for platform_id in platforms_sync_data:
		if platforms_sync_data[platform_id]:
			apply_platform_sync_data(platforms_sync_data[platform_id])

func get_platform_configuration_data() -> Array:
	"""Get platform configuration data for multiplayer syncing"""
	var config_data = []
	
	# Clean up completely freed platforms first (but keep broken ones in states)
	cleanup_freed_platforms()
	
	# Collect all platform data including broken ones - now using path-based storage
	for platform_path in platform_states.keys():
		var glass_type = platform_states[platform_path]
		var platform_obj = platform_objects.get(platform_path, null)
		
		var platform_info = {
			"path": platform_path,
			"glass_type": glass_type,
			"position": Vector3.ZERO,
			"is_broken": (glass_type == Glass.BROKEN),
			"is_breaking": (glass_type == Glass.BREAKING)
		}
		
		# Try to get position from active platform object
		if platform_obj and is_instance_valid(platform_obj):
			platform_info["position"] = platform_obj.global_position
			
		config_data.append(platform_info)
		
		if glass_type == Glass.BROKEN:
			print("HOST: Including broken platform in config: ", platform_path)
		elif glass_type == Glass.BREAKING:
			print("HOST: Including breaking platform in config: ", platform_path)
	
	print("HOST: Collected configuration for ", config_data.size(), " total platforms")
	return config_data

func apply_platform_configuration(config_data: Array, layers: Array[Node]):
	"""Apply platform configuration received from host"""
	print("CLIENT: Applying platform configuration for ", config_data.size(), " platforms")
	
	# Get all platforms in all layers
	var all_platforms = []
	for layer in layers:
		all_platforms.append_array(layer.get_children().filter(func(child): return child is CSGBox3D))
	
	# Create a lookup by path AND name for fast matching
	var platform_by_path = {}
	var platform_by_name = {}
	for platform in all_platforms:
		var client_path = str(platform.get_path())
		platform_by_path[client_path] = platform
		platform_by_name[platform.name] = platform
	
	# Apply configuration to matching platforms
	for config in config_data:
		var platform_path = config["path"]
		
		# Try to find platform by path first, then by name as fallback
		var platform = null
		if platform_path in platform_by_path:
			platform = platform_by_path[platform_path]
		else:
			# Extract platform name from path and try name matching
			var path_parts = platform_path.split("/")
			var platform_name = path_parts[-1]  # Get the last part (platform name)
			if platform_name in platform_by_name:
				platform = platform_by_name[platform_name]
		
		if platform:
			var glass_type = config["glass_type"]
			
			# Register platform in platform_objects using the actual client path
			var client_platform_path = str(platform.get_path())
			platform_objects[client_platform_path] = platform
			
			# Handle broken platforms
			if config.get("is_broken", false):
				setup_platform(platform, Glass.SOLID)  # Set up as solid first
				platform_states[client_platform_path] = Glass.BROKEN
				platform.visible = false  # Make broken platforms invisible
				print("CLIENT: Configured platform ", platform.name, " as BROKEN (invisible)")
			# Handle breaking platforms  
			elif config.get("is_breaking", false):
				setup_platform(platform, Glass.BRITTLE)  # Set up as brittle first
				platform_states[client_platform_path] = Glass.BREAKING
				change_platform_color(platform, Color.YELLOW)
				print("CLIENT: Configured platform ", platform.name, " as BREAKING (yellow)")
			else:
				setup_platform(platform, glass_type)
				print("CLIENT: Configured platform ", platform.name, " as ", Glass.keys()[glass_type])
		else:
			print("CLIENT: Warning - platform path not found: ", platform_path)
	
	print("CLIENT: Platform configuration applied successfully")
