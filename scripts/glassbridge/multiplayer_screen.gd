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

func _ready():
	# Hide IP label initially
	host_ip_label.visible = false
	status_label.text = ""  # Empty by default

func _input(event):
	# Host can press SPACE to start the game when players are connected
	if event.is_action_pressed("ui_accept") and multiplayer.is_server() and peer != null:
		var player_count = multiplayer.get_peers().size() + 1
		if player_count >= 1:  # Allow host to start alone
			start_multiplayer_game.rpc()  # Use RPC to call on all clients

func update_player_count():
	"""Update and sync player count to all clients"""
	var player_count = multiplayer.get_peers().size() + 1  # +1 for host
	
	if multiplayer.is_server():
		# Server status
		var server_status = "Players: " + str(player_count) + "/4 - Press SPACE to start"
		if player_count >= 2:
			server_status += " (Ready!)"
		status_label.text = server_status
		
		# Client status (without space instruction)
		var client_status = "Players: " + str(player_count) + "/4"
		update_status_on_clients.rpc(client_status)
	else:
		# This shouldn't happen since only server calls this, but just in case
		status_label.text = "Players: " + str(player_count) + "/4"

@rpc("authority", "call_remote", "reliable")
func update_status_on_clients(status_text: String):
	"""Update status on client screens"""
	status_label.text = status_text



@rpc("authority", "call_local", "reliable") 
func start_multiplayer_game():
	"""Start the multiplayer game for all connected players"""
	print("Starting multiplayer game...")
	get_tree().change_scene_to_file("res://scenes/glassbridge/game2.tscn")

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
	
	# Get and display local IP
	var local_ip = get_local_ip()
	host_ip_label.text = "Your IP: " + local_ip
	host_ip_label.visible = true
	
	# Update player count display
	update_player_count()
	
	# Connect signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	print("Server started on ", local_ip, ":", PORT)

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
	# Disconnect from multiplayer if connected
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	get_tree().change_scene_to_file("res://scenes/startmenu.tscn")


func _on_line_edit_text_submitted(new_text: String) -> void:
	print("Entered IP: " + new_text)

# Network callback functions
func _on_peer_connected(id: int):
	print("Player ", id, " connected")
	update_player_count()

func _on_peer_disconnected(id: int):
	print("Player ", id, " disconnected")
	update_player_count()

func _on_connected_to_server():
	print("Connected to server!")
	# Don't set status here - let the server send us the player count
	# The server will call update_status_on_clients.rpc() when we connect

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
