extends Area3D

@onready var timer: Timer = $Timer
@onready var player: CharacterBody3D = $"../Player"

func _on_body_entered(body: Node3D) -> void:
	if body == player:
		player.freeze()
		player.release_mouse()
		timer.start()


func _on_timer_timeout() -> void:
	get_tree().change_scene_to_file("res://scenes/startmenu.tscn")
