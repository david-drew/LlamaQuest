class_name WorldFeatureRegistry
extends RefCounted

const DEFAULT_PATH := "res://data/worldgen/world_features/"

var definitions: Dictionary = {}


func load_all(path: String = DEFAULT_PATH) -> void:
	definitions.clear()
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("WorldFeatureRegistry: Missing directory " + path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and _is_resource_file(file_name):
			_load_definition(path.path_join(file_name))
		file_name = dir.get_next()


func get_feature(feature_id: String) -> WorldFeatureDefinition:
	if not definitions.has(feature_id):
		push_warning("WorldFeatureRegistry: Missing world feature id '" + feature_id + "'.")
		return null
	var definition: WorldFeatureDefinition = definitions[feature_id]
	return definition


func get_site_features() -> Array[WorldFeatureDefinition]:
	var features: Array[WorldFeatureDefinition] = []
	for raw_definition in definitions.values():
		var definition: WorldFeatureDefinition = raw_definition
		if definition.is_site_feature():
			features.append(definition)
	return features


func get_region_features() -> Array[WorldFeatureDefinition]:
	var features: Array[WorldFeatureDefinition] = []
	for raw_definition in definitions.values():
		var definition: WorldFeatureDefinition = raw_definition
		if definition.is_region_feature():
			features.append(definition)
	return features


func get_network_features() -> Array[WorldFeatureDefinition]:
	var features: Array[WorldFeatureDefinition] = []
	for raw_definition in definitions.values():
		var definition: WorldFeatureDefinition = raw_definition
		if definition.is_network_feature():
			features.append(definition)
	return features


func get_features_by_tag(tag: String) -> Array[WorldFeatureDefinition]:
	var features: Array[WorldFeatureDefinition] = []
	for raw_definition in definitions.values():
		var definition: WorldFeatureDefinition = raw_definition
		if definition.tags.has(tag) or definition.derived_tags.has(tag):
			features.append(definition)
	return features


func _load_definition(path: String) -> void:
	var resource: Resource = load(path)
	if not (resource is WorldFeatureDefinition):
		push_warning("WorldFeatureRegistry: Ignoring non-WorldFeatureDefinition resource " + path)
		return
	var definition: WorldFeatureDefinition = resource
	var errors := definition.validate()
	if not errors.is_empty():
		push_error("WorldFeatureRegistry: Invalid definition " + path + ": " + "; ".join(errors))
		return
	if definitions.has(definition.id):
		push_error("WorldFeatureRegistry: Duplicate world feature id '" + definition.id + "' at " + path)
		return
	definitions[definition.id] = definition


func _is_resource_file(file_name: String) -> bool:
	return file_name.ends_with(".tres") or file_name.ends_with(".res")
