class_name BuildingTypeDefinition
extends Resource

@export var id: String = ""
@export var version: int = 1
@export var tags: PackedStringArray = []
@export var lot_rules: Dictionary = {}
@export var footprint_rules: Dictionary = {}
@export var entrance_rules: Dictionary = {}
@export var attachment_rules: Dictionary = {}
@export var visual_rules: Dictionary = {}


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "":
		errors.append("BuildingTypeDefinition.id is required.")
	if version <= 0:
		errors.append("BuildingTypeDefinition.version must be positive.")
	return errors


func supports_district_tag(tag: String) -> bool:
	if tags.has(tag):
		return true
	var district_tags: PackedStringArray = lot_rules.get("district_tags", PackedStringArray())
	if district_tags.is_empty():
		return true
	return district_tags.has(tag)


func can_fit_lot(lot: LotInstance) -> bool:
	if lot == null:
		return false
	var min_size: Vector2 = footprint_rules.get("min_size", Vector2.ZERO)
	if min_size != Vector2.ZERO:
		if lot.build_area.size.x < min_size.x or lot.build_area.size.y < min_size.y:
			return false
	var max_size: Vector2 = footprint_rules.get("max_size", Vector2.ZERO)
	if max_size != Vector2.ZERO:
		if lot.build_area.size.x > max_size.x or lot.build_area.size.y > max_size.y:
			return false
	return true


func to_dict() -> Dictionary:
	return {
		"id": id,
		"version": version,
		"tags": tags,
		"lot_rules": lot_rules,
		"footprint_rules": footprint_rules,
		"entrance_rules": entrance_rules,
		"attachment_rules": attachment_rules,
		"visual_rules": visual_rules
	}


static func from_dict(data: Dictionary) -> BuildingTypeDefinition:
	var definition := BuildingTypeDefinition.new()
	definition.id = String(data.get("id", ""))
	definition.version = int(data.get("version", 1))
	definition.tags = data.get("tags", PackedStringArray())
	definition.lot_rules = data.get("lot_rules", {})
	definition.footprint_rules = data.get("footprint_rules", {})
	definition.entrance_rules = data.get("entrance_rules", {})
	definition.attachment_rules = data.get("attachment_rules", {})
	definition.visual_rules = data.get("visual_rules", {})
	return definition
