extends Node

@onready var quest_gen = get_node("/root/Main/Systems/QuestGenerator")
@onready var lore_manager = get_node("/root/Main/Systems/LoreManager")
@onready var history_summarizer = get_node("/root/Main/Systems/HistorySummarizer")

var npc_name = "Thorin"
var npc_profession = "Blacksmith"
var npc_location = "Oakhaven Village"

# --- FEATURE 1: Regular Chatting ---
func chat_with_npc():
	var keywords = [npc_profession, npc_location]
	var static_lore = lore_manager.get_relevant_lore(keywords) 
	var dynamic_history = history_summarizer.get_recent_history()
	
	var persona = "You are %s, a %s in %s." % [npc_name, npc_profession, npc_location]
	var format_req = "Output ONLY JSON with a single 'text' key containing your response."
	
	var system_instruction = persona + "\n" + static_lore + "\n" + dynamic_history + "\n" + format_req
	var user_request = "The player walks up to you. Greet them naturally."
	
	var final_prompt = system_instruction + "\n\n" + user_request
	
	var data = await LlmManager.query_llm(final_prompt)
	
	if data.has("text"):
		print(npc_name, " says: ", data["text"])
		return npc_name + " says: " + data["text"]
	else:
		print(npc_name, " says: ... (Error parsing dialogue)")
		return npc_name + " says: ... (Error parsing dialogue)"

# --- FEATURE 2: Quest Generation ---
func ask_for_work():
	# This calls the generator we built, which handles its own RAG and validation
	var new_quest = await quest_gen.generate_quest(npc_name, npc_profession, npc_location)
	
	if not new_quest.has("error"):
		# 1. Output the generated speech to the player
		print(npc_name, " says: ", new_quest["dialogue_pitch"])
		
		# 2. Add it to the global Autoload tracker
		QuestTracker.add_quest(new_quest)
		return npc_name + " says: " + new_quest["dialogue_pitch"]

	else:
		return npc_name + " says: I have no work for you right now."
