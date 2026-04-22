class_name WorldManager
extends Node

@export var overland_seed: int = 424242

var season:String = "Thothdawn"
var month:String  = "Midders"
var mdate:int = 1

const MODE_OVERLAND := "overland"
const MODE_SITE := "site"
const TRANSITION_CONTEXT_SCRIPT := preload("res://scripts/world/transition_context.gd")

var current_mode: String = MODE_OVERLAND
var current_world: WorldSpec
var current_site: SiteSpec
var overland_view: OverlandView
var transition_context

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
	call_deferred("_enter_overland", Vector2.ZERO)

func regenerate_overland_with_seed(seed: int) -> void:
	overland_seed = seed
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

func _enter_overland(spawn_position: Vector2 = Vector2.ZERO) -> void:
	current_mode = MODE_OVERLAND

	if current_world == null:
		current_world = OverlandBuilder.build_world(overland_seed, Vector2(2200, 1500))

	_clear_world_root()
	_set_dialog_visible(false)

	overland_view = OverlandView.new()
	overland_view.name = "OverlandView"
	overland_view.build_from_spec(current_world)
	overland_view.site_enter_requested.connect(_on_site_enter_requested)
	world_root.add_child(overland_view)

	var player_spawn := spawn_position
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

	var resolved_site := _resolve_site(site.site_id)
	if resolved_site == null:
		push_warning("WorldManager: Site id not found in current world: " + site.site_id)
		return

	current_site = resolved_site
	_capture_transition_context(resolved_site)
	call_deferred("_enter_site_deferred")

func _enter_site_deferred() -> void:
	if current_site == null:
		return
	_enter_site(current_site)

func _enter_site(site: SiteSpec) -> void:
	if not _is_supported_site_type(site.site_type):
		push_warning("WorldManager: Unknown site type '" + site.site_type + "'. Returning to overland.")
		_enter_overland(_get_overland_return_position())
		return

	current_mode = MODE_SITE
	_clear_world_root()

	if site.site_type == "town":
		var town := town_scene.instantiate()
		_apply_entry_context_if_supported(town)
		world_root.add_child(town)

		var npc_node := Node.new()
		npc_node.name = "NpcNode"
		npc_node.set_script(npc_dialogue_script)
		world_root.add_child(npc_node)

		_spawn_player(Vector2(0, -560))
		_set_dialog_visible(true)
		_create_local_exit_zone("TownExitZone", Vector2(0, -680), "Exit to Overland")
		return

	if site.site_type == "dungeon":
		var dungeon := dungeon_scene.instantiate()
		_apply_entry_context_if_supported(dungeon)
		world_root.add_child(dungeon)
		if dungeon.has_signal("exit_requested"):
			dungeon.connect("exit_requested", _on_local_site_exit_requested)
		var dungeon_spawn := Vector2(0, 40)
		if dungeon.has_method("get_entry_spawn_position"):
			dungeon_spawn = dungeon.call("get_entry_spawn_position")
		_spawn_player(dungeon_spawn)
		_set_dialog_visible(false)
		return

	if site.site_type == "wilderness_site":
		var wilderness := wilderness_scene.instantiate()
		_apply_entry_context_if_supported(wilderness)
		world_root.add_child(wilderness)
		if wilderness.has_signal("exit_requested"):
			wilderness.connect("exit_requested", _on_local_site_exit_requested)
		var wilderness_spawn := Vector2(0, 40)
		if wilderness.has_method("get_entry_spawn_position"):
			wilderness_spawn = wilderness.call("get_entry_spawn_position")
		_spawn_player(wilderness_spawn)
		_set_dialog_visible(false)
		return

	push_warning("WorldManager: Unsupported site type '" + site.site_type + "'. Returning to overland.")
	_enter_overland(_get_overland_return_position())

func _create_local_exit_zone(zone_name: String, position: Vector2, label_text: String) -> void:
	var root := Node2D.new()
	root.name = zone_name
	root.position = position
	world_root.add_child(root)

	var exit_area := Area2D.new()
	exit_area.name = "ExitArea"
	exit_area.collision_layer = 16
	exit_area.collision_mask = 2
	exit_area.monitoring = true
	exit_area.monitorable = true
	root.add_child(exit_area)

	var exit_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(120, 80)
	exit_shape.shape = shape
	exit_area.add_child(exit_shape)

	var marker := Polygon2D.new()
	marker.polygon = PackedVector2Array([
		Vector2(-60, -40),
		Vector2(60, -40),
		Vector2(60, 40),
		Vector2(-60, 40)
	])
	marker.color = Color(0.2, 0.9, 1.0, 0.34)
	root.add_child(marker)

	var label := Label.new()
	label.text = label_text
	label.position = Vector2(-68, 52)
	root.add_child(label)

	exit_area.body_entered.connect(_on_local_exit_body_entered)

func _on_local_exit_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return

	request_exit_to_overland()

func request_exit_to_overland() -> void:
	if current_mode != MODE_SITE:
		return
	call_deferred("_return_to_overland_deferred")

func _on_local_site_exit_requested() -> void:
	request_exit_to_overland()

func _return_to_overland_deferred() -> void:
	var return_pos := _get_overland_return_position()
	_enter_overland(return_pos)

func _clear_world_root() -> void:
	for child in world_root.get_children():
		child.queue_free()

func _spawn_player(position: Vector2) -> void:
	var player := player_scene.instantiate()
	player.position = position
	world_root.add_child(player)

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
	context.world_seed = current_world.seed
	context.site_id = site.site_id
	context.site_type = site.site_type
	context.site_seed = site.seed
	context.site_subtype = site.routing_id
	context.overland_position_before_entry = _get_player_world_position()
	context.overland_return_position = site.position + Vector2(0, 96)
	transition_context = context

func _get_player_world_position() -> Vector2:
	var player := get_node_or_null("/root/Main/World/Player")
	if player == null:
		return _get_default_overland_spawn()
	return player.global_position

func _get_overland_return_position() -> Vector2:
	if transition_context != null:
		if transition_context.world_seed == overland_seed:
			return transition_context.overland_return_position
	return _get_default_overland_spawn()

func _apply_entry_context_if_supported(content_node: Node) -> void:
	if content_node == null:
		return
	if content_node.has_method("configure_entry_context"):
		content_node.call("configure_entry_context", transition_context)
