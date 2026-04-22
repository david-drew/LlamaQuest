
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

class BSPNode:
	var partition_rect: Rect2
	var left_child: BSPNode
	var right_child: BSPNode
	var room: DungeonRoom # This will be null until we carve the rooms
	
	func _init(rect: Rect2):
		partition_rect = rect

	func is_leaf() -> bool:
		return left_child == null and right_child == null

# Generator Parameters
@export var dungeon_size := Vector2i(64, 64)
@export var min_floors := 2
@export var max_floors := 4

@export var grid_size := Vector2i(64, 64)
@export var min_partition_size := 12
@export var max_partition_size := 24
@export var min_room_size := 6

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


func _partition_space(rect: Rect2) -> BSPNode:
	var node = BSPNode.new(rect)
	
	# If the partition is already small enough, maybe don't split it (add some RNG)
	if rect.size.x < max_partition_size and rect.size.y < max_partition_size:
		if randf() > 0.75: # 25% chance to stop early for organic variety
			return node
			
	# Determine split direction based on aspect ratio to avoid long, thin slices
	var split_horizontal := randf() > 0.5
	if rect.size.x > rect.size.y * 1.25:
		split_horizontal = false # Too wide, force vertical split
	elif rect.size.y > rect.size.x * 1.25:
		split_horizontal = true  # Too tall, force horizontal split

	# Calculate the maximum allowed split point
	var max_split: int
	if split_horizontal:
		max_split = int(rect.size.y) - min_partition_size
	else:
		max_split = int(rect.size.x) - min_partition_size

	# If the space is too small to split legally, we stop and make it a leaf
	if max_split <= min_partition_size:
		return node

	# Execute the split
	var split_point = randi_range(min_partition_size, max_split)
	
	var rect1: Rect2
	var rect2: Rect2
	
	if split_horizontal:
		rect1 = Rect2(rect.position, Vector2(rect.size.x, split_point))
		rect2 = Rect2(rect.position + Vector2(0, split_point), Vector2(rect.size.x, rect.size.y - split_point))
	else:
		rect1 = Rect2(rect.position, Vector2(split_point, rect.size.y))
		rect2 = Rect2(rect.position + Vector2(split_point, 0), Vector2(rect.size.x - split_point, rect.size.y))

	# Recurse
	node.left_child = _partition_space(rect1)
	node.right_child = _partition_space(rect2)

	return node
