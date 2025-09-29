extends Control

var player_manager: PlayerManager
var main_scene: Node3D

func _ready():
	visible = false

func _on_resume_pressed() -> void:
	close_player_menu()

func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/startmenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func close_player_menu():
	"""Close the player menu through main scene for proper state management"""
	if main_scene and player_manager:
		var primary_player = player_manager.get_primary_player()
		if primary_player:
			var player_id = player_manager.get_player_id(primary_player)
			main_scene.close_player_menu(player_id)
