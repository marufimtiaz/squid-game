extends Control

const PORT = 7000
const MAX_CLIENTS = 4

@onready var single_player: Button = $VBoxContainer/SinglePlayer
@onready var host: Button = $VBoxContainer/Host
@onready var host_ip_label: Label = $VBoxContainer/HostIPLabel
@onready var line_edit: LineEdit = $VBoxContainer/LineEdit
@onready var join: Button = $VBoxContainer/Join
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var back: Button = $VBoxContainer/Back

var peer: ENetMultiplayerPeer
var is_hosting: bool = false  # Track if we're actually hosting

func _ready():
	# Hide IP label initially
	var local_ip = get_local_ip()
	host_ip_label.text = "Host IP: " + local_ip
	host_ip_label.visible = true
	status_label.text = ""  # Empty by default
	
	# Check if we were sent here due to late joining
	if get_tree().has_meta("late_joiner_message"):
		var message = get_tree().get_meta("late_joiner_message")
		status_label.text = message
		# Clear the message so it doesn't persist
		get_tree().remove_meta("late_joiner_message")
		print("Multiplayer Screen: Displayed late joiner message: ", message)

# REMOVED: SPACE bar game starting - host goes directly to game now
# func _input(event): - No longer needed

# REMOVED: update_player_count - no longer needed since host/clients go directly to game
# func update_player_count(): - Players see each other in game scene now

# REMOVED: RPC functions no longer needed - host and clients go directly to game
# @rpc update_status_on_clients() - Status managed in game scene now  
# @rpc start_multiplayer_game() - No manual start needed

func _on_single_player_pressed() -> void:
	# For single player, just go directly to game without networking
	get_tree().change_scene_to_file("res://scenes/glassbridge/game2.tscn")



func _on_host_pressed() -> void:
	# Create server
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CLIENTS)
	
	if error != OK:
		status_label.text = "Failed to host!"
		return
	
	# Set up multiplayer
	multiplayer.multiplayer_peer = peer
	is_hosting = true  # Mark that we're now hosting
	
	# Get and display local IP
	var local_ip = get_local_ip()
	print("Server started on ", local_ip, ":", PORT)
	
	# Connect signals for when clients join later
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	# Host immediately goes to game scene
	print("Host starting game immediately...")
	get_tree().change_scene_to_file("res://scenes/glassbridge/game2.tscn")

func _on_join_pressed() -> void:
	var ip = line_edit.text.strip_edges()
	if ip == "":
		status_label.text = "Enter host IP address"
		return
	
	# Create client
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, PORT)
	
	if error != OK:
		status_label.text = "Failed to connect!"
		return
	
	# Set up multiplayer
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting to " + ip + "..."
	
	# Connect signals
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	print("Connecting to ", ip, ":", PORT)


func _on_back_pressed() -> void:
	# Reset state and disconnect from multiplayer if connected
	is_hosting = false
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	get_tree().change_scene_to_file("res://scenes/startmenu.tscn")


func _on_line_edit_text_submitted(new_text: String) -> void:
	print("Entered IP: " + new_text)

# Network callback functions
func _on_peer_connected(id: int):
	print("Player ", id, " connected")
	# Player count is now managed in game scene

func _on_peer_disconnected(id: int):
	print("Player ", id, " disconnected")
	# Player count is now managed in game scene

func _on_connected_to_server():
	print("Connected to server!")
	# Client immediately goes to game scene to join the host
	print("Client joining game...")
	get_tree().change_scene_to_file("res://scenes/glassbridge/game2.tscn")

func _on_connection_failed():
	print("Failed to connect to server")
	status_label.text = "Connection failed!"

func _on_server_disconnected():
	print("Server disconnected")
	status_label.text = "Host disconnected"

# Utility function to get local IP
func get_local_ip() -> String:
	var addresses = IP.get_local_addresses()
	for address in addresses:
		# Look for local network IP (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
		if address.begins_with("192.168.") or address.begins_with("10.") or (address.begins_with("172.") and address.split(".")[1].to_int() >= 16 and address.split(".")[1].to_int() <= 31):
			return address
	# Fallback to first available address
	return addresses[0] if addresses.size() > 0 else "127.0.0.1"
