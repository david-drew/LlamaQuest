extends Node
class_name LoreManager

var lore_database: Array = []

func _ready():
	_load_lore_database()

func _load_lore_database():
	var file = FileAccess.open("res://data/lore/world_facts.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		if json and json.has("lore"):
			lore_database = json["lore"]
		file.close()

# Pass in the player's current context or the NPC's primary topic
func get_relevant_lore(search_keywords: Array) -> String:
	var relevant_facts = []
	
	for entry in lore_database:
		for keyword in search_keywords:
			if keyword.to_lower() in entry["tags"]:
				if not relevant_facts.has(entry["fact"]):
					relevant_facts.append(entry["fact"])
				break # Move to next entry once a match is found
				
	if relevant_facts.is_empty():
		return ""
		
	# Combine facts into a single context string
	return "Local Lore Context: " + " ".join(relevant_facts)
