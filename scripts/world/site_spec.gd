class_name SiteSpec
extends Resource

@export var id: String = ""
@export var site_type: String = ""
@export var subtype: String = ""
@export var generator_id: String = ""
@export var seed: int = 0
@export var world_pos: Vector2i = Vector2i.ZERO
@export var world_region_id: String = ""
@export var biome: String = ""
@export var tags: PackedStringArray = []
@export var connections: Dictionary = {}
@export var access_points: Array = []
@export var placement_context: Dictionary = {}
@export var scale: Dictionary = {}
@export var faction: Dictionary = {}
@export var generation_params: Dictionary = {}
@export var state: Dictionary = {}
@export var version: int = 1

var site_id: String = ""
var display_name: String = ""
var position: Vector2 = Vector2.ZERO
var routing_id: String = ""


func _init(
	_site_id: String = "",
	_site_type: String = "",
	_display_name: String = "",
	_position: Vector2 = Vector2.ZERO,
	_seed: int = 0,
	_routing_id: String = ""
) -> void:
	id = _site_id
	site_id = _site_id
	site_type = _site_type
	display_name = _display_name
	position = _position
	world_pos = Vector2i(roundi(_position.x), roundi(_position.y))
	seed = _seed
	routing_id = _routing_id
	generator_id = _routing_id
	subtype = _routing_id


func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == "" and site_id == "":
		errors.append("SiteSpec.id is required.")
	if site_type == "":
		errors.append("SiteSpec.site_type is required.")
	if seed == 0:
		errors.append("SiteSpec.seed must be nonzero.")
	if version <= 0:
		errors.append("SiteSpec.version must be positive.")
	if site_type == "wilderness_site":
		_validate_wilderness_site(errors)
	return errors


func is_town() -> bool:
	return site_type == "town"


func is_wilderness_site() -> bool:
	return site_type == "wilderness_site"


func get_access_point(access_point_id: String) -> Dictionary:
	for access_point in access_points:
		if not (access_point is Dictionary):
			continue
		if String(access_point.get("id", "")) == access_point_id:
			return access_point
	return {}


func to_dict() -> Dictionary:
	return {
		"id": _canonical_id(),
		"site_id": _canonical_id(),
		"site_type": site_type,
		"subtype": subtype,
		"display_name": display_name,
		"generator_id": generator_id,
		"seed": seed,
		"world_pos": world_pos,
		"position": position,
		"routing_id": routing_id,
		"world_region_id": world_region_id,
		"biome": biome,
		"tags": tags,
		"connections": connections,
		"access_points": access_points,
		"placement_context": placement_context,
		"scale": scale,
		"faction": faction,
		"generation_params": generation_params,
		"state": state,
		"version": version
	}


static func from_dict(data: Dictionary) -> SiteSpec:
	var loaded_id: String = String(data.get("id", data.get("site_id", "")))
	var loaded_pos: Vector2 = data.get("position", Vector2.ZERO)
	if loaded_pos == Vector2.ZERO and data.has("world_pos"):
		var loaded_world_pos: Vector2i = data.get("world_pos", Vector2i.ZERO)
		loaded_pos = Vector2(loaded_world_pos)

	var spec: SiteSpec = SiteSpec.new(
		loaded_id,
		String(data.get("site_type", "")),
		String(data.get("display_name", loaded_id)),
		loaded_pos,
		int(data.get("seed", 0)),
		String(data.get("routing_id", data.get("generator_id", "")))
	)
	spec.subtype = String(data.get("subtype", spec.subtype))
	spec.generator_id = String(data.get("generator_id", spec.generator_id))
	spec.world_pos = data.get("world_pos", spec.world_pos)
	spec.world_region_id = String(data.get("world_region_id", ""))
	spec.biome = String(data.get("biome", ""))
	spec.tags = data.get("tags", PackedStringArray())
	spec.connections = data.get("connections", {})
	spec.access_points = data.get("access_points", [])
	spec.placement_context = data.get("placement_context", {})
	spec.scale = data.get("scale", {})
	spec.faction = data.get("faction", {})
	spec.generation_params = data.get("generation_params", {})
	spec.state = data.get("state", {})
	spec.version = int(data.get("version", 1))
	return spec


func _canonical_id() -> String:
	if id != "":
		return id
	return site_id


func _validate_wilderness_site(errors: PackedStringArray) -> void:
	if subtype != "forest_clearing" and subtype != "roadside_glade" and subtype != "lakeshore_site":
		errors.append("Wilderness SiteSpec.subtype must be forest_clearing, roadside_glade, or lakeshore_site.")
	if generator_id != "wilderness_site_generator_v1" and generator_id != "wilderness_site":
		errors.append("Wilderness SiteSpec.generator_id must be wilderness_site_generator_v1.")
	if access_points.is_empty():
		errors.append("Wilderness SiteSpec.access_points must contain at least one access point.")
	for access_point in access_points:
		if not (access_point is Dictionary):
			continue
		var kind: String = String(access_point.get("kind", access_point.get("type", "")))
		if kind != "trail_entry" and kind != "road_entry" and kind != "shore_entry":
			errors.append("Wilderness access point kind must be trail_entry, road_entry, or shore_entry.")
		var direction: String = String(access_point.get("direction", ""))
		if direction != "north" and direction != "south" and direction != "east" and direction != "west":
			errors.append("Wilderness access point direction must be north, south, east, or west.")
