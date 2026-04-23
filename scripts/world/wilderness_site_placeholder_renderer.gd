class_name WildernessSitePlaceholderRenderer
extends Node2D

var site_spec: SiteSpec
var layout: WildernessSiteLayout
var debug_options: Dictionary = {
	"show_bounds": true,
	"show_anchors": true,
	"show_paths": true,
	"show_blockers": true,
	"show_open_regions": true,
	"show_poi": true
}


func render_site(p_site_spec: SiteSpec, p_layout: WildernessSiteLayout) -> void:
	site_spec = p_site_spec
	layout = p_layout
	queue_redraw()


func set_debug_options(options: Dictionary) -> void:
	for key in options.keys():
		debug_options[String(key)] = options[key]
	queue_redraw()


func _draw() -> void:
	if layout == null:
		return
	_draw_ground()
	_draw_open_regions()
	_draw_paths()
	_draw_blockers()
	_draw_pois()
	_draw_anchors()
	_draw_debug_bounds()


func _draw_ground() -> void:
	draw_rect(layout.site_bounds, _ground_color(), true)


func _draw_open_regions() -> void:
	if not bool(debug_options.get("show_open_regions", true)):
		return
	for region in layout.open_regions:
		if not (region is Dictionary):
			continue
		var rect: Rect2 = region.get("rect", Rect2())
		draw_rect(rect, Color(0.40, 0.52, 0.29, 1.0), true)
		draw_rect(rect, Color(0.23, 0.34, 0.18, 0.55), false, 2.0)


func _draw_paths() -> void:
	if not bool(debug_options.get("show_paths", true)):
		return
	for path in layout.paths:
		if not (path is Dictionary):
			continue
		var points: PackedVector2Array = path.get("points", PackedVector2Array())
		if points.size() < 2:
			continue
		var width: float = float(path.get("width", 52.0))
		draw_polyline(points, Color(0.48, 0.38, 0.21, 1.0), width, true)
		draw_polyline(points, Color(0.64, 0.54, 0.34, 1.0), max(6.0, width * 0.28), true)


func _draw_blockers() -> void:
	if not bool(debug_options.get("show_blockers", true)):
		return
	for blocker in layout.blocker_regions:
		if not (blocker is Dictionary):
			continue
		var rect: Rect2 = blocker.get("rect", Rect2())
		var blocker_type: String = String(blocker.get("type", "tree_cluster"))
		if blocker_type == "water":
			draw_rect(rect, Color(0.12, 0.34, 0.58, 1.0), true)
			continue
		if blocker_type == "rock_cluster":
			draw_rect(rect, Color(0.36, 0.36, 0.34, 1.0), true)
			draw_rect(rect, Color(0.20, 0.20, 0.19, 0.8), false, 2.0)
			continue
		draw_rect(rect, Color(0.11, 0.27, 0.12, 1.0), true)
		draw_rect(rect.grow(-10.0), Color(0.16, 0.34, 0.16, 1.0), true)


func _draw_pois() -> void:
	if not bool(debug_options.get("show_poi", true)):
		return
	var font: Font = ThemeDB.fallback_font
	for poi in layout.points_of_interest:
		if not (poi is Dictionary):
			continue
		var position: Vector2 = poi.get("position", Vector2.ZERO)
		var radius: float = float(poi.get("radius", 46.0))
		draw_circle(position, radius, Color(0.64, 0.58, 0.43, 1.0))
		draw_circle(position, radius * 0.45, Color(0.28, 0.25, 0.20, 1.0))
		draw_string(font, position + Vector2(-70, radius + 20), String(poi.get("type", "poi")), HORIZONTAL_ALIGNMENT_CENTER, 140.0, 13, Color.WHITE)


func _draw_anchors() -> void:
	if not bool(debug_options.get("show_anchors", true)):
		return
	for anchor in layout.entry_anchors:
		if anchor is Dictionary:
			var entry_pos: Vector2 = anchor.get("position", Vector2.ZERO)
			draw_circle(entry_pos, 18.0, Color(0.20, 0.90, 1.0, 1.0))
	for anchor in layout.exit_anchors:
		if anchor is Dictionary:
			var exit_pos: Vector2 = anchor.get("position", Vector2.ZERO)
			draw_circle(exit_pos, 14.0, Color(1.0, 0.86, 0.25, 1.0))


func _draw_debug_bounds() -> void:
	if bool(debug_options.get("show_bounds", false)):
		draw_rect(layout.site_bounds, Color.BLACK, false, 4.0)


func _ground_color() -> Color:
	if site_spec == null:
		return Color(0.23, 0.34, 0.20, 1.0)
	if site_spec.subtype == "roadside_glade":
		return Color(0.30, 0.36, 0.22, 1.0)
	if site_spec.subtype == "lakeshore_site":
		return Color(0.24, 0.36, 0.26, 1.0)
	return Color(0.21, 0.31, 0.18, 1.0)
