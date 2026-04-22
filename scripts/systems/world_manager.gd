class_name WorldManager
extends Node

# Grab references to other systems that might need updating
# @onready var weather_system = get_node("/root/Main/Systems/WeatherSystem")
# @onready var npc_spawner = get_node("/root/Main/Systems/NPCSpawner")

var season:String = "Thothdawn"
var month:String  = "Midders"
var mdate:int = 1

## Takes the parsed JSON data from the EventGenerator and alters the game state
func apply_event(category: String, target: String) -> void:
	print("WorldManager: Applying event category '", category, "' with target '", target, "'")
	
	match category:
		"weather":
			_handle_weather_change(target)
		"npc_arrival":
			_handle_npc_spawn(target)
		"hazard":
			_handle_world_hazard(target)
		_:
			push_warning("WorldManager: Unknown event category received: " + category)

func _handle_weather_change(weather_type: String) -> void:
	match weather_type:
		"severe_storm":
			print("GAME STATE: Starting rain particle emitters. Player movement speed is set to 1/3rd default.")
			# weather_system.start_rain()
		"heavy_rain":
			print("GAME STATE: Starting rain particle emitters. Halving player movement speed.")
			# weather_system.start_rain()
		"clear_skies":
			print("GAME STATE: Stopping rain. Restoring movement speed.")
			# weather_system.stop_rain()
		_:
			print("GAME STATE: Unrecognized weather target: ", weather_type)

func _handle_npc_spawn(npc_type: String) -> void:
	if npc_type == "traveling_merchant":
		print("GAME STATE: Enabling Traveling Merchant node in the village square.")
		# npc_spawner.spawn("merchant", Vector2(100, 100))

func _handle_world_hazard(hazard_type: String) -> void:
	if hazard_type == "goblin_raiding_party":
		print("GAME STATE: Spawning 3 extra goblins in the eastern woods.")
		# npc_spawner.spawn_group("goblin", 3, "eastern_woods")

func get_date() -> String:
	mdate += 1
	var fulldate:String = "%s, %s %02d" % [season, month, mdate]
	return fulldate
