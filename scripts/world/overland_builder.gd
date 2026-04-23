class_name OverlandBuilder
extends RefCounted

const MIN_SITE_SPACING := 240.0
const DUNGEON_TOWN_MIN_DISTANCE := 520.0
const WORLD_MARGIN := 120.0
const MAX_RETRIES := 24
const SITE_CANDIDATE_COUNT := 96
const SITE_MARKER_RADIUS := 48.0
const HUGE_DISTANCE := 1000000000.0

const SITE_RULES := {
	"town": {
		"display_name": "Oakhaven",
		"routing_id": "town",
		"hard_rules": ["within_bounds", "not_in_lake", "site_spacing", "near_road"],
		"soft_preferences": ["prefer_near_road", "prefer_open_land"],
		"default_min_spacing": 220.0,
		"max_road_distance": 150.0,
		"ideal_road_distance": 20.0,
		"min_distance_by_type": {
			"dungeon": DUNGEON_TOWN_MIN_DISTANCE,
			"wilderness_site": MIN_SITE_SPACING
		}
	},
	"dungeon": {
		"display_name": "Fallen Watch",
		"routing_id": "dungeon",
		"hard_rules": ["within_bounds", "not_in_lake", "site_spacing"],
		"soft_preferences": ["prefer_remote_from_town", "prefer_near_forest", "prefer_away_from_road"],
		"default_min_spacing": MIN_SITE_SPACING,
		"min_distance_by_type": {
			"town": DUNGEON_TOWN_MIN_DISTANCE,
			"wilderness_site": MIN_SITE_SPACING
		}
	},
	"wilderness_site": {
		"display_name": "Amber Meadow",
		"routing_id": "wilderness_site",
		"hard_rules": ["within_bounds", "not_in_lake", "site_spacing", "outdoor_context"],
		"soft_preferences": ["prefer_near_forest", "prefer_near_lake_edge", "prefer_remote_from_town"],
		"default_min_spacing": MIN_SITE_SPACING,
		"outdoor_context_distance": 180.0,
		"min_distance_by_type": {
			"town": 300.0,
			"dungeon": MIN_SITE_SPACING
		}
	}
}

static func build_world(seed: int, extents: Vector2) -> WorldSpec:
	assert(seed != 0, "WorldSpec.world_seed must be assigned before generation")
	var spec := WorldSpec.new(seed, extents)
	assert(spec.id != "", "WorldSpec.id must be assigned before generation")
	assert(spec.world_seed != 0, "WorldSpec.world_seed must be assigned before generation")
	var sub_seeds := _derive_sub_seeds(seed)
	spec.sub_seeds = sub_seeds

	var forest := _build_forest_region(sub_seeds["forest"], extents)
	var lake := _build_lake_region(sub_seeds["lake"], extents, forest)
	spec.regions.append(forest)
	spec.regions.append(lake)

	var river_network := _build_river_network(sub_seeds["river"], extents)
	var road_network := _build_road_network(sub_seeds["road"], extents)
	var regions: Array[WorldRegion] = [forest, lake]
	var networks: Array[WorldNetwork] = [river_network, road_network]

	var placed_sites: Array[SiteSpec] = []
	var town_site := _place_site_by_rules("town", "site_town_oakhaven", sub_seeds["site_town_oakhaven"], extents, regions, networks, placed_sites)
	placed_sites.append(town_site)
	var dungeon_site := _place_site_by_rules("dungeon", "site_dungeon_fallen_watch", sub_seeds["site_dungeon_fallen_watch"], extents, regions, networks, placed_sites)
	placed_sites.append(dungeon_site)
	var wilderness_site := _place_site_by_rules("wilderness_site", "site_wilderness_amber_meadow", sub_seeds["site_wilderness_amber_meadow"], extents, regions, networks, placed_sites)
	placed_sites.append(wilderness_site)
	_validate_placed_sites(extents, regions, networks, placed_sites)

	spec.networks.append(river_network)
	spec.networks.append(road_network)
	spec.sites.append(town_site)
	spec.sites.append(dungeon_site)
	spec.sites.append(wilderness_site)

	return spec

static func _derive_sub_seeds(seed: int) -> Dictionary:
	return {
		"forest": derive_child_seed(seed, "forest_01", "region"),
		"lake": derive_child_seed(seed, "lake_01", "region"),
		"river": derive_child_seed(seed, "river_01", "network"),
		"road": derive_child_seed(seed, "road_01", "network"),
		"site_town_oakhaven": derive_child_seed(seed, "site_town_oakhaven", "site"),
		"site_dungeon_fallen_watch": derive_child_seed(seed, "site_dungeon_fallen_watch", "site"),
		"site_wilderness_amber_meadow": derive_child_seed(seed, "site_wilderness_amber_meadow", "site")
	}

static func derive_child_seed(root_seed: int, stable_id: String, phase: String = "") -> int:
	var key := "%s:%s:%s" % [str(root_seed), stable_id, phase]
	var derived := int(hash(key))
	if derived < 0:
		derived = -derived
	if derived == 0:
		derived = 1
	return derived

static func _build_forest_region(sub_seed: int, extents: Vector2) -> WorldRegion:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed

	var center := Vector2(
		rng.randf_range(-extents.x * 0.30, extents.x * 0.08),
		rng.randf_range(-extents.y * 0.24, extents.y * 0.18)
	)
	var radius := Vector2(
		rng.randf_range(extents.x * 0.22, extents.x * 0.30),
		rng.randf_range(extents.y * 0.20, extents.y * 0.28)
	)
	return WorldRegion.new("forest_01", "forest", center, radius, sub_seed)

static func _build_lake_region(sub_seed: int, extents: Vector2, forest: WorldRegion) -> WorldRegion:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed

	var lake := WorldRegion.new(
		"lake_01",
		"lake",
		Vector2(extents.x * 0.20, extents.y * 0.12),
		Vector2(extents.x * 0.12, extents.y * 0.14),
		sub_seed
	)

	for _attempt in range(MAX_RETRIES):
		var candidate_center := Vector2(
			rng.randf_range(-extents.x * 0.18, extents.x * 0.34),
			rng.randf_range(-extents.y * 0.16, extents.y * 0.28)
		)
		var candidate_radius := Vector2(
			rng.randf_range(extents.x * 0.11, extents.x * 0.17),
			rng.randf_range(extents.y * 0.10, extents.y * 0.16)
		)
		var candidate := WorldRegion.new("lake_01", "lake", candidate_center, candidate_radius, sub_seed)
		if _is_region_within_bounds(candidate, extents) and _has_reasonable_region_separation(candidate, forest):
			return candidate

	return lake

static func _build_river_network(sub_seed: int, extents: Vector2) -> WorldNetwork:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed

	var start := Vector2(-extents.x * 0.48, rng.randf_range(-extents.y * 0.32, -extents.y * 0.12))
	var mid_a := Vector2(-extents.x * 0.16, rng.randf_range(-extents.y * 0.08, extents.y * 0.10))
	var mid_b := Vector2(extents.x * 0.12, rng.randf_range(-extents.y * 0.12, extents.y * 0.16))
	var end := Vector2(extents.x * 0.44, rng.randf_range(extents.y * 0.12, extents.y * 0.30))

	var points := PackedVector2Array([start, mid_a, mid_b, end])
	return WorldNetwork.new("river_01", "river", points, 16.0, sub_seed)

static func _build_road_network(sub_seed: int, extents: Vector2) -> WorldNetwork:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed

	var road_y := rng.randf_range(-extents.y * 0.08, extents.y * 0.16)
	var start := Vector2(-extents.x * 0.46, road_y + rng.randf_range(-60.0, 40.0))
	var mid_a := Vector2(-extents.x * 0.18, road_y + rng.randf_range(-50.0, 50.0))
	var mid_b := Vector2(extents.x * 0.12, road_y + rng.randf_range(-50.0, 50.0))
	var end := Vector2(extents.x * 0.44, road_y + rng.randf_range(-60.0, 60.0))
	var points := PackedVector2Array([start, mid_a, mid_b, end])

	return WorldNetwork.new("road_01", "road", points, 10.0, sub_seed)

static func _place_site_by_rules(
	site_type: String,
	site_id: String,
	sub_seed: int,
	extents: Vector2,
	regions: Array[WorldRegion],
	networks: Array[WorldNetwork],
	existing_sites: Array[SiteSpec]
) -> SiteSpec:
	var rules := _get_site_rules(site_type)
	var candidates := _generate_site_candidates(site_type, sub_seed, extents, regions, networks)
	var best_position := Vector2.ZERO
	var best_score := -HUGE_DISTANCE
	var found_position := false

	for candidate in candidates:
		if not _is_site_candidate_valid(site_type, candidate, extents, regions, networks, existing_sites):
			continue
		var score := _score_site_candidate(site_type, candidate, extents, regions, networks, existing_sites)
		if not found_position or score > best_score:
			best_position = candidate
			best_score = score
			found_position = true

	if not found_position:
		best_position = _find_fallback_site_position(site_type, extents, regions, networks, existing_sites)

	var site_spec := SiteSpec.new(
		site_id,
		site_type,
		String(rules.get("display_name", site_type)),
		best_position,
		sub_seed,
		String(rules.get("routing_id", site_type))
	)
	site_spec.placement_context = {
		"placement_rules": rules,
		"world_position": best_position
	}
	if site_type == "town":
		site_spec.subtype = "walled_market_town"
		site_spec.scale = {
			"size_tier": "small",
			"population": 180
		}
		site_spec.access_points = [
			{
				"id": "access_road_south",
				"type": "road_entry",
				"direction": "south",
				"network_type": "road"
			}
		]
		site_spec.generation_params["building_profile"] = "prototype_town"
		site_spec.generation_params["has_wall"] = true
		site_spec.generation_params["district_style"] = "market_town"
		site_spec.generation_params["special_features"] = PackedStringArray(["market_square"])
	elif site_type == "wilderness_site":
		site_spec.subtype = "forest_clearing"
		site_spec.generator_id = "wilderness_site_generator_v1"
		site_spec.routing_id = "wilderness_site"
		site_spec.tags = PackedStringArray(["outdoor", "wilderness", "enterable"])
		site_spec.access_points = [
			{
				"id": "trail_entry_south",
				"kind": "trail_entry",
				"type": "trail_entry",
				"direction": "south"
			}
		]
		site_spec.generation_params = {
			"site_radius_tier": "small",
			"blocker_density": "medium",
			"poi_type": "standing_stones",
			"has_side_path": true,
			"ground_cover": "forest_floor",
			"feature_profile": "default_forest_clearing"
		}
	print("[World] Generating site id=%s seed=%s" % [site_spec.site_id, str(site_spec.seed)])
	return site_spec

static func _generate_site_candidates(
	site_type: String,
	sub_seed: int,
	extents: Vector2,
	regions: Array[WorldRegion],
	networks: Array[WorldNetwork]
) -> Array[Vector2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed
	var candidates: Array[Vector2] = []
	var road: WorldNetwork = _get_network_by_type(networks, "road")
	var forest: WorldRegion = _get_region_by_type(regions, "forest")
	var lake: WorldRegion = _get_region_by_type(regions, "lake")

	if site_type == "town" and road != null:
		for _i in range(int(SITE_CANDIDATE_COUNT / 2)):
			var road_point := _sample_network_point(road, rng.randf())
			var offset := Vector2(0, rng.randf_range(-120.0, 120.0))
			offset = offset.rotated(rng.randf_range(-0.45, 0.45))
			candidates.append(road_point + offset)

	if site_type == "wilderness_site":
		if forest != null:
			for _i in range(int(SITE_CANDIDATE_COUNT / 3)):
				var angle := rng.randf_range(0.0, TAU)
				var dist := rng.randf_range(forest.radius.x * 0.25, forest.radius.x * 0.82)
				candidates.append(forest.center + Vector2(cos(angle), sin(angle)) * dist)
		if lake != null:
			for _i in range(int(SITE_CANDIDATE_COUNT / 4)):
				var angle := rng.randf_range(0.0, TAU)
				var radius_scale := rng.randf_range(1.08, 1.38)
				var offset := Vector2(cos(angle) * lake.radius.x * radius_scale, sin(angle) * lake.radius.y * radius_scale)
				candidates.append(lake.center + offset)

	if site_type == "dungeon" and forest != null:
		for _i in range(int(SITE_CANDIDATE_COUNT / 3)):
			var angle := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(forest.radius.x * 0.62, forest.radius.x * 1.10)
			candidates.append(forest.center + Vector2(cos(angle), sin(angle)) * dist)

	while candidates.size() < SITE_CANDIDATE_COUNT:
		candidates.append(Vector2(
			rng.randf_range(-extents.x * 0.42, extents.x * 0.42),
			rng.randf_range(-extents.y * 0.36, extents.y * 0.36)
		))

	return candidates

static func _is_site_candidate_valid(
	site_type: String,
	candidate: Vector2,
	extents: Vector2,
	regions: Array[WorldRegion],
	networks: Array[WorldNetwork],
	existing_sites: Array[SiteSpec]
) -> bool:
	var rules := _get_site_rules(site_type)
	var hard_rules = rules.get("hard_rules", [])

	for rule_name in hard_rules:
		if rule_name == "within_bounds":
			if not _is_point_within_site_bounds(candidate, extents):
				return false
		elif rule_name == "not_in_lake":
			if _is_point_in_region_type(candidate, regions, "lake"):
				return false
		elif rule_name == "site_spacing":
			if not _is_site_spacing_valid(site_type, candidate, existing_sites):
				return false
		elif rule_name == "near_road":
			var road_distance := _distance_to_network_type(candidate, networks, "road")
			if road_distance > float(rules.get("max_road_distance", HUGE_DISTANCE)):
				return false
		elif rule_name == "outdoor_context":
			if not _has_outdoor_context(site_type, candidate, regions):
				return false

	return true

static func _score_site_candidate(
	site_type: String,
	candidate: Vector2,
	extents: Vector2,
	regions: Array[WorldRegion],
	networks: Array[WorldNetwork],
	existing_sites: Array[SiteSpec]
) -> float:
	var rules := _get_site_rules(site_type)
	var preferences = rules.get("soft_preferences", [])
	var score := 0.0

	for preference in preferences:
		if preference == "prefer_near_road":
			var ideal_road_distance := float(rules.get("ideal_road_distance", 0.0))
			score += max(0.0, 180.0 - abs(_distance_to_network_type(candidate, networks, "road") - ideal_road_distance))
		elif preference == "prefer_open_land":
			score += min(_distance_to_region_edge_type(candidate, regions, "lake"), 240.0) * 0.25
		elif preference == "prefer_remote_from_town":
			score += min(_distance_to_site_type(candidate, existing_sites, "town"), 900.0) * 0.35
		elif preference == "prefer_near_forest":
			score += max(0.0, 260.0 - _distance_to_region_edge_type(candidate, regions, "forest"))
		elif preference == "prefer_near_lake_edge":
			score += max(0.0, 220.0 - _distance_to_region_edge_type(candidate, regions, "lake")) * 0.75
		elif preference == "prefer_away_from_road":
			score += min(_distance_to_network_type(candidate, networks, "road"), 420.0) * 0.20

	score += _edge_readability_score(candidate, extents)
	return score

static func _is_region_within_bounds(region: WorldRegion, extents: Vector2) -> bool:
	var min_x := -extents.x * 0.5 + WORLD_MARGIN
	var max_x := extents.x * 0.5 - WORLD_MARGIN
	var min_y := -extents.y * 0.5 + WORLD_MARGIN
	var max_y := extents.y * 0.5 - WORLD_MARGIN

	if region.center.x - region.radius.x < min_x:
		return false
	if region.center.x + region.radius.x > max_x:
		return false
	if region.center.y - region.radius.y < min_y:
		return false
	if region.center.y + region.radius.y > max_y:
		return false
	return true

static func _has_reasonable_region_separation(region_a: WorldRegion, region_b: WorldRegion) -> bool:
	var center_distance := region_a.center.distance_to(region_b.center)
	var overlap_threshold := (region_a.radius.length() + region_b.radius.length()) * 0.35
	return center_distance > overlap_threshold

static func _get_site_rules(site_type: String) -> Dictionary:
	return SITE_RULES.get(site_type, {})

static func _validate_placed_sites(
	extents: Vector2,
	regions: Array[WorldRegion],
	networks: Array[WorldNetwork],
	sites: Array[SiteSpec]
) -> void:
	var prior_sites: Array[SiteSpec] = []
	for site in sites:
		if not SITE_RULES.has(site.site_type):
			push_warning("OverlandBuilder: Missing site placement rules for type '" + site.site_type + "'.")
		if site.seed == 0:
			push_warning("OverlandBuilder: Site '" + site.site_id + "' has invalid seed 0.")
		if not _is_site_candidate_valid(site.site_type, site.position, extents, regions, networks, prior_sites):
			push_warning("OverlandBuilder: Site '" + site.site_id + "' failed placement validation.")
		prior_sites.append(site)

static func _find_fallback_site_position(
	site_type: String,
	extents: Vector2,
	regions: Array[WorldRegion],
	networks: Array[WorldNetwork],
	existing_sites: Array[SiteSpec]
) -> Vector2:
	var fallback_candidates := _get_rule_fallback_candidates(site_type, extents, regions, networks)
	var best_position := Vector2.ZERO
	var best_score := -HUGE_DISTANCE
	var found_position := false

	for candidate in fallback_candidates:
		if not _is_site_candidate_valid(site_type, candidate, extents, regions, networks, existing_sites):
			continue
		var score := _score_site_candidate(site_type, candidate, extents, regions, networks, existing_sites)
		if not found_position or score > best_score:
			best_position = candidate
			best_score = score
			found_position = true

	if found_position:
		return best_position

	for candidate in _get_relaxed_fallback_candidates(site_type, extents, regions, networks):
		var clamped := _clamp_point_to_site_bounds(candidate, extents)
		if not _is_point_in_region_type(clamped, regions, "lake"):
			return clamped

	return _clamp_point_to_site_bounds(Vector2.ZERO, extents)

static func _get_rule_fallback_candidates(
	site_type: String,
	extents: Vector2,
	regions: Array[WorldRegion],
	networks: Array[WorldNetwork]
) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	var road: WorldNetwork = _get_network_by_type(networks, "road")
	var forest: WorldRegion = _get_region_by_type(regions, "forest")
	var lake: WorldRegion = _get_region_by_type(regions, "lake")

	if site_type == "town" and road != null:
		candidates.append(_sample_network_point(road, 0.42) + Vector2(0, 56))
		candidates.append(_sample_network_point(road, 0.58) + Vector2(0, -56))
		candidates.append(_sample_network_point(road, 0.50))
	elif site_type == "dungeon":
		candidates.append(Vector2(extents.x * 0.34, -extents.y * 0.22))
		candidates.append(Vector2(extents.x * 0.34, extents.y * 0.22))
		if forest != null:
			candidates.append(forest.center + Vector2(forest.radius.x * 0.95, -forest.radius.y * 0.20))
	elif site_type == "wilderness_site":
		if forest != null:
			candidates.append(forest.center + Vector2(forest.radius.x * 0.25, forest.radius.y * 0.10))
			candidates.append(forest.center + Vector2(-forest.radius.x * 0.35, forest.radius.y * 0.20))
		if lake != null:
			candidates.append(lake.center + Vector2(lake.radius.x * 1.25, 0))

	return candidates

static func _get_relaxed_fallback_candidates(
	site_type: String,
	extents: Vector2,
	regions: Array[WorldRegion],
	networks: Array[WorldNetwork]
) -> Array[Vector2]:
	var candidates := _get_rule_fallback_candidates(site_type, extents, regions, networks)
	if site_type == "town":
		candidates.append(Vector2(-extents.x * 0.10, extents.y * 0.05))
	elif site_type == "dungeon":
		candidates.append(Vector2(extents.x * 0.34, -extents.y * 0.08))
	elif site_type == "wilderness_site":
		candidates.append(Vector2(-extents.x * 0.26, extents.y * 0.18))
	candidates.append(Vector2.ZERO)
	return candidates

static func _is_point_within_site_bounds(pos: Vector2, extents: Vector2) -> bool:
	var half_w := extents.x * 0.5
	var half_h := extents.y * 0.5
	if pos.x < -half_w + WORLD_MARGIN:
		return false
	if pos.x > half_w - WORLD_MARGIN:
		return false
	if pos.y < -half_h + WORLD_MARGIN:
		return false
	if pos.y > half_h - WORLD_MARGIN:
		return false

	return true

static func _clamp_point_to_site_bounds(pos: Vector2, extents: Vector2) -> Vector2:
	var half_w := extents.x * 0.5
	var half_h := extents.y * 0.5
	return Vector2(
		clampf(pos.x, -half_w + WORLD_MARGIN, half_w - WORLD_MARGIN),
		clampf(pos.y, -half_h + WORLD_MARGIN, half_h - WORLD_MARGIN)
	)

static func _is_point_in_region_type(pos: Vector2, regions: Array[WorldRegion], region_type: String) -> bool:
	for region in regions:
		if region.region_type != region_type:
			continue
		if _point_in_region_ellipse(pos, region):
			return true
	return false

static func _has_outdoor_context(site_type: String, pos: Vector2, regions: Array[WorldRegion]) -> bool:
	var rules := _get_site_rules(site_type)
	var context_distance := float(rules.get("outdoor_context_distance", 0.0))
	if _distance_to_region_edge_type(pos, regions, "forest") <= context_distance:
		return true
	if _distance_to_region_edge_type(pos, regions, "lake") <= context_distance:
		return true
	return false

static func _is_site_spacing_valid(site_type: String, candidate: Vector2, existing_sites: Array[SiteSpec]) -> bool:
	for site in existing_sites:
		var min_distance := _get_spacing_requirement(site_type, site.site_type)
		if candidate.distance_to(site.position) < min_distance:
			return false
	return true

static func _get_spacing_requirement(site_type: String, other_site_type: String) -> float:
	var min_distance := SITE_MARKER_RADIUS * 2.0
	var rules := _get_site_rules(site_type)
	min_distance = max(min_distance, float(rules.get("default_min_spacing", MIN_SITE_SPACING)))

	var distances = rules.get("min_distance_by_type", {})
	if distances.has(other_site_type):
		min_distance = max(min_distance, float(distances[other_site_type]))

	var other_rules := _get_site_rules(other_site_type)
	var other_distances = other_rules.get("min_distance_by_type", {})
	if other_distances.has(site_type):
		min_distance = max(min_distance, float(other_distances[site_type]))

	return min_distance

static func _distance_to_site_type(pos: Vector2, sites: Array[SiteSpec], site_type: String) -> float:
	var best_distance := HUGE_DISTANCE
	for site in sites:
		if site.site_type != site_type:
			continue
		best_distance = min(best_distance, pos.distance_to(site.position))
	return best_distance

static func _distance_to_region_edge_type(pos: Vector2, regions: Array[WorldRegion], region_type: String) -> float:
	var best_distance := HUGE_DISTANCE
	for region in regions:
		if region.region_type != region_type:
			continue
		best_distance = min(best_distance, _distance_to_region_edge(pos, region))
	return best_distance

static func _distance_to_region_edge(pos: Vector2, region: WorldRegion) -> float:
	var local := pos - region.center
	if local.length() <= 0.01:
		return 0.0
	if region.radius.x <= 0.01:
		return HUGE_DISTANCE
	if region.radius.y <= 0.01:
		return HUGE_DISTANCE

	var x_term := (local.x * local.x) / (region.radius.x * region.radius.x)
	var y_term := (local.y * local.y) / (region.radius.y * region.radius.y)
	var normalized := sqrt(x_term + y_term)
	if normalized <= 1.0:
		return 0.0

	var edge_point := region.center + local / normalized
	return pos.distance_to(edge_point)

static func _distance_to_network_type(pos: Vector2, networks: Array[WorldNetwork], network_type: String) -> float:
	var best_distance := HUGE_DISTANCE
	for network in networks:
		if network.network_type != network_type:
			continue
		best_distance = min(best_distance, _distance_to_network(pos, network))
	return best_distance

static func _distance_to_network(pos: Vector2, network: WorldNetwork) -> float:
	if network.points.size() == 0:
		return HUGE_DISTANCE
	if network.points.size() == 1:
		return pos.distance_to(network.points[0])

	var best_distance := HUGE_DISTANCE
	for i in range(network.points.size() - 1):
		var start := network.points[i]
		var end := network.points[i + 1]
		best_distance = min(best_distance, _distance_to_segment(pos, start, end))
	return best_distance

static func _distance_to_segment(pos: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var segment_length_sq := segment.length_squared()
	if segment_length_sq <= 0.01:
		return pos.distance_to(start)
	var t := clampf((pos - start).dot(segment) / segment_length_sq, 0.0, 1.0)
	var closest := start + segment * t
	return pos.distance_to(closest)

static func _sample_network_point(network: WorldNetwork, t: float) -> Vector2:
	if network.points.size() == 0:
		return Vector2.ZERO
	if network.points.size() == 1:
		return network.points[0]

	var total_length := 0.0
	for i in range(network.points.size() - 1):
		total_length += network.points[i].distance_to(network.points[i + 1])
	if total_length <= 0.01:
		return network.points[0]

	var clamped_t: float = clampf(t, 0.0, 1.0)
	var target_distance: float = clamped_t * total_length
	var traversed := 0.0
	for i in range(network.points.size() - 1):
		var start := network.points[i]
		var end := network.points[i + 1]
		var segment_length := start.distance_to(end)
		if segment_length <= 0.01:
			continue
		if traversed + segment_length >= target_distance:
			var local_t := (target_distance - traversed) / segment_length
			return start.lerp(end, local_t)
		traversed += segment_length

	return network.points[network.points.size() - 1]

static func _get_region_by_type(regions: Array[WorldRegion], region_type: String) -> WorldRegion:
	for region in regions:
		if region.region_type == region_type:
			return region
	return null

static func _get_network_by_type(networks: Array[WorldNetwork], network_type: String) -> WorldNetwork:
	for network in networks:
		if network.network_type == network_type:
			return network
	return null

static func _edge_readability_score(pos: Vector2, extents: Vector2) -> float:
	var half_w := extents.x * 0.5
	var half_h := extents.y * 0.5
	var left_distance := pos.x - (-half_w + WORLD_MARGIN)
	var right_distance := (half_w - WORLD_MARGIN) - pos.x
	var top_distance := pos.y - (-half_h + WORLD_MARGIN)
	var bottom_distance := (half_h - WORLD_MARGIN) - pos.y
	var distance_from_edge: float = min(min(left_distance, right_distance), min(top_distance, bottom_distance))
	return clampf(distance_from_edge, 0.0, 220.0) * 0.10

static func _point_in_region_ellipse(pos: Vector2, region: WorldRegion) -> bool:
	var local := pos - region.center
	if region.radius.x <= 0.01:
		return false
	if region.radius.y <= 0.01:
		return false
	var x_term := (local.x * local.x) / (region.radius.x * region.radius.x)
	var y_term := (local.y * local.y) / (region.radius.y * region.radius.y)
	return x_term + y_term <= 1.0
