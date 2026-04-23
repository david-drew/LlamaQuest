class_name WorldFeatureDefinition
extends Resource

@export var id: String = ""
@export var feature_class: String = ""
@export var site_type: String = ""
@export var subtype: String = ""
@export var generator_id: String = ""
@export var version: int = 1
@export var tags: PackedStringArray = []
@export var weight: float = 1.0
@export var min_instances_per_world: int = 0
@export var max_instances_per_world: int = 0
@export var placement_rules: Dictionary = {}
@export var context_rules: Dictionary = {}
@export var generation_defaults: Dictionary = {}
@export var derived_tags: PackedStringArray = []


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "":
		errors.append("WorldFeatureDefinition.id is required.")
	if feature_class == "":
		errors.append("WorldFeatureDefinition.feature_class is required.")
	if version <= 0:
		errors.append("WorldFeatureDefinition.version must be positive.")
	if weight < 0.0:
		errors.append("WorldFeatureDefinition.weight cannot be negative.")
	if max_instances_per_world != 0 and min_instances_per_world > max_instances_per_world:
		errors.append("WorldFeatureDefinition min_instances_per_world cannot exceed max_instances_per_world.")
	return errors


func is_site_feature() -> bool:
	return feature_class == "site" or site_type != ""


func is_region_feature() -> bool:
	return feature_class == "region"


func is_network_feature() -> bool:
	return feature_class == "network"


func to_dict() -> Dictionary:
	return {
		"id": id,
		"feature_class": feature_class,
		"site_type": site_type,
		"subtype": subtype,
		"generator_id": generator_id,
		"version": version,
		"tags": tags,
		"weight": weight,
		"min_instances_per_world": min_instances_per_world,
		"max_instances_per_world": max_instances_per_world,
		"placement_rules": placement_rules,
		"context_rules": context_rules,
		"generation_defaults": generation_defaults,
		"derived_tags": derived_tags
	}


static func from_dict(data: Dictionary) -> WorldFeatureDefinition:
	var definition := WorldFeatureDefinition.new()
	definition.id = String(data.get("id", ""))
	definition.feature_class = String(data.get("feature_class", ""))
	definition.site_type = String(data.get("site_type", ""))
	definition.subtype = String(data.get("subtype", ""))
	definition.generator_id = String(data.get("generator_id", ""))
	definition.version = int(data.get("version", 1))
	definition.tags = data.get("tags", PackedStringArray())
	definition.weight = float(data.get("weight", 1.0))
	definition.min_instances_per_world = int(data.get("min_instances_per_world", 0))
	definition.max_instances_per_world = int(data.get("max_instances_per_world", 0))
	definition.placement_rules = data.get("placement_rules", {})
	definition.context_rules = data.get("context_rules", {})
	definition.generation_defaults = data.get("generation_defaults", {})
	definition.derived_tags = data.get("derived_tags", PackedStringArray())
	return definition
