extends Button

func _on_pressed() -> void:
	print("UI: Quit requested. Initiating graceful shutdown...")
	
	# This tells Godot to close the game. 
	# As the tree collapses, LlmManager._exit_tree() will automatically 
	# fire and run OS.kill() to shut down the llama-server.
	get_tree().quit()
