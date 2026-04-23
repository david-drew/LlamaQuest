class_name WildernessSiteGenerator
extends RefCounted

const SUBTYPE_FOREST_CLEARING := "forest_clearing"
const SUBTYPE_ROADSIDE_GLADE := "roadside_glade"
const SUBTYPE_LAKESHORE_SITE := "lakeshore_site"
const GENERATOR_ID := "wilderness_site_generator_v1"

const SIDE_NORTH := "north"
const SIDE_SOUTH := "south"
const SIDE_EAST := "east"
const SIDE_WEST := "west"

const TIER_SIZES := {
	"small": Vector2(2000, 1300),
	"medium": Vector2(2400, 1550)
}


func build_from_site_spec(spec: SiteSpec) -> WildernessSiteLayout:
	var layout: WildernessSiteLayout = WildernessSiteLayout.new()
	var input_errors: PackedStringArray = _validate_spec(spec)
	if spec != null:
		layout.id = _get_site_id(spec) + "_wilderness_layout"
		layout.version = spec.version
	if not input_errors.is_empty():
		layout.validation_errors = input_errors
		return layout

	var rng: RandomNumberGenerator = _make_rng(spec.seed, "wilderness_layout")
	var subtype: String = _resolve_subtype(spec)
	var bounds: Rect2 = _resolve_bounds(spec)
	var entry_side: String = _resolve_entry_side(spec)
	var access_anchor_id: String = _resolve_entry_anchor_alias(spec)
	var poi_type: String = _resolve_poi_type(spec, subtype, rng)
	var entry_anchor: Dictionary = _make_anchor("main_entry", "entry", bounds, entry_side, 145.0)
	var exit_anchor: Dictionary = _make_anchor("main_exit", "exit", bounds, entry_side, 72.0)
	var open_regions: Array = _build_open_regions(bounds, subtype, entry_side, rng)
	var poi_position: Vector2 = _pick_poi_position(open_regions, rng)

	layout.site_bounds = bounds
	layout.entry_anchors = [
		entry_anchor,
		_alias_anchor(entry_anchor, "default_entry"),
		_alias_anchor(entry_anchor, entry_side + "_entry")
	]
	if access_anchor_id != "":
		layout.entry_anchors.append(_alias_anchor(entry_anchor, access_anchor_id))
	layout.exit_anchors = [
		exit_anchor,
		_alias_anchor(exit_anchor, "default_exit"),
		_alias_anchor(exit_anchor, entry_side + "_exit")
	]
	layout.open_regions = open_regions
	layout.points_of_interest = [
		{
			"id": "poi_primary",
			"type": poi_type,
			"position": poi_position,
			"radius": 46.0,
			"tags": _poi_tags(poi_type)
		}
	]
	layout.paths = _build_paths(bounds, entry_anchor, poi_position, subtype, spec, rng)
	layout.blocker_regions = _build_blockers(bounds, open_regions, entry_side, subtype, spec, rng)
	layout.debug_notes = _make_debug_notes(spec, subtype, entry_side, poi_type, layout)
	layout.validation_errors = layout.validate()
	print("[WildernessSiteGenerator] site=%s subtype=%s seed=%s entry=%s poi=%s blockers=%d paths=%d" % [
		_get_site_id(spec),
		subtype,
		str(spec.seed),
		entry_side,
		poi_type,
		layout.blocker_regions.size(),
		layout.paths.size()
	])
	return layout


func _validate_spec(spec: SiteSpec) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if spec == null:
		errors.append("SiteSpec is required for wilderness-site generation.")
		return errors
	if spec.site_type != "wilderness_site":
		errors.append("SiteSpec.site_type must be 'wilderness_site'.")
	var subtype: String = _resolve_subtype(spec)
	if not _is_supported_subtype(subtype):
		errors.append("Unsupported wilderness_site subtype '" + subtype + "'.")
	if spec.generator_id != "" and spec.generator_id != GENERATOR_ID and spec.generator_id != "wilderness_site":
		errors.append("Unsupported wilderness_site generator_id '" + spec.generator_id + "'.")
	if spec.seed == 0:
		errors.append("SiteSpec.seed must be nonzero for wilderness-site generation.")
	if spec.access_points.is_empty():
		errors.append("Wilderness SiteSpec requires at least one access point.")
	if spec.biome == "" and spec.placement_context.is_empty():
		errors.append("Wilderness SiteSpec requires biome or placement_context.")
	if not spec.access_points.is_empty():
		var access: Dictionary = _resolve_primary_access_point(spec)
		if access.is_empty():
			errors.append("Wilderness SiteSpec requires a usable trail_entry, road_entry, or shore_entry access point.")
		else:
			var direction: String = String(access.get("direction", "")).to_lower()
			if not _is_supported_side(direction):
				errors.append("Wilderness access point direction must be north, south, east, or west.")
	return errors


func _resolve_bounds(spec: SiteSpec) -> Rect2:
	var tier: String = String(spec.generation_params.get("site_radius_tier", spec.scale.get("size_tier", "small"))).to_lower()
	var size: Vector2 = TIER_SIZES.get(tier, TIER_SIZES["small"])
	return Rect2(-size.x / 2.0, -size.y / 2.0, size.x, size.y)


func _build_open_regions(bounds: Rect2, subtype: String, entry_side: String, rng: RandomNumberGenerator) -> Array:
	var regions: Array = []
	var center_offset: Vector2 = _get_inward_vector(entry_side) * rng.randf_range(30.0, 110.0)
	if subtype == SUBTYPE_ROADSIDE_GLADE:
		center_offset += _get_inward_vector(entry_side) * 120.0
	elif subtype == SUBTYPE_LAKESHORE_SITE:
		center_offset -= _get_inward_vector(entry_side) * 60.0
	regions.append({
		"id": "open_primary",
		"type": "clearing",
		"rect": _make_centered_rect(bounds.get_center() + center_offset, Vector2(bounds.size.x * 0.46, bounds.size.y * 0.42)),
		"tags": PackedStringArray(["walkable", "clearing"])
	})
	if subtype == SUBTYPE_FOREST_CLEARING:
		var tangent: Vector2 = _get_side_tangent(entry_side)
		var side_center: Vector2 = bounds.get_center() + tangent * rng.randf_range(-bounds.size.x * 0.18, bounds.size.x * 0.18)
		regions.append({
			"id": "open_side_pocket",
			"type": "pocket",
			"rect": _make_centered_rect(side_center + _get_inward_vector(entry_side) * 230.0, Vector2(300, 210)),
			"tags": PackedStringArray(["walkable", "pocket"])
		})
	return regions


func _build_paths(
	bounds: Rect2,
	entry_anchor: Dictionary,
	poi_position: Vector2,
	subtype: String,
	spec: SiteSpec,
	rng: RandomNumberGenerator
) -> Array:
	var paths: Array = []
	var entry_pos: Vector2 = entry_anchor.get("position", Vector2.ZERO)
	var bend: Vector2 = entry_pos.lerp(poi_position, 0.46)
	bend += _get_side_tangent(String(entry_anchor.get("facing", SIDE_NORTH))) * rng.randf_range(-90.0, 90.0)
	paths.append({
		"id": "path_entry_to_poi",
		"type": "trail",
		"width": _path_width_for_subtype(subtype),
		"points": PackedVector2Array([entry_pos, bend, poi_position]),
		"tags": PackedStringArray(["walkable", "primary"])
	})
	if bool(spec.generation_params.get("has_side_path", subtype == SUBTYPE_FOREST_CLEARING)):
		var side_target: Vector2 = bounds.get_center() + _get_side_tangent(String(entry_anchor.get("facing", SIDE_NORTH))) * 330.0
		paths.append({
			"id": "path_side_pocket",
			"type": "side_trail",
			"width": 42.0,
			"points": PackedVector2Array([poi_position, side_target]),
			"tags": PackedStringArray(["walkable", "secondary"])
		})
	return paths


func _build_blockers(
	bounds: Rect2,
	open_regions: Array,
	entry_side: String,
	subtype: String,
	spec: SiteSpec,
	rng: RandomNumberGenerator
) -> Array:
	var blockers: Array = []
	var density: String = String(spec.generation_params.get("blocker_density", "medium")).to_lower()
	var cluster_count: int = 12
	if density == "low":
		cluster_count = 8
	elif density == "high":
		cluster_count = 17

	_add_edge_blockers(blockers, bounds, entry_side, subtype)
	for i in range(cluster_count):
		var pos: Vector2 = _sample_blocker_position(bounds, open_regions, entry_side, rng)
		var size: Vector2 = Vector2(rng.randf_range(75.0, 170.0), rng.randf_range(55.0, 145.0))
		blockers.append({
			"id": "blocker_%02d" % i,
			"type": _blocker_type_for_subtype(subtype, rng),
			"rect": _make_centered_rect(pos, size),
			"tags": PackedStringArray(["blocked"])
		})
	return blockers


func _add_edge_blockers(blockers: Array, bounds: Rect2, entry_side: String, subtype: String) -> void:
	var edge_depth: float = 105.0
	if subtype == SUBTYPE_ROADSIDE_GLADE:
		edge_depth = 86.0
	var edges: Dictionary = {
		SIDE_NORTH: Rect2(bounds.position, Vector2(bounds.size.x, edge_depth)),
		SIDE_SOUTH: Rect2(Vector2(bounds.position.x, bounds.end.y - edge_depth), Vector2(bounds.size.x, edge_depth)),
		SIDE_WEST: Rect2(bounds.position, Vector2(edge_depth, bounds.size.y)),
		SIDE_EAST: Rect2(Vector2(bounds.end.x - edge_depth, bounds.position.y), Vector2(edge_depth, bounds.size.y))
	}
	for side in edges.keys():
		if String(side) == entry_side:
			continue
		blockers.append({
			"id": "edge_blocker_" + String(side),
			"type": "tree_mass",
			"rect": edges[side],
			"tags": PackedStringArray(["blocked", "edge"])
		})
	if subtype == SUBTYPE_LAKESHORE_SITE:
		blockers.append({
			"id": "water_edge",
			"type": "water",
			"rect": edges[entry_side],
			"tags": PackedStringArray(["blocked", "water"])
		})


func _sample_blocker_position(bounds: Rect2, open_regions: Array, entry_side: String, rng: RandomNumberGenerator) -> Vector2:
	for _attempt in range(24):
		var pos: Vector2 = Vector2(
			rng.randf_range(bounds.position.x + 180.0, bounds.end.x - 180.0),
			rng.randf_range(bounds.position.y + 140.0, bounds.end.y - 140.0)
		)
		if _is_near_entry(pos, bounds, entry_side):
			continue
		if not _point_in_open_regions(pos, open_regions):
			return pos
	return bounds.get_center()


func _pick_poi_position(open_regions: Array, rng: RandomNumberGenerator) -> Vector2:
	if open_regions.is_empty():
		return Vector2.ZERO
	var region: Dictionary = open_regions[0]
	var rect: Rect2 = region.get("rect", Rect2())
	return Vector2(
		rng.randf_range(rect.position.x + rect.size.x * 0.18, rect.end.x - rect.size.x * 0.18),
		rng.randf_range(rect.position.y + rect.size.y * 0.18, rect.end.y - rect.size.y * 0.18)
	)


func _make_anchor(anchor_id: String, kind: String, bounds: Rect2, side: String, inset: float) -> Dictionary:
	var position: Vector2 = _side_center(bounds, side) + _get_inward_vector(side) * inset
	return {
		"id": anchor_id,
		"kind": kind,
		"position": position,
		"facing": side,
		"site_link": "overland"
	}


func _alias_anchor(anchor: Dictionary, alias_id: String) -> Dictionary:
	var copy: Dictionary = anchor.duplicate(true)
	copy["id"] = alias_id
	return copy


func _make_debug_notes(
	spec: SiteSpec,
	subtype: String,
	entry_side: String,
	poi_type: String,
	layout: WildernessSiteLayout
) -> PackedStringArray:
	var notes: PackedStringArray = PackedStringArray()
	notes.append("site_id=" + _get_site_id(spec))
	notes.append("seed=" + str(spec.seed))
	notes.append("subtype=" + subtype)
	notes.append("entry_side=" + entry_side)
	notes.append("poi_type=" + poi_type)
	notes.append("open_regions=" + str(layout.open_regions.size()))
	notes.append("blockers=" + str(layout.blocker_regions.size()))
	notes.append("paths=" + str(layout.paths.size()))
	return notes


func _resolve_primary_access_point(spec: SiteSpec) -> Dictionary:
	for access_point in spec.access_points:
		if not (access_point is Dictionary):
			continue
		var kind: String = String(access_point.get("kind", access_point.get("type", ""))).to_lower()
		if kind == "trail_entry" or kind == "road_entry" or kind == "shore_entry":
			return access_point
	for access_point in spec.access_points:
		if access_point is Dictionary:
			return access_point
	return {}


func _resolve_entry_side(spec: SiteSpec) -> String:
	var access: Dictionary = _resolve_primary_access_point(spec)
	var direction: String = String(access.get("direction", SIDE_SOUTH)).to_lower()
	if _is_supported_side(direction):
		return direction
	return SIDE_SOUTH


func _resolve_entry_anchor_alias(spec: SiteSpec) -> String:
	var access: Dictionary = _resolve_primary_access_point(spec)
	if access.is_empty():
		return ""
	var access_id: String = String(access.get("id", ""))
	if access_id == "main_entry":
		return ""
	if access_id == "default_entry":
		return ""
	return access_id


func _resolve_subtype(spec: SiteSpec) -> String:
	if spec == null:
		return SUBTYPE_FOREST_CLEARING
	if spec.subtype != "":
		return spec.subtype
	return SUBTYPE_FOREST_CLEARING


func _resolve_poi_type(spec: SiteSpec, subtype: String, rng: RandomNumberGenerator) -> String:
	var requested: String = String(spec.generation_params.get("poi_type", ""))
	if requested != "":
		return requested
	var options: PackedStringArray = PackedStringArray()
	if subtype == SUBTYPE_ROADSIDE_GLADE:
		options = PackedStringArray(["camp_remains", "wagon_tracks", "trail_marker", "roadside_shrine"])
	elif subtype == SUBTYPE_LAKESHORE_SITE:
		options = PackedStringArray(["shoreline_marker", "old_fire_ring", "standing_stones"])
	else:
		options = PackedStringArray(["standing_stones", "old_fire_ring", "shrine_stump", "fallen_tree_focus"])
	return options[rng.randi_range(0, options.size() - 1)]


func _poi_tags(poi_type: String) -> PackedStringArray:
	return PackedStringArray(["poi", poi_type])


func _path_width_for_subtype(subtype: String) -> float:
	if subtype == SUBTYPE_ROADSIDE_GLADE:
		return 78.0
	if subtype == SUBTYPE_LAKESHORE_SITE:
		return 58.0
	return 52.0


func _blocker_type_for_subtype(subtype: String, rng: RandomNumberGenerator) -> String:
	if subtype == SUBTYPE_LAKESHORE_SITE and rng.randf() < 0.36:
		return "rock_cluster"
	if rng.randf() < 0.24:
		return "rock_cluster"
	return "tree_cluster"


func _point_in_open_regions(pos: Vector2, open_regions: Array) -> bool:
	for region in open_regions:
		if not (region is Dictionary):
			continue
		var rect: Rect2 = region.get("rect", Rect2())
		if rect.has_point(pos):
			return true
	return false


func _is_near_entry(pos: Vector2, bounds: Rect2, entry_side: String) -> bool:
	var entry: Vector2 = _side_center(bounds, entry_side)
	return pos.distance_to(entry) < 360.0


func _side_center(bounds: Rect2, side: String) -> Vector2:
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


func _get_side_tangent(side: String) -> Vector2:
	if side == SIDE_NORTH or side == SIDE_SOUTH:
		return Vector2(1, 0)
	return Vector2(0, 1)


func _make_centered_rect(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - size / 2.0, size)


func _is_supported_subtype(subtype: String) -> bool:
	return subtype == SUBTYPE_FOREST_CLEARING or subtype == SUBTYPE_ROADSIDE_GLADE or subtype == SUBTYPE_LAKESHORE_SITE


func _is_supported_side(side: String) -> bool:
	return side == SIDE_NORTH or side == SIDE_SOUTH or side == SIDE_EAST or side == SIDE_WEST


func _get_site_id(spec: SiteSpec) -> String:
	if spec.id != "":
		return spec.id
	return spec.site_id


func _make_rng(seed_value: int, phase: String) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var derived: int = int(hash(str(seed_value) + ":" + phase))
	if derived < 0:
		derived = -derived
	if derived == 0:
		derived = 1
	rng.seed = derived
	return rng
