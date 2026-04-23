class_name SiteTransitionService
extends RefCounted

const MODE_OVERLAND := "overland"
const TRANSITION_CONTEXT_SCRIPT := preload("res://scripts/world/transition_context.gd")

var world_manager: Node
var persistence_service: WorldPersistenceService
var active_world_spec: WorldSpec

func configure(_world_manager: Node, _persistence_service: WorldPersistenceService) -> void:
	world_manager = _world_manager
	persistence_service = _persistence_service

func configure_world(world_spec: WorldSpec) -> void:
	active_world_spec = world_spec

func enter_site(site_id: String, entry_point_id: String = "", overland_player_pos: Vector2 = Vector2.ZERO) -> void:
	if active_world_spec == null:
		push_warning("SiteTransitionService: Cannot enter site without an active WorldSpec.")
		return
	var site: SiteSpec = active_world_spec.get_site_by_id(site_id)
	if site == null:
		push_warning("SiteTransitionService: Requested site_id does not exist: " + site_id)
		return
	if overland_player_pos == Vector2.ZERO and world_manager != null and world_manager.has_method("_get_player_world_position"):
		var manager_position = world_manager.call("_get_player_world_position")
		if manager_position is Vector2:
			overland_player_pos = manager_position
	var context: TransitionContext = build_site_context_from_overland(active_world_spec, site, overland_player_pos, entry_point_id)
	enter_site_with_context(context)

func build_site_context_from_overland(
	world_spec: WorldSpec,
	site: SiteSpec,
	overland_player_pos: Vector2,
	entry_point_id: String = ""
) -> TransitionContext:
	var context: TransitionContext = TRANSITION_CONTEXT_SCRIPT.new()
	context.world_id = _get_world_id(world_spec)
	context.world_seed = world_spec.world_seed
	context.source_mode = MODE_OVERLAND
	context.destination_mode = site.site_type
	context.site_id = site.site_id
	context.site_type = site.site_type
	context.site_subtype = site.subtype
	context.site_seed = site.seed
	context.entry_point_id = _resolve_entry_point_id(site, entry_point_id)
	context.overland_position_before_entry = overland_player_pos
	context.overland_return_position = _resolve_overland_return_position(site, context.entry_point_id)
	context.overland_return_pos = Vector2i(roundi(context.overland_return_position.x), roundi(context.overland_return_position.y))
	context.spawn_hint = {
		"entry_kind": "overland_site",
		"entry_direction": _get_entry_direction(site, context.entry_point_id),
		"preferred_spawn_tag": "main_entry",
		"preferred_gate_id": context.entry_point_id,
		"overland_site_pos": site.position
	}
	context.metadata = {
		"site_world_pos": site.position,
		"routing_id": site.routing_id,
		"generator_id": site.generator_id
	}
	return context

func enter_site_with_context(context) -> void:
	if not _is_valid_site_entry_context(context):
		push_warning("SiteTransitionService: Invalid site entry context.")
		return
	if not _is_valid_mode_transition(context.source_mode, context.destination_mode):
		push_warning("SiteTransitionService: Invalid mode transition %s -> %s." % [context.source_mode, context.destination_mode])
		return

	persistence_service.set_last_transition(context)
	persistence_service.update_player_overland_pos(Vector2i(
		roundi(context.overland_position_before_entry.x),
		roundi(context.overland_position_before_entry.y)
	))
	persistence_service.mark_site_discovered(context.site_id)
	persistence_service.mark_site_visited(context.site_id)
	persistence_service.set_current_site(context.site_id, context.destination_mode)

	var delta: SiteRuntimeDelta = persistence_service.get_or_create_site_delta(context.site_id)
	print("[Traversal] enter world=%s site=%s type=%s subtype=%s seed=%s entry=%s source=%s dest=%s" % [
		context.world_id,
		context.site_id,
		context.site_type,
		context.site_subtype,
		str(context.site_seed),
		context.entry_point_id,
		context.source_mode,
		context.destination_mode
	])
	world_manager.call("_enter_site_from_transition", context, delta)

func exit_current_site(exit_point_id: String = "") -> void:
	var context = persistence_service.get_runtime_state().last_transition
	if context == null:
		push_warning("SiteTransitionService: Exit requested with no active transition context.")
		return
	context.exit_point_id = exit_point_id
	exit_to_overland(context)

func exit_to_overland(context) -> void:
	if context == null:
		context = persistence_service.get_runtime_state().last_transition
	if context == null:
		push_warning("SiteTransitionService: Missing transition context for overland return.")
		return

	context.source_mode = context.site_type
	context.destination_mode = MODE_OVERLAND
	context.overland_return_position = _resolve_context_return_position(context)
	context.overland_return_pos = Vector2i(roundi(context.overland_return_position.x), roundi(context.overland_return_position.y))
	persistence_service.update_last_overland_return_pos(context.overland_return_pos)
	if context.site_id != "":
		var delta: SiteRuntimeDelta = persistence_service.get_or_create_site_delta(context.site_id)
		if delta != null:
			delta.metadata["last_exit_point_id"] = context.exit_point_id
			delta.metadata["last_overland_return_position"] = context.overland_return_position
	persistence_service.set_last_transition(context)
	persistence_service.leave_current_site()
	print("[Traversal] exit site=%s exit=%s return=%s dest=%s" % [
		context.site_id,
		context.exit_point_id,
		str(context.overland_return_position),
		context.destination_mode
	])
	world_manager.call("_return_to_overland_from_transition", context)

func _is_valid_site_entry_context(context) -> bool:
	if context == null:
		return false
	if context.world_id == "":
		return false
	if context.site_id == "":
		return false
	if context.destination_mode == "":
		return false
	if context.site_type == "":
		return false
	return true

func _is_valid_mode_transition(source_mode: String, destination_mode: String) -> bool:
	if source_mode == MODE_OVERLAND:
		return destination_mode != "" and destination_mode != MODE_OVERLAND
	if destination_mode == MODE_OVERLAND:
		return source_mode != "" and source_mode != MODE_OVERLAND
	return false

func _get_world_id(world_spec: WorldSpec) -> String:
	if world_spec.id != "":
		return world_spec.id
	return "world_%d" % world_spec.world_seed

func _resolve_entry_point_id(site: SiteSpec, requested_entry_point_id: String) -> String:
	if requested_entry_point_id != "":
		if not site.get_access_point(requested_entry_point_id).is_empty():
			return requested_entry_point_id
		push_warning("SiteTransitionService: Requested entry point not found on site '%s': %s" % [site.site_id, requested_entry_point_id])
	for access_point in site.access_points:
		if not (access_point is Dictionary):
			continue
		if String(access_point.get("kind", access_point.get("type", ""))) == "road_entry":
			return String(access_point.get("id", "main_entry"))
	for access_point in site.access_points:
		if access_point is Dictionary:
			return String(access_point.get("id", "main_entry"))
	return "main_entry"

func _get_entry_direction(site: SiteSpec, entry_point_id: String) -> String:
	var access_point: Dictionary = site.get_access_point(entry_point_id)
	if not access_point.is_empty():
		return String(access_point.get("direction", ""))
	return ""

func _resolve_overland_return_position(site: SiteSpec, entry_point_id: String) -> Vector2:
	var access_point: Dictionary = site.get_access_point(entry_point_id)
	var direction: String = String(access_point.get("direction", ""))
	var offset: Vector2 = Vector2.ZERO
	if direction == "north":
		offset = Vector2(0, -96)
	elif direction == "south":
		offset = Vector2(0, 96)
	elif direction == "west":
		offset = Vector2(-96, 0)
	elif direction == "east":
		offset = Vector2(96, 0)
	else:
		offset = Vector2(0, 96)
	return site.position + offset

func _resolve_context_return_position(context) -> Vector2:
	if context.overland_return_position != Vector2.ZERO:
		return context.overland_return_position
	if context.overland_return_pos != Vector2i.ZERO:
		return Vector2(context.overland_return_pos)
	if active_world_spec != null:
		var site: SiteSpec = active_world_spec.get_site_by_id(context.site_id)
		if site != null:
			return site.position
	return Vector2.ZERO
