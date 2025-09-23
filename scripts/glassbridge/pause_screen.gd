extends Control

# Reference to player manager for mouse handling (set by main game script)
var player_manager: PlayerManager
# Keep legacy player reference for compatibility
var player: CharacterBody3D

func _ready():
	# Make sure the pause screen is initially hidden
	visible = false

func _on_resume_pressed() -> void:
	# Resume the game instead of reloading the scene
	resume_game()

func _on_main_menu_pressed() -> void:
	# Unpause before changing scene
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/startmenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func show_pause():
	"""Show the pause screen and pause the game"""
	visible = true
	get_tree().paused = true
	# Release mouse when pausing
	if player_manager:
		player_manager.release_mouse_all_players()
	elif player:
		player.release_mouse()

func resume_game():
	"""Hide the pause screen and resume the game"""
	visible = false
	get_tree().paused = false
	# Re-capture mouse when resuming
	if player_manager:
		var primary_player = player_manager.get_primary_player()
		if primary_player and primary_player.has_method("resume_from_pause"):
			primary_player.resume_from_pause()
	elif player:
		player.resume_from_pause()
