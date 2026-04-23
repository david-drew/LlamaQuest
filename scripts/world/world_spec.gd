class_name WorldSpec
extends Resource

@export var id: String = ""
@export var world_seed: int = 0
@export var version: int = 1
@export var size: Vector2i = Vector2i.ZERO
@export var climate: Dictionary = {}
@export var biome_defaults: Dictionary = {}
@export var regions: Array = []
@export var networks: Array = []
@export var sites: Array[SiteSpec] = []
@export var global_rules: Dictionary = {}

var seed: int = 0
var extents: Vector2 = Vector2.ZERO
var sub_seeds: Dictionary = {}


func _init(_seed: int = 0, _extents: Vector2 = Vector2.ZERO) -> void:
	seed = _seed
	world_seed = _seed
	extents = _extents
	size = Vector2i(roundi(_extents.x), roundi(_extents.y))
	if _seed != 0:
		id = "world_%d" % _seed


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "":
		errors.append("WorldSpec.id is required.")
	if world_seed == 0:
		errors.append("WorldSpec.world_seed must be nonzero.")
	if version <= 0:
		errors.append("WorldSpec.version must be positive.")
	if size.x < 0 or size.y < 0:
		errors.append("WorldSpec.size cannot be negative.")

	for site in sites:
		if site == null:
			errors.append("WorldSpec.sites contains a null SiteSpec.")
			continue
		var site_errors := site.validate()
		for site_error in site_errors:
			errors.append("Site '" + site.site_id + "': " + site_error)

	return errors


func get_site_by_id(site_id: String) -> SiteSpec:
	for site in sites:
		if site == null:
			continue
		if site.id == site_id or site.site_id == site_id:
			return site
	return null


func has_site(site_id: String) -> bool:
	return get_site_by_id(site_id) != null


func to_dict() -> Dictionary:
	var site_data: Array = []
	for site in sites:
		if site == null:
			continue
		site_data.append(site.to_dict())

	return {
		"id": id,
		"world_seed": world_seed,
		"seed": seed,
		"version": version,
		"size": size,
		"extents": extents,
		"climate": climate,
		"biome_defaults": biome_defaults,
		"regions": regions,
		"networks": networks,
		"sites": site_data,
		"global_rules": global_rules,
		"sub_seeds": sub_seeds
	}


static func from_dict(data: Dictionary) -> WorldSpec:
	var loaded_seed := int(data.get("world_seed", data.get("seed", 0)))
	var loaded_extents: Vector2 = data.get("extents", Vector2.ZERO)
	var spec := WorldSpec.new(loaded_seed, loaded_extents)
	spec.id = String(data.get("id", spec.id))
	spec.version = int(data.get("version", 1))
	spec.size = data.get("size", spec.size)
	spec.climate = data.get("climate", {})
	spec.biome_defaults = data.get("biome_defaults", {})
	spec.regions = data.get("regions", [])
	spec.networks = data.get("networks", [])
	spec.global_rules = data.get("global_rules", {})
	spec.sub_seeds = data.get("sub_seeds", {})
	spec.sites = []

	var raw_sites: Array = data.get("sites", [])
	for raw_site in raw_sites:
		if raw_site is SiteSpec:
			spec.sites.append(raw_site)
		elif raw_site is Dictionary:
			spec.sites.append(SiteSpec.from_dict(raw_site))

	return spec
