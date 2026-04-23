class_name TownLayoutSkeleton
extends Resource

@export var id: String = ""
@export var version: int = 1
@export var town_bounds: Rect2 = Rect2()
@export var wall: Dictionary = {}
@export var gates: Array = []
@export var roads: Array = []
@export var squares: Array = []
@export var reserved_open_areas: Array = []
@export var buildable_bands: Array = []
@export var district_hints: Array = []
@export var validation_errors: PackedStringArray = []


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "":
		errors.append("TownLayoutSkeleton.id is required.")
	if version <= 0:
		errors.append("TownLayoutSkeleton.version must be positive.")
	if town_bounds.size.x <= 0.0 or town_bounds.size.y <= 0.0:
		errors.append("TownLayoutSkeleton.town_bounds must have a positive size.")
	for error in validation_errors:
		errors.append(error)
	return errors


func has_validation_errors() -> bool:
	return not validation_errors.is_empty()


func get_gate_by_id(gate_id: String) -> Dictionary:
	for gate in gates:
		if not (gate is Dictionary):
			continue
		if String(gate.get("id", "")) == gate_id:
			return gate
	return {}


func get_buildable_bands() -> Array:
	return buildable_bands


func to_dict() -> Dictionary:
	return {
		"id": id,
		"version": version,
		"town_bounds": town_bounds,
		"wall": wall,
		"gates": gates,
		"roads": roads,
		"squares": squares,
		"reserved_open_areas": reserved_open_areas,
		"buildable_bands": buildable_bands,
		"district_hints": district_hints,
		"validation_errors": validation_errors
	}


static func from_dict(data: Dictionary) -> TownLayoutSkeleton:
	var skeleton := TownLayoutSkeleton.new()
	skeleton.id = String(data.get("id", ""))
	skeleton.version = int(data.get("version", 1))
	skeleton.town_bounds = data.get("town_bounds", Rect2())
	skeleton.wall = data.get("wall", {})
	skeleton.gates = data.get("gates", [])
	skeleton.roads = data.get("roads", [])
	skeleton.squares = data.get("squares", [])
	skeleton.reserved_open_areas = data.get("reserved_open_areas", [])
	skeleton.buildable_bands = data.get("buildable_bands", [])
	skeleton.district_hints = data.get("district_hints", [])
	skeleton.validation_errors = data.get("validation_errors", PackedStringArray())
	return skeleton
