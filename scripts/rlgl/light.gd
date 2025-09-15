extends Node2D

signal switched(is_red: bool)

@export var min_interval := 2.0
@export var max_interval := 4.0
@export var color_green := Color(0.2, 0.9, 0.3)
@export var color_red := Color(0.95, 0.2, 0.2)

var is_red := false
var rng := RandomNumberGenerator.new()

@onready var _timer: Timer = $Timer
@onready var _rect: ColorRect = $ColorRect

func _ready():
	rng.randomize()
	_rect.color = color_green
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer_timeout)
	_arm_timer()

func _arm_timer():
	_timer.wait_time = rng.randf_range(min_interval, max_interval)
	_timer.start()

func _on_timer_timeout():
	is_red = !is_red
	_rect.color = color_red if is_red else color_green
	emit_signal("switched", is_red)
	_arm_timer()
