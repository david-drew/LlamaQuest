extends Node

# Simple global quest log for the prototype
var active_quests: Dictionary = {}
var completed_quests: Array = []

signal quest_added(quest_data: Dictionary)
signal quest_completed(quest_id: String)

func add_quest(quest_data: Dictionary) -> void:
	if not quest_data.has("quest_id"):
		push_error("QuestTracker: Cannot add quest without quest_id")
		return
		
	var id = quest_data["quest_id"]
	active_quests[id] = quest_data
	
	# FIX: Use quest_id since quest_name isn't in our LLM template
	print("QuestTracker: New quest accepted: ", id)
	quest_added.emit(quest_data)

func complete_quest(quest_id: String) -> void:
	if active_quests.has(quest_id):
		var quest = active_quests[quest_id]
		completed_quests.append(quest)
		active_quests.erase(quest_id)
		
		# FIX: Safely use quest_id here as well
		print("QuestTracker: Quest completed: ", quest_id)
		quest_completed.emit(quest_id)

func is_quest_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)

func get_active_quests() -> Array:
	return active_quests.values()
