class_name SiteRuntimeDelta
extends Resource

@export var site_id: String = ""
@export var discovered: bool = false
@export var visited: bool = false
@export var cleared: bool = false
@export var disabled: bool = false
@export var local_flags: Dictionary = {}
@export var removed_object_ids: PackedStringArray = []
@export var modified_objects: Dictionary = {}
@export var metadata: Dictionary = {}
@export var version: int = 1

func to_dict() -> Dictionary:
	return {
		"site_id": site_id,
		"discovered": discovered,
		"visited": visited,
		"cleared": cleared,
		"disabled": disabled,
		"local_flags": local_flags,
		"removed_object_ids": removed_object_ids,
		"modified_objects": modified_objects,
		"metadata": metadata,
		"version": version
	}

func load_from_dict(data: Dictionary) -> void:
	site_id = String(data.get("site_id", ""))
	discovered = data.get("discovered", false)
	visited = data.get("visited", false)
	cleared = data.get("cleared", false)
	disabled = data.get("disabled", false)
	local_flags = data.get("local_flags", {})
	removed_object_ids = data.get("removed_object_ids", PackedStringArray())
	modified_objects = data.get("modified_objects", {})
	metadata = data.get("metadata", {})
	version = int(data.get("version", 1))
