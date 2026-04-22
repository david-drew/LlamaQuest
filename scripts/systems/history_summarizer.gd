extends Node
class_name HistorySummarizer

@onready var event_logger = get_node("/root/Main/Systems/EventLogger")

# This string holds the current active memory for your NPCs
var current_history_summary: String = "The player recently arrived in the area."

## Call this when the player sleeps at an inn, levels up, or fast-travels
func trigger_summarization() -> void:
	var raw_events = event_logger.get_unsummarized_events()
	
	# Don't waste an LLM call if nothing happened
	if raw_events == "No recent events of note.":
		print("No new events to summarize.")
		return
		
	print("Summarizing recent events...")
	
	# 1. Instruct the LLM on exactly how to compress the memory
	var sys_prompt = "You are a video game background system. Summarize the following list of player actions into a single, cohesive paragraph written in the third-person past tense. Output ONLY JSON with a single key named 'summary'."
	
	# 2. Assemble the prompt (incorporating the old summary + new events)
	var context_to_summarize = "Previous Summary:\n" + current_history_summary + "\n\n" + raw_events
	var final_prompt = sys_prompt + "\n\n" + context_to_summarize
	
	# 3. Call the LlmManager
	var response = await LlmManager.query_llm(final_prompt)
	
	# 4. Parse the result and reset the logger
	if response.has("summary"):
		current_history_summary = response["summary"]
		event_logger.clear_events()
		print("New History Summary: ", current_history_summary)
	else:
		push_error("Summarization failed or returned bad JSON: " + str(response))

## Retrieve the current summary to inject into NPC dialogue
func get_recent_history() -> String:
	return "Recent Events: " + current_history_summary
