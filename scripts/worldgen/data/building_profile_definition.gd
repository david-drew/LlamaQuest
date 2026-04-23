class_name BuildingProfileDefinition
extends Resource

@export var id: String = ""
@export var version: int = 1
@export var tags: PackedStringArray = []
@export var allowed_town_subtypes: PackedStringArray = []
@export var scale_rules: Dictionary = {}
@export var building_types: Dictionary = {}
@export var guaranteed_buildings: PackedStringArray = []
@export var special_feature_requirements: Dictionary = {}
@export var district_bias: Dictionary = {}
@export var fallback_rules: Dictionary = {}


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "":
		errors.append("BuildingProfileDefinition.id is required.")
	if version <= 0:
		errors.append("BuildingProfileDefinition.version must be positive.")
	if building_types.is_empty():
		errors.append("BuildingProfileDefinition.building_types cannot be empty.")
	for building_type_id in building_types.keys():
		if String(building_type_id) == "":
			errors.append("BuildingProfileDefinition.building_types contains an empty id.")
	return errors


func supports_town_subtype(subtype: String) -> bool:
	if allowed_town_subtypes.is_empty():
		return true
	return allowed_town_subtypes.has(subtype)


func supports_scale(scale: Dictionary) -> bool:
	if scale_rules.is_empty():
		return true
	var min_population := int(scale_rules.get("min_population", 0))
	var max_population := int(scale_rules.get("max_population", 0))
	var population := int(scale.get("population", 0))
	if min_population > 0 and population < min_population:
		return false
	if max_population > 0 and population > max_population:
		return false
	return true


func get_required_building_ids(special_features: Array) -> PackedStringArray:
	var required := PackedStringArray()
	for building_id in guaranteed_buildings:
		if not required.has(building_id):
			required.append(building_id)

	for feature_id in special_features:
		var key := String(feature_id)
		if not special_feature_requirements.has(key):
			continue
		var feature_requirements = special_feature_requirements[key]
		for building_id in feature_requirements:
			var required_id := String(building_id)
			if not required.has(required_id):
				required.append(required_id)

	return required


func to_dict() -> Dictionary:
	return {
		"id": id,
		"version": version,
		"tags": tags,
		"allowed_town_subtypes": allowed_town_subtypes,
		"scale_rules": scale_rules,
		"building_types": building_types,
		"guaranteed_buildings": guaranteed_buildings,
		"special_feature_requirements": special_feature_requirements,
		"district_bias": district_bias,
		"fallback_rules": fallback_rules
	}


static func from_dict(data: Dictionary) -> BuildingProfileDefinition:
	var definition := BuildingProfileDefinition.new()
	definition.id = String(data.get("id", ""))
	definition.version = int(data.get("version", 1))
	definition.tags = data.get("tags", PackedStringArray())
	definition.allowed_town_subtypes = data.get("allowed_town_subtypes", PackedStringArray())
	definition.scale_rules = data.get("scale_rules", {})
	definition.building_types = data.get("building_types", {})
	definition.guaranteed_buildings = data.get("guaranteed_buildings", PackedStringArray())
	definition.special_feature_requirements = data.get("special_feature_requirements", {})
	definition.district_bias = data.get("district_bias", {})
	definition.fallback_rules = data.get("fallback_rules", {})
	return definition
