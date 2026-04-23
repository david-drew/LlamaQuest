class_name WorldRuntimeState
extends Resource

@export var world_id: String = ""
@export var world_seed: int = 0
@export var current_mode: String = "overland"
@export var current_site_id: String = ""
@export var player_overland_pos: Vector2i = Vector2i.ZERO
@export var last_overland_return_pos: Vector2i = Vector2i.ZERO
@export var last_transition: Resource
@export var discovered_site_ids: PackedStringArray = []
@export var cleared_site_ids: PackedStringArray = []
@export var visited_site_ids: PackedStringArray = []
@export var site_deltas: Dictionary = {}
@export var world_flags: Dictionary = {}

func to_dict() -> Dictionary:
	var serialized_deltas := {}
	for site_id in site_deltas.keys():
		var delta = site_deltas[site_id]
		if delta != null and delta.has_method("to_dict"):
			serialized_deltas[site_id] = delta.call("to_dict")

	var transition_data := {}
	if last_transition != null:
		transition_data = last_transition.to_dict()

	return {
		"world_id": world_id,
		"world_seed": world_seed,
		"current_mode": current_mode,
		"current_site_id": current_site_id,
		"player_overland_pos": player_overland_pos,
		"last_overland_return_pos": last_overland_return_pos,
		"last_transition": transition_data,
		"discovered_site_ids": discovered_site_ids,
		"cleared_site_ids": cleared_site_ids,
		"visited_site_ids": visited_site_ids,
		"site_deltas": serialized_deltas,
		"world_flags": world_flags
	}
