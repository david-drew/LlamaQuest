class_name LotInstance
extends Resource

const STANDARD_SCORE_KEYS := [
	"gate",
	"market",
	"residential",
	"work",
	"quiet",
	"prestige",
	"edge",
	"main_road",
	"civic"
]

@export var id: String = ""
@export var version: int = 1
@export var rect: Rect2 = Rect2()
@export var build_area: Rect2 = Rect2()
@export var frontage: Dictionary = {}
@export var district_tags: PackedStringArray = []
@export var context_tags: PackedStringArray = []
@export var scores: Dictionary = {}
@export var constraints: Dictionary = {}
@export var assignment: Dictionary = {}


func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == "":
		errors.append("LotInstance.id is required.")
	if version <= 0:
		errors.append("LotInstance.version must be positive.")
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		errors.append("LotInstance.rect must have a positive size.")
	if build_area.size.x < 0.0 or build_area.size.y < 0.0:
		errors.append("LotInstance.build_area cannot have a negative size.")
	if not bool(constraints.get("blocked", false)):
		if build_area.size.x <= 0.0 or build_area.size.y <= 0.0:
			errors.append("LotInstance.build_area must have a positive size for unblocked lots.")
	if not _rect_contains_rect(rect, build_area):
		errors.append("LotInstance.build_area must be inside LotInstance.rect.")
	if String(frontage.get("side", "")) == "":
		errors.append("LotInstance.frontage.side is required.")
	if String(frontage.get("kind", "")) == "":
		errors.append("LotInstance.frontage.kind is required.")
	if String(assignment.get("status", "")) == "":
		errors.append("LotInstance.assignment.status is required.")
	var status: String = String(assignment.get("status", ""))
	if status != "unassigned" and status != "assigned" and status != "reserved" and status != "blocked":
		errors.append("LotInstance.assignment.status is invalid.")
	for score_key in STANDARD_SCORE_KEYS:
		var key: String = String(score_key)
		if not scores.has(key):
			errors.append("LotInstance.scores missing standard key '" + key + "'.")
	return errors


func is_available() -> bool:
	if bool(constraints.get("blocked", false)):
		return false
	if bool(constraints.get("reserved", false)):
		return false
	return String(assignment.get("status", "unassigned")) == "unassigned"


func has_tag(tag: String) -> bool:
	return district_tags.has(tag) or context_tags.has(tag)


func get_score(tag: String) -> float:
	return float(scores.get(tag, 0.0))


func can_host_building() -> bool:
	if bool(constraints.get("allow_building", false)) == false:
		return false
	return is_available()


func assign_building(building_type_id: String, building_instance_id: String = "") -> void:
	assignment["status"] = "assigned"
	assignment["building_type_id"] = building_type_id
	assignment["building_instance_id"] = building_instance_id


func _rect_contains_rect(outer: Rect2, inner: Rect2) -> bool:
	if inner.size.x < 0.0 or inner.size.y < 0.0:
		return false
	if inner.position.x < outer.position.x - 0.01:
		return false
	if inner.position.y < outer.position.y - 0.01:
		return false
	if inner.end.x > outer.end.x + 0.01:
		return false
	if inner.end.y > outer.end.y + 0.01:
		return false
	return true


func to_dict() -> Dictionary:
	return {
		"id": id,
		"version": version,
		"rect": rect,
		"build_area": build_area,
		"frontage": frontage,
		"district_tags": district_tags,
		"context_tags": context_tags,
		"scores": scores,
		"constraints": constraints,
		"assignment": assignment
	}


static func from_dict(data: Dictionary) -> LotInstance:
	var lot: LotInstance = LotInstance.new()
	lot.id = String(data.get("id", ""))
	lot.version = int(data.get("version", 1))
	lot.rect = data.get("rect", Rect2())
	lot.build_area = data.get("build_area", Rect2())
	lot.frontage = data.get("frontage", {})
	lot.district_tags = data.get("district_tags", PackedStringArray())
	lot.context_tags = data.get("context_tags", PackedStringArray())
	lot.scores = data.get("scores", {})
	lot.constraints = data.get("constraints", {})
	lot.assignment = data.get("assignment", {})
	return lot
