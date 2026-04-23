class_name BuildingProfileRegistry
extends RefCounted

const DEFAULT_PATH := "res://data/worldgen/building_profiles/"

var definitions: Dictionary = {}


func load_all(path: String = DEFAULT_PATH) -> void:
	definitions.clear()
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("BuildingProfileRegistry: Missing directory " + path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and _is_resource_file(file_name):
			_load_definition(path.path_join(file_name))
		file_name = dir.get_next()


func get_profile(profile_id: String) -> BuildingProfileDefinition:
	if not definitions.has(profile_id):
		push_warning("BuildingProfileRegistry: Missing building profile id '" + profile_id + "'.")
		return null
	var definition: BuildingProfileDefinition = definitions[profile_id]
	return definition


func has_profile(profile_id: String) -> bool:
	return definitions.has(profile_id)


func get_all_profile_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for profile_id in definitions.keys():
		ids.append(String(profile_id))
	return ids


func _load_definition(path: String) -> void:
	var resource: Resource = load(path)
	if not (resource is BuildingProfileDefinition):
		push_warning("BuildingProfileRegistry: Ignoring non-BuildingProfileDefinition resource " + path)
		return
	var definition: BuildingProfileDefinition = resource
	var errors := definition.validate()
	if not errors.is_empty():
		push_error("BuildingProfileRegistry: Invalid definition " + path + ": " + "; ".join(errors))
		return
	if definitions.has(definition.id):
		push_error("BuildingProfileRegistry: Duplicate building profile id '" + definition.id + "' at " + path)
		return
	definitions[definition.id] = definition


func _is_resource_file(file_name: String) -> bool:
	return file_name.ends_with(".tres") or file_name.ends_with(".res")
