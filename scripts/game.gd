extends Node2D

enum State { PLAYING, DEAD, WON }

var state: State = State.PLAYING
var light_is_red := false
var last_player_pos := Vector2.ZERO
const MOVE_EPS := 0.5  # tiny tolerance so micro-jitter doesn't kill you

@onready var player: CharacterBody2D = $Player
@onready var light: Node2D = $Player/Camera2D/Light
#@onready var light_label: Label = $Player/Camera2D/LightLabel
@onready var status_label: Label = $Player/Camera2D/StatusLabel
@onready var restart_button: Button = $Player/Camera2D/RestartButton
@onready var spawn: Marker2D = $Spawn
@onready var goal: Area2D = $Goal




func _ready():
	# Spawn player
	player.global_position = spawn.global_position
	last_player_pos = player.global_position


func _on_exit_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/startmenu.tscn")


func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()



func _physics_process(_delta):
	if state != State.PLAYING:
		return

	# Illegal movement while RED? -> eliminated
	if light_is_red:
		var moved := player.global_position.distance_to(last_player_pos) > MOVE_EPS
		if moved:
			_die("Moved on RED!")
	last_player_pos = player.global_position

func _on_light_switched(is_red: bool):
	light_is_red = is_red


func _on_goal_body_entered(body):
	if body == player and state == State.PLAYING:
		state = State.WON
		player.freeze()
		status_label.text = "YOU WIN 🎉"
		status_label.modulate = Color(1, 1, 1)
		status_label.visible = true

func _die(reason: String):
	state = State.DEAD
	player.freeze()
	status_label.text = "ELIMINATED ☠  " + reason
	status_label.modulate = Color(1, 0.4, 0.4)
	status_label.visible = true
