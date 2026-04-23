class_name WildernessSiteLayout
extends Resource

@export var id: String = ""
@export var version: int = 1
@export var site_bounds: Rect2 = Rect2()
@export var entry_anchors: Array = []
@export var exit_anchors: Array = []
@export var paths: Array = []
@export var blocker_regions: Array = []
@export var open_regions: Array = []
@export var points_of_interest: Array = []
@export var debug_notes: PackedStringArray = []
@export var validation_errors: PackedStringArray = []


func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == "":
		errors.append("WildernessSiteLayout.id is required.")
	if version <= 0:
		errors.append("WildernessSiteLayout.version must be positive.")
	if site_bounds.size.x <= 0.0 or site_bounds.size.y <= 0.0:
		errors.append("WildernessSiteLayout.site_bounds must have positive size.")
	if entry_anchors.is_empty():
		errors.append("WildernessSiteLayout requires at least one entry anchor.")
	if exit_anchors.is_empty():
		errors.append("WildernessSiteLayout requires at least one exit anchor.")

	for anchor in entry_anchors:
		if anchor is Dictionary:
			_validate_anchor(anchor, "entry", errors)
	for anchor in exit_anchors:
		if anchor is Dictionary:
			_validate_anchor(anchor, "exit", errors)
	for poi in points_of_interest:
		if not (poi is Dictionary):
			continue
		var pos: Vector2 = poi.get("position", Vector2.ZERO)
		if not _point_in_bounds(pos):
			errors.append("Point of interest '" + String(poi.get("id", "")) + "' is outside wilderness bounds.")
	for path in paths:
		if not (path is Dictionary):
			continue
		var points: PackedVector2Array = path.get("points", PackedVector2Array())
		for point in points:
			if not _point_in_bounds(point):
				errors.append("Path '" + String(path.get("id", "")) + "' contains an out-of-bounds point.")

	return errors


func has_validation_errors() -> bool:
	return not validation_errors.is_empty()


func get_entry_anchor(anchor_id: String) -> Dictionary:
	return _get_anchor(entry_anchors, anchor_id)


func get_exit_anchor(anchor_id: String) -> Dictionary:
	return _get_anchor(exit_anchors, anchor_id)


func get_default_entry_anchor() -> Dictionary:
	if entry_anchors.is_empty():
		return {}
	if entry_anchors[0] is Dictionary:
		return entry_anchors[0]
	return {}


func get_default_exit_anchor() -> Dictionary:
	if exit_anchors.is_empty():
		return {}
	if exit_anchors[0] is Dictionary:
		return exit_anchors[0]
	return {}


func _get_anchor(anchors: Array, anchor_id: String) -> Dictionary:
	for anchor in anchors:
		if not (anchor is Dictionary):
			continue
		if String(anchor.get("id", "")) == anchor_id:
			return anchor
	return {}


func _validate_anchor(anchor: Dictionary, label: String, errors: PackedStringArray) -> void:
	var anchor_id: String = String(anchor.get("id", ""))
	if anchor_id == "":
		errors.append(label + " anchor id is required.")
	var pos: Vector2 = anchor.get("position", Vector2.ZERO)
	if not _point_in_bounds(pos):
		errors.append(label + " anchor '" + anchor_id + "' is outside wilderness bounds.")


func _point_in_bounds(pos: Vector2) -> bool:
	if pos.x < site_bounds.position.x - 0.01:
		return false
	if pos.y < site_bounds.position.y - 0.01:
		return false
	if pos.x > site_bounds.end.x + 0.01:
		return false
	if pos.y > site_bounds.end.y + 0.01:
		return false
	return true
