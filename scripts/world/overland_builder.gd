class_name OverlandBuilder
extends RefCounted

const MIN_SITE_SPACING := 240.0
const DUNGEON_TOWN_MIN_DISTANCE := 520.0
const WORLD_MARGIN := 120.0
const MAX_RETRIES := 24

static func build_world(seed: int, extents: Vector2) -> WorldSpec:
	var spec := WorldSpec.new(seed, extents)
	var sub_seeds := _derive_sub_seeds(seed)
	spec.sub_seeds = sub_seeds

	var forest := _build_forest_region(sub_seeds["forest"], extents)
	var lake := _build_lake_region(sub_seeds["lake"], extents, forest)
	spec.regions.append(forest)
	spec.regions.append(lake)

	var town_site := _place_town_site(sub_seeds["sites"], extents, lake)
	var road_network := _build_road_network(sub_seeds["road"], extents, town_site.position)

	var dungeon_site := _place_dungeon_site(sub_seeds["sites_dungeon"], extents, lake, town_site.position)
	var wilderness_site := _place_wilderness_site(
		sub_seeds["sites_wilderness"],
		extents,
		lake,
		forest,
		[town_site.position, dungeon_site.position]
	)

	var river_network := _build_river_network(sub_seeds["river"], extents)

	spec.networks.append(river_network)
	spec.networks.append(road_network)
	spec.sites.append(town_site)
	spec.sites.append(dungeon_site)
	spec.sites.append(wilderness_site)

	return spec

static func _derive_sub_seeds(seed: int) -> Dictionary:
	var root_rng := RandomNumberGenerator.new()
	root_rng.seed = seed

	return {
		"forest": int(root_rng.randi()),
		"lake": int(root_rng.randi()),
		"river": int(root_rng.randi()),
		"road": int(root_rng.randi()),
		"sites": int(root_rng.randi()),
		"sites_dungeon": int(root_rng.randi()),
		"sites_wilderness": int(root_rng.randi())
	}

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

static func _build_road_network(sub_seed: int, extents: Vector2, town_pos: Vector2) -> WorldNetwork:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed

	var road_y_offset := rng.randf_range(-48.0, 48.0)
	var start := Vector2(-extents.x * 0.46, town_pos.y + road_y_offset)
	var near_town_left := town_pos + Vector2(-120, rng.randf_range(-24.0, 24.0))
	var near_town_right := town_pos + Vector2(120, rng.randf_range(-24.0, 24.0))
	var end := Vector2(extents.x * 0.44, town_pos.y + rng.randf_range(-90.0, 90.0))
	var points := PackedVector2Array([start, near_town_left, near_town_right, end])

	return WorldNetwork.new("road_01", "road", points, 10.0, sub_seed)

static func _place_town_site(sub_seed: int, extents: Vector2, lake: WorldRegion) -> SiteSpec:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed

	var fallback := SiteSpec.new(
		"site_town_oakhaven",
		"town",
		"Oakhaven",
		Vector2(-extents.x * 0.10, extents.y * 0.05),
		sub_seed,
		"town"
	)

	for _attempt in range(MAX_RETRIES):
		var candidate := Vector2(
			rng.randf_range(-extents.x * 0.30, extents.x * 0.10),
			rng.randf_range(-extents.y * 0.10, extents.y * 0.22)
		)
		if _is_point_valid_site_position(candidate, extents, [lake]):
			return SiteSpec.new("site_town_oakhaven", "town", "Oakhaven", candidate, sub_seed, "town")

	return fallback

static func _place_dungeon_site(sub_seed: int, extents: Vector2, lake: WorldRegion, town_pos: Vector2) -> SiteSpec:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed

	var fallback := SiteSpec.new(
		"site_dungeon_fallen_watch",
		"dungeon",
		"Fallen Watch",
		Vector2(extents.x * 0.30, -extents.y * 0.08),
		sub_seed,
		"dungeon"
	)

	for _attempt in range(MAX_RETRIES):
		var candidate := Vector2(
			rng.randf_range(extents.x * 0.10, extents.x * 0.38),
			rng.randf_range(-extents.y * 0.28, extents.y * 0.24)
		)
		if candidate.distance_to(town_pos) < DUNGEON_TOWN_MIN_DISTANCE:
			continue
		if _is_point_valid_site_position(candidate, extents, [lake]):
			return SiteSpec.new("site_dungeon_fallen_watch", "dungeon", "Fallen Watch", candidate, sub_seed, "dungeon")

	return fallback

static func _place_wilderness_site(
	sub_seed: int,
	extents: Vector2,
	lake: WorldRegion,
	forest: WorldRegion,
	other_sites: Array
) -> SiteSpec:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed

	var fallback := SiteSpec.new(
		"site_wilderness_amber_meadow",
		"wilderness_site",
		"Amber Meadow",
		forest.center + Vector2(forest.radius.x * 0.25, forest.radius.y * 0.10),
		sub_seed,
		"wilderness_site"
	)

	for _attempt in range(MAX_RETRIES):
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(forest.radius.x * 0.25, forest.radius.x * 0.68)
		var candidate := forest.center + Vector2(cos(angle), sin(angle)) * dist
		if not _is_point_valid_site_position(candidate, extents, [lake]):
			continue
		if not _is_spacing_valid(candidate, other_sites, MIN_SITE_SPACING):
			continue
		return SiteSpec.new(
			"site_wilderness_amber_meadow",
			"wilderness_site",
			"Amber Meadow",
			candidate,
			sub_seed,
			"wilderness_site"
		)

	return fallback

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

static func _is_point_valid_site_position(pos: Vector2, extents: Vector2, blocked_regions: Array[WorldRegion]) -> bool:
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

	for region in blocked_regions:
		if _point_in_region_ellipse(pos, region):
			return false
	return true

static func _point_in_region_ellipse(pos: Vector2, region: WorldRegion) -> bool:
	var local := pos - region.center
	if region.radius.x <= 0.01:
		return false
	if region.radius.y <= 0.01:
		return false
	var x_term := (local.x * local.x) / (region.radius.x * region.radius.x)
	var y_term := (local.y * local.y) / (region.radius.y * region.radius.y)
	return x_term + y_term <= 1.0

static func _is_spacing_valid(candidate: Vector2, existing_positions: Array, min_spacing: float) -> bool:
	for pos in existing_positions:
		if candidate.distance_to(pos) < min_spacing:
			return false
	return true
