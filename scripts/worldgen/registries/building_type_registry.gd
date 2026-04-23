class_name BuildingTypeRegistry
extends RefCounted

const DEFAULT_PATH := "res://data/worldgen/building_types/"

var definitions: Dictionary = {}


func load_all(path: String = DEFAULT_PATH) -> void:
	definitions.clear()
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("BuildingTypeRegistry: Missing directory " + path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and _is_resource_file(file_name):
			_load_definition(path.path_join(file_name))
		file_name = dir.get_next()


func get_type(building_type_id: String) -> BuildingTypeDefinition:
	if not definitions.has(building_type_id):
		push_warning("BuildingTypeRegistry: Missing building type id '" + building_type_id + "'.")
		return null
	var definition: BuildingTypeDefinition = definitions[building_type_id]
	return definition


func has_type(building_type_id: String) -> bool:
	return definitions.has(building_type_id)


func get_all_type_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for type_id in definitions.keys():
		ids.append(String(type_id))
	return ids


func _load_definition(path: String) -> void:
	var resource: Resource = load(path)
	if not (resource is BuildingTypeDefinition):
		push_warning("BuildingTypeRegistry: Ignoring non-BuildingTypeDefinition resource " + path)
		return
	var definition: BuildingTypeDefinition = resource
	var errors := definition.validate()
	if not errors.is_empty():
		push_error("BuildingTypeRegistry: Invalid definition " + path + ": " + "; ".join(errors))
		return
	if definitions.has(definition.id):
		push_error("BuildingTypeRegistry: Duplicate building type id '" + definition.id + "' at " + path)
		return
	definitions[definition.id] = definition


func _is_resource_file(file_name: String) -> bool:
	return file_name.ends_with(".tres") or file_name.ends_with(".res")
