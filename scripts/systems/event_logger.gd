class_name EventLogger
extends Node

# The queue to hold our raw event strings
var recent_events: Array[String] = []

# The maximum number of events to hold before we force a summarization
# or drop the oldest memories.
var max_events: int = 20

## Call this from anywhere in your game to record an action
func log_event(event_description: String) -> void:
	recent_events.append(event_description)
	print("Memory Logged: ", event_description) # Helpful for debugging
	
	# Safety valve: If we somehow exceed the max without summarizing, 
	# we drop the oldest event so the array doesn't grow infinitely.
	if recent_events.size() > max_events:
		recent_events.pop_front()

## Retrieves the current queue as a formatted bulleted list for the LLM
func get_unsummarized_events() -> String:
	if recent_events.is_empty():
		return "No recent events of note."
		
	var history_string = "Raw Recent Events:\n"
	for event in recent_events:
		history_string += "- " + event + "\n"
		
	return history_string

## Called AFTER the LLM successfully summarizes these events
func clear_events() -> void:
	recent_events.clear()
	print("Event Logger cleared for new memories.")
