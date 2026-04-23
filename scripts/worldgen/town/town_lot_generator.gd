class_name TownLotGenerator
extends RefCounted

const SIDE_NORTH := "north"
const SIDE_SOUTH := "south"
const SIDE_EAST := "east"
const SIDE_WEST := "west"

const FRONTAGE_ROAD := "road"
const FRONTAGE_LANE := "lane"
const FRONTAGE_SQUARE := "square"

const SCORE_KEYS := [
	"gate",
	"market",
	"residential",
	"work",
	"quiet",
	"prestige",
	"edge",
	"main_road",
	"civic"
]

const MIN_LOT_SHORT_EDGE := 72.0
const MIN_BUILD_WIDTH := 42.0
const MIN_BUILD_DEPTH := 42.0
const FRONT_SETBACK_ROAD := 24.0
const FRONT_SETBACK_LANE := 18.0
const FRONT_SETBACK_SQUARE := 34.0
const SIDE_MARGIN := 12.0
const BACK_MARGIN := 16.0
const BREATHING_GAP := 20.0
const ROAD_CLEARANCE_MARGIN := 4.0


func generate_lots(spec: SiteSpec, skeleton: TownLayoutSkeleton) -> Array[LotInstance]:
	var input_errors: PackedStringArray = _validate_inputs(spec, skeleton)
	if not input_errors.is_empty():
		push_error("TownLotGenerator: " + "; ".join(input_errors))
		var empty_lots: Array[LotInstance] = []
		return empty_lots

	var lots: Array[LotInstance] = []
	var bands: Array = _collect_buildable_bands(skeleton)
	for band_index in range(bands.size()):
		var band: Dictionary = bands[band_index]
		var band_lots: Array[LotInstance] = _subdivide_band_into_lots(spec, skeleton, band, band_index)
		for lot in band_lots:
			lots.append(lot)

	_finalize_and_validate_lots(lots, skeleton)
	return lots


func _validate_inputs(spec: SiteSpec, skeleton: TownLayoutSkeleton) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if spec == null:
		errors.append("SiteSpec is required.")
	elif spec.site_type != "town":
		errors.append("SiteSpec.site_type must be 'town'.")

	if skeleton == null:
		errors.append("TownLayoutSkeleton is required.")
		return errors
	if skeleton.has_validation_errors():
		for error in skeleton.validation_errors:
			errors.append("Skeleton validation error: " + error)
	if skeleton.town_bounds.size.x <= 0.0 or skeleton.town_bounds.size.y <= 0.0:
		errors.append("TownLayoutSkeleton.town_bounds must be valid.")
	if skeleton.buildable_bands.is_empty():
		errors.append("TownLayoutSkeleton.buildable_bands cannot be empty.")
	if skeleton.district_hints.is_empty():
		errors.append("TownLayoutSkeleton.district_hints cannot be empty for lot scoring.")

	var source_ids: Dictionary = _collect_source_ids(skeleton)
	for band in skeleton.buildable_bands:
		if not (band is Dictionary):
			errors.append("Buildable band must be a Dictionary.")
			continue
		var band_id: String = String(band.get("id", ""))
		var band_rect: Rect2 = band.get("rect", Rect2())
		if band_id == "":
			errors.append("Buildable band id is required.")
		if band_rect.size.x <= 0.0 or band_rect.size.y <= 0.0:
			errors.append("Buildable band '" + band_id + "' has an invalid rect.")
		var source_type: String = String(band.get("source_type", ""))
		var source_id: String = String(band.get("source_id", ""))
		var band_side: String = String(band.get("side", ""))
		if source_type != "road" and source_type != "square":
			errors.append("Buildable band '" + band_id + "' has unsupported source_type '" + source_type + "'.")
		if not source_ids.has(source_id):
			errors.append("Buildable band '" + band_id + "' references missing source '" + source_id + "'.")
		if not _is_supported_side(band_side):
			errors.append("Buildable band '" + band_id + "' has invalid side.")
		if not _is_band_side_valid_for_source(skeleton, source_type, source_id, band_side):
			errors.append("Buildable band '" + band_id + "' side does not match source orientation.")
	return errors


func _collect_buildable_bands(skeleton: TownLayoutSkeleton) -> Array:
	var bands: Array = []
	for band in skeleton.buildable_bands:
		if band is Dictionary:
			bands.append(band)
	return bands


func _subdivide_band_into_lots(
	spec: SiteSpec,
	skeleton: TownLayoutSkeleton,
	band: Dictionary,
	band_index: int
) -> Array[LotInstance]:
	var lots: Array[LotInstance] = []
	var band_rect: Rect2 = band.get("rect", Rect2())
	var horizontal: bool = band_rect.size.x >= band_rect.size.y
	var long_length: float = band_rect.size.x
	if not horizontal:
		long_length = band_rect.size.y
	if long_length < MIN_LOT_SHORT_EDGE:
		push_warning("TownLotGenerator: Band '" + String(band.get("id", "")) + "' is too short for lots.")
		return lots

	var rng: RandomNumberGenerator = _make_rng(spec.seed, String(band.get("id", "")), band_index)
	var cursor: float = 0.0
	var lot_index: int = 0
	var width_range: Vector2 = _get_lot_width_range(spec, band, skeleton)
	while cursor + width_range.x <= long_length:
		var remaining: float = long_length - cursor
		var target_width: float = rng.randf_range(width_range.x, width_range.y)
		if remaining - target_width < width_range.x * 0.72:
			target_width = remaining
		var lot_rect: Rect2 = _make_lot_rect_from_band_slice(band_rect, horizontal, cursor, target_width)
		var lot: LotInstance = _make_lot(spec, skeleton, band, band_index, lot_index, lot_rect, rng)
		lots.append(lot)
		lot_index += 1
		cursor += target_width

		if _should_leave_breathing_gap(rng, band, lot_index, long_length - cursor):
			cursor += BREATHING_GAP

	if lots.is_empty():
		push_warning("TownLotGenerator: Band '" + String(band.get("id", "")) + "' produced zero lots.")
	return lots


func _make_lot(
	spec: SiteSpec,
	skeleton: TownLayoutSkeleton,
	band: Dictionary,
	band_index: int,
	lot_index: int,
	lot_rect: Rect2,
	rng: RandomNumberGenerator
) -> LotInstance:
	var lot: LotInstance = LotInstance.new()
	lot.id = "lot_%03d_%03d" % [band_index, lot_index]
	lot.version = 1
	lot.rect = lot_rect
	lot.frontage = _build_lot_frontage(lot_rect, band, skeleton)
	lot.build_area = _build_lot_build_area(lot_rect, lot.frontage, skeleton)
	lot.context_tags = _apply_context_tags(spec, skeleton, lot)
	lot.district_tags = _apply_district_tags(skeleton, band, lot)
	lot.scores = _compute_scores(spec, skeleton, lot)
	lot.constraints = _apply_constraints(spec, skeleton, lot, rng)
	lot.assignment = {
		"status": "unassigned"
	}
	if bool(lot.constraints.get("blocked", false)):
		lot.assignment["status"] = "blocked"
	elif bool(lot.constraints.get("reserved", false)):
		lot.assignment["status"] = "reserved"
	return lot


func _build_lot_frontage(lot_rect: Rect2, band: Dictionary, skeleton: TownLayoutSkeleton) -> Dictionary:
	var source_type: String = String(band.get("source_type", ""))
	var source_id: String = String(band.get("source_id", ""))
	var band_side: String = String(band.get("side", ""))
	var frontage_side: String = _opposite_side(band_side)
	var frontage_kind: String = ""
	if source_type == "square":
		frontage_kind = FRONTAGE_SQUARE
	elif source_type == "road":
		var source: Dictionary = _get_source_by_id(skeleton, source_id)
		var road_type: String = String(source.get("type", ""))
		if road_type == "side_lane":
			frontage_kind = FRONTAGE_LANE
		else:
			frontage_kind = FRONTAGE_ROAD

	var width: float = lot_rect.size.x
	if frontage_side == SIDE_EAST or frontage_side == SIDE_WEST:
		width = lot_rect.size.y
	return {
		"side": frontage_side,
		"kind": frontage_kind,
		"width": width,
		"source_type": source_type,
		"source_id": source_id,
		"band_id": String(band.get("id", ""))
	}


func _build_lot_build_area(lot_rect: Rect2, frontage: Dictionary, skeleton: TownLayoutSkeleton) -> Rect2:
	var front_side: String = String(frontage.get("side", ""))
	var front_setback: float = _get_front_setback(String(frontage.get("kind", "")))
	var left_margin: float = SIDE_MARGIN
	var right_margin: float = SIDE_MARGIN
	var top_margin: float = SIDE_MARGIN
	var bottom_margin: float = SIDE_MARGIN

	if front_side == SIDE_NORTH:
		top_margin = front_setback
		bottom_margin = BACK_MARGIN
	elif front_side == SIDE_SOUTH:
		top_margin = BACK_MARGIN
		bottom_margin = front_setback
	elif front_side == SIDE_EAST:
		left_margin = BACK_MARGIN
		right_margin = front_setback
	elif front_side == SIDE_WEST:
		left_margin = front_setback
		right_margin = BACK_MARGIN

	var width: float = lot_rect.size.x - left_margin - right_margin
	var height: float = lot_rect.size.y - top_margin - bottom_margin
	if width < 0.0:
		width = 0.0
	if height < 0.0:
		height = 0.0
	var initial_area: Rect2 = Rect2(
		lot_rect.position + Vector2(left_margin, top_margin),
		Vector2(width, height)
	)
	return _clip_build_area_away_from_roads(initial_area, skeleton)


func _apply_district_tags(skeleton: TownLayoutSkeleton, band: Dictionary, lot: LotInstance) -> PackedStringArray:
	var tags: PackedStringArray = PackedStringArray()
	_add_tags(tags, band.get("district_tags", PackedStringArray()))

	for hint in skeleton.district_hints:
		if not (hint is Dictionary):
			continue
		var hint_rect: Rect2 = hint.get("rect", Rect2())
		if _rect_overlap_ratio(lot.rect, hint_rect) >= 0.12 or hint_rect.has_point(lot.rect.get_center()):
			_add_tags(tags, hint.get("tags", PackedStringArray()))

	if lot.context_tags.has("near_gate"):
		_add_tag(tags, "gate")
	if lot.context_tags.has("near_square"):
		_add_tag(tags, "market")
		_add_tag(tags, "civic")
	if lot.context_tags.has("near_wall") or lot.context_tags.has("edge_lot"):
		_add_tag(tags, "edge")
	if String(lot.frontage.get("kind", "")) == FRONTAGE_LANE:
		_add_tag(tags, "residential")
	if String(lot.frontage.get("kind", "")) == FRONTAGE_SQUARE:
		_add_tag(tags, "prestige")

	return _filter_standard_district_tags(tags)


func _apply_context_tags(spec: SiteSpec, skeleton: TownLayoutSkeleton, lot: LotInstance) -> PackedStringArray:
	var tags: PackedStringArray = PackedStringArray()
	var frontage_kind: String = String(lot.frontage.get("kind", ""))
	if frontage_kind == FRONTAGE_ROAD:
		_add_tag(tags, "road_frontage")
	elif frontage_kind == FRONTAGE_LANE:
		_add_tag(tags, "lane_frontage")
	elif frontage_kind == FRONTAGE_SQUARE:
		_add_tag(tags, "square_frontage")

	var gate_center: Vector2 = _get_primary_gate_center(skeleton)
	var square_rect: Rect2 = _get_primary_square_rect(skeleton)
	var lot_center: Vector2 = lot.rect.get_center()
	if _has_primary_gate(skeleton) and lot_center.distance_to(gate_center) <= 420.0:
		_add_tag(tags, "near_gate")
	if square_rect.size.x > 0.0 and lot_center.distance_to(square_rect.get_center()) <= 440.0:
		_add_tag(tags, "near_square")
	if _distance_to_bounds_edge(lot.rect, skeleton.town_bounds) <= 105.0:
		_add_tag(tags, "near_wall")
		_add_tag(tags, "edge_lot")
	else:
		_add_tag(tags, "interior_lot")
	if _is_corner_lot(lot.rect, skeleton):
		_add_tag(tags, "corner_lot")
	if _is_adjacent_to_open_space(lot.rect, skeleton):
		_add_tag(tags, "adjacent_open_space")
	if _has_attachment_space(lot):
		_add_tag(tags, "attachment_friendly")
	return tags


func _compute_scores(spec: SiteSpec, skeleton: TownLayoutSkeleton, lot: LotInstance) -> Dictionary:
	var scores: Dictionary = _make_empty_scores()
	var gate_center: Vector2 = _get_primary_gate_center(skeleton)
	var square_rect: Rect2 = _get_primary_square_rect(skeleton)
	var lot_center: Vector2 = lot.rect.get_center()
	var square_distance_score: float = 0.0
	var gate_distance_score: float = 0.0
	if square_rect.size.x > 0.0:
		square_distance_score = _distance_score(lot_center.distance_to(square_rect.get_center()), 650.0)
	if _has_primary_gate(skeleton):
		gate_distance_score = _distance_score(lot_center.distance_to(gate_center), 620.0)
	var edge_score: float = _distance_score(_distance_to_bounds_edge(lot.rect, skeleton.town_bounds), 260.0)
	var frontage_kind: String = String(lot.frontage.get("kind", ""))
	var area_factor: float = clampf(lot.build_area.get_area() / 18000.0, 0.0, 1.0)

	scores["gate"] = _score_from_signals(lot, "gate", gate_distance_score, 0.25)
	scores["market"] = _score_from_signals(lot, "market", square_distance_score, _frontage_bonus(frontage_kind, FRONTAGE_SQUARE))
	scores["main_road"] = _score_from_signals(lot, "main_road", 0.0, _frontage_bonus(frontage_kind, FRONTAGE_ROAD))
	scores["residential"] = _score_from_signals(lot, "residential", 0.0, _frontage_bonus(frontage_kind, FRONTAGE_LANE))
	scores["work"] = _score_from_signals(lot, "work", edge_score, area_factor * 0.20)
	scores["quiet"] = clampf((1.0 - max(gate_distance_score, square_distance_score)) * 0.70 + _frontage_bonus(frontage_kind, FRONTAGE_LANE), 0.0, 1.0)
	scores["prestige"] = _score_from_signals(lot, "prestige", square_distance_score * 0.55, area_factor * 0.25)
	scores["edge"] = _score_from_signals(lot, "edge", edge_score, 0.0)
	scores["civic"] = _score_from_signals(lot, "civic", square_distance_score * 0.55, _frontage_bonus(frontage_kind, FRONTAGE_SQUARE))

	for key in SCORE_KEYS:
		scores[key] = clampf(float(scores[key]), 0.0, 1.0)
	return scores


func _apply_constraints(spec: SiteSpec, skeleton: TownLayoutSkeleton, lot: LotInstance, rng: RandomNumberGenerator) -> Dictionary:
	var constraints: Dictionary = {
		"blocked": false,
		"reserved": false,
		"allow_building": true,
		"allow_attachment_space": lot.context_tags.has("attachment_friendly"),
		"reasons": PackedStringArray()
	}
	var reasons: PackedStringArray = PackedStringArray()
	if lot.rect.size.x <= 0.0 or lot.rect.size.y <= 0.0:
		reasons.append("degenerate_lot_rect")
	if String(lot.frontage.get("side", "")) == "" or String(lot.frontage.get("kind", "")) == "":
		reasons.append("invalid_frontage")
	if lot.build_area.size.x < MIN_BUILD_WIDTH or lot.build_area.size.y < MIN_BUILD_DEPTH:
		reasons.append("build_area_too_small")
	if not _rect_contains_rect(lot.rect, lot.build_area):
		reasons.append("build_area_outside_lot")
	if _overlaps_road(lot.build_area, skeleton):
		reasons.append("road_overlap")
	if _overlaps_reserved_open_area(lot.rect, skeleton):
		reasons.append("reserved_open_area_overlap")

	if not reasons.is_empty():
		constraints["blocked"] = true
		constraints["allow_building"] = false
		constraints["reasons"] = reasons
		return constraints

	if _should_reserve_lot(lot, rng):
		constraints["reserved"] = true
		constraints["allow_building"] = false
		reasons.append("intentional_breathing_space")

	constraints["reasons"] = reasons
	return constraints


func _finalize_and_validate_lots(lots: Array[LotInstance], skeleton: TownLayoutSkeleton) -> void:
	var ids: Dictionary = {}
	var lots_by_band: Dictionary = {}
	var blocked_by_band: Dictionary = {}
	var total_by_band: Dictionary = {}
	var market_unusable_by_band: Dictionary = {}
	var gate_attachment_count: int = 0
	var available_count: int = 0
	for lot in lots:
		if ids.has(lot.id):
			push_warning("TownLotGenerator: Duplicate lot id '" + lot.id + "'.")
		ids[lot.id] = true
		var band_id: String = String(lot.frontage.get("band_id", ""))
		if not lots_by_band.has(band_id):
			lots_by_band[band_id] = []
			blocked_by_band[band_id] = 0
			total_by_band[band_id] = 0
			market_unusable_by_band[band_id] = 0
		var band_lots: Array = lots_by_band[band_id]
		band_lots.append(lot)
		lots_by_band[band_id] = band_lots
		total_by_band[band_id] = int(total_by_band[band_id]) + 1
		for key in SCORE_KEYS:
			if not lot.scores.has(key):
				lot.scores[key] = 0.0
		if lot.is_available():
			available_count += 1
		if bool(lot.constraints.get("blocked", false)):
			blocked_by_band[band_id] = int(blocked_by_band[band_id]) + 1
		if String(lot.frontage.get("kind", "")) == FRONTAGE_SQUARE and not lot.is_available():
			market_unusable_by_band[band_id] = int(market_unusable_by_band[band_id]) + 1
		if lot.context_tags.has("near_gate") and bool(lot.constraints.get("allow_attachment_space", false)):
			gate_attachment_count += 1
		if not _rect_contains_rect(skeleton.town_bounds, lot.rect):
			push_warning("TownLotGenerator: Lot '" + lot.id + "' escapes town bounds.")
		var errors: PackedStringArray = lot.validate()
		if not errors.is_empty():
			push_warning("TownLotGenerator: Invalid lot '" + lot.id + "': " + "; ".join(errors))
	if available_count == 0 and not lots.is_empty():
		push_warning("TownLotGenerator: Generated lots but none are available for building assignment.")
	_warn_for_overlaps_by_band(lots_by_band)
	_warn_for_band_quality(total_by_band, blocked_by_band, market_unusable_by_band, gate_attachment_count)


func _get_lot_width_range(spec: SiteSpec, band: Dictionary, skeleton: TownLayoutSkeleton) -> Vector2:
	var source_type: String = String(band.get("source_type", ""))
	var tags: PackedStringArray = band.get("district_tags", PackedStringArray())
	var size_tier: String = _get_size_tier(spec.scale)
	var scale_factor: float = 1.0
	if size_tier == "tiny":
		scale_factor = 0.86
	elif size_tier == "medium":
		scale_factor = 1.12
	var range: Vector2 = Vector2(105.0, 165.0)
	if source_type == "square" or tags.has("market"):
		range = Vector2(138.0, 210.0)
	elif tags.has("main_road"):
		range = Vector2(128.0, 196.0)
	elif tags.has("work") or tags.has("edge"):
		range = Vector2(150.0, 230.0)
	return range * scale_factor


func _make_lot_rect_from_band_slice(band_rect: Rect2, horizontal: bool, cursor: float, width: float) -> Rect2:
	if horizontal:
		return Rect2(
			Vector2(band_rect.position.x + cursor, band_rect.position.y),
			Vector2(width, band_rect.size.y)
		)
	return Rect2(
		Vector2(band_rect.position.x, band_rect.position.y + cursor),
		Vector2(band_rect.size.x, width)
	)


func _should_leave_breathing_gap(rng: RandomNumberGenerator, band: Dictionary, lot_index: int, remaining: float) -> bool:
	if lot_index < 2:
		return false
	if remaining < 240.0:
		return false
	if String(band.get("source_type", "")) == "square":
		return rng.randf() < 0.10
	return rng.randf() < 0.06


func _should_reserve_lot(lot: LotInstance, rng: RandomNumberGenerator) -> bool:
	if lot.context_tags.has("near_gate") and lot.context_tags.has("adjacent_open_space"):
		return rng.randf() < 0.18
	if lot.context_tags.has("corner_lot") and lot.context_tags.has("near_square"):
		return rng.randf() < 0.12
	return false


func _get_size_tier(scale: Dictionary) -> String:
	var size_tier: String = String(scale.get("size_tier", scale.get("tier", ""))).to_lower()
	if size_tier == "tiny" or size_tier == "small" or size_tier == "medium":
		return size_tier
	var population: int = int(scale.get("population", 0))
	if population > 350:
		return "medium"
	if population > 0 and population < 90:
		return "tiny"
	return "small"


func _get_front_setback(frontage_kind: String) -> float:
	if frontage_kind == FRONTAGE_SQUARE:
		return FRONT_SETBACK_SQUARE
	if frontage_kind == FRONTAGE_LANE:
		return FRONT_SETBACK_LANE
	return FRONT_SETBACK_ROAD


func _score_from_signals(lot: LotInstance, district_tag: String, distance_signal: float, frontage_signal: float) -> float:
	var score: float = 0.0
	if lot.district_tags.has(district_tag):
		score += 0.46
	if lot.context_tags.has("adjacent_open_space"):
		score += 0.08
	score += distance_signal * 0.34
	score += frontage_signal * 0.28
	return clampf(score, 0.0, 1.0)


func _frontage_bonus(actual: String, expected: String) -> float:
	if actual == expected:
		return 0.55
	return 0.0


func _make_empty_scores() -> Dictionary:
	var scores: Dictionary = {}
	for key in SCORE_KEYS:
		scores[key] = 0.0
	return scores


func _collect_source_ids(skeleton: TownLayoutSkeleton) -> Dictionary:
	var ids: Dictionary = {}
	for road in skeleton.roads:
		if road is Dictionary:
			ids[String(road.get("id", ""))] = true
	for square in skeleton.squares:
		if square is Dictionary:
			ids[String(square.get("id", ""))] = true
	return ids


func _get_source_by_id(skeleton: TownLayoutSkeleton, source_id: String) -> Dictionary:
	for road in skeleton.roads:
		if road is Dictionary and String(road.get("id", "")) == source_id:
			return road
	for square in skeleton.squares:
		if square is Dictionary and String(square.get("id", "")) == source_id:
			return square
	return {}


func _is_band_side_valid_for_source(skeleton: TownLayoutSkeleton, source_type: String, source_id: String, side: String) -> bool:
	if not _is_supported_side(side):
		return false
	if source_type == "square":
		return true
	if source_type != "road":
		return false
	var source: Dictionary = _get_source_by_id(skeleton, source_id)
	if source.is_empty():
		return false
	var axis: String = String(source.get("axis", ""))
	if axis == "vertical":
		return side == SIDE_WEST or side == SIDE_EAST
	if axis == "horizontal":
		return side == SIDE_NORTH or side == SIDE_SOUTH
	return true


func _get_primary_gate_center(skeleton: TownLayoutSkeleton) -> Vector2:
	if skeleton.gates.is_empty():
		return Vector2.ZERO
	if skeleton.gates[0] is Dictionary:
		var gate: Dictionary = skeleton.gates[0]
		var center: Vector2 = gate.get("center", Vector2.ZERO)
		return center
	return Vector2.ZERO


func _has_primary_gate(skeleton: TownLayoutSkeleton) -> bool:
	if skeleton.gates.is_empty():
		return false
	return skeleton.gates[0] is Dictionary


func _get_primary_square_rect(skeleton: TownLayoutSkeleton) -> Rect2:
	if skeleton.squares.is_empty():
		return Rect2()
	if skeleton.squares[0] is Dictionary:
		var square: Dictionary = skeleton.squares[0]
		var rect: Rect2 = square.get("rect", Rect2())
		return rect
	return Rect2()


func _is_adjacent_to_open_space(rect: Rect2, skeleton: TownLayoutSkeleton) -> bool:
	var grown: Rect2 = rect.grow(18.0)
	for area in skeleton.reserved_open_areas:
		if not (area is Dictionary):
			continue
		var area_rect: Rect2 = area.get("rect", Rect2())
		if grown.intersects(area_rect):
			return true
	return false


func _overlaps_reserved_open_area(rect: Rect2, skeleton: TownLayoutSkeleton) -> bool:
	for area in skeleton.reserved_open_areas:
		if not (area is Dictionary):
			continue
		var area_rect: Rect2 = area.get("rect", Rect2())
		if rect.intersects(area_rect):
			return true
	return false


func _overlaps_road(rect: Rect2, skeleton: TownLayoutSkeleton) -> bool:
	for road in skeleton.roads:
		if not (road is Dictionary):
			continue
		var road_rect: Rect2 = road.get("rect", Rect2())
		if road_rect.size.x <= 0.0 or road_rect.size.y <= 0.0:
			continue
		if rect.intersects(road_rect.grow(ROAD_CLEARANCE_MARGIN)):
			return true
	return false


func _clip_build_area_away_from_roads(build_area: Rect2, skeleton: TownLayoutSkeleton) -> Rect2:
	var candidates: Array[Rect2] = [build_area]
	for road in skeleton.roads:
		if not (road is Dictionary):
			continue
		var road_rect: Rect2 = road.get("rect", Rect2())
		if road_rect.size.x <= 0.0 or road_rect.size.y <= 0.0:
			continue
		var blocker: Rect2 = road_rect.grow(ROAD_CLEARANCE_MARGIN)
		var next_candidates: Array[Rect2] = []
		for candidate in candidates:
			for piece in _subtract_rect(candidate, blocker):
				if piece.size.x >= MIN_BUILD_WIDTH and piece.size.y >= MIN_BUILD_DEPTH:
					next_candidates.append(piece)
		if not next_candidates.is_empty():
			candidates = next_candidates

	return _largest_rect(candidates)


func _subtract_rect(source: Rect2, blocker: Rect2) -> Array[Rect2]:
	var pieces: Array[Rect2] = []
	if not source.intersects(blocker):
		pieces.append(source)
		return pieces

	var intersection: Rect2 = source.intersection(blocker)
	if intersection.size.x <= 0.0 or intersection.size.y <= 0.0:
		pieces.append(source)
		return pieces

	if intersection.position.y > source.position.y:
		pieces.append(Rect2(
			source.position,
			Vector2(source.size.x, intersection.position.y - source.position.y)
		))
	if intersection.end.y < source.end.y:
		pieces.append(Rect2(
			Vector2(source.position.x, intersection.end.y),
			Vector2(source.size.x, source.end.y - intersection.end.y)
		))
	if intersection.position.x > source.position.x:
		pieces.append(Rect2(
			Vector2(source.position.x, intersection.position.y),
			Vector2(intersection.position.x - source.position.x, intersection.size.y)
		))
	if intersection.end.x < source.end.x:
		pieces.append(Rect2(
			Vector2(intersection.end.x, intersection.position.y),
			Vector2(source.end.x - intersection.end.x, intersection.size.y)
		))
	return pieces


func _largest_rect(rects: Array[Rect2]) -> Rect2:
	var best: Rect2 = Rect2()
	var best_area: float = -1.0
	for rect in rects:
		var area: float = rect.get_area()
		if area > best_area:
			best = rect
			best_area = area
	return best


func _has_attachment_space(lot: LotInstance) -> bool:
	var slack_x: float = lot.rect.size.x - lot.build_area.size.x
	var slack_y: float = lot.rect.size.y - lot.build_area.size.y
	if max(slack_x, slack_y) >= 44.0 and lot.build_area.get_area() >= 9000.0:
		return true
	return false


func _is_corner_lot(rect: Rect2, skeleton: TownLayoutSkeleton) -> bool:
	var square_rect: Rect2 = _get_primary_square_rect(skeleton)
	if square_rect.size.x <= 0.0:
		return false
	var near_x: bool = abs(rect.get_center().x - square_rect.position.x) <= rect.size.x * 0.7
	if abs(rect.get_center().x - square_rect.end.x) <= rect.size.x * 0.7:
		near_x = true
	var near_y: bool = abs(rect.get_center().y - square_rect.position.y) <= rect.size.y * 0.7
	if abs(rect.get_center().y - square_rect.end.y) <= rect.size.y * 0.7:
		near_y = true
	return near_x and near_y


func _distance_to_bounds_edge(rect: Rect2, bounds: Rect2) -> float:
	var left: float = rect.position.x - bounds.position.x
	var top: float = rect.position.y - bounds.position.y
	var right: float = bounds.end.x - rect.end.x
	var bottom: float = bounds.end.y - rect.end.y
	return min(min(left, right), min(top, bottom))


func _distance_score(distance: float, max_distance: float) -> float:
	if max_distance <= 0.0:
		return 0.0
	return clampf(1.0 - (distance / max_distance), 0.0, 1.0)


func _rect_overlap_ratio(a: Rect2, b: Rect2) -> float:
	if a.size.x <= 0.0 or a.size.y <= 0.0:
		return 0.0
	var intersection: Rect2 = a.intersection(b)
	if intersection.size.x <= 0.0 or intersection.size.y <= 0.0:
		return 0.0
	return clampf(intersection.get_area() / a.get_area(), 0.0, 1.0)


func _rect_contains_rect(outer: Rect2, inner: Rect2) -> bool:
	if inner.position.x < outer.position.x - 0.01:
		return false
	if inner.position.y < outer.position.y - 0.01:
		return false
	if inner.end.x > outer.end.x + 0.01:
		return false
	if inner.end.y > outer.end.y + 0.01:
		return false
	return true


func _warn_for_overlaps_by_band(lots_by_band: Dictionary) -> void:
	for band_id in lots_by_band.keys():
		var band_lots: Array = lots_by_band[band_id]
		for i in range(band_lots.size()):
			var lot_a: LotInstance = band_lots[i]
			for j in range(i + 1, band_lots.size()):
				var lot_b: LotInstance = band_lots[j]
				if lot_a.rect.intersects(lot_b.rect):
					push_warning("TownLotGenerator: Lots '" + lot_a.id + "' and '" + lot_b.id + "' overlap in band '" + String(band_id) + "'.")


func _warn_for_band_quality(
	total_by_band: Dictionary,
	blocked_by_band: Dictionary,
	market_unusable_by_band: Dictionary,
	gate_attachment_count: int
) -> void:
	for band_id in total_by_band.keys():
		var total: int = int(total_by_band[band_id])
		var blocked: int = int(blocked_by_band.get(band_id, 0))
		if total > 0 and float(blocked) / float(total) >= 0.45:
			push_warning("TownLotGenerator: Band '" + String(band_id) + "' has an unusually high blocked-lot ratio.")
		var market_unusable: int = int(market_unusable_by_band.get(band_id, 0))
		if total > 0 and market_unusable == total:
			push_warning("TownLotGenerator: Market-facing band '" + String(band_id) + "' has no usable lots.")
	if gate_attachment_count == 0:
		push_warning("TownLotGenerator: Gate-adjacent lots have no attachment-friendly candidates.")


func _add_tag(tags: PackedStringArray, tag: String) -> void:
	if tag == "":
		return
	if not tags.has(tag):
		tags.append(tag)


func _add_tags(tags: PackedStringArray, new_tags) -> void:
	for tag in new_tags:
		_add_tag(tags, String(tag))


func _filter_standard_district_tags(tags: PackedStringArray) -> PackedStringArray:
	var filtered: PackedStringArray = PackedStringArray()
	for tag in tags:
		if SCORE_KEYS.has(tag):
			_add_tag(filtered, tag)
	return filtered


func _is_supported_side(side: String) -> bool:
	return side == SIDE_NORTH or side == SIDE_SOUTH or side == SIDE_EAST or side == SIDE_WEST


func _opposite_side(side: String) -> String:
	if side == SIDE_NORTH:
		return SIDE_SOUTH
	if side == SIDE_SOUTH:
		return SIDE_NORTH
	if side == SIDE_EAST:
		return SIDE_WEST
	return SIDE_EAST


func _make_rng(seed_value: int, band_id: String, band_index: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var derived: int = int(hash(str(seed_value) + ":town_lots:" + band_id + ":" + str(band_index)))
	if derived < 0:
		derived = -derived
	if derived == 0:
		derived = 1
	rng.seed = derived
	return rng
