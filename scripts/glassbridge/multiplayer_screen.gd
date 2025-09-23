extends Control


@onready var single_player: Button = $VBoxContainer/SinglePlayer
@onready var host: Button = $VBoxContainer/Host
@onready var line_edit: LineEdit = $VBoxContainer/LineEdit
@onready var join: Button = $VBoxContainer/Join
@onready var back: Button = $VBoxContainer/Back

func _on_single_player_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/glassbridge/game2.tscn")



func _on_host_pressed() -> void:
	pass # Replace with function body.


func _on_join_pressed() -> void:
	pass # Replace with function body.


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/startmenu.tscn")


func _on_line_edit_text_submitted(new_text: String) -> void:
	print("Entered IP: " + new_text)
