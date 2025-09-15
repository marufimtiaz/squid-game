extends Node

# Get the children nodes list
@onready var glass_platforms: Array[Node] = get_children().filter(func(child): return child is CSGBox3D)


func _ready():
	# Create a copy of the array and shuffle it randomly
	var shuffled_platforms = glass_platforms.duplicate()
	shuffled_platforms.shuffle()
	
	# Determine how many platforms to disable (1-3)
	var platforms_to_disable = (len(shuffled_platforms)/2) as int
	
	# Disable collision for the first N platforms in the shuffled array
	for i in range(platforms_to_disable):
		var platform = shuffled_platforms[i]
		platform.use_collision = false
		change_platform_color(platform, Color.RED) 
		print("Disabled collision for: ", platform.name)
	
	
	# Function to change the platform's material color
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
