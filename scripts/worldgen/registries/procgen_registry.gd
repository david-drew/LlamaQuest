class_name ProcgenRegistry
extends RefCounted

var world_features: WorldFeatureRegistry = WorldFeatureRegistry.new()
var building_profiles: BuildingProfileRegistry = BuildingProfileRegistry.new()
var building_types: BuildingTypeRegistry = BuildingTypeRegistry.new()
var loaded: bool = false


func load_all() -> void:
	world_features.load_all()
	building_profiles.load_all()
	building_types.load_all()
	loaded = true


func ensure_loaded() -> void:
	if loaded:
		return
	load_all()


func get_world_feature(feature_id: String) -> WorldFeatureDefinition:
	ensure_loaded()
	return world_features.get_feature(feature_id)


func get_site_features() -> Array[WorldFeatureDefinition]:
	ensure_loaded()
	return world_features.get_site_features()


func get_building_profile(profile_id: String) -> BuildingProfileDefinition:
	ensure_loaded()
	return building_profiles.get_profile(profile_id)


func has_building_profile(profile_id: String) -> bool:
	ensure_loaded()
	return building_profiles.has_profile(profile_id)


func get_building_type(building_type_id: String) -> BuildingTypeDefinition:
	ensure_loaded()
	return building_types.get_type(building_type_id)


func has_building_type(building_type_id: String) -> bool:
	ensure_loaded()
	return building_types.has_type(building_type_id)
