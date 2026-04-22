extends Node2D

signal exit_requested

const MAP_SIZE := Vector2(2000, 1300)
const TRANSITION_CONTEXT_SCRIPT := preload("res://scripts/world/transition_context.gd")

@export var base_title: String = "Wilderness Site"

var entry_context

func configure_entry_context(context) -> void:
	if context != null and context is TRANSITION_CONTEXT_SCRIPT:
		entry_context = context
	else:
		entry_context = null

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.21, 0.30, 0.18, 1.0))
	_build_layout()

func get_entry_spawn_position() -> Vector2:
	return Vector2(0, MAP_SIZE.y * 0.36)

func _build_layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _get_deterministic_seed()

	var ground := Polygon2D.new()
	ground.polygon = _make_centered_rect(MAP_SIZE)
	ground.color = Color(0.27, 0.40, 0.22, 1.0)
	ground.z_index = -20
	add_child(ground)

	var clearing := Polygon2D.new()
	clearing.polygon = _make_ellipse(Vector2(520, 330))
	clearing.color = Color(0.38, 0.50, 0.29, 1.0)
	clearing.z_index = -15
	add_child(clearing)

	_add_tree_ring(rng)
	_add_rocks(rng)
	_add_labels()
	_add_exit_affordance()

func _add_tree_ring(rng: RandomNumberGenerator) -> void:
	for _i in range(24):
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(380.0, 760.0)
		var pos := Vector2(cos(angle), sin(angle)) * dist

		var tree := Polygon2D.new()
		tree.polygon = _make_ellipse(Vector2(rng.randf_range(16.0, 30.0), rng.randf_range(20.0, 34.0)), 18)
		tree.position = pos
		tree.color = Color(0.13, 0.28, 0.14, 1.0)
		tree.z_index = -6
		add_child(tree)

func _add_rocks(rng: RandomNumberGenerator) -> void:
	for _i in range(8):
		var pos := Vector2(
			rng.randf_range(-780.0, 780.0),
			rng.randf_range(-440.0, 440.0)
		)
		if pos.distance_to(Vector2.ZERO) < 260.0:
			pos += Vector2(180, 180)

		var rock := Polygon2D.new()
		rock.polygon = _make_centered_rect(Vector2(rng.randf_range(24.0, 56.0), rng.randf_range(18.0, 42.0)))
		rock.position = pos
		rock.color = Color(0.42, 0.42, 0.40, 1.0)
		rock.z_index = -8
		add_child(rock)

func _add_labels() -> void:
	var title_label := Label.new()
	title_label.text = _get_title_text()
	title_label.position = Vector2(-220, -110)
	add_child(title_label)

	var hint_label := Label.new()
	hint_label.text = "Outdoor clearing stub. Walk to south cyan zone to return."
	hint_label.position = Vector2(-320, -84)
	add_child(hint_label)

func _add_exit_affordance() -> void:
	var exit_root := Node2D.new()
	exit_root.name = "WildernessExit"
	exit_root.position = Vector2(0, MAP_SIZE.y * 0.44)
	add_child(exit_root)

	var exit_area := Area2D.new()
	exit_area.name = "ExitArea"
	exit_area.collision_layer = 16
	exit_area.collision_mask = 2
	exit_area.monitoring = true
	exit_area.monitorable = true
	exit_root.add_child(exit_area)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(260, 72)
	collision.shape = shape
	exit_area.add_child(collision)

	var visual := Polygon2D.new()
	visual.polygon = _make_centered_rect(Vector2(260, 72))
	visual.color = Color(0.20, 0.90, 1.0, 0.35)
	visual.z_index = 2
	exit_root.add_child(visual)

	var label := Label.new()
	label.text = "Exit to Overland"
	label.position = Vector2(-58, 46)
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
	return "%s: %s (%d)" % [base_title, entry_context.site_id, entry_context.site_seed]

func _make_centered_rect(size: Vector2) -> PackedVector2Array:
	var half := size / 2.0
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])

func _make_ellipse(radius: Vector2, points: int = 28) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in range(points):
		var angle := TAU * (float(i) / float(points))
		poly.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return poly
