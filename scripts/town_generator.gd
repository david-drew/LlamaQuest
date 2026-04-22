extends Node2D
# class_name TownGenerator

@export var map_width: int = 1200
@export var map_height: int = 800
@export var wall_thickness: int = 40
@export var gate_width: int = 180
@export var gate_on_top: bool = true

# Store center points of placed buildings.
var occupied_positions: Array[Vector2] = []

func _ready() -> void:
	randomize()
	RenderingServer.set_default_clear_color(Color.BURLYWOOD)
	generate_floor()
	generate_walls()
	generate_building_zone("Inn", Color.DEEP_SKY_BLUE)
	generate_building_zone("Blacksmith", Color.DARK_RED)

func generate_floor() -> void:
	var floor = Polygon2D.new()
	floor.polygon = _make_centered_rect_polygon(Vector2(map_width, map_height))
	floor.color = Color.BURLYWOOD
	floor.z_index = -10
	add_child(floor)

func generate_walls() -> void:
	var half_map_width = map_width / 2.0
	var half_map_height = map_height / 2.0
	var half_gate_width = gate_width / 2.0

	if gate_on_top:
		_create_wall_segment(Rect2(
			-half_map_width,
			-half_map_height - wall_thickness,
			half_map_width - half_gate_width,
			wall_thickness
		))
		_create_wall_segment(Rect2(
			half_gate_width,
			-half_map_height - wall_thickness,
			half_map_width - half_gate_width,
			wall_thickness
		))
		_create_wall_segment(Rect2(
			-half_map_width,
			half_map_height,
			map_width,
			wall_thickness
		))
	else:
		_create_wall_segment(Rect2(
			-half_map_width,
			-half_map_height - wall_thickness,
			map_width,
			wall_thickness
		))
		_create_wall_segment(Rect2(
			-half_map_width,
			half_map_height,
			half_map_width - half_gate_width,
			wall_thickness
		))
		_create_wall_segment(Rect2(
			half_gate_width,
			half_map_height,
			half_map_width - half_gate_width,
			wall_thickness
		))

	_create_wall_segment(Rect2(
		-half_map_width - wall_thickness,
		-half_map_height - wall_thickness,
		wall_thickness,
		map_height + (wall_thickness * 2)
	))
	_create_wall_segment(Rect2(
		half_map_width,
		-half_map_height - wall_thickness,
		wall_thickness,
		map_height + (wall_thickness * 2)
	))

func _create_wall_segment(rect: Rect2) -> void:
	var wall_body = StaticBody2D.new()
	wall_body.collision_layer = 1
	wall_body.position = rect.position + (rect.size / 2.0)

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape

	var visual = Polygon2D.new()
	visual.polygon = _make_centered_rect_polygon(rect.size)
	visual.color = Color.DIM_GRAY

	wall_body.add_child(visual)
	wall_body.add_child(collision)
	add_child(wall_body)

func generate_building_zone(zone_name: String, zone_color: Color) -> void:
	var zone_size = Vector2(150, 100)
	var door_visual_size = Vector2(28, 14)
	var door_trigger_size = Vector2(40, 24)
	var half_w = (map_width / 2.0) - zone_size.x
	var half_h = (map_height / 2.0) - zone_size.y

	var placement_pos = Vector2.ZERO
	var valid_position = false
	var attempts = 0

	while not valid_position and attempts < 50:
		placement_pos = Vector2(
			randf_range(-half_w, half_w),
			randf_range(-half_h, half_h)
		)

		var has_overlap = false
		for pos in occupied_positions:
			if placement_pos.distance_to(pos) < 200.0:
				has_overlap = true
				break

		if not has_overlap:
			valid_position = true

		attempts += 1

	if not valid_position:
		print("TownGenerator: Failed to place ", zone_name)
		return

	occupied_positions.append(placement_pos)

	var building_root = Node2D.new()
	building_root.name = zone_name
	building_root.position = placement_pos
	add_child(building_root)

	var building_body = StaticBody2D.new()
	building_body.collision_layer = 1
	building_root.add_child(building_body)

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = zone_size
	collision.shape = shape
	building_body.add_child(collision)

	var visual = Polygon2D.new()
	visual.polygon = _make_centered_rect_polygon(zone_size)
	visual.color = zone_color
	visual.z_index = 1
	building_body.add_child(visual)

	var door_visual = Polygon2D.new()
	door_visual.polygon = _make_centered_rect_polygon(door_visual_size)
	door_visual.color = Color.SADDLE_BROWN
	door_visual.position = Vector2(0, (zone_size.y / 2.0) - (door_visual_size.y / 2.0))
	door_visual.z_index = 2
	building_root.add_child(door_visual)

	var door_trigger = Area2D.new()
	door_trigger.name = zone_name + "Door"
	door_trigger.collision_layer = 16
	door_trigger.collision_mask = 2
	door_trigger.monitoring = true
	door_trigger.monitorable = true
	door_trigger.position = Vector2(0, (zone_size.y / 2.0) + (door_trigger_size.y / 2.0) - 2.0)
	building_root.add_child(door_trigger)

	var door_collision = CollisionShape2D.new()
	var door_shape = RectangleShape2D.new()
	door_shape.size = door_trigger_size
	door_collision.shape = door_shape
	door_trigger.add_child(door_collision)

	print("%s added at %s" % [zone_name, placement_pos])

	door_trigger.body_entered.connect(_on_zone_entered.bind(zone_name))

func _make_centered_rect_polygon(size: Vector2) -> PackedVector2Array:
	var half_size = size / 2.0
	return PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y)
	])

func _on_zone_entered(body: Node2D, zone_name: String) -> void:
	if body.name == "Player":
		print("Player entered the ", zone_name)
