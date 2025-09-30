#!/usr/bin/env gdscript
# Test script to validate multiplayer fixes

extends SceneTree

func _init():
	print("=== Multiplayer Fix Validation ===")
	
	# Test 1: Check if our scene files can load
	print("\n1. Testing scene loading...")
	var game_scene = load("res://scenes/glassbridge/game2.tscn")
	var player_scene = load("res://scenes/glassbridge/player_glass.tscn")
	
	if game_scene:
		print("✓ Game scene loads successfully")
	else:
		print("✗ Game scene failed to load")
	
	if player_scene:
		print("✓ Player scene loads successfully")
	else:
		print("✗ Player scene failed to load")
	
	# Test 2: Check if our scripts compile without errors
	print("\n2. Testing script compilation...")
	var glsbrg_script = load("res://scripts/glassbridge/glsbrg.gd")
	var player_script = load("res://scripts/glassbridge/player_glass.gd")
	
	if glsbrg_script:
		print("✓ glsbrg.gd compiles successfully")
	else:
		print("✗ glsbrg.gd compilation failed")
	
	if player_script:
		print("✓ player_glass.gd compiles successfully")
	else:
		print("✗ player_glass.gd compilation failed")
	
	# Test 3: Instantiate a player to check MultiplayerSynchronizer
	print("\n3. Testing player instantiation...")
	if player_scene:
		var player_instance = player_scene.instantiate()
		if player_instance:
			print("✓ Player instantiated successfully")
			var sync_node = player_instance.get_node_or_null("MultiplayerSynchronizer")
			if sync_node:
				print("✓ MultiplayerSynchronizer found in player")
				print("  - Synchronizer class: ", sync_node.get_class())
				print("  - Synchronizer enabled: ", not sync_node.is_disabled())
			else:
				print("✗ MultiplayerSynchronizer not found in player")
			player_instance.queue_free()
		else:
			print("✗ Failed to instantiate player")
	
	print("\n=== Validation Complete ===")
	quit()