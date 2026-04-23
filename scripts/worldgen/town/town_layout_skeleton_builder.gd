class_name TownLayoutSkeletonBuilder
extends RefCounted

const SIDE_NORTH := "north"
const SIDE_SOUTH := "south"
const SIDE_EAST := "east"
const SIDE_WEST := "west"

const SUBTYPE_WALLED_MARKET_TOWN := "walled_market_town"
const ACCESS_TYPE_ROAD_ENTRY := "road_entry"

const DEFAULTS := {
	"tiny": {
		"size": Vector2(1500, 1040),
		"square": Vector2(300, 220),
		"lane_count_min": 2,
		"lane_count_max": 2,
		"band_depth": 120.0
	},
	"small": {
		"size": Vector2(2200, 1500),
		"square": Vector2(420, 300),
		"lane_count_min": 2,
		"lane_count_max": 3,
		"band_depth": 150.0
	},
	"medium": {
		"size": Vector2(2850, 1950),
		"square": Vector2(520, 360),
		"lane_count_min": 3,
		"lane_count_max": 4,
		"band_depth": 180.0
	}
}

const WALL_THICKNESS := 40.0
const GATE_WIDTH := 220.0
const MAIN_ROAD_WIDTH := 92.0
const SIDE_LANE_WIDTH := 54.0
const GATE_CLEARANCE_DEPTH := 330.0
const MIN_BAND_EDGE := 90.0
const INNER_MARGIN := 28.0


func build_from_site_spec(spec: SiteSpec) -> TownLayoutSkeleton:
	var skeleton := TownLayoutSkeleton.new()
	var input_errors := _validate_town_spec(spec)
	if spec != null:
		skeleton.id = _get_spec_id(spec) + "_layout_skeleton"
		skeleton.version = spec.version
	if not input_errors.is_empty():
		skeleton.validation_errors = input_errors
		return skeleton

	var access_point := _resolve_primary_access_point(spec)
	var entry_side := String(access_point.get("direction", access_point.get("side", ""))).to_lower()
	var rng := _make_rng(spec.seed, "town_layout")
	var bounds := _resolve_town_dimensions(spec, rng)
	var gate := _build_gate(spec, bounds, entry_side)
	var wall := _build_wall(bounds, gate)
	var square := _build_market_square(spec, bounds, gate, rng)
	var main_road := _build_main_road(bounds, gate, square)
	var side_lanes := _build_side_lanes(spec, bounds, square, gate, rng)
	var roads: Array = [main_road]
	for lane in side_lanes:
		roads.append(lane)
	var reserved_open_areas := _build_reserved_open_areas(gate, square, bounds)
	var buildable_bands := _build_buildable_bands(spec, bounds, roads, square, reserved_open_areas)
	var district_hints := _build_district_hints(bounds, gate, square, roads)

	skeleton.id = _get_spec_id(spec) + "_layout_skeleton"
	skeleton.version = spec.version
	skeleton.town_bounds = bounds
	skeleton.wall = wall
	skeleton.gates = [gate]
	skeleton.roads = roads
	skeleton.squares = [square]
	skeleton.reserved_open_areas = reserved_open_areas
	skeleton.buildable_bands = buildable_bands
	skeleton.district_hints = district_hints
	skeleton.validation_errors = _validate_skeleton(skeleton)
	return skeleton


func _validate_town_spec(spec: SiteSpec) -> PackedStringArray:
	var errors := PackedStringArray()
	if spec == null:
		errors.append("SiteSpec is required for town layout skeleton generation.")
		return errors
	if spec.site_type != "town":
		errors.append("SiteSpec.site_type must be 'town' for town layout skeleton generation.")
	if spec.subtype == "":
		errors.append("SiteSpec.subtype is required for town layout skeleton generation.")
	elif spec.subtype != SUBTYPE_WALLED_MARKET_TOWN:
		errors.append("Unsupported town subtype '" + spec.subtype + "'. Only '" + SUBTYPE_WALLED_MARKET_TOWN + "' is implemented.")
	if spec.generator_id == "":
		errors.append("SiteSpec.generator_id is required for town layout skeleton generation.")
	if spec.seed == 0:
		errors.append("SiteSpec.seed must be nonzero for deterministic town layout generation.")
	if spec.access_points.is_empty():
		errors.append("SiteSpec.access_points must contain at least one usable access point.")
	if spec.scale.is_empty():
		errors.append("SiteSpec.scale is required for town layout skeleton generation.")
	if spec.generation_params.is_empty():
		errors.append("SiteSpec.generation_params is required for town layout skeleton generation.")

	if not spec.access_points.is_empty():
		var access_point := _resolve_primary_access_point(spec)
		if access_point.is_empty():
			errors.append("SiteSpec.access_points must include a road_entry access point, or explicitly allow access_point fallback.")
		else:
			var direction := String(access_point.get("direction", access_point.get("side", ""))).to_lower()
			if not _is_supported_side(direction):
				errors.append("Primary access point direction must be north, south, east, or west.")
	return errors


func _resolve_primary_access_point(spec: SiteSpec) -> Dictionary:
	for access_point in spec.access_points:
		if not (access_point is Dictionary):
			continue
		var access_type := String(access_point.get("type", access_point.get("access_type", ""))).to_lower()
		if access_type == ACCESS_TYPE_ROAD_ENTRY:
			return access_point

	if bool(spec.generation_params.get("allow_access_point_fallback", false)):
		for access_point in spec.access_points:
			if access_point is Dictionary:
				push_warning("TownLayoutSkeletonBuilder: Falling back to first access point for '" + _get_spec_id(spec) + "'.")
				return access_point

	return {}


func _resolve_town_dimensions(spec: SiteSpec, rng: RandomNumberGenerator) -> Rect2:
	var size_tier := _get_size_tier(spec.scale)
	var defaults: Dictionary = DEFAULTS.get(size_tier, DEFAULTS["small"])
	var base_size: Vector2 = defaults.get("size", DEFAULTS["small"]["size"])
	var size_jitter := Vector2(
		rng.randf_range(-70.0, 90.0),
		rng.randf_range(-50.0, 70.0)
	)
	var size := Vector2(
		round(base_size.x + size_jitter.x),
		round(base_size.y + size_jitter.y)
	)
	return Rect2(-size.x / 2.0, -size.y / 2.0, size.x, size.y)


func _build_gate(spec: SiteSpec, bounds: Rect2, entry_side: String) -> Dictionary:
	var center := _get_side_center(bounds, entry_side)
	var inward := _get_inward_vector(entry_side)
	var tangent := _get_side_tangent(entry_side)
	var max_offset := _get_gate_offset_limit(bounds, entry_side)
	var rng := _make_rng(spec.seed, "gate")
	var offset:Variant = round(rng.randf_range(-max_offset, max_offset))
	center += tangent * offset

	return {
		"id": "gate_primary",
		"type": "primary",
		"side": entry_side,
		"center": center,
		"width": GATE_WIDTH,
		"inward": inward,
		"rect": _make_centered_rect(center, _get_gate_rect_size(entry_side))
	}


func _build_wall(bounds: Rect2, gate: Dictionary) -> Dictionary:
	return {
		"enabled": true,
		"type": "rectangular_ring",
		"thickness": WALL_THICKNESS,
		"gate_ids": PackedStringArray([String(gate.get("id", ""))]),
		"outer_rect": bounds.grow(WALL_THICKNESS),
		"inner_rect": bounds.grow(-WALL_THICKNESS)
	}


func _build_main_road(bounds: Rect2, gate: Dictionary, square: Dictionary) -> Dictionary:
	var gate_center: Vector2 = gate.get("center", Vector2.ZERO)
	var square_rect: Rect2 = square.get("rect", Rect2())
	var side := String(gate.get("side", SIDE_SOUTH))
	var endpoint := _get_square_connection_point(square_rect, side)
	var start := gate_center
	var end := endpoint
	var road_rect := _make_axis_road_rect(start, end, MAIN_ROAD_WIDTH)
	road_rect = _clip_rect_to_bounds(road_rect, bounds.grow(-WALL_THICKNESS))
	return {
		"id": "road_main",
		"type": "main",
		"from_gate_id": String(gate.get("id", "")),
		"centerline": PackedVector2Array([start, end]),
		"width": MAIN_ROAD_WIDTH,
		"rect": road_rect,
		"axis": _get_axis_from_side(side),
		"district_tags": PackedStringArray(["main_road", "gate", "market"])
	}


func _build_market_square(spec: SiteSpec, bounds: Rect2, gate: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var size_tier := _get_size_tier(spec.scale)
	var defaults: Dictionary = DEFAULTS.get(size_tier, DEFAULTS["small"])
	var base_square: Vector2 = defaults.get("square", DEFAULTS["small"]["square"])
	var square_size := Vector2(
		round(base_square.x + rng.randf_range(-34.0, 46.0)),
		round(base_square.y + rng.randf_range(-24.0, 34.0))
	)
	var side := String(gate.get("side", SIDE_SOUTH))
	var inward: Vector2 = _get_inward_vector(side)
	var tangent: Vector2 = _get_side_tangent(side)
	var gate_center: Vector2 = gate.get("center", Vector2.ZERO)
	var inward_distance: float = _get_inward_depth(bounds, side) * rng.randf_range(0.46, 0.55)
	var tangent_offset_limit: float = _get_inward_span(bounds, side) * 0.08
	var tangent_offset: float = round(rng.randf_range(-tangent_offset_limit, tangent_offset_limit))
	var center: Vector2 = gate_center + inward * inward_distance + tangent * tangent_offset
	var inner: Rect2 = bounds.grow(-(WALL_THICKNESS + INNER_MARGIN + 8.0))
	center = _clamp_square_center(center, square_size, inner)
	return {
		"id": "square_market",
		"type": "market",
		"rect": _make_centered_rect(center, square_size),
		"district_tags": PackedStringArray(["market", "civic", "central"])
	}


func _build_side_lanes(spec: SiteSpec, bounds: Rect2, square: Dictionary, gate: Dictionary, rng: RandomNumberGenerator) -> Array:
	var lanes: Array = []
	var size_tier := _get_size_tier(spec.scale)
	var defaults: Dictionary = DEFAULTS.get(size_tier, DEFAULTS["small"])
	var min_count := int(defaults.get("lane_count_min", 2))
	var max_count := int(defaults.get("lane_count_max", 3))
	var lane_count := rng.randi_range(min_count, max_count)
	var square_rect: Rect2 = square.get("rect", Rect2())
	var gate_side := String(gate.get("side", SIDE_SOUTH))
	var branch_sides := _get_lane_branch_sides(gate_side, lane_count)
	var inner := bounds.grow(-(WALL_THICKNESS + INNER_MARGIN))

	for i in range(branch_sides.size()):
		var side := String(branch_sides[i])
		var start := _get_square_connection_point(square_rect, side)
		var outward := _get_outward_vector_from_square_side(side)
		var length_limit := _get_lane_length_limit(start, outward, inner)
		var length := clampf(length_limit * rng.randf_range(0.52, 0.78), 220.0, length_limit)
		var end := start + outward * length
		var road_rect := _make_axis_road_rect(start, end, SIDE_LANE_WIDTH)
		road_rect = _clip_rect_to_bounds(road_rect, inner)
		lanes.append({
			"id": "lane_%02d" % [i + 1],
			"type": "side_lane",
			"connects_to": String(square.get("id", "")),
			"branch_side": side,
			"centerline": PackedVector2Array([start, end]),
			"width": SIDE_LANE_WIDTH,
			"rect": road_rect,
			"axis": _get_axis_from_vector(outward),
			"district_tags": PackedStringArray(["residential", "edge"])
		})

	return lanes


func _build_reserved_open_areas(gate: Dictionary, square: Dictionary, bounds: Rect2) -> Array:
	var side := String(gate.get("side", SIDE_SOUTH))
	var gate_center: Vector2 = gate.get("center", Vector2.ZERO)
	var inward := _get_inward_vector(side)
	var center := gate_center + inward * (GATE_CLEARANCE_DEPTH / 2.0)
	var size := _get_gate_clearance_size(side)
	var gate_rect := _clip_rect_to_bounds(_make_centered_rect(center, size), bounds.grow(-WALL_THICKNESS))
	return [
		{
			"id": "reserve_gate_clearance",
			"type": "gate_clearance",
			"rect": gate_rect,
			"tags": PackedStringArray(["gate", "open"])
		},
		{
			"id": "reserve_market_square",
			"type": "market_square",
			"rect": square.get("rect", Rect2()),
			"tags": PackedStringArray(["market", "open", "civic"])
		}
	]


func _build_buildable_bands(
	spec: SiteSpec,
	bounds: Rect2,
	roads: Array,
	square: Dictionary,
	reserved_open_areas: Array
) -> Array:
	var bands: Array = []
	var inner := bounds.grow(-(WALL_THICKNESS + INNER_MARGIN))
	var size_tier := _get_size_tier(spec.scale)
	var defaults: Dictionary = DEFAULTS.get(size_tier, DEFAULTS["small"])
	var band_depth := float(defaults.get("band_depth", DEFAULTS["small"]["band_depth"]))
	var band_index := 1

	for road in roads:
		var road_rect: Rect2 = road.get("rect", Rect2())
		var road_axis := String(road.get("axis", "vertical"))
		var sides := _get_band_sides_for_axis(road_axis)
		for side in sides:
			var rect := _make_road_band_rect(road_rect, String(side), band_depth)
			rect = _clip_rect_to_bounds(rect, inner)
			if _is_usable_band(rect, reserved_open_areas):
				bands.append(_make_band("band_%02d" % band_index, "road", String(road.get("id", "")), String(side), rect, road.get("district_tags", PackedStringArray())))
				band_index += 1

	var square_rect: Rect2 = square.get("rect", Rect2())
	for side in [SIDE_NORTH, SIDE_SOUTH, SIDE_EAST, SIDE_WEST]:
		var rect := _make_square_band_rect(square_rect, side, band_depth)
		rect = _clip_rect_to_bounds(rect, inner)
		if _is_usable_band(rect, reserved_open_areas):
			bands.append(_make_band("band_%02d" % band_index, "square", String(square.get("id", "")), side, rect, PackedStringArray(["market", "civic", "central"])))
			band_index += 1

	return bands


func _build_district_hints(bounds: Rect2, gate: Dictionary, square: Dictionary, roads: Array) -> Array:
	var square_rect: Rect2 = square.get("rect", Rect2())
	var gate_rect: Rect2 = gate.get("rect", Rect2())
	var side := String(gate.get("side", SIDE_SOUTH))
	var gate_hint_center := gate_rect.get_center() + _get_inward_vector(side) * 150.0
	var gate_hint := _make_centered_rect(gate_hint_center, _get_gate_clearance_size(side) + Vector2(120, 120))
	var market_hint := square_rect.grow(170.0)
	var inner := bounds.grow(-(WALL_THICKNESS + INNER_MARGIN))
	var residential_a := Rect2(inner.position, Vector2(inner.size.x * 0.32, inner.size.y))
	var residential_b := Rect2(Vector2(inner.end.x - inner.size.x * 0.32, inner.position.y), Vector2(inner.size.x * 0.32, inner.size.y))
	var work_edge := _make_edge_hint_rect(inner, side)
	var main_road_rect := Rect2()
	for road in roads:
		if String(road.get("type", "")) == "main":
			main_road_rect = road.get("rect", Rect2()).grow(80.0)

	return [
		{
			"id": "district_gate",
			"rect": _clip_rect_to_bounds(gate_hint, inner),
			"tags": PackedStringArray(["gate", "main_road"])
		},
		{
			"id": "district_market",
			"rect": _clip_rect_to_bounds(market_hint, inner),
			"tags": PackedStringArray(["market", "civic", "central"])
		},
		{
			"id": "district_residential_west",
			"rect": residential_a,
			"tags": PackedStringArray(["residential", "quiet"])
		},
		{
			"id": "district_residential_east",
			"rect": residential_b,
			"tags": PackedStringArray(["residential", "quiet"])
		},
		{
			"id": "district_work_edge",
			"rect": work_edge,
			"tags": PackedStringArray(["work", "edge"])
		},
		{
			"id": "district_main_road",
			"rect": _clip_rect_to_bounds(main_road_rect, inner),
			"tags": PackedStringArray(["main_road", "gate", "market"])
		}
	]


func _validate_skeleton(skeleton: TownLayoutSkeleton) -> PackedStringArray:
	var errors := PackedStringArray()
	if skeleton.town_bounds.size.x <= 0.0 or skeleton.town_bounds.size.y <= 0.0:
		errors.append("TownLayoutSkeleton.town_bounds must be populated.")
	if skeleton.gates.size() != 1:
		errors.append("TownLayoutSkeleton must contain exactly one gate for walled_market_town v1.")
	if skeleton.roads.is_empty():
		errors.append("TownLayoutSkeleton must contain at least one road.")
	if skeleton.squares.is_empty():
		errors.append("TownLayoutSkeleton must contain at least one square.")
	if skeleton.reserved_open_areas.is_empty():
		errors.append("TownLayoutSkeleton must contain reserved open areas.")
	if skeleton.buildable_bands.is_empty():
		errors.append("TownLayoutSkeleton must contain buildable bands.")

	var gate_ids := {}
	for gate in skeleton.gates:
		if gate is Dictionary:
			gate_ids[String(gate.get("id", ""))] = true
	var wall_gate_ids: PackedStringArray = skeleton.wall.get("gate_ids", PackedStringArray())
	for gate_id in wall_gate_ids:
		if not gate_ids.has(gate_id):
			errors.append("Wall gate id '" + gate_id + "' does not resolve to a gate.")

	var source_ids := {}
	for road in skeleton.roads:
		if road is Dictionary:
			source_ids[String(road.get("id", ""))] = true
			var road_rect: Rect2 = road.get("rect", Rect2())
			if not _rect_is_inside(road_rect, skeleton.town_bounds.grow(WALL_THICKNESS + 1.0)):
				errors.append("Road '" + String(road.get("id", "")) + "' is outside town bounds.")
	for square in skeleton.squares:
		if square is Dictionary:
			source_ids[String(square.get("id", ""))] = true
			var square_rect: Rect2 = square.get("rect", Rect2())
			if not _rect_is_inside(square_rect, skeleton.town_bounds):
				errors.append("Square '" + String(square.get("id", "")) + "' is outside town bounds.")

	for band in skeleton.buildable_bands:
		if not (band is Dictionary):
			continue
		var source_id := String(band.get("source_id", ""))
		if not source_ids.has(source_id):
			errors.append("Buildable band '" + String(band.get("id", "")) + "' references missing source '" + source_id + "'.")
		var band_rect: Rect2 = band.get("rect", Rect2())
		if band_rect.size.x < MIN_BAND_EDGE or band_rect.size.y < MIN_BAND_EDGE:
			errors.append("Buildable band '" + String(band.get("id", "")) + "' is below minimum useful size.")

	for hint in skeleton.district_hints:
		if not (hint is Dictionary):
			continue
		var hint_rect: Rect2 = hint.get("rect", Rect2())
		if not _rect_is_inside(hint_rect, skeleton.town_bounds):
			errors.append("District hint '" + String(hint.get("id", "")) + "' extends outside town bounds.")

	return errors


func _make_band(id: String, source_type: String, source_id: String, side: String, rect: Rect2, tags) -> Dictionary:
	return {
		"id": id,
		"source_type": source_type,
		"source_id": source_id,
		"side": side,
		"rect": rect,
		"district_tags": tags
	}


func _get_spec_id(spec: SiteSpec) -> String:
	if spec.id != "":
		return spec.id
	return spec.site_id


func _get_size_tier(scale: Dictionary) -> String:
	var size_tier := String(scale.get("size_tier", scale.get("tier", ""))).to_lower()
	if DEFAULTS.has(size_tier):
		return size_tier
	var population := int(scale.get("population", 0))
	if population > 350:
		return "medium"
	if population > 0 and population < 90:
		return "tiny"
	return "small"


func _make_rng(seed_value: int, phase: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var derived := int(hash(str(seed_value) + ":" + phase))
	if derived < 0:
		derived = -derived
	if derived == 0:
		derived = 1
	rng.seed = derived
	return rng


func _is_supported_side(side: String) -> bool:
	return side == SIDE_NORTH or side == SIDE_SOUTH or side == SIDE_EAST or side == SIDE_WEST


func _get_side_center(bounds: Rect2, side: String) -> Vector2:
	if side == SIDE_NORTH:
		return Vector2(bounds.get_center().x, bounds.position.y)
	if side == SIDE_SOUTH:
		return Vector2(bounds.get_center().x, bounds.end.y)
	if side == SIDE_EAST:
		return Vector2(bounds.end.x, bounds.get_center().y)
	return Vector2(bounds.position.x, bounds.get_center().y)


func _get_inward_vector(side: String) -> Vector2:
	if side == SIDE_NORTH:
		return Vector2(0, 1)
	if side == SIDE_SOUTH:
		return Vector2(0, -1)
	if side == SIDE_EAST:
		return Vector2(-1, 0)
	return Vector2(1, 0)


func _get_outward_vector_from_square_side(side: String) -> Vector2:
	if side == SIDE_NORTH:
		return Vector2(0, -1)
	if side == SIDE_SOUTH:
		return Vector2(0, 1)
	if side == SIDE_EAST:
		return Vector2(1, 0)
	return Vector2(-1, 0)


func _get_side_tangent(side: String) -> Vector2:
	if side == SIDE_NORTH or side == SIDE_SOUTH:
		return Vector2(1, 0)
	return Vector2(0, 1)


func _get_gate_offset_limit(bounds: Rect2, side: String) -> float:
	if side == SIDE_NORTH or side == SIDE_SOUTH:
		return max(0.0, bounds.size.x * 0.10)
	return max(0.0, bounds.size.y * 0.10)


func _get_gate_rect_size(side: String) -> Vector2:
	if side == SIDE_NORTH or side == SIDE_SOUTH:
		return Vector2(GATE_WIDTH, WALL_THICKNESS)
	return Vector2(WALL_THICKNESS, GATE_WIDTH)


func _get_gate_clearance_size(side: String) -> Vector2:
	if side == SIDE_NORTH or side == SIDE_SOUTH:
		return Vector2(GATE_WIDTH + 170.0, GATE_CLEARANCE_DEPTH)
	return Vector2(GATE_CLEARANCE_DEPTH, GATE_WIDTH + 170.0)


func _get_axis_from_side(side: String) -> String:
	if side == SIDE_NORTH or side == SIDE_SOUTH:
		return "vertical"
	return "horizontal"


func _get_axis_from_vector(direction: Vector2) -> String:
	if abs(direction.x) > abs(direction.y):
		return "horizontal"
	return "vertical"


func _get_inward_depth(bounds: Rect2, side: String) -> float:
	if side == SIDE_NORTH or side == SIDE_SOUTH:
		return bounds.size.y
	return bounds.size.x


func _get_inward_span(bounds: Rect2, side: String) -> float:
	if side == SIDE_NORTH or side == SIDE_SOUTH:
		return bounds.size.x
	return bounds.size.y


func _clamp_square_center(center: Vector2, square_size: Vector2, inner: Rect2) -> Vector2:
	var half := square_size / 2.0
	return Vector2(
		clampf(center.x, inner.position.x + half.x, inner.end.x - half.x),
		clampf(center.y, inner.position.y + half.y, inner.end.y - half.y)
	)


func _get_square_connection_point(square_rect: Rect2, side: String) -> Vector2:
	if side == SIDE_NORTH:
		return Vector2(square_rect.get_center().x, square_rect.position.y)
	if side == SIDE_SOUTH:
		return Vector2(square_rect.get_center().x, square_rect.end.y)
	if side == SIDE_EAST:
		return Vector2(square_rect.end.x, square_rect.get_center().y)
	return Vector2(square_rect.position.x, square_rect.get_center().y)


func _get_lane_branch_sides(gate_side: String, lane_count: int) -> Array:
	var sides: Array = []
	if gate_side == SIDE_NORTH or gate_side == SIDE_SOUTH:
		sides.append(SIDE_WEST)
		sides.append(SIDE_EAST)
		if lane_count >= 3:
			sides.append(SIDE_NORTH)
		if lane_count >= 4:
			sides.append(SIDE_SOUTH)
	else:
		sides.append(SIDE_NORTH)
		sides.append(SIDE_SOUTH)
		if lane_count >= 3:
			sides.append(SIDE_WEST)
		if lane_count >= 4:
			sides.append(SIDE_EAST)
	return sides


func _get_lane_length_limit(start: Vector2, direction: Vector2, inner: Rect2) -> float:
	if direction.x > 0.0:
		return max(220.0, inner.end.x - start.x)
	if direction.x < 0.0:
		return max(220.0, start.x - inner.position.x)
	if direction.y > 0.0:
		return max(220.0, inner.end.y - start.y)
	return max(220.0, start.y - inner.position.y)


func _get_band_sides_for_axis(axis: String) -> Array:
	if axis == "vertical":
		return [SIDE_WEST, SIDE_EAST]
	return [SIDE_NORTH, SIDE_SOUTH]


func _make_road_band_rect(road_rect: Rect2, side: String, depth: float) -> Rect2:
	if side == SIDE_WEST:
		return Rect2(road_rect.position.x - depth, road_rect.position.y, depth, road_rect.size.y)
	if side == SIDE_EAST:
		return Rect2(road_rect.end.x, road_rect.position.y, depth, road_rect.size.y)
	if side == SIDE_NORTH:
		return Rect2(road_rect.position.x, road_rect.position.y - depth, road_rect.size.x, depth)
	return Rect2(road_rect.position.x, road_rect.end.y, road_rect.size.x, depth)


func _make_square_band_rect(square_rect: Rect2, side: String, depth: float) -> Rect2:
	if side == SIDE_WEST:
		return Rect2(square_rect.position.x - depth, square_rect.position.y, depth, square_rect.size.y)
	if side == SIDE_EAST:
		return Rect2(square_rect.end.x, square_rect.position.y, depth, square_rect.size.y)
	if side == SIDE_NORTH:
		return Rect2(square_rect.position.x, square_rect.position.y - depth, square_rect.size.x, depth)
	return Rect2(square_rect.position.x, square_rect.end.y, square_rect.size.x, depth)


func _is_usable_band(rect: Rect2, reserved_open_areas: Array) -> bool:
	if rect.size.x < MIN_BAND_EDGE or rect.size.y < MIN_BAND_EDGE:
		return false
	for area in reserved_open_areas:
		if not (area is Dictionary):
			continue
		var reserve_rect: Rect2 = area.get("rect", Rect2())
		if rect.intersects(reserve_rect):
			return false
	return true


func _make_edge_hint_rect(inner: Rect2, gate_side: String) -> Rect2:
	var depth := 260.0
	if gate_side == SIDE_NORTH:
		return Rect2(inner.position.x, inner.end.y - depth, inner.size.x, depth)
	if gate_side == SIDE_SOUTH:
		return Rect2(inner.position.x, inner.position.y, inner.size.x, depth)
	if gate_side == SIDE_EAST:
		return Rect2(inner.position.x, inner.position.y, depth, inner.size.y)
	return Rect2(inner.end.x - depth, inner.position.y, depth, inner.size.y)


func _make_centered_rect(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - (size / 2.0), size)


func _make_axis_road_rect(start: Vector2, end: Vector2, width: float) -> Rect2:
	if abs(start.x - end.x) < abs(start.y - end.y):
		var top:Variant = min(start.y, end.y)
		var bottom:Variant = max(start.y, end.y)
		return Rect2(start.x - width / 2.0, top, width, bottom - top)
	var left: Variant= min(start.x, end.x)
	var right:Variant = max(start.x, end.x)
	return Rect2(left, start.y - width / 2.0, right - left, width)


func _clip_rect_to_bounds(rect: Rect2, bounds: Rect2) -> Rect2:
	var left:Variant = max(rect.position.x, bounds.position.x)
	var top:Variant = max(rect.position.y, bounds.position.y)
	var right:Variant = min(rect.end.x, bounds.end.x)
	var bottom:Variant = min(rect.end.y, bounds.end.y)
	if right <= left or bottom <= top:
		return Rect2()
	return Rect2(left, top, right - left, bottom - top)


func _rect_is_inside(rect: Rect2, bounds: Rect2) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	if rect.position.x < bounds.position.x - 0.01:
		return false
	if rect.position.y < bounds.position.y - 0.01:
		return false
	if rect.end.x > bounds.end.x + 0.01:
		return false
	if rect.end.y > bounds.end.y + 0.01:
		return false
	return true
