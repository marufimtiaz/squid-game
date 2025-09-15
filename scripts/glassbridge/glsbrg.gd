extends Node3D

enum State { PLAYING, DEAD, WON }
var state: State = State.PLAYING

@onready var player: CharacterBody3D = $Player
@onready var platforms: Node3D = $Platforms
@onready var goaltimer: Timer = $Platforms/FinishPlatform/Goal/Timer
@onready var layer3: Node = $Platforms/Layer3
@onready var layer4: Node = $Platforms/Layer4

func _ready() -> void:

	# Get the list of platforms under the layer and shuffle
	var glass_platforms_l3 = layer3.get_children().filter(func(child): return child is CSGBox3D)
	glass_platforms_l3.shuffle()

	var glass_platforms_l4 = layer4.get_children().filter(func(child): return child is CSGBox3D)
	glass_platforms_l4.shuffle()
	
	
	# Disable half the platforms
	var platforms_to_disable_l3 = (len(glass_platforms_l3)/2)
	var platforms_to_disable_l4 = (len(glass_platforms_l4)/2)
	
	
	# Disable collision for the first N platforms in the Layer
	for i in range(platforms_to_disable_l3):
		var platform = glass_platforms_l3[i]
		disable_platform(platform)
		
	for i in range(platforms_to_disable_l4):
		var platform = glass_platforms_l4[i]
		disable_platform(platform)



func disable_platform(platform: CSGBox3D):
	platform.use_collision = false
	change_platform_color(platform, Color.RED) 
	print("Disabled collision for: ", platform.name)


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


func _on_goal_body_entered(body: Node3D) -> void:
	if body == player:
		state = State.WON
		player.slow()
		player.release_mouse()
		goaltimer.start()

func _on_timer_timeout() -> void:
	player.freeze()
	get_tree().change_scene_to_file("res://scenes/startmenu.tscn")
