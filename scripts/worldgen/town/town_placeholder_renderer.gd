class_name TownPlaceholderRenderer
extends Node2D

const STYLES := preload("res://scripts/worldgen/town/town_render_styles.gd")

var site_spec: SiteSpec
var skeleton: TownLayoutSkeleton
var lots: Array[LotInstance] = []
var debug_options: Dictionary = {
	"show_bounds": false,
	"show_wall": false,
	"show_roads": false,
	"show_squares": false,
	"show_reserved_open_areas": false,
	"show_buildable_bands": false,
	"show_district_hints": false,
	"show_lots": false,
	"show_build_areas": false,
	"show_lot_labels": false,
	"show_assignment_labels": false,
	"show_spawn_points": true,
	"show_exit_points": true,
	"show_doors": true
}


func render_town(p_site_spec: SiteSpec, p_skeleton: TownLayoutSkeleton, p_lots: Array[LotInstance]) -> void:
	site_spec = p_site_spec
	skeleton = p_skeleton
	lots = p_lots.duplicate()
	lots.sort_custom(Callable(self, "_sort_lots_by_id"))
	queue_redraw()


func clear_render() -> void:
	site_spec = null
	skeleton = null
	lots.clear()
	queue_redraw()


func set_debug_options(options: Dictionary) -> void:
	for key in options.keys():
		debug_options[String(key)] = options[key]
	queue_redraw()


func refresh_debug_overlay() -> void:
	queue_redraw()


func _draw() -> void:
	if skeleton == null:
		return
	_draw_ground()
	_draw_structure()
	_draw_buildings()
	_draw_markers()
	_draw_debug()


func _draw_ground() -> void:
	var biome: String = ""
	if site_spec != null:
		biome = site_spec.biome
	draw_rect(skeleton.town_bounds, STYLES.ground_color(biome), true)


func _draw_structure() -> void:
	_draw_wall()
	_draw_roads()
	_draw_squares()


func _draw_wall() -> void:
	if not bool(skeleton.wall.get("enabled", false)):
		return
	var thickness: float = float(skeleton.wall.get("thickness", 40.0))
	var bounds: Rect2 = skeleton.town_bounds
	var top_rect: Rect2 = Rect2(bounds.position.x - thickness, bounds.position.y - thickness, bounds.size.x + thickness * 2.0, thickness)
	var bottom_rect: Rect2 = Rect2(bounds.position.x - thickness, bounds.end.y, bounds.size.x + thickness * 2.0, thickness)
	var left_rect: Rect2 = Rect2(bounds.position.x - thickness, bounds.position.y - thickness, thickness, bounds.size.y + thickness * 2.0)
	var right_rect: Rect2 = Rect2(bounds.end.x, bounds.position.y - thickness, thickness, bounds.size.y + thickness * 2.0)
	for segment in _split_wall_rect_for_gates(top_rect, "north"):
		draw_rect(segment, STYLES.WALL, true)
	for segment in _split_wall_rect_for_gates(bottom_rect, "south"):
		draw_rect(segment, STYLES.WALL, true)
	for segment in _split_wall_rect_for_gates(left_rect, "west"):
		draw_rect(segment, STYLES.WALL, true)
	for segment in _split_wall_rect_for_gates(right_rect, "east"):
		draw_rect(segment, STYLES.WALL, true)

	for gate in skeleton.gates:
		if gate is Dictionary:
			var gate_rect: Rect2 = gate.get("rect", Rect2())
			draw_rect(gate_rect.grow(6.0), STYLES.GATE, true)


func _split_wall_rect_for_gates(rect: Rect2, side: String) -> Array[Rect2]:
	var segments: Array[Rect2] = []
	segments.append(rect)
	for gate in skeleton.gates:
		if not (gate is Dictionary):
			continue
		if String(gate.get("side", "")) != side:
			continue
		var gate_rect: Rect2 = gate.get("rect", Rect2())
		var next_segments: Array[Rect2] = []
		for segment in segments:
			for split in _subtract_gate_from_wall_segment(segment, gate_rect.grow(8.0), side):
				next_segments.append(split)
		segments = next_segments
	return segments


func _subtract_gate_from_wall_segment(segment: Rect2, gate_rect: Rect2, side: String) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not segment.intersects(gate_rect):
		result.append(segment)
		return result
	if side == "north" or side == "south":
		var left_width: float = max(0.0, gate_rect.position.x - segment.position.x)
		var right_x: float = gate_rect.end.x
		var right_width: float = max(0.0, segment.end.x - right_x)
		if left_width > 0.0:
			result.append(Rect2(segment.position, Vector2(left_width, segment.size.y)))
		if right_width > 0.0:
			result.append(Rect2(Vector2(right_x, segment.position.y), Vector2(right_width, segment.size.y)))
	else:
		var top_height: float = max(0.0, gate_rect.position.y - segment.position.y)
		var bottom_y: float = gate_rect.end.y
		var bottom_height: float = max(0.0, segment.end.y - bottom_y)
		if top_height > 0.0:
			result.append(Rect2(segment.position, Vector2(segment.size.x, top_height)))
		if bottom_height > 0.0:
			result.append(Rect2(Vector2(segment.position.x, bottom_y), Vector2(segment.size.x, bottom_height)))
	return result


func _draw_roads() -> void:
	for road in skeleton.roads:
		if not (road is Dictionary):
			continue
		var rect: Rect2 = road.get("rect", Rect2())
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			draw_rect(rect, STYLES.ROAD, true)


func _draw_squares() -> void:
	for square in skeleton.squares:
		if not (square is Dictionary):
			continue
		var rect: Rect2 = square.get("rect", Rect2())
		draw_rect(rect, STYLES.SQUARE, true)
		draw_rect(rect, Color(0.22, 0.18, 0.12, 0.55), false, 3.0)


func _draw_buildings() -> void:
	for lot in lots:
		if String(lot.assignment.get("status", "")) != "assigned":
			continue
		var building_type_id: String = String(lot.assignment.get("building_type_id", ""))
		var footprint: Rect2 = _get_building_footprint(lot)
		var color: Color = STYLES.building_color(building_type_id)
		draw_rect(footprint, color.darkened(0.18), true)
		draw_rect(footprint.grow(-min(10.0, min(footprint.size.x, footprint.size.y) * 0.12)), color, true)
		_draw_attachment(lot, footprint, building_type_id)
		_draw_door_marker(lot, footprint)


func _get_building_footprint(lot: LotInstance) -> Rect2:
	var margin: float = 8.0
	var rect: Rect2 = lot.build_area.grow(-margin)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return lot.build_area
	return rect


func _draw_attachment(lot: LotInstance, footprint: Rect2, building_type_id: String) -> void:
	var accent: String = String(lot.assignment.get("accent", ""))
	if accent == "":
		accent = _fallback_accent_for_type(building_type_id)
	if accent == "":
		return
	var side: String = String(lot.frontage.get("side", ""))
	var attach_rect: Rect2 = _make_attachment_rect(footprint, side, accent)
	if attach_rect.size.x > 0.0 and attach_rect.size.y > 0.0:
		if _rect_overlaps_any_road(attach_rect):
			return
		draw_rect(attach_rect, STYLES.attachment_color(accent), true)


func _fallback_accent_for_type(building_type_id: String) -> String:
	if building_type_id == "stable":
		return "pen"
	if building_type_id == "blacksmith":
		return "forge_yard"
	if building_type_id == "general_store":
		return "stall"
	if building_type_id == "temple":
		return "forecourt"
	if building_type_id == "inn" or building_type_id == "manor":
		return "courtyard"
	if building_type_id == "apothecary":
		return "garden"
	return ""


func _make_attachment_rect(footprint: Rect2, frontage_side: String, accent: String) -> Rect2:
	var depth: float = 28.0
	if accent == "pen" or accent == "courtyard":
		depth = 44.0
	if frontage_side == "north":
		return Rect2(footprint.position.x, footprint.position.y - depth - 4.0, footprint.size.x, depth)
	if frontage_side == "south":
		return Rect2(footprint.position.x, footprint.end.y + 4.0, footprint.size.x, depth)
	if frontage_side == "east":
		return Rect2(footprint.end.x + 4.0, footprint.position.y, depth, footprint.size.y)
	if frontage_side == "west":
		return Rect2(footprint.position.x - depth - 4.0, footprint.position.y, depth, footprint.size.y)
	return Rect2()


func _rect_overlaps_any_road(rect: Rect2) -> bool:
	if skeleton == null:
		return false
	for road in skeleton.roads:
		if not (road is Dictionary):
			continue
		var road_rect: Rect2 = road.get("rect", Rect2())
		if road_rect.size.x <= 0.0 or road_rect.size.y <= 0.0:
			continue
		if rect.intersects(road_rect):
			return true
	return false


func _draw_door_marker(lot: LotInstance, footprint: Rect2) -> void:
	if not bool(debug_options.get("show_doors", true)):
		return
	var side: String = String(lot.frontage.get("side", ""))
	var door_size: Vector2 = Vector2(22, 8)
	var pos: Vector2 = footprint.get_center()
	if side == "north":
		pos = Vector2(footprint.get_center().x, footprint.position.y)
	elif side == "south":
		pos = Vector2(footprint.get_center().x, footprint.end.y)
	elif side == "east":
		door_size = Vector2(8, 22)
		pos = Vector2(footprint.end.x, footprint.get_center().y)
	elif side == "west":
		door_size = Vector2(8, 22)
		pos = Vector2(footprint.position.x, footprint.get_center().y)
	else:
		return
	draw_rect(Rect2(pos - door_size / 2.0, door_size), STYLES.DOOR, true)


func _draw_markers() -> void:
	var gate_center: Vector2 = _get_primary_gate_center()
	if bool(debug_options.get("show_spawn_points", true)):
		draw_circle(_get_spawn_point(gate_center), 16.0, STYLES.SPAWN)
	if bool(debug_options.get("show_exit_points", true)):
		draw_circle(gate_center, 14.0, STYLES.EXIT)


func _draw_debug() -> void:
	if bool(debug_options.get("show_bounds", false)):
		draw_rect(skeleton.town_bounds, Color.BLACK, false, 4.0)
	if bool(debug_options.get("show_reserved_open_areas", false)):
		for area in skeleton.reserved_open_areas:
			if area is Dictionary:
				var rect: Rect2 = area.get("rect", Rect2())
				draw_rect(rect, STYLES.RESERVED, true)
				draw_rect(rect, Color(0.1, 0.35, 0.65, 0.45), false, 2.0)
	if bool(debug_options.get("show_buildable_bands", false)):
		for band in skeleton.buildable_bands:
			if band is Dictionary:
				var rect: Rect2 = band.get("rect", Rect2())
				draw_rect(rect, STYLES.BAND, true)
	if bool(debug_options.get("show_district_hints", false)):
		for hint in skeleton.district_hints:
			if hint is Dictionary:
				var rect: Rect2 = hint.get("rect", Rect2())
				draw_rect(rect, STYLES.DISTRICT_HINT, true)
	if bool(debug_options.get("show_lots", false)) or bool(debug_options.get("show_build_areas", false)):
		_draw_lot_debug()


func _draw_lot_debug() -> void:
	var font: Font = ThemeDB.fallback_font
	for lot in lots:
		var status: String = String(lot.assignment.get("status", "empty"))
		if bool(debug_options.get("show_lots", false)):
			draw_rect(lot.rect, Color(0, 0, 0, 0), false, 1.5)
			draw_rect(lot.rect, STYLES.lot_status_color(status), false, 2.0)
		if bool(debug_options.get("show_build_areas", false)):
			draw_rect(lot.build_area, STYLES.BUILD_AREA, true)
			draw_rect(lot.build_area, Color.WHITE, false, 1.0)
		if bool(debug_options.get("show_lot_labels", false)):
			draw_string(font, lot.rect.position + Vector2(4, 14), lot.id, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, STYLES.LABEL)
		if bool(debug_options.get("show_assignment_labels", false)) and status == "assigned":
			var building_type_id: String = String(lot.assignment.get("building_type_id", ""))
			draw_string(font, lot.rect.get_center(), building_type_id, HORIZONTAL_ALIGNMENT_CENTER, lot.rect.size.x, 12, STYLES.LABEL)


func _get_primary_gate_center() -> Vector2:
	if skeleton == null or skeleton.gates.is_empty():
		return Vector2.ZERO
	if skeleton.gates[0] is Dictionary:
		var gate: Dictionary = skeleton.gates[0]
		var center: Vector2 = gate.get("center", Vector2.ZERO)
		return center
	return Vector2.ZERO


func _get_spawn_point(gate_center: Vector2) -> Vector2:
	if skeleton == null or skeleton.gates.is_empty():
		return Vector2.ZERO
	if skeleton.gates[0] is Dictionary:
		var gate: Dictionary = skeleton.gates[0]
		var inward: Vector2 = gate.get("inward", Vector2.ZERO)
		if inward != Vector2.ZERO:
			return gate_center + inward * 140.0
	return gate_center


func get_local_bounds() -> Rect2:
	if skeleton == null:
		return Rect2()
	return skeleton.town_bounds


func _sort_lots_by_id(a: LotInstance, b: LotInstance) -> bool:
	return a.id < b.id
