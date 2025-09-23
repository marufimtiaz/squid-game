extends Area3D

@onready var player: CharacterBody3D = $"../Player"

# Reference to game manager for proper state handling
var game_manager: GameManager

func _ready():
	# Connect to player signals for better communication
	if player:
		player.player_hit_killzone.connect(_on_player_hit_killzone)
		player.fallimpact_finished.connect(_on_player_fallimpact_finished)
	
	# Get reference to game manager from parent scene
	var main_scene = get_parent()
	if main_scene and main_scene.has_method("get") and main_scene.get("game_manager"):
		game_manager = main_scene.game_manager

func _on_body_entered(body: Node3D) -> void:
	if body == player:
		print("Player entered killzone - triggering fallimpact")
		# Trigger fallimpact animation and freeze player
		player.play_fallimpact()
		player.release_mouse()
		
		# Notify game manager about player death
		if game_manager:
			game_manager.handle_player_death()

func _on_player_hit_killzone():
	# This gets called when the player plays the fallimpact animation
	print("Player hit killzone - fallimpact animation triggered")

func _on_player_fallimpact_finished():
	# This gets called when the fallimpact animation finishes
	print("Fallimpact animation finished - transitioning to lose screen")
	get_tree().change_scene_to_file("res://scenes/glassbridge/lose_screen.tscn")
