class_name PlatformManager
extends RefCounted

enum Glass { SOLID, BRITTLE, BROKEN }

# Dictionary to track platform states
var platform_states = {}
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

func setup_platforms(layer3: Node, layer4: Node):
	print("===== PLATFORM SETUP STARTING =====")
	
	# Get the list of platforms under the layer and shuffle
	var glass_platforms_l3 = layer3.get_children().filter(func(child): return child is CSGBox3D)
	glass_platforms_l3.shuffle()

	var glass_platforms_l4 = layer4.get_children().filter(func(child): return child is CSGBox3D)
	glass_platforms_l4.shuffle()
	
	print("Found ", len(glass_platforms_l3), " platforms in Layer3")
	print("Found ", len(glass_platforms_l4), " platforms in Layer4")
	
	# Set half the platforms as brittle
	var platforms_to_make_brittle_l3 = (len(glass_platforms_l3)/2.0) as int
	var platforms_to_make_brittle_l4 = (len(glass_platforms_l4)/2.0) as int
	
	print("Making ", platforms_to_make_brittle_l3, " platforms brittle in Layer3")
	print("Making ", platforms_to_make_brittle_l4, " platforms brittle in Layer4")
	
	# Set the first N platforms in each layer as brittle, rest as solid
	for i in range(len(glass_platforms_l3)):
		var platform = glass_platforms_l3[i]
		if i < platforms_to_make_brittle_l3:
			setup_platform(platform, Glass.BRITTLE)
		else:
			setup_platform(platform, Glass.SOLID)
		
	for i in range(len(glass_platforms_l4)):
		var platform = glass_platforms_l4[i]
		if i < platforms_to_make_brittle_l4:
			setup_platform(platform, Glass.BRITTLE)
		else:
			setup_platform(platform, Glass.SOLID)
	
	print("===== PLATFORM SETUP COMPLETE =====")
	
	# Debug: Print all brittle platforms and their Area3D children
	print("===== DEBUG: BRITTLE PLATFORM CHECK =====")
	for platform in platform_states.keys():
		if platform_states[platform] == Glass.BRITTLE:
			print("Brittle platform: ", platform.name)
			print("  Position: ", platform.global_position)
			print("  Size: ", platform.size)
			var areas = platform.get_children().filter(func(child): return child is Area3D)
			print("  Area3D children: ", len(areas))
			for area in areas:
				print("    Area name: ", area.name, " Position: ", area.global_position)
		elif platform_states[platform] == Glass.BROKEN:
			print("Broken platform: ", platform.name)
	print("==========================================")

func setup_platform(platform: CSGBox3D, glass_type: Glass):
	platform_states[platform] = glass_type
	
	if glass_type == Glass.BRITTLE:
		change_platform_color(platform, Color.ORANGE)  # Orange for brittle
		print("Set platform as brittle: ", platform.name)
		
		# Add collision detection for brittle platforms
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
		
	else:
		#change_platform_color(platform, Color.BLUE)    # Blue for solid
		print("Set platform as solid: ", platform.name)

func disable_platform(platform: CSGBox3D):
	print("Deleting platform: ", platform.name, " - Setting state to BROKEN and cleaning up")
	
	# Set state to BROKEN first
	platform_states[platform] = Glass.BROKEN  
	
	# Clean up timer if it exists
	if platform in brittle_timers and brittle_timers[platform]:
		brittle_timers[platform].queue_free()
		brittle_timers.erase(platform)
	
	# Clean up affected players
	if platform in platform_affected_players:
		platform_affected_players.erase(platform)
	
	# Delete the platform
	platform.queue_free()
	
	# Remove from state tracking after a short delay to allow one last sync
	call_deferred("_cleanup_single_platform", platform)

func _cleanup_single_platform(platform: CSGBox3D):
	"""Clean up a single platform's references after it's been freed"""
	if platform in platform_states:
		platform_states.erase(platform)
		print("PLATFORM_CLEANUP: Cleaned up references for freed platform")

func _on_brittle_platform_entered(body: Node3D, platform: CSGBox3D):
	print("Body entered brittle platform area! Body: ", body.name, " Platform: ", platform.name)
	print("Platform current state: ", platform_states[platform])
	
	# Only trigger if platform is still brittle (not broken)
	if platform_states[platform] != Glass.BRITTLE:
		print("Platform ", platform.name, " is not brittle anymore (state: ", platform_states[platform], ") - ignoring collision")
		return
	
	# Check if it's any managed player (multiplayer-ready logic)
	if player_manager.is_valid_player(body):
		var player_id = player_manager.get_player_id(body as CharacterBody3D)
		print("CONFIRMED: Player ", player_id, " stepped on brittle platform: ", platform.name)
		start_brittle_timer(platform, player_id)
	else:
		print("Not a managed player - ignoring collision with: ", body.name)

func start_brittle_timer(platform: CSGBox3D, triggering_player_id: int = 0):
	print("start_brittle_timer called for platform: ", platform.name, " by player: ", triggering_player_id)
	
	# Check platform state before starting timer
	if platform_states[platform] != Glass.BRITTLE:
		print("Platform ", platform.name, " is no longer brittle (state: ", platform_states[platform], ") - cannot start timer")
		return
	
	# Don't start timer if one is already running for this platform
	if platform in brittle_timers:
		print("Timer already running for platform: ", platform.name, " - skipping")
		return
		
	print("Starting ", BREAK_TIME, "-second timer for brittle platform: ", platform.name, " triggered by player: ", triggering_player_id)
	change_platform_color(platform, Color.YELLOW)  # Change to yellow when timer starts
	
	# Step 8: Track affected player for sync
	var affected_players: Array[int] = []
	if triggering_player_id > 0:
		affected_players.append(triggering_player_id)
	platform_affected_players[platform] = affected_players
	
	# Create and start timer
	var timer = Timer.new()
	timer.wait_time = BREAK_TIME
	timer.one_shot = true
	timer.timeout.connect(_on_brittle_timer_timeout.bind(platform))
	game_node.add_child(timer)
	timer.start()
	
	brittle_timers[platform] = timer
	print("Timer created and started for platform: ", platform.name, " - wait time: ", timer.wait_time)
	
	# Step 8: Log sync data for this platform
	var sync_data = create_platform_sync_data(platform)
	if sync_data:
		print("SYNC Platform: ", platform.name, " State=", PlatformManager.Glass.keys()[sync_data.state], " Timer=", "%.2f" % sync_data.timer_remaining, " AffectedPlayers=", sync_data.affected_players)

func _on_brittle_timer_timeout(platform: CSGBox3D):
	print("===== TIMER TIMEOUT =====")
	print("Brittle platform timer expired, disabling: ", platform.name)
	
	# Step 8: Log final sync state before breaking
	var sync_data = create_platform_sync_data(platform)
	if sync_data:
		print("SYNC Final Platform: ", platform.name, " State=", PlatformManager.Glass.keys()[sync_data.state], " AffectedPlayers=", sync_data.affected_players)
	
	disable_platform(platform)
	
	# Clean up timer
	if platform in brittle_timers:
		var timer = brittle_timers[platform]
		print("Cleaning up timer for platform: ", platform.name)
		timer.queue_free()
		brittle_timers.erase(platform)
		platform_affected_players.erase(platform)  # Clean up affected players too
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
	return platform_states.get(platform, Glass.SOLID)

func cleanup():
	# Clean up all timers
	for timer in brittle_timers.values():
		if timer and is_instance_valid(timer):
			timer.queue_free()
	brittle_timers.clear()
	platform_states.clear()
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

func create_platform_sync_data(platform: CSGBox3D) -> SyncData.PlatformSyncData:
	"""Create sync data for a specific platform"""
	if not platform or not is_instance_valid(platform):
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
	
	# Find platform by ID (for now we don't have a reverse lookup, this is preparatory)
	# In a real multiplayer scenario, we'd maintain a platform registry
	print("Would apply sync data for platform: ", sync_data.platform_id, " state: ", sync_data.state, " timer: ", sync_data.timer_remaining)
	
	# This is a preparatory method - in real multiplayer we would:
	# 1. Find the platform by platform_id
	# 2. Set its state to sync_data.state
	# 3. If timer_remaining > 0, start/adjust timer to that remaining time
	# 4. Update affected_players list

func get_all_platforms_sync_data() -> Dictionary:
	"""Get sync data for all platforms that have active state"""
	var sync_data = {}
	
	# Clean up freed platforms first
	cleanup_freed_platforms()
	
	# Include all platforms with non-default state or active timers
	for platform in platform_states:
		# Skip if platform is invalid/freed
		if not is_instance_valid(platform):
			continue
			
		var state = platform_states[platform]
		var has_timer = platform in brittle_timers and brittle_timers[platform] != null
		
		# Include platforms that are not solid (brittle/broken) or have active timers
		if state != Glass.SOLID or has_timer:
			var platform_id = get_platform_id(platform)
			sync_data[platform_id] = create_platform_sync_data(platform)
	
	return sync_data

func cleanup_freed_platforms():
	"""Remove references to freed platforms from all tracking dictionaries"""
	var platforms_to_remove = []
	
	# Find all freed platforms
	for platform in platform_states:
		if not is_instance_valid(platform):
			platforms_to_remove.append(platform)
	
	# Remove them from all tracking dictionaries
	for platform in platforms_to_remove:
		print("PLATFORM_CLEANUP: Removing freed platform references for ", platform.name if platform else "unknown")
		
		# Remove from state tracking
		if platform in platform_states:
			platform_states.erase(platform)
		
		# Remove from timer tracking  
		if platform in brittle_timers:
			if brittle_timers[platform] and is_instance_valid(brittle_timers[platform]):
				brittle_timers[platform].queue_free()
			brittle_timers.erase(platform)
		
		# Remove from affected players tracking
		if platform in platform_affected_players:
			platform_affected_players.erase(platform)

func apply_all_platforms_sync_data(platforms_sync_data: Dictionary):
	"""Apply sync data to all platforms"""
	for platform_id in platforms_sync_data:
		if platforms_sync_data[platform_id]:
			apply_platform_sync_data(platforms_sync_data[platform_id])
