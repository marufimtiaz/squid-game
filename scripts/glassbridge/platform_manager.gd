class_name PlatformManager
extends RefCounted

enum Glass { SOLID, BRITTLE, BROKEN }

# Dictionary to track platform states
var platform_states = {}
# Dictionary to track timers for brittle platforms
var brittle_timers = {}

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
	platform_states[platform] = Glass.BROKEN  # Set state to BROKEN
	print("Deleting platform: ", platform.name, " - State set to BROKEN")
	
	# Simply delete the platform
	platform.queue_free()

func _on_brittle_platform_entered(body: Node3D, platform: CSGBox3D):
	print("Body entered brittle platform area! Body: ", body.name, " Platform: ", platform.name)
	print("Platform current state: ", platform_states[platform])
	
	# Only trigger if platform is still brittle (not broken)
	if platform_states[platform] != Glass.BRITTLE:
		print("Platform ", platform.name, " is not brittle anymore (state: ", platform_states[platform], ") - ignoring collision")
		return
	
	var primary_player = player_manager.get_primary_player()
	print("Body type: ", body.get_class(), " Player type: ", primary_player.get_class() if primary_player else "NULL")
	print("Is body the primary player? ", body == primary_player)
	
	# Check if it's a managed player (future-proof for multiplayer)
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
	
	# Create and start timer
	var timer = Timer.new()
	timer.wait_time = BREAK_TIME
	timer.one_shot = true
	timer.timeout.connect(_on_brittle_timer_timeout.bind(platform))
	game_node.add_child(timer)
	timer.start()
	
	brittle_timers[platform] = timer
	print("Timer created and started for platform: ", platform.name, " - wait time: ", timer.wait_time)

func _on_brittle_timer_timeout(platform: CSGBox3D):
	print("===== TIMER TIMEOUT =====")
	print("Brittle platform timer expired, disabling: ", platform.name)
	disable_platform(platform)
	
	# Clean up timer
	if platform in brittle_timers:
		var timer = brittle_timers[platform]
		print("Cleaning up timer for platform: ", platform.name)
		timer.queue_free()
		brittle_timers.erase(platform)
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
