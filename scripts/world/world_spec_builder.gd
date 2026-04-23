class_name WorldSpecBuilder
extends RefCounted

const DEFAULT_EXTENTS: Vector2 = Vector2(2200, 1500)
const PROCGEN_REGISTRY_SCRIPT := preload("res://scripts/worldgen/registries/procgen_registry.gd")
const WORLD_VALIDATION_SCRIPT := preload("res://scripts/world/world_validation.gd")

var procgen_registry: ProcgenRegistry
var _phase_log: PackedStringArray = PackedStringArray()


func build_new_world(world_seed: int, settings: Dictionary = {}) -> WorldSpec:
	assert(world_seed != 0, "WorldSpecBuilder requires a nonzero root world_seed.")
	_phase_log.clear()
	_ensure_procgen_registry()

	_log_phase_start("initialize")
	var spec: WorldSpec = _initialize_world(world_seed, settings)
	_log_phase_end("initialize")

	_log_phase_start("overland_context")
	_create_overland_context(spec)
	_log_phase_end("overland_context")

	_log_phase_start("networks")
	_create_networks(spec)
	_log_phase_end("networks")

	_log_phase_start("primary_sites")
	_place_primary_sites(spec)
	_log_phase_end("primary_sites")

	_log_phase_start("secondary_sites")
	_place_secondary_sites(spec)
	_log_phase_end("secondary_sites")

	_log_phase_start("finalize")
	_finalize_site_specs(spec)
	_log_phase_end("finalize")

	_log_phase_start("validate")
	var errors: PackedStringArray = WORLD_VALIDATION_SCRIPT.validate_world(spec)
	if not errors.is_empty():
		for error in errors:
			push_error("WorldSpecBuilder: " + error)
		assert(false, "WorldSpecBuilder produced invalid WorldSpec.")
	_log_phase_end("validate")

	print("[WorldSpecBuilder] built world id=%s seed=%s regions=%d networks=%d sites=%d" % [
		spec.id,
		str(spec.world_seed),
		spec.regions.size(),
		spec.networks.size(),
		spec.sites.size()
	])
	print(WORLD_VALIDATION_SCRIPT.make_debug_dump(spec))
	return spec


func get_phase_log() -> PackedStringArray:
	var copied_log: PackedStringArray = PackedStringArray()
	for entry in _phase_log:
		copied_log.append(entry)
	return copied_log


func debug_dump(spec: WorldSpec) -> String:
	return WORLD_VALIDATION_SCRIPT.make_debug_dump(spec)


static func derive_child_seed(root_seed: int, stable_id: String, phase: String = "") -> int:
	var key: String = "%s:%s:%s" % [str(root_seed), stable_id, phase]
	var derived: int = int(hash(key))
	if derived < 0:
		derived = -derived
	if derived == 0:
		derived = 1
	return derived


func _initialize_world(world_seed: int, settings: Dictionary) -> WorldSpec:
	var extents: Vector2 = settings.get("extents", DEFAULT_EXTENTS)
	var spec: WorldSpec = WorldSpec.new(world_seed, extents)
	spec.id = String(settings.get("world_id", "world_%d" % world_seed))
	spec.version = int(settings.get("version", 1))
	spec.climate = {
		"temperature": "temperate",
		"moisture": "mixed",
		"seasonality": "moderate"
	}
	spec.biome_defaults = {
		"base": "grassland",
		"land": "grassland",
		"forest": "temperate_forest",
		"water": "lake"
	}
	spec.global_rules = {
		"builder": "WorldSpecBuilder",
		"builder_version": 1,
		"content_density": String(settings.get("content_density", "prototype")),
		"phase_order": PackedStringArray([
			"initialize",
			"overland_context",
			"networks",
			"primary_sites",
			"secondary_sites",
			"finalize",
			"validate"
		])
	}
	spec.sub_seeds = _derive_sub_seeds(world_seed)
	return spec


func _create_overland_context(spec: WorldSpec) -> void:
	var forest_seed: int = int(spec.sub_seeds.get("forest_01", derive_child_seed(spec.world_seed, "forest_01", "region")))
	var lake_seed: int = int(spec.sub_seeds.get("lake_01", derive_child_seed(spec.world_seed, "lake_01", "region")))
	var forest: WorldRegion = OverlandBuilder._build_forest_region(forest_seed, spec.extents)
	var lake: WorldRegion = OverlandBuilder._build_lake_region(lake_seed, spec.extents, forest)
	spec.regions.append(forest)
	spec.regions.append(lake)
	print("[WorldSpecBuilder] context region id=%s type=%s center=%s radius=%s" % [
		forest.region_id,
		forest.region_type,
		str(forest.center),
		str(forest.radius)
	])
	print("[WorldSpecBuilder] context region id=%s type=%s center=%s radius=%s" % [
		lake.region_id,
		lake.region_type,
		str(lake.center),
		str(lake.radius)
	])


func _create_networks(spec: WorldSpec) -> void:
	var river_seed: int = int(spec.sub_seeds.get("river_01", derive_child_seed(spec.world_seed, "river_01", "network")))
	var road_seed: int = int(spec.sub_seeds.get("road_01", derive_child_seed(spec.world_seed, "road_01", "network")))
	var river: WorldNetwork = OverlandBuilder._build_river_network(river_seed, spec.extents)
	var road: WorldNetwork = OverlandBuilder._build_road_network(road_seed, spec.extents)
	spec.networks.append(river)
	spec.networks.append(road)
	print("[WorldSpecBuilder] network id=%s type=%s points=%d" % [river.network_id, river.network_type, river.points.size()])
	print("[WorldSpecBuilder] network id=%s type=%s points=%d" % [road.network_id, road.network_type, road.points.size()])


func _place_primary_sites(spec: WorldSpec) -> void:
	var town_feature: WorldFeatureDefinition = _get_site_feature("town")
	var town_seed: int = int(spec.sub_seeds.get("site_town_oakhaven", derive_child_seed(spec.world_seed, "site_town_oakhaven", "site")))
	var site: SiteSpec = OverlandBuilder._place_site_by_rules(
		"town",
		"site_town_oakhaven",
		town_seed,
		spec.extents,
		_regions_as_typed_array(spec.regions),
		_networks_as_typed_array(spec.networks),
		[]
	)
	_apply_site_feature_defaults(site, town_feature)
	site.display_name = "Oakhaven"
	spec.sites.append(site)
	print("[WorldSpecBuilder] primary site id=%s type=%s pos=%s seed=%s" % [
		site.site_id,
		site.site_type,
		str(site.position),
		str(site.seed)
	])


func _place_secondary_sites(spec: WorldSpec) -> void:
	var existing_sites: Array[SiteSpec] = _sites_as_typed_array(spec.sites)
	var dungeon_feature: WorldFeatureDefinition = _get_site_feature("dungeon")
	var dungeon_seed: int = int(spec.sub_seeds.get("site_dungeon_fallen_watch", derive_child_seed(spec.world_seed, "site_dungeon_fallen_watch", "site")))
	var dungeon: SiteSpec = OverlandBuilder._place_site_by_rules(
		"dungeon",
		"site_dungeon_fallen_watch",
		dungeon_seed,
		spec.extents,
		_regions_as_typed_array(spec.regions),
		_networks_as_typed_array(spec.networks),
		existing_sites
	)
	_apply_site_feature_defaults(dungeon, dungeon_feature)
	dungeon.display_name = "Fallen Watch"
	spec.sites.append(dungeon)
	existing_sites.append(dungeon)
	print("[WorldSpecBuilder] secondary site id=%s type=%s pos=%s seed=%s" % [
		dungeon.site_id,
		dungeon.site_type,
		str(dungeon.position),
		str(dungeon.seed)
	])

	var wilderness_feature: WorldFeatureDefinition = _get_world_feature("forest_clearing_minor")
	var wilderness_seed: int = int(spec.sub_seeds.get("site_wilderness_amber_meadow", derive_child_seed(spec.world_seed, "site_wilderness_amber_meadow", "site")))
	var wilderness: SiteSpec = OverlandBuilder._place_site_by_rules(
		"wilderness_site",
		"site_wilderness_amber_meadow",
		wilderness_seed,
		spec.extents,
		_regions_as_typed_array(spec.regions),
		_networks_as_typed_array(spec.networks),
		existing_sites
	)
	_apply_site_feature_defaults(wilderness, wilderness_feature)
	wilderness.display_name = "Amber Meadow"
	spec.sites.append(wilderness)
	print("[WorldSpecBuilder] secondary site id=%s type=%s pos=%s seed=%s" % [
		wilderness.site_id,
		wilderness.site_type,
		str(wilderness.position),
		str(wilderness.seed)
	])


func _finalize_site_specs(spec: WorldSpec) -> void:
	var road: WorldNetwork = _get_network_by_type(spec.networks, "road")
	var river: WorldNetwork = _get_network_by_type(spec.networks, "river")
	for site in spec.sites:
		if site == null:
			continue
		site.id = site.site_id
		site.world_pos = Vector2i(roundi(site.position.x), roundi(site.position.y))
		site.world_region_id = _get_primary_region_id(site.position, spec.regions)
		site.biome = _get_site_biome(site.position, spec.regions, spec.biome_defaults)
		site.connections = _build_connections(site, spec.sites, road, river)
		site.placement_context = _build_placement_context(site, spec.regions, spec.networks)
		if site.site_type == "town":
			_finalize_town_site(site, road)
		elif site.site_type == "dungeon":
			_finalize_dungeon_site(site)
		elif site.site_type == "wilderness_site":
			_finalize_wilderness_site(site)
		site.version = 1


func _finalize_town_site(site: SiteSpec, road: WorldNetwork) -> void:
	if site.subtype == "" or site.subtype == "town":
		site.subtype = "walled_market_town"
	if site.generator_id == "":
		site.generator_id = "town"
	site.routing_id = "town"
	if not site.tags.has("settlement"):
		site.tags.append("settlement")
	if not site.tags.has("enterable"):
		site.tags.append("enterable")
	if site.scale.is_empty():
		site.scale = {
			"size_tier": "small",
			"importance": "local",
			"population_tier": "village",
			"population": 180
		}
	var gate_direction: String = "south"
	if road != null:
		gate_direction = _get_access_direction_from_network(site.position, road)
	site.access_points = [
		{
			"id": "access_road_" + gate_direction,
			"kind": "road_entry",
			"type": "road_entry",
			"direction": gate_direction,
			"network_id": "road_01",
			"network_type": "road"
		}
	]
	if String(site.generation_params.get("building_profile", "")) == "":
		site.generation_params["building_profile"] = "prototype_town"
	if not site.generation_params.has("has_wall"):
		site.generation_params["has_wall"] = true
	if String(site.generation_params.get("district_style", "")) == "":
		site.generation_params["district_style"] = "market_town"
	if not site.generation_params.has("special_features"):
		site.generation_params["special_features"] = PackedStringArray(["market_square"])


func _finalize_dungeon_site(site: SiteSpec) -> void:
	site.routing_id = "dungeon"
	site.generator_id = "dungeon"
	if site.subtype == "":
		site.subtype = "dungeon"
	if site.tags.is_empty():
		site.tags = PackedStringArray(["danger", "enterable"])
	if site.scale.is_empty():
		site.scale = {
			"size_tier": "small",
			"importance": "local"
		}


func _finalize_wilderness_site(site: SiteSpec) -> void:
	site.routing_id = "wilderness_site"
	site.generator_id = "wilderness_site_generator_v1"
	if site.subtype == "":
		site.subtype = "forest_clearing"
	if site.tags.is_empty():
		site.tags = PackedStringArray(["outdoor", "wilderness", "enterable"])
	if site.scale.is_empty():
		site.scale = {
			"size_tier": "small",
			"importance": "local"
		}
	if site.access_points.is_empty():
		var direction: String = "south"
		if float(site.placement_context.get("road_distance", 1000000000.0)) < 180.0:
			direction = "south"
		site.access_points = [
			{
				"id": "trail_entry_" + direction,
				"kind": "trail_entry",
				"type": "trail_entry",
				"direction": direction
			}
		]
	if String(site.generation_params.get("site_radius_tier", "")) == "":
		site.generation_params["site_radius_tier"] = "small"
	if String(site.generation_params.get("blocker_density", "")) == "":
		site.generation_params["blocker_density"] = "medium"
	if String(site.generation_params.get("ground_cover", "")) == "":
		site.generation_params["ground_cover"] = "forest_floor"
	if String(site.generation_params.get("feature_profile", "")) == "":
		site.generation_params["feature_profile"] = "default_forest_clearing"
	if not site.generation_params.has("has_side_path"):
		site.generation_params["has_side_path"] = true


func _apply_site_feature_defaults(site: SiteSpec, feature: WorldFeatureDefinition) -> void:
	if site == null or feature == null:
		return
	site.subtype = feature.subtype
	site.generator_id = feature.generator_id
	site.routing_id = feature.generator_id
	var copied_tags: PackedStringArray = PackedStringArray()
	for tag in feature.tags:
		copied_tags.append(tag)
	site.tags = copied_tags
	for key in feature.generation_defaults.keys():
		site.generation_params[key] = feature.generation_defaults[key]


func _build_connections(
	site: SiteSpec,
	sites: Array[SiteSpec],
	road: WorldNetwork,
	river: WorldNetwork
) -> Dictionary:
	var roads: Array = []
	var rivers: Array = []
	var adjacent_sites: Array = []
	if road != null and _distance_to_network(site.position, road) <= 180.0:
		roads.append(road.network_id)
	if river != null and _distance_to_network(site.position, river) <= 150.0:
		rivers.append(river.network_id)
	for other_site in sites:
		if other_site == null or other_site == site:
			continue
		if site.position.distance_to(other_site.position) <= 420.0:
			adjacent_sites.append(other_site.site_id)
	return {
		"roads": roads,
		"rivers": rivers,
		"adjacent_sites": adjacent_sites
	}


func _build_placement_context(site: SiteSpec, regions: Array, networks: Array) -> Dictionary:
	return {
		"world_position": site.position,
		"world_region_id": _get_primary_region_id(site.position, regions),
		"near_water": _distance_to_region_edge_type(site.position, regions, "lake") <= 180.0,
		"river_adjacent": _distance_to_network_type(site.position, networks, "river") <= 150.0,
		"lake_adjacent": _distance_to_region_edge_type(site.position, regions, "lake") <= 180.0,
		"forest_adjacent": _distance_to_region_edge_type(site.position, regions, "forest") <= 220.0,
		"road_distance": _distance_to_network_type(site.position, networks, "road"),
		"elevation": "low",
		"slope": "gentle"
	}


func _derive_sub_seeds(world_seed: int) -> Dictionary:
	return {
		"forest_01": derive_child_seed(world_seed, "forest_01", "region"),
		"lake_01": derive_child_seed(world_seed, "lake_01", "region"),
		"river_01": derive_child_seed(world_seed, "river_01", "network"),
		"road_01": derive_child_seed(world_seed, "road_01", "network"),
		"site_town_oakhaven": derive_child_seed(world_seed, "site_town_oakhaven", "site"),
		"site_dungeon_fallen_watch": derive_child_seed(world_seed, "site_dungeon_fallen_watch", "site"),
		"site_wilderness_amber_meadow": derive_child_seed(world_seed, "site_wilderness_amber_meadow", "site")
	}


func _get_site_feature(site_type: String) -> WorldFeatureDefinition:
	_ensure_procgen_registry()
	for feature in procgen_registry.get_site_features():
		if feature.site_type == site_type:
			return feature
	return null


func _get_world_feature(feature_id: String) -> WorldFeatureDefinition:
	_ensure_procgen_registry()
	return procgen_registry.get_world_feature(feature_id)


func _ensure_procgen_registry() -> void:
	if procgen_registry != null:
		return
	procgen_registry = PROCGEN_REGISTRY_SCRIPT.new()
	procgen_registry.load_all()


func _log_phase_start(phase_name: String) -> void:
	var message: String = "[WorldSpecBuilder] phase start: " + phase_name
	_phase_log.append(message)
	print(message)


func _log_phase_end(phase_name: String) -> void:
	var message: String = "[WorldSpecBuilder] phase end: " + phase_name
	_phase_log.append(message)
	print(message)


func _regions_as_typed_array(regions: Array) -> Array[WorldRegion]:
	var typed: Array[WorldRegion] = []
	for region in regions:
		if region is WorldRegion:
			typed.append(region)
	return typed


func _networks_as_typed_array(networks: Array) -> Array[WorldNetwork]:
	var typed: Array[WorldNetwork] = []
	for network in networks:
		if network is WorldNetwork:
			typed.append(network)
	return typed


func _sites_as_typed_array(sites: Array[SiteSpec]) -> Array[SiteSpec]:
	var typed: Array[SiteSpec] = []
	for site in sites:
		if site != null:
			typed.append(site)
	return typed


func _get_primary_region_id(pos: Vector2, regions: Array) -> String:
	var best_region_id: String = ""
	var best_distance: float = 1000000000.0
	for region in regions:
		if region == null:
			continue
		var distance: float = _distance_to_region_edge(pos, region)
		if _point_in_region_ellipse(pos, region):
			return String(region.region_id)
		if distance < best_distance:
			best_distance = distance
			best_region_id = String(region.region_id)
	return best_region_id


func _get_site_biome(pos: Vector2, regions: Array, defaults: Dictionary) -> String:
	for region in regions:
		if region == null:
			continue
		if not _point_in_region_ellipse(pos, region):
			continue
		if String(region.region_type) == "forest":
			return String(defaults.get("forest", "temperate_forest"))
		if String(region.region_type) == "lake":
			return String(defaults.get("water", "lake"))
	return String(defaults.get("land", defaults.get("base", "grassland")))


func _get_network_by_type(networks: Array, network_type: String) -> WorldNetwork:
	for network in networks:
		if network is WorldNetwork and network.network_type == network_type:
			return network
	return null


func _get_access_direction_from_network(pos: Vector2, network: WorldNetwork) -> String:
	var nearest: Vector2 = _closest_point_on_network(pos, network)
	var delta: Vector2 = nearest - pos
	if abs(delta.x) > abs(delta.y):
		if delta.x > 0.0:
			return "east"
		return "west"
	if delta.y > 0.0:
		return "south"
	return "north"


func _closest_point_on_network(pos: Vector2, network: WorldNetwork) -> Vector2:
	if network == null or network.points.size() == 0:
		return pos
	if network.points.size() == 1:
		return network.points[0]
	var best_point: Vector2 = network.points[0]
	var best_distance: float = 1000000000.0
	for i in range(network.points.size() - 1):
		var candidate: Vector2 = _closest_point_on_segment(pos, network.points[i], network.points[i + 1])
		var distance: float = pos.distance_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best_point = candidate
	return best_point


func _closest_point_on_segment(pos: Vector2, start: Vector2, end: Vector2) -> Vector2:
	var segment: Vector2 = end - start
	var segment_length_sq: float = segment.length_squared()
	if segment_length_sq <= 0.01:
		return start
	var t: float = clampf((pos - start).dot(segment) / segment_length_sq, 0.0, 1.0)
	return start + segment * t


func _distance_to_network_type(pos: Vector2, networks: Array, network_type: String) -> float:
	var best_distance: float = 1000000000.0
	for network in networks:
		if not (network is WorldNetwork):
			continue
		if network.network_type != network_type:
			continue
		best_distance = min(best_distance, _distance_to_network(pos, network))
	return best_distance


func _distance_to_network(pos: Vector2, network: WorldNetwork) -> float:
	if network == null or network.points.size() == 0:
		return 1000000000.0
	var closest: Vector2 = _closest_point_on_network(pos, network)
	return pos.distance_to(closest)


func _distance_to_region_edge_type(pos: Vector2, regions: Array, region_type: String) -> float:
	var best_distance: float = 1000000000.0
	for region in regions:
		if region == null:
			continue
		if String(region.region_type) != region_type:
			continue
		best_distance = min(best_distance, _distance_to_region_edge(pos, region))
	return best_distance


func _distance_to_region_edge(pos: Vector2, region) -> float:
	if region.radius.x <= 0.01:
		return 1000000000.0
	if region.radius.y <= 0.01:
		return 1000000000.0
	var local: Vector2 = pos - region.center
	if local.length() <= 0.01:
		return 0.0
	var x_term: float = (local.x * local.x) / (region.radius.x * region.radius.x)
	var y_term: float = (local.y * local.y) / (region.radius.y * region.radius.y)
	var normalized: float = sqrt(x_term + y_term)
	if normalized <= 1.0:
		return 0.0
	var edge_point: Vector2 = region.center + local / normalized
	return pos.distance_to(edge_point)


func _point_in_region_ellipse(pos: Vector2, region) -> bool:
	if region.radius.x <= 0.01:
		return false
	if region.radius.y <= 0.01:
		return false
	var local: Vector2 = pos - region.center
	var x_term: float = (local.x * local.x) / (region.radius.x * region.radius.x)
	var y_term: float = (local.y * local.y) / (region.radius.y * region.radius.y)
	return x_term + y_term <= 1.0
