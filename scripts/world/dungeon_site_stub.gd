extends Node2D

signal exit_requested

const MAP_SIZE := Vector2(1800, 1200)
const TRANSITION_CONTEXT_SCRIPT := preload("res://scripts/world/transition_context.gd")

@export var base_title: String = "Dungeon Stub"

var entry_context

func configure_entry_context(context) -> void:
	if context != null and context is TRANSITION_CONTEXT_SCRIPT:
		entry_context = context
	else:
		entry_context = null

func _ready() -> void:
	RenderingServer.set_default_clear_color(_get_theme_clear_color())
	_build_layout()

func get_entry_spawn_position() -> Vector2:
	return Vector2(0, MAP_SIZE.y * 0.34)

func _build_layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _get_deterministic_seed()

	var floor := Polygon2D.new()
	floor.polygon = _make_centered_rect(MAP_SIZE)
	floor.color = _get_theme_floor_color()
	floor.z_index = -30
	add_child(floor)

	var chamber_size := Vector2(980, 620)
	var chamber := Polygon2D.new()
	chamber.polygon = _make_centered_rect(chamber_size)
	chamber.color = _get_theme_chamber_color()
	chamber.z_index = -22
	add_child(chamber)

	_add_wall_frame(chamber_size)
	_add_side_alcoves(rng)
	_add_pillars(rng)
	_add_labels()
	_add_exit_affordance()

func _add_wall_frame(chamber_size: Vector2) -> void:
	var half := chamber_size / 2.0
	var wall_thickness := 38.0

	_add_wall_rect(Vector2(0, -half.y), Vector2(chamber_size.x + wall_thickness * 2.0, wall_thickness))
	_add_wall_rect(Vector2(0, half.y), Vector2(chamber_size.x + wall_thickness * 2.0, wall_thickness))
	_add_wall_rect(Vector2(-half.x, 0), Vector2(wall_thickness, chamber_size.y))
	_add_wall_rect(Vector2(half.x, 0), Vector2(wall_thickness, chamber_size.y))

func _add_wall_rect(position: Vector2, size: Vector2) -> void:
	var wall := Polygon2D.new()
	wall.polygon = _make_centered_rect(size)
	wall.position = position
	wall.color = Color(0.11, 0.12, 0.14, 1.0)
	wall.z_index = -18
	add_child(wall)

func _add_side_alcoves(rng: RandomNumberGenerator) -> void:
	for i in range(3):
		var y := -230.0 + float(i) * 230.0 + rng.randf_range(-20.0, 20.0)
		var left_alcove := Polygon2D.new()
		left_alcove.polygon = _make_centered_rect(Vector2(140, 110))
		left_alcove.position = Vector2(-430, y)
		left_alcove.color = Color(0.16, 0.17, 0.20, 1.0)
		left_alcove.z_index = -20
		add_child(left_alcove)

		var right_alcove := Polygon2D.new()
		right_alcove.polygon = _make_centered_rect(Vector2(140, 110))
		right_alcove.position = Vector2(430, y + rng.randf_range(-12.0, 12.0))
		right_alcove.color = Color(0.16, 0.17, 0.20, 1.0)
		right_alcove.z_index = -20
		add_child(right_alcove)

func _add_pillars(rng: RandomNumberGenerator) -> void:
	for x in [-220.0, 0.0, 220.0]:
		for y in [-150.0, 90.0]:
			var pillar := Polygon2D.new()
			var radius := Vector2(26.0 + rng.randf_range(-4.0, 6.0), 24.0 + rng.randf_range(-3.0, 5.0))
			pillar.polygon = _make_ellipse(radius, 16)
			pillar.position = Vector2(x + rng.randf_range(-8.0, 8.0), y + rng.randf_range(-8.0, 8.0))
			pillar.color = Color(0.34, 0.34, 0.37, 1.0)
			pillar.z_index = -10
			add_child(pillar)

func _add_labels() -> void:
	var title_label := Label.new()
	title_label.text = _get_title_text()
	title_label.position = Vector2(-240, -84)
	add_child(title_label)

	var hint_label := Label.new()
	hint_label.text = _get_flavor_hint_text()
	hint_label.position = Vector2(-320, -58)
	add_child(hint_label)

func _add_exit_affordance() -> void:
	var exit_root := Node2D.new()
	exit_root.name = "DungeonExit"
	exit_root.position = Vector2(0, -MAP_SIZE.y * 0.40)
	add_child(exit_root)

	var stairs := Polygon2D.new()
	stairs.polygon = _make_centered_rect(Vector2(240, 86))
	stairs.color = Color(0.14, 0.16, 0.18, 1.0)
	stairs.z_index = -8
	exit_root.add_child(stairs)

	var exit_area := Area2D.new()
	exit_area.name = "ExitArea"
	exit_area.collision_layer = 16
	exit_area.collision_mask = 2
	exit_area.monitoring = true
	exit_area.monitorable = true
	exit_root.add_child(exit_area)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(240, 86)
	collision.shape = shape
	exit_area.add_child(collision)

	var glow := Polygon2D.new()
	glow.polygon = _make_centered_rect(Vector2(240, 86))
	glow.color = Color(0.20, 0.90, 1.0, 0.35)
	glow.z_index = 2
	exit_root.add_child(glow)

	var label := Label.new()
	label.text = "Stairs to Overland"
	label.position = Vector2(-60, 54)
	exit_root.add_child(label)

	exit_area.body_entered.connect(_on_exit_body_entered)

func _on_exit_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	call_deferred("_emit_exit_requested")

func _emit_exit_requested() -> void:
	exit_requested.emit()

func _get_deterministic_seed() -> int:
	if entry_context == null:
		return 0
	return int(entry_context.site_seed) ^ int(entry_context.site_id.hash())

func _get_title_text() -> String:
	if entry_context == null:
		return base_title
	var subtype := _get_site_subtype()
	if subtype == "":
		return "%s: %s (%d)" % [base_title, entry_context.site_id, entry_context.site_seed]
	return "%s [%s]: %s (%d)" % [base_title, subtype, entry_context.site_id, entry_context.site_seed]

func _get_site_subtype() -> String:
	if entry_context == null:
		return ""
	return String(entry_context.site_subtype)

func _get_theme_clear_color() -> Color:
	if _get_site_subtype() == "crypt":
		return Color(0.07, 0.09, 0.12, 1.0)
	return Color(0.10, 0.11, 0.15, 1.0)

func _get_theme_floor_color() -> Color:
	if _get_site_subtype() == "crypt":
		return Color(0.16, 0.18, 0.20, 1.0)
	return Color(0.19, 0.20, 0.23, 1.0)

func _get_theme_chamber_color() -> Color:
	if _get_site_subtype() == "crypt":
		return Color(0.22, 0.24, 0.27, 1.0)
	return Color(0.26, 0.27, 0.31, 1.0)

func _get_flavor_hint_text() -> String:
	var subtype := _get_site_subtype()
	if subtype == "crypt":
		return "Crypt-like interior stub. Walk north to cyan stairway to return."
	return "Interior dungeon stub. Walk north to cyan stairway to return."

func _make_centered_rect(size: Vector2) -> PackedVector2Array:
	var half := size / 2.0
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])

func _make_ellipse(radius: Vector2, points: int = 24) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in range(points):
		var angle := TAU * (float(i) / float(points))
		poly.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return poly
