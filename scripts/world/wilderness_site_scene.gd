extends Node2D

signal exit_requested

const WILDERNESS_SITE_GENERATOR_SCRIPT := preload("res://scripts/worldgen/wilderness_site_generator.gd")
const WILDERNESS_SITE_RENDERER_SCRIPT := preload("res://scripts/world/wilderness_site_placeholder_renderer.gd")

@export var base_title: String = "Wilderness Site"
@export var show_wilderness_debug: bool = true

var entry_context
var site_spec: SiteSpec
var site_delta: SiteRuntimeDelta
var layout: WildernessSiteLayout
var renderer: WildernessSitePlaceholderRenderer
var traversal_anchors: Dictionary = {}


func setup_from_site_spec(spec: SiteSpec, transition, runtime_state: WorldRuntimeState) -> void:
	configure_entry_context(transition)
	site_spec = spec
	if runtime_state != null and runtime_state.site_deltas.has(spec.site_id):
		site_delta = runtime_state.site_deltas[spec.site_id]


func configure_site_runtime(context, spec: SiteSpec, delta: SiteRuntimeDelta) -> void:
	configure_entry_context(context)
	site_spec = spec
	site_delta = delta


func configure_entry_context(context) -> void:
	if context != null and context is TransitionContext:
		entry_context = context
	else:
		entry_context = null


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.19, 0.27, 0.17, 1.0))
	_build_layout()
	_build_traversal_anchors()
	_render_layout()
	_add_labels()
	_add_exit_affordance()


func resolve_spawn_anchor(transition) -> Node2D:
	_ensure_ready_layout()
	var anchor_id: String = _resolve_entry_anchor_id(transition)
	if traversal_anchors.has(anchor_id):
		var anchor: Node2D = traversal_anchors[anchor_id] as Node2D
		print("WildernessSiteScene: Resolved spawn anchor '" + anchor_id + "' at " + str(anchor.global_position) + ".")
		return anchor
	if traversal_anchors.has("default_entry"):
		push_warning("WildernessSiteScene: Missing requested spawn anchor '" + anchor_id + "'; using default_entry.")
		return traversal_anchors["default_entry"] as Node2D
	push_warning("WildernessSiteScene: No wilderness spawn anchor exists.")
	return null


func resolve_spawn_position(transition) -> Vector2:
	var anchor: Node2D = resolve_spawn_anchor(transition)
	if anchor != null:
		return anchor.global_position
	return Vector2.ZERO


func get_entry_spawn_position() -> Vector2:
	_ensure_ready_layout()
	var anchor: Dictionary = layout.get_default_entry_anchor()
	return anchor.get("position", Vector2.ZERO)


func prepare_for_exit(exit_point_id: String) -> Dictionary:
	_ensure_ready_layout()
	var anchor: Dictionary = _resolve_exit_anchor(exit_point_id)
	return {
		"exit_point_id": String(anchor.get("id", exit_point_id)),
		"local_exit_position": anchor.get("position", Vector2.ZERO)
	}


func _build_layout() -> void:
	var generator: WildernessSiteGenerator = WILDERNESS_SITE_GENERATOR_SCRIPT.new()
	if site_spec == null:
		site_spec = _make_standalone_site_spec()
	layout = generator.build_from_site_spec(site_spec)
	if layout.has_validation_errors():
		push_warning("WildernessSiteScene: Layout validation failed: " + _join_errors(layout.validation_errors))


func _render_layout() -> void:
	renderer = WILDERNESS_SITE_RENDERER_SCRIPT.new()
	renderer.name = "WildernessSiteVisualRoot"
	add_child(renderer)
	renderer.set_debug_options({
		"show_bounds": show_wilderness_debug,
		"show_anchors": show_wilderness_debug,
		"show_paths": true,
		"show_blockers": true,
		"show_open_regions": true,
		"show_poi": true
	})
	renderer.render_site(site_spec, layout)


func _build_traversal_anchors() -> void:
	traversal_anchors.clear()
	if layout == null:
		return
	for anchor in layout.entry_anchors:
		if anchor is Dictionary:
			_add_anchor_node(anchor)
	for anchor in layout.exit_anchors:
		if anchor is Dictionary:
			_add_anchor_node(anchor)


func _add_anchor_node(anchor: Dictionary) -> void:
	var anchor_id: String = String(anchor.get("id", ""))
	if anchor_id == "":
		return
	if traversal_anchors.has(anchor_id):
		return
	var node: Node2D = Node2D.new()
	node.name = anchor_id
	node.position = anchor.get("position", Vector2.ZERO)
	add_child(node)
	traversal_anchors[anchor_id] = node


func _add_labels() -> void:
	var title_label: Label = Label.new()
	title_label.text = _get_title_text()
	title_label.position = Vector2(-260, -layout.site_bounds.size.y * 0.5 + 62)
	add_child(title_label)

	var hint_label: Label = Label.new()
	hint_label.text = "Wilderness site. Follow the trail; cyan/yellow markers show entry and exit."
	hint_label.position = title_label.position + Vector2(0, 26)
	add_child(hint_label)


func _add_exit_affordance() -> void:
	var exit_anchor: Dictionary = layout.get_default_exit_anchor()
	var exit_root: Node2D = Node2D.new()
	exit_root.name = "WildernessExit"
	exit_root.position = exit_anchor.get("position", Vector2.ZERO)
	add_child(exit_root)

	var exit_area: Area2D = Area2D.new()
	exit_area.name = "ExitArea"
	exit_area.collision_layer = 16
	exit_area.collision_mask = 2
	exit_area.monitoring = true
	exit_area.monitorable = true
	exit_root.add_child(exit_area)

	var collision: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(260, 78)
	collision.shape = shape
	exit_area.add_child(collision)

	var visual: Polygon2D = Polygon2D.new()
	visual.polygon = _make_centered_rect(Vector2(260, 78))
	visual.color = Color(0.20, 0.90, 1.0, 0.28)
	exit_root.add_child(visual)

	var label: Label = Label.new()
	label.text = "Exit to Overland"
	label.position = Vector2(-62, 48)
	exit_root.add_child(label)
	exit_area.body_entered.connect(_on_exit_body_entered)


func _on_exit_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	call_deferred("_emit_exit_requested")


func _emit_exit_requested() -> void:
	exit_requested.emit()


func _ensure_ready_layout() -> void:
	if layout == null:
		_build_layout()
	if traversal_anchors.is_empty():
		_build_traversal_anchors()


func _resolve_entry_anchor_id(transition) -> String:
	if transition != null:
		if String(transition.entry_point_id) != "":
			return String(transition.entry_point_id)
		if transition.spawn_hint.has("preferred_gate_id") and String(transition.spawn_hint["preferred_gate_id"]) != "":
			return String(transition.spawn_hint["preferred_gate_id"])
		if transition.spawn_hint.has("preferred_spawn_tag") and String(transition.spawn_hint["preferred_spawn_tag"]) != "":
			return String(transition.spawn_hint["preferred_spawn_tag"])
	return "default_entry"


func _resolve_exit_anchor(exit_point_id: String) -> Dictionary:
	if exit_point_id != "":
		var anchor: Dictionary = layout.get_exit_anchor(exit_point_id)
		if not anchor.is_empty():
			return anchor
	return layout.get_default_exit_anchor()


func _make_standalone_site_spec() -> SiteSpec:
	var spec: SiteSpec = SiteSpec.new("standalone_wilderness", "wilderness_site", base_title, Vector2.ZERO, 1, "wilderness_site_generator_v1")
	spec.subtype = "forest_clearing"
	spec.generator_id = "wilderness_site_generator_v1"
	spec.biome = "temperate_forest"
	spec.access_points = [
		{
			"id": "trail_entry_south",
			"kind": "trail_entry",
			"type": "trail_entry",
			"direction": "south"
		}
	]
	spec.generation_params = {
		"site_radius_tier": "small",
		"blocker_density": "medium",
		"poi_type": "standing_stones",
		"has_side_path": true,
		"ground_cover": "forest_floor",
		"feature_profile": "default_forest_clearing"
	}
	return spec


func _get_title_text() -> String:
	if site_spec == null:
		return base_title
	var visited_text: String = ""
	if site_delta != null and site_delta.visited:
		visited_text = " (visited)"
	return "%s [%s] seed=%s%s" % [
		site_spec.display_name,
		site_spec.subtype,
		str(site_spec.seed),
		visited_text
	]


func _join_errors(errors: PackedStringArray) -> String:
	var output: String = ""
	for i in range(errors.size()):
		if i > 0:
			output += "; "
		output += errors[i]
	return output


func _make_centered_rect(size: Vector2) -> PackedVector2Array:
	var half: Vector2 = size / 2.0
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])
