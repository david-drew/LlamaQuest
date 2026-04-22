class_name EventGenerator
extends Node

@onready var lore_manager = get_node("/root/Main/Systems/LoreManager")
@onready var history_summarizer = get_node("/root/Main/Systems/HistorySummarizer")

func generate_world_event(current_location: String) -> Dictionary:
	var system_prompt = """
	You are a 2D RPG world event generator. 
	You must output ONLY valid JSON. Do not use markdown blocks.
	You must strictly use the following keys: event_id, title, description, event_category, system_target, duration_days.
	The event_category must be 'weather', 'npc_arrival', or 'hazard'.
	
	Example 1:
	{"event_id": "sudden_downpour", "title": "Heavy Rain", "description": "Dark clouds have rolled in, soaking the ground and making travel difficult.", "event_category": "weather", "system_target": "heavy_rain", "duration_days": 2}
	
	Example 2:
	{"event_id": "merchant_arrival", "title": "Wandering Trader", "description": "Drawn by the recent clearing of the local ruins, a merchant has set up a temporary shop.", "event_category": "npc_arrival", "system_target": "traveling_merchant", "duration_days": 1}
	"""
	
	# Fetch Context: We specifically want history so events react to the player
	var static_lore = lore_manager.get_relevant_lore([current_location, "environment", "rumors"])
	var dynamic_history = history_summarizer.get_recent_history()
	
	var context_block = "Current World Context:\n" + static_lore + "\n" + dynamic_history
	var user_request = "Generate a new, unique world event for %s. It should be a mix of random chance and extrapolations of the Recent Events." % current_location
	
	var final_prompt = system_prompt + "\n\n" + context_block + "\n\n" + user_request
	
	var max_retries = 2
	var attempts = 0
	
	while attempts <= max_retries:
		print("Generating world event for ", current_location, " (Attempt ", attempts + 1, ")...")
		var event_data = await LlmManager.query_llm(final_prompt)
		
		if _is_valid_event(event_data):
			return event_data
			
		print("EventGenerator: Validation failed. Retrying...")
		attempts += 1
		
	push_error("EventGenerator: LLM failed to return valid event JSON.")
	return {"error": "Failed to generate event."}

# Validation Helper
func _is_valid_event(data: Dictionary) -> bool:
	var required_keys = [
		"event_id", "title", "description", "event_category", 
		"system_target", "duration_days"
	]
	for key in required_keys:
		if not data.has(key):
			return false
	return true
