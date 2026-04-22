class_name OverlandBuilder
extends RefCounted

static func build_world(seed: int, extents: Vector2) -> WorldSpec:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var spec := WorldSpec.new(seed, extents)

	var forest_center := Vector2(-extents.x * 0.25, -extents.y * 0.15)
	var lake_center := Vector2(extents.x * 0.22, extents.y * 0.16)
	spec.regions.append(WorldRegion.new("forest_01", "forest", forest_center, Vector2(420, 250)))
	spec.regions.append(WorldRegion.new("lake_01", "lake", lake_center, Vector2(260, 180)))

	var river_points := PackedVector2Array([
		Vector2(-extents.x * 0.42, -extents.y * 0.34),
		Vector2(-extents.x * 0.16, -extents.y * 0.08),
		Vector2(extents.x * 0.08, extents.y * 0.04),
		Vector2(extents.x * 0.36, extents.y * 0.26)
	])
	var road_points := PackedVector2Array([
		Vector2(-extents.x * 0.30, extents.y * 0.28),
		Vector2(-extents.x * 0.10, extents.y * 0.18),
		Vector2(extents.x * 0.14, extents.y * 0.10),
		Vector2(extents.x * 0.34, extents.y * 0.02)
	])
	spec.networks.append(WorldNetwork.new("river_01", "river", river_points))
	spec.networks.append(WorldNetwork.new("road_01", "road", road_points))

	var town_seed := int(rng.randi())
	var dungeon_seed := int(rng.randi())
	var wilderness_seed := int(rng.randi())

	spec.sites.append(SiteSpec.new(
		"site_town_oakhaven",
		"town",
		"Oakhaven",
		Vector2(-120, 90),
		town_seed
	))
	spec.sites.append(SiteSpec.new(
		"site_dungeon_fallen_watch",
		"dungeon",
		"Fallen Watch",
		Vector2(320, -30),
		dungeon_seed
	))
	spec.sites.append(SiteSpec.new(
		"site_wilderness_amber_meadow",
		"wilderness_site",
		"Amber Meadow",
		Vector2(60, 260),
		wilderness_seed
	))

	return spec
