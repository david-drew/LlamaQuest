class_name DungeonGenerator
extends Node2D

# Inner class to hold LLM-ready room data
class DungeonRoom:
	var rect: Rect2
	var center: Vector2
	var tag: String
	
	func _init(_rect: Rect2, _tag: String = "standard"):
		rect = _rect
		center = rect.get_center()
		tag = _tag

# Generator Parameters
@export var dungeon_size := Vector2i(64, 64)
@export var min_room_size := 6
@export var min_floors := 2
@export var max_floors := 4

# Map Data: Array of dictionaries. Each dict holds the tile grid and the rooms for that floor.
var map_data: Array = [] 

func generate_full_dungeon() -> void:
	map_data.clear()
	var num_floors = randi_range(min_floors, max_floors)
	
	for floor_index in range(num_floors):
		var floor_dict = _generate_floor(floor_index, num_floors)
		map_data.append(floor_dict)
		
	print("Dungeon generated with ", num_floors, " floors.")

func _generate_floor(current_floor: int, total_floors: int) -> Dictionary:
	var rooms: Array[DungeonRoom] = []
	# We will use a 2D array (or 1D mapped to 2D) for the physical grid (0 = wall, 1 = floor)
	var grid := [] 
	
	# [BSP Logic will go here]
	# 1. Split space
	# 2. Carve rooms
	# 3. Connect corridors
	# 4. Tag rooms (Entrance, Boss, Stairs)
	
	return {"grid": grid, "rooms": rooms}
