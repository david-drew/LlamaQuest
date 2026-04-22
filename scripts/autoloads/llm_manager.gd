extends Node

# Lifecycle variables
var server_pid: int = -1
var is_ai_available: bool = false
const PORT: int = 8080 

@onready var http_request: HTTPRequest = HTTPRequest.new()

func _ready() -> void:
	add_child(http_request)
	# Connecting the signal to satisfy Godot, though we use await for the logic
	http_request.request_completed.connect(_on_request_completed)
	boot_server()

func boot_server() -> void:
	# 1. Get the absolute path to the project root
	var project_root = OS.get_executable_path().get_base_dir()
	if OS.has_feature("editor"):
		project_root = ProjectSettings.globalize_path("res://")
	
	# 2. Build absolute paths to the exe and model
	# simplify_path() ensures Windows-style backslashes
	var server_path = project_root.path_join("bin/llama-server.exe").simplify_path()
	var model_path = project_root.path_join("models/Qwen3.5-2B-Q4_K_M.gguf").simplify_path()
	
	# Safety check: Print these to the console so you can see exactly what Godot is trying to run
	print("LlmManager: Attempting to boot: ", server_path)
	print("LlmManager: Using model: ", model_path)
	
	if not FileAccess.file_exists(server_path):
		push_error("LlmManager: Server executable not found at: " + server_path)
		return

	# 3. Match your successful CLI arguments exactly
	# Note: llama-server uses --ctx-size or -c for context. 
	# Passing 0 as you did in CLI lets the model decide, though 4096 is safer for RPGs.
	var args = PackedStringArray([
		"-m", model_path,
		"--jinja",
		"-c", "4096",            # Your test used 0, but 4096 ensures enough room for quests
		"--host", "127.0.0.1",
		"--port", "8080",         # Matching your successful test port
		"--n-gpu-layers", "99",
		"--reasoning-budget", "0" # Crucial to skip the 30-second "pondering"
	])
	
	# 4. Launch with create_process
	server_pid = OS.create_process(server_path, args)
	
	if server_pid > 0:
		print("LlmManager: llama-server successfully started (PID %d)" % server_pid)
		is_ai_available = true
	else:
		push_error("LlmManager: OS.create_process failed. Try running Godot as Administrator.")

func query_llm(full_prompt: String) -> Dictionary:
	if not is_ai_available:
		return {"error": "AI server not running"}

	# FIX 1: Explicitly use 127.0.0.1 instead of localhost to match your server boot args
	var url = "http://127.0.0.1:%d/v1/chat/completions" % PORT
	
	var body = JSON.stringify({
		"messages": [
			{"role": "system", "content": "You are a helpful RPG assistant. Output JSON only."},
			{"role": "user", "content": full_prompt}
		],
		"temperature": 0.1,
		"stream": false
	})
	
	var headers = ["Content-Type: application/json"]
	
	# TRACER 1: Verify the request is actually being built
	print("LlmManager: Sending API Request to ", url)
	
	# TRACER 2: Catch Godot-side failures before the await
	var send_error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if send_error != OK:
		push_error("LlmManager: HTTPRequest failed to send! Godot Error Code: ", send_error)
		return {"error": "Request failed to send"}
	
	# Wait for the response
	var result_array = await http_request.request_completed
	
	# TRACER 3: Print the exact response payload from the server
	var http_result = result_array[0] # Godot's internal HTTP status (0 is OK)
	var response_code = result_array[1] # The server's HTTP status (e.g., 200, 404)
	var raw_body = result_array[3].get_string_from_utf8()
	
	print("LlmManager: --- RESPONSE RECEIVED ---")
	print("LlmManager: HTTP Result Enum: ", http_result)
	print("LlmManager: Response Code: ", response_code)
	print("LlmManager: Raw Body: \n", raw_body)
	print("LlmManager: -------------------------")
	
	if response_code != 200:
		push_error("LlmManager: Server returned bad HTTP code: ", response_code)
		return {"error": "Bad HTTP response"}
	
	return _parse_openai_response(result_array[3])

func _on_request_completed(_result, _response_code, _headers, _body):
	pass

func _parse_openai_response(body: PackedByteArray) -> Dictionary:
	var raw_text = body.get_string_from_utf8()
	var json = JSON.parse_string(raw_text)
	
	# llama-server (OpenAI format) nesting
	if json and json.has("choices") and json["choices"].size() > 0:
		var message = json["choices"][0].get("message", {})
		var content = message.get("content", "")
		
		if content == "":
			push_error("LlmManager: AI returned empty content.")
			return {"error": "Empty response"}
			
		return _scrub_and_parse_inner_json(content)
	
	return {"error": "Invalid API response format"}

func _scrub_and_parse_inner_json(raw_string: String) -> Dictionary:
	var scrubbed = raw_string.strip_edges()
	
	# Strip Markdown if present
	if scrubbed.begins_with("```json"):
		scrubbed = scrubbed.trim_prefix("```json").trim_suffix("```").strip_edges()
	elif scrubbed.begins_with("```"):
		scrubbed = scrubbed.trim_prefix("```").trim_suffix("```").strip_edges()
	
	var result = JSON.parse_string(scrubbed)
	if result == null:
		push_error("LlmManager: JSON Parse Failed. Text: " + scrubbed)
		return {"error": "JSON Parse Failed"}
		
	return result

func _exit_tree() -> void:
	if server_pid > 0:
		OS.kill(server_pid)
		print("LlmManager: llama-server terminated.")
