class_name TransitionContext
extends Resource

@export var world_id: String = ""
@export var source_mode: String = ""
@export var destination_mode: String = ""
@export var world_seed: int = 0
@export var site_id: String = ""
@export var site_type: String = ""
@export var site_subtype: String = ""
@export var site_seed: int = 0
@export var entry_point_id: String = ""
@export var exit_point_id: String = ""
@export var overland_position_before_entry: Vector2 = Vector2.ZERO
@export var overland_return_position: Vector2 = Vector2.ZERO
@export var overland_return_pos: Vector2i = Vector2i.ZERO
@export var spawn_hint: Dictionary = {}
@export var metadata: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"world_id": world_id,
		"source_mode": source_mode,
		"destination_mode": destination_mode,
		"world_seed": world_seed,
		"site_id": site_id,
		"site_type": site_type,
		"site_subtype": site_subtype,
		"site_seed": site_seed,
		"entry_point_id": entry_point_id,
		"exit_point_id": exit_point_id,
		"overland_position_before_entry": overland_position_before_entry,
		"overland_return_position": overland_return_position,
		"overland_return_pos": overland_return_pos,
		"spawn_hint": spawn_hint,
		"metadata": metadata
	}

func load_from_dict(data: Dictionary) -> void:
	world_id = String(data.get("world_id", ""))
	source_mode = String(data.get("source_mode", ""))
	destination_mode = String(data.get("destination_mode", ""))
	world_seed = int(data.get("world_seed", 0))
	site_id = String(data.get("site_id", ""))
	site_type = String(data.get("site_type", ""))
	site_subtype = String(data.get("site_subtype", ""))
	site_seed = int(data.get("site_seed", 0))
	entry_point_id = String(data.get("entry_point_id", ""))
	exit_point_id = String(data.get("exit_point_id", ""))
	overland_position_before_entry = data.get("overland_position_before_entry", Vector2.ZERO)
	overland_return_position = data.get("overland_return_position", Vector2.ZERO)
	overland_return_pos = data.get("overland_return_pos", Vector2i.ZERO)
	spawn_hint = data.get("spawn_hint", {})
	metadata = data.get("metadata", {})
