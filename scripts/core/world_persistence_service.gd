class_name WorldPersistenceService
extends RefCounted

const MODE_OVERLAND := "overland"
const SITE_RUNTIME_DELTA_SCRIPT := preload("res://scripts/core/site_runtime_delta.gd")
const WORLD_RUNTIME_STATE_SCRIPT := preload("res://scripts/core/world_runtime_state.gd")

var runtime_state: WorldRuntimeState

func create_fresh_world_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var new_seed := int(rng.randi())
	while new_seed == 0:
		new_seed = int(rng.randi())
	print("WorldPersistenceService: minted new world_seed ", new_seed)
	return new_seed

func get_world_id_for_seed(world_seed: int) -> String:
	return "world_%d" % world_seed

func has_active_world_session() -> bool:
	if runtime_state == null:
		return false
	return runtime_state.world_seed != 0

func start_world_session(world_id: String, world_seed: int) -> void:
	if world_seed == 0:
		push_error("WorldPersistenceService: Refusing to start world session with world_seed 0.")
		return

	if runtime_state != null and runtime_state.world_id == world_id and runtime_state.world_seed == world_seed:
		print("WorldPersistenceService: reusing loaded world_seed ", world_seed)
		return

	runtime_state = WORLD_RUNTIME_STATE_SCRIPT.new()
	runtime_state.world_id = world_id
	runtime_state.world_seed = world_seed
	runtime_state.current_mode = MODE_OVERLAND
	print("WorldPersistenceService: started world session ", world_id, " with world_seed ", world_seed)

func start_new_world_session() -> WorldRuntimeState:
	var new_seed := create_fresh_world_seed()
	start_world_session(get_world_id_for_seed(new_seed), new_seed)
	print("[World] New Game world created id=%s seed=%s" % [runtime_state.world_id, str(runtime_state.world_seed)])
	return runtime_state

func get_runtime_state() -> WorldRuntimeState:
	if runtime_state == null:
		runtime_state = WORLD_RUNTIME_STATE_SCRIPT.new()
	return runtime_state

func get_or_create_site_delta(site_id: String) -> SiteRuntimeDelta:
	var state := get_runtime_state()
	if site_id == "":
		push_warning("WorldPersistenceService: Cannot create a site delta without a site id.")
		return null
	if state.site_deltas.has(site_id):
		return state.site_deltas[site_id]

	var delta: SiteRuntimeDelta = SITE_RUNTIME_DELTA_SCRIPT.new()
	delta.site_id = site_id
	state.site_deltas[site_id] = delta
	return delta

func mark_site_discovered(site_id: String) -> void:
	var delta := get_or_create_site_delta(site_id)
	if delta == null:
		return
	delta.discovered = true
	var state := get_runtime_state()
	state.discovered_site_ids = _add_unique_site_id(state.discovered_site_ids, site_id)

func mark_site_visited(site_id: String) -> void:
	var delta := get_or_create_site_delta(site_id)
	if delta == null:
		return
	delta.visited = true
	var state := get_runtime_state()
	state.visited_site_ids = _add_unique_site_id(state.visited_site_ids, site_id)

func mark_site_cleared(site_id: String) -> void:
	var delta := get_or_create_site_delta(site_id)
	if delta == null:
		return
	delta.cleared = true
	var state := get_runtime_state()
	state.cleared_site_ids = _add_unique_site_id(state.cleared_site_ids, site_id)

func update_player_overland_pos(pos: Vector2i) -> void:
	get_runtime_state().player_overland_pos = pos

func update_last_overland_return_pos(pos: Vector2i) -> void:
	get_runtime_state().last_overland_return_pos = pos

func set_current_site(site_id: String, mode: String) -> void:
	var state := get_runtime_state()
	state.current_site_id = site_id
	state.current_mode = mode

func leave_current_site() -> void:
	var state := get_runtime_state()
	state.current_site_id = ""
	state.current_mode = MODE_OVERLAND

func set_last_transition(context) -> void:
	get_runtime_state().last_transition = context

func save_world_to_dict() -> Dictionary:
	return get_runtime_state().to_dict()

func load_world_from_dict(data: Dictionary) -> void:
	var loaded_seed := int(data.get("world_seed", 0))
	if loaded_seed == 0:
		push_error("WorldPersistenceService: Saved world is missing a nonzero world_seed.")
		return

	var loaded_world_id := String(data.get("world_id", ""))
	if loaded_world_id == "" and loaded_seed != 0:
		loaded_world_id = get_world_id_for_seed(loaded_seed)
	print("WorldPersistenceService: loading saved world_seed ", loaded_seed)
	start_world_session(loaded_world_id, loaded_seed)
	print("[World] Existing world loaded id=%s seed=%s" % [loaded_world_id, str(loaded_seed)])
	var state := get_runtime_state()
	state.current_mode = String(data.get("current_mode", MODE_OVERLAND))
	state.current_site_id = String(data.get("current_site_id", ""))
	state.player_overland_pos = data.get("player_overland_pos", Vector2i.ZERO)
	state.last_overland_return_pos = data.get("last_overland_return_pos", Vector2i.ZERO)
	state.discovered_site_ids = data.get("discovered_site_ids", PackedStringArray())
	state.cleared_site_ids = data.get("cleared_site_ids", PackedStringArray())
	state.visited_site_ids = data.get("visited_site_ids", PackedStringArray())
	state.world_flags = data.get("world_flags", {})
	state.site_deltas = {}

	var delta_data = data.get("site_deltas", {})
	for site_id in delta_data.keys():
		var delta: SiteRuntimeDelta = SITE_RUNTIME_DELTA_SCRIPT.new()
		delta.load_from_dict(delta_data[site_id])
		state.site_deltas[site_id] = delta

func _add_unique_site_id(ids: PackedStringArray, site_id: String) -> PackedStringArray:
	if ids.has(site_id):
		return ids
	ids.append(site_id)
	return ids
