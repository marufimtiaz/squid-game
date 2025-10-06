extends CanvasLayer

@onready var timer_label: Label = $Control/TimerContainer/TimerLabel
@onready var update_timer: Timer = $Timer

var game_start_time: Dictionary = {}
var is_timer_running: bool = false

# Multiplayer synchronization
@rpc("authority", "call_local", "reliable")
func sync_timer_start(start_time: Dictionary):
	"""Synchronize timer start across all clients"""
	game_start_time = start_time
	is_timer_running = true
	update_timer.start()
	print("HUD: Timer synchronized - start time: ", start_time)
	print("HUD: Timer is now running: ", is_timer_running)

@rpc("authority", "call_local", "reliable")
func sync_timer_stop():
	"""Stop timer across all clients"""
	is_timer_running = false
	update_timer.stop()

func _ready():
	# Connect the update timer signal
	update_timer.timeout.connect(_on_update_timer_timeout)
	
	# Make sure timer label is visible
	timer_label.text = "00:00"
	
	# Add some styling to make the timer more visible
	timer_label.add_theme_font_size_override("font_size", 36)
	timer_label.add_theme_color_override("font_color", Color.WHITE)
	timer_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	timer_label.add_theme_constant_override("shadow_offset_x", 2)
	timer_label.add_theme_constant_override("shadow_offset_y", 2)
	
	# Make sure HUD doesn't capture mouse input - let it pass through
	var control_node = $Control
	if control_node:
		control_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Start hidden - will be shown when game starts
	visible = false

func start_timer():
	"""Start the timer - only called by host"""
	if multiplayer.is_server():
		game_start_time = Time.get_time_dict_from_system()
		sync_timer_start.rpc(game_start_time)
	else:
		print("Warning: Only host can start timer")

func stop_timer():
	"""Stop the timer - only called by host"""
	if multiplayer.is_server():
		sync_timer_stop.rpc()

func _on_update_timer_timeout():
	"""Update timer display every 0.1 seconds"""
	if is_timer_running:
		update_display()

func update_display():
	"""Update the timer display with current elapsed time"""
	if not is_timer_running:
		return
		
	var current_time = Time.get_time_dict_from_system()
	var elapsed_time = calculate_elapsed_time(current_time, game_start_time)
	
	timer_label.text = format_time(elapsed_time)
	# Debug print every few seconds to verify timer is updating
	if int(elapsed_time) % 5 == 0 and int(elapsed_time * 10) % 10 == 0:
		print("HUD: Timer update - elapsed: ", elapsed_time, " display: ", timer_label.text)

func calculate_elapsed_time(current_time: Dictionary, start_time: Dictionary) -> float:
	"""Calculate elapsed time in seconds between two time dictionaries"""
	# Convert time dictionaries to total seconds
	var current_seconds = current_time["hour"] * 3600 + current_time["minute"] * 60 + current_time["second"]
	var start_seconds = start_time["hour"] * 3600 + start_time["minute"] * 60 + start_time["second"]
	
	var elapsed = current_seconds - start_seconds
	
	# Handle day rollover (if elapsed is negative, add 24 hours)
	if elapsed < 0:
		elapsed += 24 * 3600
		
	return elapsed

func format_time(seconds: float) -> String:
	"""Format seconds into MM:SS format"""
	var minutes = int(seconds / 60)  # This integer division is intentional
	var secs = int(seconds) % 60
	return "%02d:%02d" % [minutes, secs]

func get_elapsed_time() -> float:
	"""Get current elapsed time in seconds"""
	if not is_timer_running:
		return 0.0
		
	var current_time = Time.get_time_dict_from_system()
	return calculate_elapsed_time(current_time, game_start_time)

func show_hud():
	"""Show the HUD during gameplay"""
	visible = true

func hide_hud():
	"""Hide the HUD during menus/pause"""
	visible = false

func get_timer_running() -> bool:
	"""Get whether the timer is currently running"""
	return is_timer_running

func get_timer_start_time() -> Dictionary:
	"""Get the timer start time for synchronization"""
	return game_start_time
