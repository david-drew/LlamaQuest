class_name OverlandView
extends Node2D

signal site_enter_requested(site: SiteSpec)

const SITE_COLOR_BY_TYPE := {
	"town": Color.DARK_ORANGE,
	"dungeon": Color.DARK_SLATE_BLUE,
	"wilderness_site": Color.DARK_SEA_GREEN
}

var world_spec: WorldSpec

func build_from_spec(spec: WorldSpec) -> void:
	world_spec = spec
	_clear_existing()
	_build_background(spec)
	_build_sites(spec)

func _clear_existing() -> void:
	for child in get_children():
		child.queue_free()

func _build_background(spec: WorldSpec) -> void:
	for region in spec.regions:
		var region_poly := Polygon2D.new()
		region_poly.polygon = _make_ellipse(region.radius)
		region_poly.position = region.center
		region_poly.color = _get_region_color(region.region_type)
		region_poly.z_index = -20
		add_child(region_poly)

	for network in spec.networks:
		var line := Line2D.new()
		line.points = network.points
		line.width = _get_network_width(network.network_type)
		line.default_color = _get_network_color(network.network_type)
		line.z_index = -10
		add_child(line)

func _build_sites(spec: WorldSpec) -> void:
	for site in spec.sites:
		var root := Node2D.new()
		root.name = site.site_id
		root.position = site.position
		add_child(root)

		var marker := Polygon2D.new()
		marker.polygon = _make_centered_rect(Vector2(42, 42))
		marker.color = SITE_COLOR_BY_TYPE.get(site.site_type, Color.GRAY)
		marker.z_index = 10
		root.add_child(marker)

		var label := Label.new()
		label.text = "%s (%s)" % [site.display_name, site.site_type]
		label.position = Vector2(-68, 30)
		root.add_child(label)

		var enter_zone := Area2D.new()
		enter_zone.name = "EnterZone"
		enter_zone.collision_layer = 16
		enter_zone.collision_mask = 2
		enter_zone.monitoring = true
		enter_zone.monitorable = true
		root.add_child(enter_zone)

		var zone_shape := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 48
		zone_shape.shape = shape
		enter_zone.add_child(zone_shape)

		var zone_visual := Polygon2D.new()
		zone_visual.polygon = _make_centered_rect(Vector2(96, 96))
		zone_visual.color = Color(1.0, 1.0, 1.0, 0.10)
		zone_visual.z_index = 9
		root.add_child(zone_visual)

		enter_zone.body_entered.connect(_on_enter_zone_body_entered.bind(site))

func _on_enter_zone_body_entered(body: Node2D, site: SiteSpec) -> void:
	if body.name != "Player":
		return
	site_enter_requested.emit(site)

func _get_region_color(region_type: String) -> Color:
	if region_type == "forest":
		return Color(0.24, 0.45, 0.24, 0.62)
	if region_type == "lake":
		return Color(0.20, 0.45, 0.70, 0.64)
	return Color(0.4, 0.4, 0.4, 0.4)

func _get_network_color(network_type: String) -> Color:
	if network_type == "river":
		return Color(0.14, 0.42, 0.85, 0.88)
	if network_type == "road":
		return Color(0.66, 0.58, 0.44, 0.88)
	return Color.WHITE

func _get_network_width(network_type: String) -> float:
	if network_type == "river":
		return 16.0
	if network_type == "road":
		return 10.0
	return 8.0

func _make_ellipse(radius: Vector2, points: int = 28) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in range(points):
		var angle := TAU * (float(i) / float(points))
		poly.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return poly

func _make_centered_rect(size: Vector2) -> PackedVector2Array:
	var half := size / 2.0
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])
