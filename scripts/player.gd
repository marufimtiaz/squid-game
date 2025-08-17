extends CharacterBody2D

@export var speed := 200.0
var can_move := true

func freeze():
	can_move = false
	velocity = Vector2.ZERO

func _physics_process(_delta):
	if not can_move:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dir := 0.0
	if Input.is_action_pressed("ui_left"):
		dir -= 1.0
	if Input.is_action_pressed("ui_right"):
		dir += 1.0

	velocity.x = dir * speed
	velocity.y = 0.0
	move_and_slide()
