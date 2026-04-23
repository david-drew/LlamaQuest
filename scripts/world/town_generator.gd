extends Node2D
# class_name TownGenerator

const SIDE_NORTH := "north"
const SIDE_SOUTH := "south"
const SIDE_EAST := "east"
const SIDE_WEST := "west"
const PROCGEN_REGISTRY_SCRIPT := preload("res://scripts/worldgen/registries/procgen_registry.gd")
const TOWN_LAYOUT_SKELETON_BUILDER_SCRIPT := preload("res://scripts/worldgen/town/town_layout_skeleton_builder.gd")
const TOWN_LOT_GENERATOR_SCRIPT := preload("res://scripts/worldgen/town/town_lot_generator.gd")
const BUILDING_ASSIGNMENT_SERVICE_SCRIPT := preload("res://scripts/worldgen/town/building_assignment_service.gd")
const TOWN_PLACEHOLDER_RENDERER_SCRIPT := preload("res://scripts/worldgen/town/town_placeholder_renderer.gd")

@export var map_width: int = 2200
@export var map_height: int = 1500
@export var wall_thickness: int = 40
@export var gate_width: int = 220
@export var gate_on_top: bool = true
@export var building_padding: float = 60.0
@export var max_placement_attempts: int = 350
@export var show_debug_triggers: bool = false
@export var show_layout_skeleton_debug: bool = false
@export var show_lot_debug: bool = false
@export var show_town_renderer_debug: bool = false
@export var lot_debug_score_key: String = "market"
@export var standalone_seed: int = 1

var occupied_rects: Array[Rect2] = []
var building_counts: Dictionary = {}
var entry_context
var site_spec: SiteSpec
var site_delta: SiteRuntimeDelta
var procgen_registry: ProcgenRegistry
var layout_skeleton: TownLayoutSkeleton
var lot_instances: Array[LotInstance] = []
var building_assignment_result: Dictionary = {}
var town_renderer: TownPlaceholderRenderer
var traversal_anchors: Dictionary = {}


func configure_site_runtime(context, spec: SiteSpec, delta: SiteRuntimeDelta) -> void:
	entry_context = context
	site_spec = spec
	site_delta = delta


func setup_from_site_spec(spec: SiteSpec, transition, runtime_state: WorldRuntimeState) -> void:
	entry_context = transition
	site_spec = spec
	if runtime_state != null and runtime_state.site_deltas.has(spec.site_id):
		site_delta = runtime_state.site_deltas[spec.site_id]


func configure_entry_context(context) -> void:
	entry_context = context


func _ready() -> void:
	_seed_generation()
	_build_layout_skeleton()
	_generate_lots()
	_assign_buildings_to_lots()
	RenderingServer.set_default_clear_color(Color.BURLYWOOD)
	if _can_render_structured_town():
		_render_structured_town()
	else:
		generate_floor()
		generate_walls()
		if show_layout_skeleton_debug:
			_render_layout_skeleton_debug()
		if show_lot_debug:
			_print_lot_debug_summary()
			_render_lot_debug()
		generate_town()
	_build_traversal_anchors()


func _seed_generation() -> void:
	var site_seed: int = _get_site_seed()
	if site_seed == 0:
		push_warning("TownGenerator: Missing SiteSpec seed; using standalone deterministic seed %d." % standalone_seed)
		seed(standalone_seed)
		return
	seed(site_seed)


func _get_site_seed() -> int:
	if site_spec != null and site_spec.seed != 0:
		return site_spec.seed
	if entry_context != null and int(entry_context.site_seed) != 0:
		return int(entry_context.site_seed)
	if standalone_seed != 0:
		return standalone_seed
	return 0


func _build_layout_skeleton() -> void:
	var spec: SiteSpec = site_spec
	if spec == null:
		spec = _make_standalone_layout_spec()

	var builder: TownLayoutSkeletonBuilder = TOWN_LAYOUT_SKELETON_BUILDER_SCRIPT.new()
	layout_skeleton = builder.build_from_site_spec(spec)
	if layout_skeleton.has_validation_errors():
		push_warning("TownGenerator: TownLayoutSkeleton build failed: " + "; ".join(layout_skeleton.validation_errors))
		return

	map_width = roundi(layout_skeleton.town_bounds.size.x)
	map_height = roundi(layout_skeleton.town_bounds.size.y)
	wall_thickness = roundi(float(layout_skeleton.wall.get("thickness", wall_thickness)))
	if not layout_skeleton.gates.is_empty():
		var gate: Dictionary = layout_skeleton.gates[0]
		gate_width = roundi(float(gate.get("width", gate_width)))
		var gate_side: String = String(gate.get("side", SIDE_SOUTH))
		if gate_side == SIDE_NORTH:
			gate_on_top = true
		elif gate_side == SIDE_SOUTH:
			gate_on_top = false
		else:
			push_warning("TownGenerator: Existing wall renderer only supports north/south gates; skeleton debug still shows '" + gate_side + "'.")
	print("TownGenerator: Built layout skeleton '%s' with %d roads and %d buildable bands." % [
		layout_skeleton.id,
		layout_skeleton.roads.size(),
		layout_skeleton.buildable_bands.size()
	])


func _generate_lots() -> void:
	lot_instances.clear()
	if layout_skeleton == null:
		return
	if layout_skeleton.has_validation_errors():
		return

	var spec: SiteSpec = site_spec
	if spec == null:
		spec = _make_standalone_layout_spec()
	var generator: TownLotGenerator = TOWN_LOT_GENERATOR_SCRIPT.new()
	lot_instances = generator.generate_lots(spec, layout_skeleton)

	var available_count: int = 0
	var reserved_count: int = 0
	var blocked_count: int = 0
	for lot in lot_instances:
		if bool(lot.constraints.get("blocked", false)):
			blocked_count += 1
		elif bool(lot.constraints.get("reserved", false)):
			reserved_count += 1
		elif lot.is_available():
			available_count += 1
	print("TownGenerator: Generated %d lots (%d available, %d reserved, %d blocked)." % [
		lot_instances.size(),
		available_count,
		reserved_count,
		blocked_count
	])


func _assign_buildings_to_lots() -> void:
	building_assignment_result = {}
	if lot_instances.is_empty():
		return
	var spec: SiteSpec = site_spec
	if spec == null:
		spec = _make_standalone_layout_spec()
	_ensure_procgen_registry()
	var assignment_service: BuildingAssignmentService = BUILDING_ASSIGNMENT_SERVICE_SCRIPT.new(procgen_registry)
	building_assignment_result = assignment_service.assign_buildings(spec, lot_instances)
	var assignments: Array = building_assignment_result.get("assignments", [])
	var warnings: Array = building_assignment_result.get("warnings", [])
	print("TownGenerator: Assigned %d buildings to generated lots (%d warnings)." % [
		assignments.size(),
		warnings.size()
	])


func _can_render_structured_town() -> bool:
	if layout_skeleton == null:
		return false
	if layout_skeleton.has_validation_errors():
		return false
	if lot_instances.is_empty():
		return false
	return true


func _render_structured_town() -> void:
	town_renderer = TOWN_PLACEHOLDER_RENDERER_SCRIPT.new()
	town_renderer.name = "TownVisualRoot"
	add_child(town_renderer)
	town_renderer.set_debug_options(_make_renderer_debug_options())
	var spec: SiteSpec = site_spec
	if spec == null:
		spec = _make_standalone_layout_spec()
	town_renderer.render_town(spec, layout_skeleton, lot_instances)
	if show_lot_debug or show_town_renderer_debug:
		_print_lot_debug_summary()


func resolve_spawn_anchor(transition) -> Node2D:
	if traversal_anchors.is_empty():
		_build_traversal_anchors()
	var anchor_id: String = _resolve_entry_anchor_id(transition)
	if traversal_anchors.has(anchor_id):
		var anchor: Node2D = traversal_anchors[anchor_id] as Node2D
		print("TownGenerator: Resolved spawn anchor '" + anchor_id + "' at " + str(anchor.global_position) + ".")
		return anchor
	if traversal_anchors.has("default_entry"):
		push_warning("TownGenerator: Missing requested spawn anchor '" + anchor_id + "'; using default_entry.")
		return traversal_anchors["default_entry"] as Node2D
	push_warning("TownGenerator: No local fallback anchor exists.")
	return null


func resolve_spawn_position(transition) -> Vector2:
	var anchor: Node2D = resolve_spawn_anchor(transition)
	if anchor != null:
		return anchor.global_position
	return Vector2.ZERO


func get_exit_trigger_position(transition) -> Vector2:
	if traversal_anchors.is_empty():
		_build_traversal_anchors()
	var exit_id: String = _get_exit_anchor_id(transition)
	if traversal_anchors.has(exit_id):
		var anchor: Node2D = traversal_anchors[exit_id] as Node2D
		return anchor.position
	if traversal_anchors.has("default_exit"):
		var fallback: Node2D = traversal_anchors["default_exit"] as Node2D
		return fallback.position
	return Vector2(0, -680)


func prepare_for_exit(exit_point_id: String) -> Dictionary:
	return {
		"exit_point_id": exit_point_id,
		"local_exit_position": get_exit_trigger_position(entry_context)
	}


func _build_traversal_anchors() -> void:
	traversal_anchors.clear()
	var direction: String = _get_primary_access_direction()
	var entry_position: Vector2 = _get_entry_spawn_position_for_direction(direction)
	var exit_position: Vector2 = _get_exit_position_for_direction(direction)
	_add_traversal_anchor("main_entry", entry_position)
	_add_traversal_anchor("default_entry", entry_position)
	_add_traversal_anchor(direction + "_entry", entry_position)
	_add_traversal_anchor("main_exit", exit_position)
	_add_traversal_anchor("default_exit", exit_position)
	_add_traversal_anchor(direction + "_exit", exit_position)
	if site_spec != null:
		for access_point in site_spec.access_points:
			if access_point is Dictionary:
				var access_id: String = String(access_point.get("id", ""))
				if access_id != "":
					_add_traversal_anchor(access_id, entry_position)


func _add_traversal_anchor(anchor_id: String, anchor_position: Vector2) -> void:
	if traversal_anchors.has(anchor_id):
		return
	var anchor: Node2D = Node2D.new()
	anchor.name = anchor_id
	anchor.position = anchor_position
	add_child(anchor)
	traversal_anchors[anchor_id] = anchor


func _resolve_entry_anchor_id(transition) -> String:
	if transition != null:
		if String(transition.entry_point_id) != "":
			return String(transition.entry_point_id)
		if transition.spawn_hint.has("preferred_gate_id") and String(transition.spawn_hint["preferred_gate_id"]) != "":
			return String(transition.spawn_hint["preferred_gate_id"])
	if site_spec != null and not site_spec.access_points.is_empty():
		var access_point = site_spec.access_points[0]
		if access_point is Dictionary:
			return String(access_point.get("id", "main_entry"))
	return "main_entry"


func _get_exit_anchor_id(transition) -> String:
	if transition != null and String(transition.exit_point_id) != "":
		return String(transition.exit_point_id)
	return "main_exit"


func _get_primary_access_direction() -> String:
	if site_spec != null:
		for access_point in site_spec.access_points:
			if access_point is Dictionary:
				var direction: String = String(access_point.get("direction", ""))
				if direction != "":
					return direction
	if gate_on_top:
		return SIDE_NORTH
	return SIDE_SOUTH


func _get_entry_spawn_position_for_direction(direction: String) -> Vector2:
	var inset: float = 170.0
	if direction == SIDE_NORTH:
		return Vector2(0, -float(map_height) * 0.5 + inset)
	if direction == SIDE_SOUTH:
		return Vector2(0, float(map_height) * 0.5 - inset)
	if direction == SIDE_WEST:
		return Vector2(-float(map_width) * 0.5 + inset, 0)
	if direction == SIDE_EAST:
		return Vector2(float(map_width) * 0.5 - inset, 0)
	return Vector2(0, float(map_height) * 0.5 - inset)


func _get_exit_position_for_direction(direction: String) -> Vector2:
	var outward: float = 80.0
	if direction == SIDE_NORTH:
		return Vector2(0, -float(map_height) * 0.5 - outward)
	if direction == SIDE_SOUTH:
		return Vector2(0, float(map_height) * 0.5 + outward)
	if direction == SIDE_WEST:
		return Vector2(-float(map_width) * 0.5 - outward, 0)
	if direction == SIDE_EAST:
		return Vector2(float(map_width) * 0.5 + outward, 0)
	return Vector2(0, float(map_height) * 0.5 + outward)


func _make_renderer_debug_options() -> Dictionary:
	return {
		"show_bounds": show_layout_skeleton_debug or show_town_renderer_debug,
		"show_wall": show_layout_skeleton_debug or show_town_renderer_debug,
		"show_roads": show_layout_skeleton_debug or show_town_renderer_debug,
		"show_squares": show_layout_skeleton_debug or show_town_renderer_debug,
		"show_reserved_open_areas": show_layout_skeleton_debug or show_town_renderer_debug,
		"show_buildable_bands": show_layout_skeleton_debug or show_town_renderer_debug,
		"show_district_hints": show_layout_skeleton_debug or show_town_renderer_debug,
		"show_lots": show_lot_debug or show_town_renderer_debug,
		"show_build_areas": show_lot_debug or show_town_renderer_debug,
		"show_lot_labels": show_lot_debug,
		"show_assignment_labels": show_lot_debug or show_town_renderer_debug,
		"show_spawn_points": true,
		"show_exit_points": true,
		"show_doors": true
	}


func _make_standalone_layout_spec() -> SiteSpec:
	var spec: SiteSpec = SiteSpec.new("standalone_town", "town", "Standalone Town", Vector2.ZERO, _get_site_seed(), "town")
	spec.subtype = "walled_market_town"
	spec.generator_id = "town"
	spec.biome = "grassland"
	spec.access_points = [
		{
			"id": "access_road_south",
			"type": "road_entry",
			"direction": "south",
			"network_type": "road"
		}
	]
	spec.scale = {
		"size_tier": "small",
		"population": 180
	}
	spec.generation_params = {
		"building_profile": "prototype_town",
		"has_wall": true,
		"district_style": "market_town",
		"special_features": PackedStringArray(["market_square"])
	}
	return spec


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


func _render_layout_skeleton_debug() -> void:
	if layout_skeleton == null or layout_skeleton.has_validation_errors():
		return
	_add_debug_rect(layout_skeleton.town_bounds, Color(0.1, 0.1, 0.1, 0.10), Color.BLACK, 4.0, 60)
	if layout_skeleton.wall.has("inner_rect"):
		_add_debug_rect(layout_skeleton.wall["inner_rect"], Color(0.15, 0.15, 0.15, 0.05), Color.DIM_GRAY, 3.0, 61)

	for gate in layout_skeleton.gates:
		if gate is Dictionary:
			_add_debug_rect(gate.get("rect", Rect2()), Color(0.1, 0.8, 0.3, 0.38), Color.GREEN, 3.0, 70)

	for road in layout_skeleton.roads:
		if not (road is Dictionary):
			continue
		_add_debug_rect(road.get("rect", Rect2()), Color(0.35, 0.35, 0.35, 0.34), Color.GRAY, 2.0, 62)
		var points: PackedVector2Array = road.get("centerline", PackedVector2Array())
		_add_debug_polyline(points, Color.WHITE, 5.0, 72)

	for square in layout_skeleton.squares:
		if square is Dictionary:
			_add_debug_rect(square.get("rect", Rect2()), Color(0.95, 0.78, 0.25, 0.35), Color.GOLDENROD, 3.0, 63)

	for area in layout_skeleton.reserved_open_areas:
		if area is Dictionary:
			_add_debug_rect(area.get("rect", Rect2()), Color(0.2, 0.7, 1.0, 0.18), Color.DEEP_SKY_BLUE, 2.0, 64)

	for band in layout_skeleton.buildable_bands:
		if band is Dictionary:
			_add_debug_rect(band.get("rect", Rect2()), Color(0.0, 0.45, 0.95, 0.16), Color.CORNFLOWER_BLUE, 2.0, 65)

	for hint in layout_skeleton.district_hints:
		if hint is Dictionary:
			_add_debug_rect(hint.get("rect", Rect2()), Color(0.75, 0.15, 0.85, 0.08), Color.MEDIUM_PURPLE, 1.0, 58)


func _render_lot_debug() -> void:
	for lot in lot_instances:
		var fill_color := _get_lot_debug_color(lot)
		_add_debug_rect(lot.rect, fill_color, Color.BLACK, 1.0, 78)
		_add_debug_rect(lot.build_area, Color(0.95, 0.95, 0.95, 0.22), Color.WHITE, 1.0, 80)
		_add_frontage_debug_marker(lot)


func _print_lot_debug_summary() -> void:
	print("TownGenerator: Lot debug score key = '" + lot_debug_score_key + "'.")
	if not building_assignment_result.is_empty():
		print("TownGenerator: Assignment profile = '" + String(building_assignment_result.get("profile_id", "")) + "'.")
		for record in building_assignment_result.get("assignments", []):
			print("Assignment: " + str(record))
		for warning in building_assignment_result.get("warnings", []):
			print("Assignment warning: " + str(warning))
	for lot in lot_instances:
		var status := String(lot.assignment.get("status", "unassigned"))
		var score := lot.get_score(lot_debug_score_key)
		print("%s status=%s rect=%s build_area=%s frontage=%s score=%.2f tags=%s context=%s" % [
			lot.id,
			status,
			str(lot.rect),
			str(lot.build_area),
			str(lot.frontage),
			score,
			str(lot.district_tags),
			str(lot.context_tags)
		])


func _get_lot_debug_color(lot: LotInstance) -> Color:
	if bool(lot.constraints.get("blocked", false)):
		return Color(0.85, 0.05, 0.05, 0.30)
	if bool(lot.constraints.get("reserved", false)):
		return Color(0.95, 0.75, 0.15, 0.28)
	if String(lot.assignment.get("status", "")) == "assigned":
		return _get_assigned_lot_color(String(lot.assignment.get("building_type_id", "")))
	if lot_debug_score_key != "":
		var score := clampf(lot.get_score(lot_debug_score_key), 0.0, 1.0)
		return Color(0.1 + score * 0.75, 0.25 + score * 0.35, 0.85 - score * 0.65, 0.24)
	if lot.district_tags.has("market"):
		return Color(0.95, 0.65, 0.10, 0.24)
	if lot.district_tags.has("work"):
		return Color(0.55, 0.35, 0.20, 0.24)
	if lot.district_tags.has("residential"):
		return Color(0.20, 0.65, 0.30, 0.22)
	return Color(0.25, 0.45, 0.85, 0.20)


func _get_assigned_lot_color(building_type_id: String) -> Color:
	if building_type_id == "house":
		return Color(0.20, 0.65, 0.30, 0.34)
	if building_type_id == "tavern" or building_type_id == "inn" or building_type_id == "general_store":
		return Color(0.95, 0.55, 0.10, 0.36)
	if building_type_id == "stable" or building_type_id == "blacksmith" or building_type_id == "workshop":
		return Color(0.58, 0.34, 0.18, 0.36)
	if building_type_id == "temple" or building_type_id == "manor":
		return Color(0.50, 0.62, 0.95, 0.36)
	if building_type_id == "guard_post":
		return Color(0.45, 0.48, 0.54, 0.36)
	return Color(0.72, 0.35, 0.85, 0.34)


func _add_frontage_debug_marker(lot: LotInstance) -> void:
	var side := String(lot.frontage.get("side", ""))
	var marker_size := Vector2(20, 6)
	var pos := lot.rect.get_center()
	if side == SIDE_NORTH:
		pos = Vector2(lot.rect.get_center().x, lot.rect.position.y + 3.0)
	elif side == SIDE_SOUTH:
		pos = Vector2(lot.rect.get_center().x, lot.rect.end.y - 3.0)
	elif side == SIDE_EAST:
		marker_size = Vector2(6, 20)
		pos = Vector2(lot.rect.end.x - 3.0, lot.rect.get_center().y)
	elif side == SIDE_WEST:
		marker_size = Vector2(6, 20)
		pos = Vector2(lot.rect.position.x + 3.0, lot.rect.get_center().y)
	else:
		return
	_add_simple_rect(self, marker_size, pos, Color.WHITE, 86)


func _add_debug_rect(rect: Rect2, fill_color: Color, outline_color: Color, outline_width: float, z_index: int) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var visual := Polygon2D.new()
	visual.polygon = _make_centered_rect_polygon(rect.size)
	visual.position = rect.get_center()
	visual.color = fill_color
	visual.z_index = z_index
	add_child(visual)
	_add_rect_outline(self, rect.size, rect.get_center(), outline_color, outline_width, z_index + 1)


func _add_debug_polyline(points: PackedVector2Array, color: Color, width: float, z_index: int) -> void:
	if points.size() < 2:
		return
	var line := Line2D.new()
	line.points = points
	line.default_color = color
	line.width = width
	line.z_index = z_index
	add_child(line)


func generate_town() -> void:
	if _has_assigned_lots():
		_generate_town_from_assigned_lots()
		return

	var building_definitions := _get_building_definitions()

	for building_def in building_definitions:
		var min_count: int = building_def.get("min_count", 1)
		var max_count: int = building_def.get("max_count", 1)
		var building_total := randi_range(min_count, max_count)

		for _i in range(building_total):
			generate_building_zone(building_def)


func _has_assigned_lots() -> bool:
	for lot in lot_instances:
		if String(lot.assignment.get("status", "")) == "assigned":
			return true
	return false


func _generate_town_from_assigned_lots() -> void:
	_ensure_procgen_registry()
	for lot in lot_instances:
		if String(lot.assignment.get("status", "")) != "assigned":
			continue
		var building_type_id: String = String(lot.assignment.get("building_type_id", ""))
		var building_type: BuildingTypeDefinition = procgen_registry.get_building_type(building_type_id)
		if building_type == null:
			push_warning("TownGenerator: Cannot render assigned building type '" + building_type_id + "'.")
			continue
		var building_def: Dictionary = _make_building_definition_from_resources(building_type_id, {}, building_type)
		generate_assigned_building_zone(lot, building_def)


func generate_assigned_building_zone(lot: LotInstance, building_def: Dictionary) -> void:
	var base_size: Vector2 = building_def.get("size", Vector2(150, 100))
	var zone_size: Vector2 = Vector2(
		min(base_size.x, max(lot.build_area.size.x, 24.0)),
		min(base_size.y, max(lot.build_area.size.y, 24.0))
	)
	var placement_pos: Vector2 = lot.build_area.get_center()
	var building_rect: Rect2 = Rect2(placement_pos - (zone_size / 2.0), zone_size)
	occupied_rects.append(building_rect)

	var base_name: String = building_def.get("name", "Building")
	var count: int = int(building_counts.get(base_name, 0)) + 1
	building_counts[base_name] = count
	var instance_name: String = "%s %d" % [base_name, count]
	var door_side: String = _get_door_side_from_frontage(String(lot.frontage.get("side", "")), placement_pos)

	var building_root: Node2D = Node2D.new()
	building_root.name = instance_name.replace(" ", "")
	building_root.position = placement_pos
	add_child(building_root)

	var building_body: StaticBody2D = StaticBody2D.new()
	building_body.collision_layer = 1
	building_root.add_child(building_body)

	var collision: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
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

	var door_setup: Dictionary = _get_door_setup(zone_size, door_side)
	var threshold: Polygon2D = Polygon2D.new()
	threshold.polygon = _make_centered_rect_polygon(door_setup["step_size"])
	threshold.position = door_setup["step_position"]
	threshold.color = Color.BISQUE
	threshold.z_index = 3
	building_root.add_child(threshold)

	var door_visual: Polygon2D = Polygon2D.new()
	door_visual.polygon = _make_centered_rect_polygon(door_setup["door_visual_size"])
	door_visual.color = Color.SADDLE_BROWN
	door_visual.position = door_setup["visual_position"]
	door_visual.z_index = 4
	building_root.add_child(door_visual)

	var door_trigger: Area2D = Area2D.new()
	door_trigger.name = instance_name.replace(" ", "") + "Door"
	door_trigger.collision_layer = 16
	door_trigger.collision_mask = 2
	door_trigger.monitoring = true
	door_trigger.monitorable = true
	door_trigger.position = door_setup["trigger_position"]
	building_root.add_child(door_trigger)

	var door_collision: CollisionShape2D = CollisionShape2D.new()
	var door_shape: RectangleShape2D = RectangleShape2D.new()
	door_shape.size = door_setup["door_trigger_size"]
	door_collision.shape = door_shape
	door_trigger.add_child(door_collision)

	if show_debug_triggers:
		var debug_visual: Polygon2D = Polygon2D.new()
		debug_visual.polygon = _make_centered_rect_polygon(door_setup["door_trigger_size"])
		debug_visual.color = Color(1.0, 0.0, 1.0, 0.28)
		debug_visual.z_index = 50
		door_trigger.add_child(debug_visual)

	print("%s assigned to %s at %s" % [instance_name, lot.id, placement_pos])
	door_trigger.body_entered.connect(_on_zone_entered.bind(instance_name))


func _get_door_side_from_frontage(frontage_side: String, building_pos: Vector2) -> String:
	if frontage_side == SIDE_NORTH or frontage_side == SIDE_SOUTH or frontage_side == SIDE_EAST or frontage_side == SIDE_WEST:
		return frontage_side
	return _get_door_side(building_pos)


func _get_building_definitions() -> Array:
	var registry_definitions := _get_building_definitions_from_registry()
	if not registry_definitions.is_empty():
		return registry_definitions

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


func _get_building_definitions_from_registry() -> Array:
	_ensure_procgen_registry()
	var profile_id := _get_building_profile_id()
	var profile := procgen_registry.get_building_profile(profile_id)
	if profile == null:
		return []
	if site_spec != null:
		if not profile.supports_town_subtype(site_spec.subtype):
			push_warning("TownGenerator: Building profile '" + profile_id + "' does not support town subtype '" + site_spec.subtype + "'.")
			return []
		if not profile.supports_scale(site_spec.scale):
			push_warning("TownGenerator: Building profile '" + profile_id + "' does not support this town scale.")
			return []

	var definitions: Array = []
	for building_type_id in profile.building_types.keys():
		var building_type := procgen_registry.get_building_type(String(building_type_id))
		if building_type == null:
			continue
		var count_rules: Dictionary = profile.building_types[building_type_id]
		definitions.append(_make_building_definition_from_resources(String(building_type_id), count_rules, building_type))

	return definitions


func _ensure_procgen_registry() -> void:
	if procgen_registry != null:
		return
	procgen_registry = PROCGEN_REGISTRY_SCRIPT.new()
	procgen_registry.load_all()


func _get_building_profile_id() -> String:
	var profile_id := "prototype_town"
	if site_spec != null:
		profile_id = String(site_spec.generation_params.get("building_profile", profile_id))
	return profile_id


func _make_building_definition_from_resources(
	building_type_id: String,
	count_rules: Dictionary,
	building_type: BuildingTypeDefinition
) -> Dictionary:
	var visual := building_type.visual_rules
	var footprint := building_type.footprint_rules
	return {
		"name": String(visual.get("display_name", building_type_id.capitalize())),
		"min_count": int(count_rules.get("min_count", count_rules.get("min", 1))),
		"max_count": int(count_rules.get("max_count", count_rules.get("max", 1))),
		"size": footprint.get("default_size", Vector2(150, 100)),
		"size_variation": footprint.get("size_variation", Vector2.ZERO),
		"color": visual.get("color", Color.GRAY),
		"placement": String(count_rules.get("placement", visual.get("placement", "any"))),
		"accent": String(visual.get("accent", "roof_patch"))
	}


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
