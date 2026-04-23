class_name ProcgenValidation
extends RefCounted


static func require_non_empty(value: String, field_name: String, errors: PackedStringArray) -> void:
	if value == "":
		errors.append(field_name + " is required.")


static func require_nonzero_int(value: int, field_name: String, errors: PackedStringArray) -> void:
	if value == 0:
		errors.append(field_name + " must be nonzero.")


static func require_positive_rect(rect: Rect2, field_name: String, errors: PackedStringArray) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		errors.append(field_name + " must have a positive size.")


static func require_min_lte_max(min_value: int, max_value: int, field_name: String, errors: PackedStringArray) -> void:
	if max_value == 0:
		return
	if min_value > max_value:
		errors.append(field_name + " min cannot be greater than max.")
