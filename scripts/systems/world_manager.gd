class_name WorldManager
extends Node

@export var overland_seed: int = 0

var season:String = "Thothdawn"
var month:String  = "Midders"
var mdate:int = 1

const MODE_OVERLAND := "overland"
const MODE_TOWN := "town"
const MODE_DUNGEON := "dungeon"
const MODE_WILDERNESS_SITE := "wilderness_site"
const TRANSITION_CONTEXT_SCRIPT := preload("res://scripts/world/transition_context.gd")
const WORLD_PERSISTENCE_SERVICE_SCRIPT := preload("res://scripts/core/world_persistence_service.gd")
const SITE_TRANSITION_SERVICE_SCRIPT := preload("res://scripts/core/site_transition_service.gd")
const WORLD_SPEC_BUILDER_SCRIPT := preload("res://scripts/world/world_spec_builder.gd")

var current_mode: String = MODE_OVERLAND
var current_world: WorldSpec
var current_site: SiteSpec
var overland_view: OverlandView
var transition_context
var world_persistence_service: WorldPersistenceService
var site_transition_service: SiteTransitionService

var world_root: Node2D
var dialog_panel: Control

var player_scene: PackedScene = preload("res://scenes/player.tscn")
var town_scene: PackedScene = preload("res://scenes/town.tscn")
var dungeon_scene: PackedScene = preload("res://scenes/dungeon_stub.tscn")
var wilderness_scene: PackedScene = preload("res://scenes/wilderness_stub.tscn")
var npc_dialogue_script: Script = preload("res://scripts/npc_dialogue.gd")

func _ready() -> void:
	world_root = get_node("/root/Main/World")
	dialog_panel = get_node("/root/Main/CanvasLayer/MarginContainer/DialogPanel")
	world_persistence_service = WORLD_PERSISTENCE_SERVICE_SCRIPT.new()
	site_transition_service = SITE_TRANSITION_SERVICE_SCRIPT.new()
	site_transition_service.configure(self, world_persistence_service)
	_ensure_world_seed_for_new_or_loaded_game()
	call_deferred("_enter_overland", Vector2.ZERO)

func regenerate_overland_with_seed(seed: int) -> void:
	overland_seed = seed
	if overland_seed == 0:
		var runtime: WorldRuntimeState = world_persistence_service.start_new_world_session()
		overland_seed = runtime.world_seed
	else:
		world_persistence_service.start_world_session(world_persistence_service.get_world_id_for_seed(overland_seed), overland_seed)
	print("WorldManager: starting new overland world with world_seed ", overland_seed)
	current_world = null
	current_site = null
	transition_context = null
	call_deferred("_enter_overland", Vector2.ZERO)

## Takes the parsed JSON data from the EventGenerator and alters the game state
func apply_event(category: String, target: String) -> void:
	print("WorldManager: Applying event category '", category, "' with target '", target, "'")
	
	match category:
		"weather":
			_handle_weather_change(target)
		"npc_arrival":
			_handle_npc_spawn(target)
		"hazard":
			_handle_world_hazard(target)
		_:
			push_warning("WorldManager: Unknown event category received: " + category)

func _handle_weather_change(weather_type: String) -> void:
	match weather_type:
		"severe_storm":
			print("GAME STATE: Starting rain particle emitters. Player movement speed is set to 1/3rd default.")
			# weather_system.start_rain()
		"heavy_rain":
			print("GAME STATE: Starting rain particle emitters. Halving player movement speed.")
			# weather_system.start_rain()
		"clear_skies":
			print("GAME STATE: Stopping rain. Restoring movement speed.")
			# weather_system.stop_rain()
		_:
			print("GAME STATE: Unrecognized weather target: ", weather_type)

func _handle_npc_spawn(npc_type: String) -> void:
	if npc_type == "traveling_merchant":
		print("GAME STATE: Enabling Traveling Merchant node in the village square.")
		# npc_spawner.spawn("merchant", Vector2(100, 100))

func _handle_world_hazard(hazard_type: String) -> void:
	if hazard_type == "goblin_raiding_party":
		print("GAME STATE: Spawning 3 extra goblins in the eastern woods.")
		# npc_spawner.spawn_group("goblin", 3, "eastern_woods")

func get_date() -> String:
	mdate += 1
	var fulldate:String = "%s, %s %02d" % [season, month, mdate]
	return fulldate

func get_runtime_state() -> WorldRuntimeState:
	return world_persistence_service.get_runtime_state()

func get_site_delta(site_id: String) -> SiteRuntimeDelta:
	return world_persistence_service.get_or_create_site_delta(site_id)

func mark_current_site_cleared() -> void:
	if current_site == null:
		return
	world_persistence_service.mark_site_cleared(current_site.site_id)

func load_world_from_dict(data: Dictionary) -> void:
	world_persistence_service.load_world_from_dict(data)
	var runtime: WorldRuntimeState = world_persistence_service.get_runtime_state()
	overland_seed = runtime.world_seed
	print("WorldManager: loaded saved overland world_seed ", overland_seed)
	current_world = null
	current_site = null
	transition_context = null
	call_deferred(
		"_enter_overland",
		Vector2(float(runtime.player_overland_pos.x), float(runtime.player_overland_pos.y))
	)

func _enter_overland(spawn_position: Vector2 = Vector2.ZERO) -> void:
	current_mode = MODE_OVERLAND

	if current_world == null:
		_ensure_world_seed_for_new_or_loaded_game()
		assert(overland_seed != 0, "WorldSpec.world_seed must be assigned before generation")
		print("WorldManager: building WorldSpec with world_seed ", overland_seed)
		var builder: WorldSpecBuilder = WORLD_SPEC_BUILDER_SCRIPT.new()
		current_world = builder.build_new_world(overland_seed, {"extents": Vector2(2200, 1500)})
		world_persistence_service.start_world_session(current_world.id, current_world.world_seed)
		world_persistence_service.get_runtime_state().world_flags["active_world_spec_id"] = current_world.id
		site_transition_service.configure_world(current_world)

	_clear_world_root()
	_set_dialog_visible(false)

	overland_view = OverlandView.new()
	overland_view.name = "OverlandView"
	overland_view.build_from_spec(current_world)
	overland_view.site_enter_requested.connect(_on_site_enter_requested)
	world_root.add_child(overland_view)

	var player_spawn: Vector2 = spawn_position
	if player_spawn == Vector2.ZERO:
		player_spawn = _get_overland_return_position()
	_spawn_player(player_spawn)
	if transition_context != null:
		transition_context = null

func _on_site_enter_requested(site: SiteSpec) -> void:
	if current_mode != MODE_OVERLAND:
		return

	if not _is_valid_enterable_site(site):
		push_warning("WorldManager: Invalid site entry request.")
		return

	var resolved_site: SiteSpec = _resolve_site(site.site_id)
	if resolved_site == null:
		push_warning("WorldManager: Site id not found in current world: " + site.site_id)
		return

	current_site = resolved_site
	site_transition_service.enter_site(resolved_site.site_id, "", _get_player_world_position())

func _enter_site_with_context(context) -> void:
	site_transition_service.enter_site_with_context(context)

func _enter_site_from_transition(context, site_delta: SiteRuntimeDelta) -> void:
	if context == null:
		return
	var site: SiteSpec = _resolve_site(context.site_id)
	if site == null:
		push_warning("WorldManager: Site id not found in current world: " + context.site_id)
		return
	if context.site_type != "" and context.site_type != site.site_type:
		push_warning("WorldManager: Transition site type does not match resolved site: " + context.site_id)
		return
	current_site = site
	transition_context = context
	_enter_site(site, context, site_delta)

func _enter_site(site: SiteSpec, context, site_delta: SiteRuntimeDelta) -> void:
	if not _is_supported_site_type(site.site_type):
		push_warning("WorldManager: Unknown site type '" + site.site_type + "'. Returning to overland.")
		_enter_overland(_get_overland_return_position())
		return

	current_mode = site.site_type
	_clear_world_root()

	if site.site_type == "town":
		var town: Node = town_scene.instantiate()
		_apply_site_runtime_if_supported(town, context, site, site_delta)
		world_root.add_child(town)

		var npc_node: Node = Node.new()
		npc_node.name = "NpcNode"
		npc_node.set_script(npc_dialogue_script)
		world_root.add_child(npc_node)

		_spawn_player(_resolve_local_spawn_position(town, context, site))
		_set_dialog_visible(false)
		_create_local_exit_zone("TownExitZone", _resolve_local_exit_position(town, context), "Exit to Overland")
		return

	if site.site_type == "dungeon":
		var dungeon: Node = dungeon_scene.instantiate()
		_apply_site_runtime_if_supported(dungeon, context, site, site_delta)
		world_root.add_child(dungeon)
		if dungeon.has_signal("exit_requested"):
			dungeon.connect("exit_requested", _on_local_site_exit_requested)
		var dungeon_spawn: Vector2 = _resolve_local_spawn_position(dungeon, context, site)
		_spawn_player(dungeon_spawn)
		_set_dialog_visible(false)
		return

	if site.site_type == "wilderness_site":
		var wilderness: Node = wilderness_scene.instantiate()
		_apply_site_runtime_if_supported(wilderness, context, site, site_delta)
		world_root.add_child(wilderness)
		if wilderness.has_signal("exit_requested"):
			wilderness.connect("exit_requested", _on_local_site_exit_requested)
		var wilderness_spawn: Vector2 = _resolve_local_spawn_position(wilderness, context, site)
		_spawn_player(wilderness_spawn)
		_set_dialog_visible(false)
		return

	push_warning("WorldManager: Unsupported site type '" + site.site_type + "'. Returning to overland.")
	_enter_overland(_get_overland_return_position())

func _create_local_exit_zone(zone_name: String, position: Vector2, label_text: String) -> void:
	var root: Node2D = Node2D.new()
	root.name = zone_name
	root.position = position
	world_root.add_child(root)

	var exit_area: Area2D = Area2D.new()
	exit_area.name = "ExitArea"
	exit_area.collision_layer = 16
	exit_area.collision_mask = 2
	exit_area.monitoring = true
	exit_area.monitorable = true
	root.add_child(exit_area)

	var exit_shape: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(120, 80)
	exit_shape.shape = shape
	exit_area.add_child(exit_shape)

	var marker: Polygon2D = Polygon2D.new()
	marker.polygon = PackedVector2Array([
		Vector2(-60, -40),
		Vector2(60, -40),
		Vector2(60, 40),
		Vector2(-60, 40)
	])
	marker.color = Color(0.2, 0.9, 1.0, 0.34)
	root.add_child(marker)

	var label: Label = Label.new()
	label.text = label_text
	label.position = Vector2(-68, 52)
	root.add_child(label)

	exit_area.body_entered.connect(_on_local_exit_body_entered)

func _on_local_exit_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return

	request_exit_to_overland()

func request_exit_to_overland() -> void:
	if current_mode == MODE_OVERLAND:
		return
	call_deferred("_return_to_overland_deferred", "main_exit")

func _on_local_site_exit_requested() -> void:
	request_exit_to_overland()

func _return_to_overland_deferred(exit_point_id: String = "") -> void:
	var return_context = _build_overland_return_context()
	if return_context != null:
		return_context.exit_point_id = exit_point_id
	site_transition_service.exit_current_site(exit_point_id)

func _return_to_overland_from_transition(context) -> void:
	transition_context = context
	current_site = null
	var return_pos: Vector2 = _get_overland_return_position()
	_enter_overland(return_pos)

func _clear_world_root() -> void:
	for child in world_root.get_children():
		child.queue_free()

func _spawn_player(position: Vector2) -> void:
	var player: Node2D = player_scene.instantiate() as Node2D
	player.position = position
	world_root.add_child(player)
	if current_mode == MODE_OVERLAND:
		world_persistence_service.update_player_overland_pos(Vector2i(roundi(position.x), roundi(position.y)))

func _set_dialog_visible(visible: bool) -> void:
	dialog_panel.visible = visible

func _get_default_overland_spawn() -> Vector2:
	for site in current_world.sites:
		if site.site_type == "town":
			return site.position + Vector2(0, 120)
	return Vector2.ZERO

func _is_valid_enterable_site(site: SiteSpec) -> bool:
	if site == null:
		return false
	if site.site_id == "":
		return false
	if not _is_supported_site_type(site.site_type):
		return false
	return true

func _is_supported_site_type(site_type: String) -> bool:
	if site_type == "town":
		return true
	if site_type == "dungeon":
		return true
	if site_type == "wilderness_site":
		return true
	return false

func _resolve_site(site_id: String) -> SiteSpec:
	if current_world == null:
		return null
	for site in current_world.sites:
		if site.site_id == site_id:
			return site
	return null

func _capture_transition_context(site: SiteSpec) -> void:
	var context = TRANSITION_CONTEXT_SCRIPT.new()
	context.world_id = world_persistence_service.get_world_id_for_seed(current_world.seed)
	context.source_mode = MODE_OVERLAND
	context.destination_mode = site.site_type
	context.world_seed = current_world.seed
	context.site_id = site.site_id
	context.site_type = site.site_type
	context.site_seed = site.seed
	context.site_subtype = site.routing_id
	context.overland_position_before_entry = _get_player_world_position()
	context.overland_return_position = site.position + Vector2(0, 96)
	context.overland_return_pos = Vector2i(roundi(context.overland_return_position.x), roundi(context.overland_return_position.y))
	transition_context = context

func _get_player_world_position() -> Vector2:
	var player: Node2D = get_node_or_null("/root/Main/World/Player") as Node2D
	if player == null:
		return _get_default_overland_spawn()
	return player.global_position

func _get_overland_return_position() -> Vector2:
	if transition_context != null:
		if transition_context.world_seed == overland_seed:
			if transition_context.overland_return_position != Vector2.ZERO:
				return transition_context.overland_return_position
			if transition_context.overland_return_pos != Vector2i.ZERO:
				return Vector2(transition_context.overland_return_pos)
	return _get_default_overland_spawn()

func _build_overland_return_context():
	if transition_context != null:
		transition_context.source_mode = transition_context.site_type
		transition_context.destination_mode = MODE_OVERLAND
		transition_context.exit_point_id = String(transition_context.spawn_hint.get("preferred_exit_id", "main_exit"))
		return transition_context

	var context = TRANSITION_CONTEXT_SCRIPT.new()
	context.world_id = world_persistence_service.get_world_id_for_seed(overland_seed)
	context.world_seed = overland_seed
	context.source_mode = current_mode
	context.destination_mode = MODE_OVERLAND
	context.overland_return_position = _get_default_overland_spawn()
	context.overland_return_pos = Vector2i(roundi(context.overland_return_position.x), roundi(context.overland_return_position.y))
	return context

func _ensure_world_seed_for_new_or_loaded_game() -> void:
	if world_persistence_service.has_active_world_session():
		var runtime: WorldRuntimeState = world_persistence_service.get_runtime_state()
		overland_seed = runtime.world_seed
		print("WorldManager: using loaded world_seed ", overland_seed)
		return

	if overland_seed == 0:
		var runtime: WorldRuntimeState = world_persistence_service.start_new_world_session()
		overland_seed = runtime.world_seed
		print("WorldManager: New Game assigned fresh world_seed ", overland_seed)
		return

	print("WorldManager: using provided world_seed ", overland_seed)
	world_persistence_service.start_world_session(world_persistence_service.get_world_id_for_seed(overland_seed), overland_seed)

func _resolve_local_spawn_position(content_node: Node, context, site: SiteSpec) -> Vector2:
	if content_node != null and content_node.has_method("resolve_spawn_position"):
		var resolved_position = content_node.call("resolve_spawn_position", context)
		if resolved_position is Vector2:
			print("[Traversal] local spawn site=%s pos=%s" % [site.site_id, str(resolved_position)])
			return resolved_position
	if content_node != null and content_node.has_method("resolve_spawn_anchor"):
		var anchor = content_node.call("resolve_spawn_anchor", context)
		if anchor is Node2D:
			print("[Traversal] local spawn site=%s anchor=%s pos=%s" % [site.site_id, anchor.name, str(anchor.global_position)])
			return anchor.global_position
	if content_node != null and content_node.has_method("get_entry_spawn_position"):
		var fallback_position = content_node.call("get_entry_spawn_position")
		if fallback_position is Vector2:
			push_warning("WorldManager: Using legacy local spawn fallback for site " + site.site_id)
			return fallback_position
	push_warning("WorldManager: No local spawn anchor resolved for site " + site.site_id + "; using Vector2.ZERO.")
	return Vector2.ZERO

func _resolve_local_exit_position(content_node: Node, context) -> Vector2:
	if content_node != null and content_node.has_method("get_exit_trigger_position"):
		var exit_position = content_node.call("get_exit_trigger_position", context)
		if exit_position is Vector2:
			return exit_position
	if content_node != null and content_node.has_method("prepare_for_exit"):
		var exit_data = content_node.call("prepare_for_exit", "main_exit")
		if exit_data is Dictionary and exit_data.has("local_exit_position"):
			var local_exit_position = exit_data["local_exit_position"]
			if local_exit_position is Vector2:
				return local_exit_position
	return Vector2(0, -680)

func _apply_entry_context_if_supported(content_node: Node) -> void:
	if content_node == null:
		return
	if content_node.has_method("configure_entry_context"):
		content_node.call("configure_entry_context", transition_context)

func _apply_site_runtime_if_supported(
	content_node: Node,
	context,
	site: SiteSpec,
	site_delta: SiteRuntimeDelta
) -> void:
	if content_node == null:
		return
	if content_node.has_method("setup_from_site_spec"):
		content_node.call("setup_from_site_spec", site, context, world_persistence_service.get_runtime_state())
	if content_node.has_method("configure_site_runtime"):
		content_node.call("configure_site_runtime", context, site, site_delta)
		return
	if content_node.has_method("configure_entry_context"):
		content_node.call("configure_entry_context", context)
