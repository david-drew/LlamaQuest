extends Node
class_name QuestGenerator

@onready var lore_manager = get_node("/root/Main/Systems/LoreManager")
@onready var history_summarizer = get_node("/root/Main/Systems/HistorySummarizer")

func generate_quest(npc_name: String, npc_profession: String, location: String) -> Dictionary:
	var system_prompt = """
	You are a 2D RPG quest generation engine. 
	You must output ONLY valid JSON. Do not use markdown blocks.
	You must strictly use the following keys: quest_id, title, dialogue_pitch, objective_action, objective_target, objective_amount, reward_type, reward_target, reward_amount.
	The objective_action must be 'kill', 'fetch', or 'explore'.
	
	Example 1:
	{"quest_id": "clear_cellar_rats", "title": "Rat Infestation", "dialogue_pitch": "The cellar is overrun! Please clear them out before they eat my grain.", "objective_action": "kill", "objective_target": "giant_rat", "objective_amount": 5, "reward_type": "gold", "reward_target": "none", "reward_amount": 25}
	
	Example 2:
	{"quest_id": "lost_heirloom", "title": "The Silver Ring", "dialogue_pitch": "I dropped my grandmother's ring near the riverbank. I can't leave my post to find it.", "objective_action": "fetch", "objective_target": "silver_ring", "objective_amount": 1, "reward_type": "item", "reward_target": "health_potion", "reward_amount": 2}
	"""
	
	var search_tags = [npc_profession, location, "trouble", "history"]
	var static_lore = lore_manager.get_relevant_lore(search_tags)
	var dynamic_history = history_summarizer.get_recent_history()
	
	var context_block = "Current World Context:\n" + static_lore + "\n" + dynamic_history
	var user_request = "You are %s, a %s in %s. Generate a new, unique quest based strictly on the current world context." % [npc_name, npc_profession, location]
	var final_prompt = system_prompt + "\n\n" + context_block + "\n\n" + user_request
	
	# --- THE RETRY LOGIC ---
	var max_retries = 2
	var attempts = 0
	
	while attempts <= max_retries:
		print("Generating quest for ", npc_name, " (Attempt ", attempts + 1, ")...")
		var quest_data = await LlmManager.query_llm(final_prompt)
		
		if _is_valid_quest(quest_data):
			return quest_data
			
		print("QuestGenerator: Validation failed. Retrying...")
		attempts += 1
		
	push_error("QuestGenerator: LLM failed to return valid quest JSON after 3 attempts.")
	return {"error": "Failed to generate quest after 3 attempts."}

# Validation Helper
func _is_valid_quest(data: Dictionary) -> bool:
	var required_keys = [
		"quest_id", "title", "dialogue_pitch", "objective_action", 
		"objective_target", "objective_amount", "reward_type", 
		"reward_target", "reward_amount"
	]
	for key in required_keys:
		if not data.has(key):
			return false
	return true
