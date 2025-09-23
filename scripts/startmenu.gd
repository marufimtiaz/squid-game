extends Control



func _on_start_game_1_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/redgreen/game1.tscn")


func _on_start_game_2_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/glassbridge/multiplayer_screen.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
