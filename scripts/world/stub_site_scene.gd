extends Node2D

@export var site_type: String = "dungeon"
@export var title: String = "Stub Site"
@export var clear_color: Color = Color.DIM_GRAY
var entry_context

func _ready() -> void:
	RenderingServer.set_default_clear_color(clear_color)
	_build_stub_layout()

func _build_stub_layout() -> void:
	var floor := Polygon2D.new()
	floor.polygon = _make_centered_rect(Vector2(1800, 1200))
	floor.color = clear_color.darkened(0.1)
	floor.z_index = -5
	add_child(floor)

	var title_label := Label.new()
	title_label.text = "%s (%s)" % [title, site_type]
	title_label.position = Vector2(-120, -120)
	add_child(title_label)

	var hint_label := Label.new()
	hint_label.text = "Walk into the cyan zone to return to overland."
	hint_label.position = Vector2(-220, -92)
	add_child(hint_label)

	if entry_context != null:
		var context_label := Label.new()
		context_label.text = "Site: %s | Seed: %d" % [entry_context.site_id, entry_context.site_seed]
		context_label.position = Vector2(-220, -64)
		add_child(context_label)

func configure_entry_context(context) -> void:
	entry_context = context

func _make_centered_rect(size: Vector2) -> PackedVector2Array:
	var half := size / 2.0
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])
