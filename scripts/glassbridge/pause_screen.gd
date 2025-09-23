extends Control

func _on_resume_pressed() -> void:
	get_tree().reload_current_scene()

func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/startmenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
