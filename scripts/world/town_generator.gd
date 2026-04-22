extends Node2D
# class_name TownGenerator

const SIDE_NORTH := "north"
const SIDE_SOUTH := "south"
const SIDE_EAST := "east"
const SIDE_WEST := "west"

@export var map_width: int = 2200
@export var map_height: int = 1500
@export var wall_thickness: int = 40
@export var gate_width: int = 220
@export var gate_on_top: bool = true
@export var building_padding: float = 60.0
@export var max_placement_attempts: int = 350
@export var show_debug_triggers: bool = false

var occupied_rects: Array[Rect2] = []
var building_counts: Dictionary = {}


func _ready() -> void:
	randomize()
	RenderingServer.set_default_clear_color(Color.BURLYWOOD)
	generate_floor()
	generate_walls()
	generate_town()


func generate_floor() -> void:
	var floor := Polygon2D.new()
	floor.polygon = _make_centered_rect_polygon(Vector2(map_width, map_height))
	floor.color = Color.BURLYWOOD
	floor.z_index = -20
	add_child(floor)


func generate_walls() -> void:
	var half_map_width := map_width / 2.0
	var half_map_height := map_height / 2.0
	var half_gate_width := gate_width / 2.0

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
	var wall_body := StaticBody2D.new()
	wall_body.collision_layer = 1
	wall_body.position = rect.position + (rect.size / 2.0)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape

	var visual := Polygon2D.new()
	visual.polygon = _make_centered_rect_polygon(rect.size)
	visual.color = Color.DIM_GRAY

	wall_body.add_child(visual)
	wall_body.add_child(collision)
	add_child(wall_body)


func generate_town() -> void:
	var building_definitions := _get_building_definitions()

	for building_def in building_definitions:
		var min_count: int = building_def.get("min_count", 1)
		var max_count: int = building_def.get("max_count", 1)
		var building_total := randi_range(min_count, max_count)

		for _i in range(building_total):
			generate_building_zone(building_def)


func _get_building_definitions() -> Array:
	return [
		{
			"name": "Tavern",
			"min_count": 1,
			"max_count": 3,
			"size": Vector2(230, 150),
			"size_variation": Vector2(25, 18),
			"color": Color.SIENNA,
			"placement": "center",
			"accent": "porch"
		},
		{
			"name": "Inn",
			"min_count": 1,
			"max_count": 2,
			"size": Vector2(250, 160),
			"size_variation": Vector2(30, 18),
			"color": Color.DEEP_SKY_BLUE,
			"placement": "center",
			"accent": "courtyard"
		},
		{
			"name": "House",
			"min_count": 5,
			"max_count": 10,
			"size": Vector2(130, 96),
			"size_variation": Vector2(18, 14),
			"color": Color.PERU,
			"placement": "any",
			"accent": "roof_patch"
		},
		{
			"name": "Blacksmith",
			"min_count": 1,
			"max_count": 2,
			"size": Vector2(170, 120),
			"size_variation": Vector2(20, 16),
			"color": Color.DARK_RED,
			"placement": "edge",
			"accent": "forge_yard"
		},
		{
			"name": "General Store",
			"min_count": 1,
			"max_count": 2,
			"size": Vector2(190, 125),
			"size_variation": Vector2(22, 14),
			"color": Color.DARK_OLIVE_GREEN,
			"placement": "center",
			"accent": "stall"
		},
		{
			"name": "Temple",
			"min_count": 1,
			"max_count": 1,
			"size": Vector2(190, 170),
			"size_variation": Vector2(12, 12),
			"color": Color.LIGHT_STEEL_BLUE,
			"placement": "center",
			"accent": "forecourt"
		},
		{
			"name": "Stable",
			"min_count": 1,
			"max_count": 2,
			"size": Vector2(220, 110),
			"size_variation": Vector2(20, 12),
			"color": Color.SADDLE_BROWN,
			"placement": "edge",
			"accent": "pen"
		},
		{
			"name": "Guard Post",
			"min_count": 1,
			"max_count": 2,
			"size": Vector2(150, 110),
			"size_variation": Vector2(10, 10),
			"color": Color.SLATE_GRAY,
			"placement": "gate_side",
			"accent": "side_room"
		},
		{
			"name": "Workshop",
			"min_count": 1,
			"max_count": 3,
			"size": Vector2(165, 120),
			"size_variation": Vector2(18, 14),
			"color": Color.ROSY_BROWN,
			"placement": "edge",
			"accent": "storage"
		},
		{
			"name": "Apothecary",
			"min_count": 1,
			"max_count": 1,
			"size": Vector2(150, 110),
			"size_variation": Vector2(14, 10),
			"color": Color.MEDIUM_PURPLE,
			"placement": "center",
			"accent": "garden"
		},
		{
			"name": "Manor",
			"min_count": 1,
			"max_count": 1,
			"size": Vector2(270, 180),
			"size_variation": Vector2(20, 16),
			"color": Color.GOLDENROD,
			"placement": "center",
			"accent": "court"
		}
	]


func generate_building_zone(building_def: Dictionary) -> void:
	var base_size: Vector2 = building_def.get("size", Vector2(150, 100))
	var size_variation: Vector2 = building_def.get("size_variation", Vector2.ZERO)
	var zone_size := Vector2(
		round(base_size.x + randf_range(-size_variation.x, size_variation.x)),
		round(base_size.y + randf_range(-size_variation.y, size_variation.y))
	)

	var placement_pref: String = building_def.get("placement", "any")
	var placement_result := _find_valid_position(zone_size, placement_pref)

	if not placement_result["success"]:
		print("TownGenerator: Failed to place ", building_def.get("name", "Building"))
		return

	var placement_pos: Vector2 = placement_result["position"]
	var building_rect := Rect2(placement_pos - (zone_size / 2.0), zone_size)
	occupied_rects.append(building_rect)

	var base_name: String = building_def.get("name", "Building")
	var count := int(building_counts.get(base_name, 0)) + 1
	building_counts[base_name] = count
	var instance_name := "%s %d" % [base_name, count]
	var door_side := _get_door_side(placement_pos)

	var building_root := Node2D.new()
	building_root.name = instance_name.replace(" ", "")
	building_root.position = placement_pos
	add_child(building_root)

	var building_body := StaticBody2D.new()
	building_body.collision_layer = 1
	building_root.add_child(building_body)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = zone_size
	collision.shape = shape
	building_body.add_child(collision)

	_add_main_building_visuals(building_body, zone_size, building_def.get("color", Color.GRAY), door_side)
	_add_building_details(
		building_root,
		zone_size,
		building_def.get("color", Color.GRAY),
		building_def.get("accent", "roof_patch"),
		door_side
	)

	var door_setup := _get_door_setup(zone_size, door_side)

	var threshold := Polygon2D.new()
	threshold.polygon = _make_centered_rect_polygon(door_setup["step_size"])
	threshold.position = door_setup["step_position"]
	threshold.color = Color.BISQUE
	threshold.z_index = 3
	building_root.add_child(threshold)

	var door_visual := Polygon2D.new()
	door_visual.polygon = _make_centered_rect_polygon(door_setup["door_visual_size"])
	door_visual.color = Color.SADDLE_BROWN
	door_visual.position = door_setup["visual_position"]
	door_visual.z_index = 4
	building_root.add_child(door_visual)

	var door_trigger := Area2D.new()
	door_trigger.name = instance_name.replace(" ", "") + "Door"
	door_trigger.collision_layer = 16
	door_trigger.collision_mask = 2
	door_trigger.monitoring = true
	door_trigger.monitorable = true
	door_trigger.position = door_setup["trigger_position"]
	building_root.add_child(door_trigger)

	var door_collision := CollisionShape2D.new()
	var door_shape := RectangleShape2D.new()
	door_shape.size = door_setup["door_trigger_size"]
	door_collision.shape = door_shape
	door_trigger.add_child(door_collision)

	if show_debug_triggers:
		var debug_visual := Polygon2D.new()
		debug_visual.polygon = _make_centered_rect_polygon(door_setup["door_trigger_size"])
		debug_visual.color = Color(1.0, 0.0, 1.0, 0.28)
		debug_visual.z_index = 50
		door_trigger.add_child(debug_visual)

	print("%s added at %s" % [instance_name, placement_pos])
	door_trigger.body_entered.connect(_on_zone_entered.bind(instance_name))


func _find_valid_position(zone_size: Vector2, preferred_placement: String) -> Dictionary:
	for attempt in range(max_placement_attempts):
		var placement_mode := preferred_placement
		if attempt > int(max_placement_attempts * 0.55):
			placement_mode = "any"

		var candidate := _get_candidate_position(zone_size, placement_mode)
		var candidate_rect := Rect2(candidate - (zone_size / 2.0), zone_size)

		if _is_valid_building_rect(candidate_rect):
			return {
				"success": true,
				"position": candidate
			}

	return {
		"success": false,
		"position": Vector2.ZERO
	}


func _get_candidate_position(zone_size: Vector2, placement_mode: String) -> Vector2:
	var inset := wall_thickness + 80.0
	var half_w := (map_width / 2.0) - (zone_size.x / 2.0) - inset
	var half_h := (map_height / 2.0) - (zone_size.y / 2.0) - inset

	if half_w < 40.0:
		half_w = 40.0
	if half_h < 40.0:
		half_h = 40.0

	if placement_mode == "center":
		return Vector2(
			randf_range(-half_w * 0.55, half_w * 0.55),
			randf_range(-half_h * 0.45, half_h * 0.45)
		)

	if placement_mode == "edge":
		return _get_edge_position(half_w, half_h)

	if placement_mode == "gate_side":
		return _get_gate_side_position(half_w, half_h)

	return Vector2(
		randf_range(-half_w, half_w),
		randf_range(-half_h, half_h)
	)


func _get_edge_position(half_w: float, half_h: float) -> Vector2:
	var band_x:float = min(260.0, half_w * 0.45)
	var band_y:float = min(220.0, half_h * 0.45)
	var side := randi_range(0, 3)

	if side == 0:
		return Vector2(
			randf_range(-half_w, half_w),
			randf_range(-half_h, -half_h + band_y)
		)
	if side == 1:
		return Vector2(
			randf_range(-half_w, half_w),
			randf_range(half_h - band_y, half_h)
		)
	if side == 2:
		return Vector2(
			randf_range(-half_w, -half_w + band_x),
			randf_range(-half_h, half_h)
		)

	return Vector2(
		randf_range(half_w - band_x, half_w),
		randf_range(-half_h, half_h)
	)


func _get_gate_side_position(half_w: float, half_h: float) -> Vector2:
	var gate_margin := (gate_width / 2.0) + 120.0
	var side := randi_range(0, 1)

	if gate_on_top:
		var y_top := randf_range(-half_h, -half_h + min(220.0, half_h * 0.4))
		if side == 0:
			return Vector2(randf_range(-half_w, -gate_margin), y_top)
		return Vector2(randf_range(gate_margin, half_w), y_top)

	var y_bottom := randf_range(half_h - min(220.0, half_h * 0.4), half_h)
	if side == 0:
		return Vector2(randf_range(-half_w, -gate_margin), y_bottom)
	return Vector2(randf_range(gate_margin, half_w), y_bottom)


func _is_valid_building_rect(candidate_rect: Rect2) -> bool:
	var padded_rect := candidate_rect.grow(building_padding)

	for existing_rect in occupied_rects:
		if padded_rect.intersects(existing_rect):
			return false

	var gate_keepout := _get_gate_keepout_rect()
	if padded_rect.intersects(gate_keepout):
		return false

	return true


func _get_gate_keepout_rect() -> Rect2:
	var corridor_width := gate_width + 120.0
	var corridor_depth := 320.0
	var left := -corridor_width / 2.0

	if gate_on_top:
		var top := -map_height / 2.0
		return Rect2(left, top, corridor_width, corridor_depth)

	var bottom_top := (map_height / 2.0) - corridor_depth
	return Rect2(left, bottom_top, corridor_width, corridor_depth)


func _add_main_building_visuals(parent: Node2D, zone_size: Vector2, base_color: Color, door_side: String) -> void:
	var footprint := Polygon2D.new()
	footprint.polygon = _make_centered_rect_polygon(zone_size)
	footprint.color = base_color.darkened(0.18)
	footprint.z_index = 1
	parent.add_child(footprint)

	var roof_inset := Vector2(
		max(zone_size.x - 18.0, 24.0),
		max(zone_size.y - 18.0, 24.0)
	)
	var roof := Polygon2D.new()
	roof.polygon = _make_centered_rect_polygon(roof_inset)
	roof.color = base_color
	roof.z_index = 2
	parent.add_child(roof)

	var ridge_size := Vector2(
		max(zone_size.x * 0.34, 18.0),
		max(zone_size.y * 0.16, 12.0)
	)
	var ridge := Polygon2D.new()
	ridge.polygon = _make_centered_rect_polygon(ridge_size)
	ridge.color = base_color.lightened(0.14)
	ridge.position = _get_side_normal(_get_opposite_side(door_side)) * 12.0
	ridge.z_index = 3
	parent.add_child(ridge)


func _add_building_details(building_root: Node2D, zone_size: Vector2, base_color: Color, accent_type: String, door_side: String) -> void:
	if accent_type == "roof_patch":
		var patch := Polygon2D.new()
		patch.polygon = _make_centered_rect_polygon(Vector2(zone_size.x * 0.42, zone_size.y * 0.26))
		patch.position = _get_side_normal(_get_opposite_side(door_side)) * 10.0
		patch.color = base_color.lightened(0.08)
		patch.z_index = 4
		building_root.add_child(patch)
		return

	if accent_type == "porch":
		var porch_size := _get_front_facing_size(door_side, zone_size, 18.0, 0.40)
		var porch := Polygon2D.new()
		porch.polygon = _make_centered_rect_polygon(porch_size)
		porch.position = _get_attachment_position(zone_size, door_side, porch_size, 2.0)
		porch.color = base_color.darkened(0.06)
		porch.z_index = 2
		building_root.add_child(porch)
		return

	if accent_type == "stall":
		var stall_size := _get_front_facing_size(door_side, zone_size, 22.0, 0.56)
		var stall := Polygon2D.new()
		stall.polygon = _make_centered_rect_polygon(stall_size)
		stall.position = _get_attachment_position(zone_size, door_side, stall_size, 4.0)
		stall.color = Color.BEIGE
		stall.z_index = 1
		building_root.add_child(stall)

		var stall_counter_size := _get_front_facing_size(door_side, zone_size, 10.0, 0.42)
		var counter := Polygon2D.new()
		counter.polygon = _make_centered_rect_polygon(stall_counter_size)
		counter.position = _get_attachment_position(zone_size, door_side, stall_counter_size, -2.0)
		counter.color = base_color.darkened(0.10)
		counter.z_index = 3
		building_root.add_child(counter)
		return

	if accent_type == "forecourt":
		var forecourt_size := _get_front_facing_size(door_side, zone_size, 34.0, 0.58)
		var forecourt := Polygon2D.new()
		forecourt.polygon = _make_centered_rect_polygon(forecourt_size)
		forecourt.position = _get_attachment_position(zone_size, door_side, forecourt_size, 12.0)
		forecourt.color = Color.WHEAT
		forecourt.z_index = 0
		building_root.add_child(forecourt)
		_add_rect_outline(building_root, forecourt_size, forecourt.position, Color.LIGHT_GRAY, 2.0, 1)
		return

	if accent_type == "courtyard":
		var court_size := _get_front_facing_size(door_side, zone_size, 42.0, 0.64)
		var court := Polygon2D.new()
		court.polygon = _make_centered_rect_polygon(court_size)
		court.position = _get_attachment_position(zone_size, door_side, court_size, 12.0)
		court.color = Color.BLANCHED_ALMOND
		court.z_index = 0
		building_root.add_child(court)
		_add_rect_outline(building_root, court_size, court.position, base_color.darkened(0.22), 3.0, 1)
		return

	if accent_type == "garden":
		var garden_side := _get_right_side(door_side)
		var garden_size := _get_side_facing_size(garden_side, zone_size, 44.0, 0.42)
		var garden := Polygon2D.new()
		garden.polygon = _make_centered_rect_polygon(garden_size)
		garden.position = _get_attachment_position(zone_size, garden_side, garden_size, 8.0)
		garden.color = Color.FOREST_GREEN
		garden.z_index = 0
		building_root.add_child(garden)
		_add_rect_outline(building_root, garden_size, garden.position, Color.DARK_GREEN, 2.0, 1)

		var bed_size := garden_size * Vector2(0.72, 0.22)
		var bed_offset := _get_side_tangent(garden_side) * 10.0
		_add_simple_rect(building_root, bed_size, garden.position - bed_offset, Color.DARK_SEA_GREEN, 1)
		_add_simple_rect(building_root, bed_size, garden.position + bed_offset, Color.DARK_SEA_GREEN, 1)
		return

	if accent_type == "pen":
		var pen_side := _get_right_side(door_side)
		var pen_size := _get_side_facing_size(pen_side, zone_size, 52.0, 0.56)
		var pen_position := _get_attachment_position(zone_size, pen_side, pen_size, 12.0)
		var pen_ground := Polygon2D.new()
		pen_ground.polygon = _make_centered_rect_polygon(pen_size)
		pen_ground.position = pen_position
		pen_ground.color = Color(0.54, 0.43, 0.25, 0.55)
		pen_ground.z_index = 0
		building_root.add_child(pen_ground)
		_add_rect_outline(building_root, pen_size, pen_position, Color.SADDLE_BROWN, 3.0, 1)
		return

	if accent_type == "forge_yard":
		var forge_side := _get_left_side(door_side)
		var forge_size := _get_side_facing_size(forge_side, zone_size, 34.0, 0.42)
		var forge_position := _get_attachment_position(zone_size, forge_side, forge_size, 8.0)
		var forge := Polygon2D.new()
		forge.polygon = _make_centered_rect_polygon(forge_size)
		forge.position = forge_position
		forge.color = Color.DIM_GRAY.darkened(0.25)
		forge.z_index = 0
		building_root.add_child(forge)

		var table_size := forge_size * Vector2(0.28, 0.24)
		_add_simple_rect(building_root, table_size, forge_position, base_color.darkened(0.26), 1)
		return

	if accent_type == "storage":
		var storage_side := _get_left_side(door_side)
		var storage_size := _get_side_facing_size(storage_side, zone_size, 22.0, 0.34)
		var storage := Polygon2D.new()
		storage.polygon = _make_centered_rect_polygon(storage_size)
		storage.position = _get_attachment_position(zone_size, storage_side, storage_size, -4.0)
		storage.color = base_color.darkened(0.08)
		storage.z_index = 3
		building_root.add_child(storage)
		return

	if accent_type == "side_room":
		var room_side := _get_left_side(door_side)
		var room_size := _get_side_facing_size(room_side, zone_size, 36.0, 0.46)
		var side_room := Polygon2D.new()
		side_room.polygon = _make_centered_rect_polygon(room_size)
		side_room.position = _get_attachment_position(zone_size, room_side, room_size, -6.0)
		side_room.color = base_color.darkened(0.06)
		side_room.z_index = 3
		building_root.add_child(side_room)
		return

	if accent_type == "court":
		var manor_court_size := _get_front_facing_size(door_side, zone_size, 40.0, 0.62)
		var manor_court_position := _get_attachment_position(zone_size, door_side, manor_court_size, 12.0)
		var manor_court := Polygon2D.new()
		manor_court.polygon = _make_centered_rect_polygon(manor_court_size)
		manor_court.position = manor_court_position
		manor_court.color = Color.BISQUE.darkened(0.04)
		manor_court.z_index = 0
		building_root.add_child(manor_court)
		_add_rect_outline(building_root, manor_court_size, manor_court_position, Color.TAN.darkened(0.22), 3.0, 1)

		var post_extent := manor_court_size.y
		if door_side == SIDE_NORTH or door_side == SIDE_SOUTH:
			post_extent = manor_court_size.x

		var post_side_offset := _get_side_tangent(door_side) * (post_extent * 0.28)
		var post_size := Vector2(8, 8)
		_add_simple_rect(building_root, post_size, manor_court_position - post_side_offset, Color.SADDLE_BROWN, 2)
		_add_simple_rect(building_root, post_size, manor_court_position + post_side_offset, Color.SADDLE_BROWN, 2)
		return


func _get_door_setup(zone_size: Vector2, door_side: String) -> Dictionary:
	var door_visual_size := Vector2(22, 8)
	var door_trigger_size := Vector2(30, 18)
	var step_size := Vector2(28, 10)
	var visual_position := Vector2.ZERO
	var trigger_position := Vector2.ZERO
	var step_position := Vector2.ZERO

	if door_side == SIDE_NORTH:
		visual_position = Vector2(0, -(zone_size.y / 2.0) + (door_visual_size.y / 2.0))
		step_position = Vector2(0, -(zone_size.y / 2.0) - (step_size.y / 2.0) + 2.0)
		trigger_position = Vector2(0, -(zone_size.y / 2.0) - (door_trigger_size.y / 2.0) - 2.0)
	elif door_side == SIDE_SOUTH:
		visual_position = Vector2(0, (zone_size.y / 2.0) - (door_visual_size.y / 2.0))
		step_position = Vector2(0, (zone_size.y / 2.0) + (step_size.y / 2.0) - 2.0)
		trigger_position = Vector2(0, (zone_size.y / 2.0) + (door_trigger_size.y / 2.0) + 2.0)
	elif door_side == SIDE_WEST:
		door_visual_size = Vector2(8, 22)
		door_trigger_size = Vector2(18, 30)
		step_size = Vector2(10, 28)
		visual_position = Vector2(-(zone_size.x / 2.0) + (door_visual_size.x / 2.0), 0)
		step_position = Vector2(-(zone_size.x / 2.0) - (step_size.x / 2.0) + 2.0, 0)
		trigger_position = Vector2(-(zone_size.x / 2.0) - (door_trigger_size.x / 2.0) - 2.0, 0)
	else:
		door_visual_size = Vector2(8, 22)
		door_trigger_size = Vector2(18, 30)
		step_size = Vector2(10, 28)
		visual_position = Vector2((zone_size.x / 2.0) - (door_visual_size.x / 2.0), 0)
		step_position = Vector2((zone_size.x / 2.0) + (step_size.x / 2.0) - 2.0, 0)
		trigger_position = Vector2((zone_size.x / 2.0) + (door_trigger_size.x / 2.0) + 2.0, 0)

	return {
		"door_visual_size": door_visual_size,
		"door_trigger_size": door_trigger_size,
		"step_size": step_size,
		"visual_position": visual_position,
		"step_position": step_position,
		"trigger_position": trigger_position
	}


func _get_door_side(building_pos: Vector2) -> String:
	if abs(building_pos.y) >= abs(building_pos.x):
		if building_pos.y > 0.0:
			return SIDE_NORTH
		return SIDE_SOUTH

	if building_pos.x > 0.0:
		return SIDE_WEST

	return SIDE_EAST


func _get_attachment_position(zone_size: Vector2, side: String, element_size: Vector2, margin: float) -> Vector2:
	if side == SIDE_NORTH:
		return Vector2(0, -(zone_size.y / 2.0) - margin - (element_size.y / 2.0))
	if side == SIDE_SOUTH:
		return Vector2(0, (zone_size.y / 2.0) + margin + (element_size.y / 2.0))
	if side == SIDE_WEST:
		return Vector2(-(zone_size.x / 2.0) - margin - (element_size.x / 2.0), 0)
	return Vector2((zone_size.x / 2.0) + margin + (element_size.x / 2.0), 0)


func _get_front_facing_size(side: String, zone_size: Vector2, depth: float, width_factor: float) -> Vector2:
	if side == SIDE_NORTH or side == SIDE_SOUTH:
		return Vector2(max(zone_size.x * width_factor, 18.0), depth)
	return Vector2(depth, max(zone_size.y * width_factor, 18.0))


func _get_side_facing_size(side: String, zone_size: Vector2, depth: float, length_factor: float) -> Vector2:
	if side == SIDE_NORTH or side == SIDE_SOUTH:
		return Vector2(max(zone_size.x * length_factor, 18.0), depth)
	return Vector2(depth, max(zone_size.y * length_factor, 18.0))


func _get_side_normal(side: String) -> Vector2:
	if side == SIDE_NORTH:
		return Vector2(0, -1)
	if side == SIDE_SOUTH:
		return Vector2(0, 1)
	if side == SIDE_WEST:
		return Vector2(-1, 0)
	return Vector2(1, 0)


func _get_side_tangent(side: String) -> Vector2:
	if side == SIDE_NORTH or side == SIDE_SOUTH:
		return Vector2(1, 0)
	return Vector2(0, 1)


func _get_left_side(side: String) -> String:
	if side == SIDE_NORTH:
		return SIDE_WEST
	if side == SIDE_SOUTH:
		return SIDE_EAST
	if side == SIDE_WEST:
		return SIDE_SOUTH
	return SIDE_NORTH


func _get_right_side(side: String) -> String:
	if side == SIDE_NORTH:
		return SIDE_EAST
	if side == SIDE_SOUTH:
		return SIDE_WEST
	if side == SIDE_WEST:
		return SIDE_NORTH
	return SIDE_SOUTH


func _get_opposite_side(side: String) -> String:
	if side == SIDE_NORTH:
		return SIDE_SOUTH
	if side == SIDE_SOUTH:
		return SIDE_NORTH
	if side == SIDE_WEST:
		return SIDE_EAST
	return SIDE_WEST


func _add_simple_rect(parent: Node2D, size: Vector2, pos: Vector2, color: Color, z_index: int) -> void:
	var rect := Polygon2D.new()
	rect.polygon = _make_centered_rect_polygon(size)
	rect.position = pos
	rect.color = color
	rect.z_index = z_index
	parent.add_child(rect)


func _add_rect_outline(parent: Node2D, size: Vector2, pos: Vector2, color: Color, width: float, z_index: int) -> void:
	var outline := Line2D.new()
	outline.default_color = color
	outline.width = width
	outline.closed = true
	outline.position = pos
	outline.z_index = z_index

	var half := size / 2.0
	outline.points = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])
	parent.add_child(outline)


func _make_centered_rect_polygon(size: Vector2) -> PackedVector2Array:
	var half_size := size / 2.0
	return PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y)
	])


func _on_zone_entered(body: Node2D, zone_name: String) -> void:
	if body.name == "Player":
		print("Player entered the ", zone_name)
