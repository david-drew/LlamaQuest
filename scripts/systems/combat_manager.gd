extends Node
class_name CombatManager

@onready var event_logger = get_node("/root/Main/Systems/EventLogger")
var enemy_name = "Goblin Boss"

func die():
	if enemy_name == "Goblin Boss":
		event_logger.log_event("The player bravely defeated the Goblin Boss in the eastern woods.")
	queue_free()
