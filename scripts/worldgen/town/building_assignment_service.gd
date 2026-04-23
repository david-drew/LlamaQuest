class_name BuildingAssignmentService
extends RefCounted

const SOURCE_PROFILE_REQUIRED := "profile_required"
const SOURCE_PROFILE_OPTIONAL := "profile_optional"
const SOURCE_SPECIAL_FEATURE_REQUIRED := "special_feature_required"
const SOURCE_FALLBACK_FILL := "fallback_fill"

const STATUS_UNASSIGNED := "unassigned"
const STATUS_ASSIGNED := "assigned"
const STATUS_RESERVED := "reserved"
const STATUS_BLOCKED := "blocked"
const STATUS_EMPTY := "empty"

const WARNING_MISSING_PROFILE := "missing_profile"
const WARNING_MISSING_BUILDING_TYPE := "missing_building_type"
const WARNING_INVALID_PROFILE_FOR_TOWN := "invalid_profile_for_town"
const WARNING_UNSATISFIED_REQUIRED_BUILDING := "unsatisfied_required_building"
const WARNING_UNSATISFIED_SPECIAL_FEATURE := "unsatisfied_special_feature"
const WARNING_NO_COMPATIBLE_LOT := "no_compatible_lot"
const WARNING_FALLBACK_FILL_SKIPPED := "fallback_fill_skipped"

const FEATURE_DEFAULT_REQUIREMENTS := {
	"market_square": ["tavern", "general_store"],
	"temple": ["temple"],
	"blacksmith": ["blacksmith"],
	"stable": ["stable"]
}

const ROLE_SCORE_TAGS := {
	"tavern": ["market", "main_road", "prestige"],
	"inn": ["gate", "main_road", "prestige"],
	"general_store": ["market", "main_road", "civic"],
	"temple": ["civic", "prestige", "market"],
	"stable": ["gate", "edge", "work"],
	"guard_post": ["gate", "main_road"],
	"blacksmith": ["work", "edge"],
	"house": ["residential", "quiet"],
	"workshop": ["work", "edge"],
	"apothecary": ["market", "civic", "quiet"],
	"manor": ["prestige", "quiet", "civic"]
}

var registry: ProcgenRegistry
var warnings: Array = []
var errors: PackedStringArray = PackedStringArray()
var assignment_records: Array = []
var request_records: Array = []
var building_types: Dictionary = {}
var assigned_count: int = 0


func _init(procgen_registry: ProcgenRegistry = null) -> void:
	registry = procgen_registry


func assign_buildings(spec: SiteSpec, lots: Array[LotInstance]) -> Dictionary:
	warnings.clear()
	errors.clear()
	assignment_records.clear()
	request_records.clear()
	building_types.clear()
	assigned_count = 0

	if not _validate_inputs(spec, lots):
		return _make_result("", [], false)

	_ensure_registry()
	var profile_id: String = _get_profile_id(spec)
	var profile: BuildingProfileDefinition = registry.get_building_profile(profile_id)
	if profile == null:
		_add_warning(WARNING_MISSING_PROFILE, spec, "", "", "Building profile '" + profile_id + "' could not be resolved.")
		return _make_result(profile_id, [], false)
	if not _validate_profile(spec, profile):
		return _make_result(profile_id, [], false)

	var special_features: PackedStringArray = _get_special_features(spec)
	request_records = _build_request_list(spec, profile, special_features)
	_populate_request_fit_counts(request_records, lots)
	request_records.sort_custom(Callable(self, "_sort_requests"))

	print("BuildingAssignmentService: profile='" + profile_id + "' special_features=" + str(special_features))
	print("BuildingAssignmentService: request order=" + _request_order_debug_string(request_records))

	for request in request_records:
		_assign_request_to_best_lot(spec, profile, lots, request)

	_apply_fallback_fill(spec, profile, lots)
	_mark_unused_lots_empty(lots)
	_validate_output(spec, profile, lots)
	return _make_result(profile_id, request_records, errors.is_empty())


func _validate_inputs(spec: SiteSpec, lots: Array[LotInstance]) -> bool:
	if spec == null:
		errors.append("SiteSpec is required for building assignment.")
		return false
	if spec.site_type != "town":
		errors.append("SiteSpec.site_type must be 'town' for building assignment.")
	if _get_profile_id(spec) == "":
		errors.append("SiteSpec.generation_params.building_profile is required for building assignment.")
	if lots.is_empty():
		errors.append("Lot array cannot be empty for building assignment.")
	for lot in lots:
		if lot == null:
			errors.append("Lot array contains null LotInstance.")
			continue
		if lot.id == "":
			errors.append("Every lot must have a stable id.")
		var status: String = String(lot.assignment.get("status", STATUS_UNASSIGNED))
		if not _is_valid_assignment_status(status):
			errors.append("Lot '" + lot.id + "' has invalid assignment status '" + status + "'.")
	return errors.is_empty()


func _ensure_registry() -> void:
	if registry == null:
		registry = ProcgenRegistry.new()
	registry.ensure_loaded()


func _validate_profile(spec: SiteSpec, profile: BuildingProfileDefinition) -> bool:
	if not profile.supports_town_subtype(spec.subtype):
		_add_warning(WARNING_INVALID_PROFILE_FOR_TOWN, spec, "", "", "Profile '" + profile.id + "' does not support subtype '" + spec.subtype + "'.")
		return false
	if not profile.supports_scale(spec.scale):
		_add_warning(WARNING_INVALID_PROFILE_FOR_TOWN, spec, "", "", "Profile '" + profile.id + "' does not support this scale.")
		return false

	var valid: bool = true
	for building_type_id in _sorted_string_keys(profile.building_types):
		if not registry.has_building_type(building_type_id):
			_add_warning(WARNING_MISSING_BUILDING_TYPE, spec, "", building_type_id, "Profile references missing building type.")
			valid = false
			continue
		building_types[building_type_id] = registry.get_building_type(building_type_id)

	for building_type_id in profile.guaranteed_buildings:
		var type_id: String = String(building_type_id)
		if not registry.has_building_type(type_id):
			_add_warning(WARNING_MISSING_BUILDING_TYPE, spec, "", type_id, "Guaranteed building type is missing.")
			valid = false
		else:
			building_types[type_id] = registry.get_building_type(type_id)

	var fallback_type_id: String = String(profile.fallback_rules.get("fill_with", ""))
	if fallback_type_id != "":
		if not registry.has_building_type(fallback_type_id):
			_add_warning(WARNING_MISSING_BUILDING_TYPE, spec, "", fallback_type_id, "Fallback fill building type is missing.")
			valid = false
		else:
			building_types[fallback_type_id] = registry.get_building_type(fallback_type_id)

	return valid


func _build_request_list(spec: SiteSpec, profile: BuildingProfileDefinition, special_features: PackedStringArray) -> Array:
	var requests: Array = []
	var required_counts: Dictionary = {}
	var request_index: int = 0

	for feature_id in special_features:
		var feature_requirements: PackedStringArray = _get_feature_requirements(profile, String(feature_id), spec)
		if feature_requirements.is_empty():
			_add_warning("unknown_special_feature", spec, String(feature_id), "", "Profile has no requirement mapping for requested feature.")
		for building_type_id in feature_requirements:
			var type_id: String = String(building_type_id)
			if not registry.has_building_type(type_id):
				_add_warning(WARNING_MISSING_BUILDING_TYPE, spec, String(feature_id), type_id, "Special feature requires missing building type.")
				continue
			required_counts[type_id] = max(int(required_counts.get(type_id, 0)), 1)
			requests.append(_make_request(request_index, type_id, SOURCE_SPECIAL_FEATURE_REQUIRED, String(feature_id), 120, false))
			request_index += 1

	for building_type_id in profile.guaranteed_buildings:
		var type_id: String = String(building_type_id)
		if not registry.has_building_type(type_id):
			continue
		if int(required_counts.get(type_id, 0)) <= 0:
			required_counts[type_id] = 1
			requests.append(_make_request(request_index, type_id, SOURCE_PROFILE_REQUIRED, "", 100, true))
			request_index += 1

	for building_type_id in _sorted_string_keys(profile.building_types):
		var type_id: String = String(building_type_id)
		if not registry.has_building_type(type_id):
			continue
		var rules: Dictionary = profile.building_types[type_id]
		var min_count: int = int(rules.get("min_count", rules.get("min", 0)))
		var max_count: int = int(rules.get("max_count", rules.get("max", min_count)))
		if max_count < min_count:
			max_count = min_count
		var current_required: int = int(required_counts.get(type_id, 0))
		while current_required < min_count:
			requests.append(_make_request(request_index, type_id, SOURCE_PROFILE_REQUIRED, "", 90, true))
			request_index += 1
			current_required += 1
		required_counts[type_id] = current_required

		var target_count: int = _resolve_optional_count(spec, type_id, rules, min_count, max_count)
		var existing_count: int = _count_requests_for_type(requests, type_id)
		while existing_count < target_count:
			requests.append(_make_request(request_index, type_id, SOURCE_PROFILE_OPTIONAL, "", 40, true))
			request_index += 1
			existing_count += 1

	return requests


func _get_feature_requirements(profile: BuildingProfileDefinition, feature_id: String, spec: SiteSpec) -> PackedStringArray:
	var requirements: PackedStringArray = PackedStringArray()
	if profile.special_feature_requirements.has(feature_id):
		for building_type_id in profile.special_feature_requirements[feature_id]:
			requirements.append(String(building_type_id))
		return requirements
	if FEATURE_DEFAULT_REQUIREMENTS.has(feature_id):
		for building_type_id in FEATURE_DEFAULT_REQUIREMENTS[feature_id]:
			requirements.append(String(building_type_id))
	return requirements


func _resolve_optional_count(spec: SiteSpec, building_type_id: String, rules: Dictionary, min_count: int, max_count: int) -> int:
	if max_count <= min_count:
		return min_count
	var weight: float = clampf(float(rules.get("weight", 1.0)), 0.0, 2.0)
	var rng: RandomNumberGenerator = _make_rng(spec.seed, "building_counts:" + building_type_id)
	var t: float = clampf((rng.randf() + (weight * 0.5)) / 1.5, 0.0, 1.0)
	var extra: int = int(round(float(max_count - min_count) * t))
	return int(clamp(min_count + extra, min_count, max_count))


func _populate_request_fit_counts(requests: Array, lots: Array[LotInstance]) -> void:
	for request in requests:
		var building_type_id: String = String(request.get("building_type_id", ""))
		var building_type: BuildingTypeDefinition = _get_building_type(building_type_id)
		var compatible_count: int = 0
		for lot in lots:
			if _is_lot_compatible(lot, building_type):
				compatible_count += 1
		request["compatible_count"] = compatible_count
		request["min_footprint_area"] = _get_min_footprint(building_type).x * _get_min_footprint(building_type).y


func _assign_request_to_best_lot(spec: SiteSpec, profile: BuildingProfileDefinition, lots: Array[LotInstance], request: Dictionary) -> void:
	var building_type_id: String = String(request.get("building_type_id", ""))
	var building_type: BuildingTypeDefinition = _get_building_type(building_type_id)
	var best_lot: LotInstance = null
	var best_score: float = -1.0
	var best_tie_break: float = 0.0

	for lot in lots:
		if not _is_lot_compatible(lot, building_type):
			continue
		var score: float = _score_lot_for_building(spec, profile, lot, building_type, request)
		var tie_break: float = _tie_break_value(spec.seed, String(request.get("request_id", "")), lot.id)
		if best_lot == null or score > best_score:
			best_lot = lot
			best_score = score
			best_tie_break = tie_break
		elif is_equal_approx(score, best_score):
			if lot.id < best_lot.id:
				best_lot = lot
				best_tie_break = tie_break
			elif lot.id == best_lot.id and tie_break > best_tie_break:
				best_lot = lot
				best_tie_break = tie_break

	if best_lot == null:
		_warn_unsatisfied_request(spec, request, building_type_id)
		return

	var instance_id: String = _make_building_instance_id(spec, assigned_count)
	best_lot.assign_building(building_type_id, instance_id)
	best_lot.assignment["request_id"] = String(request.get("request_id", ""))
	best_lot.assignment["request_source"] = String(request.get("request_source", ""))
	best_lot.assignment["special_feature"] = String(request.get("special_feature", ""))
	best_lot.assignment["fit_score"] = best_score
	best_lot.assignment["accent"] = String(building_type.visual_rules.get("accent", ""))
	best_lot.assignment["display_name"] = String(building_type.visual_rules.get("display_name", building_type_id.capitalize()))
	assignment_records.append({
		"building_instance_id": instance_id,
		"building_type_id": building_type_id,
		"lot_id": best_lot.id,
		"request_source": String(request.get("request_source", "")),
		"special_feature": String(request.get("special_feature", "")),
		"score": best_score
	})
	assigned_count += 1


func _apply_fallback_fill(spec: SiteSpec, profile: BuildingProfileDefinition, lots: Array[LotInstance]) -> void:
	var fallback_type_id: String = String(profile.fallback_rules.get("fill_with", ""))
	if fallback_type_id == "":
		_add_warning(WARNING_FALLBACK_FILL_SKIPPED, spec, "", "", "Profile fallback_rules.fill_with is not set.")
		return
	var fallback_type: BuildingTypeDefinition = _get_building_type(fallback_type_id)
	if fallback_type == null:
		_add_warning(WARNING_FALLBACK_FILL_SKIPPED, spec, "", fallback_type_id, "Fallback type is unavailable.")
		return

	var compatible_lots: Array[LotInstance] = []
	for lot in lots:
		if _is_lot_compatible(lot, fallback_type):
			compatible_lots.append(lot)
	if compatible_lots.is_empty():
		_add_warning(WARNING_FALLBACK_FILL_SKIPPED, spec, "", fallback_type_id, "No compatible lots remain for fallback fill.")
		return

	compatible_lots.sort_custom(Callable(self, "_sort_lots_by_id"))
	var leave_fraction: float = clampf(float(profile.fallback_rules.get("leave_empty_fraction", 0.18)), 0.10, 0.25)
	var fill_limit: int = int(floor(float(compatible_lots.size()) * (1.0 - leave_fraction)))
	var max_fill: int = int(profile.fallback_rules.get("max_fill", fill_limit))
	fill_limit = min(fill_limit, max_fill)
	for i in range(fill_limit):
		var lot: LotInstance = compatible_lots[i]
		var request: Dictionary = _make_request(10000 + i, fallback_type_id, SOURCE_FALLBACK_FILL, "", 5, true)
		var score: float = _score_lot_for_building(spec, profile, lot, fallback_type, request)
		var instance_id: String = _make_building_instance_id(spec, assigned_count)
		lot.assign_building(fallback_type_id, instance_id)
		lot.assignment["request_id"] = String(request.get("request_id", ""))
		lot.assignment["request_source"] = SOURCE_FALLBACK_FILL
		lot.assignment["special_feature"] = ""
		lot.assignment["fit_score"] = score
		lot.assignment["accent"] = String(fallback_type.visual_rules.get("accent", ""))
		lot.assignment["display_name"] = String(fallback_type.visual_rules.get("display_name", fallback_type_id.capitalize()))
		assignment_records.append({
			"building_instance_id": instance_id,
			"building_type_id": fallback_type_id,
			"lot_id": lot.id,
			"request_source": SOURCE_FALLBACK_FILL,
			"special_feature": "",
			"score": score
		})
		assigned_count += 1


func _mark_unused_lots_empty(lots: Array[LotInstance]) -> void:
	for lot in lots:
		if String(lot.assignment.get("status", STATUS_UNASSIGNED)) == STATUS_UNASSIGNED:
			lot.assignment["status"] = STATUS_EMPTY


func _is_lot_compatible(lot: LotInstance, building_type: BuildingTypeDefinition) -> bool:
	if lot == null or building_type == null:
		return false
	if not lot.can_host_building():
		return false
	if not _footprint_fits(lot, building_type):
		return false
	if not _lot_rules_fit(lot, building_type):
		return false
	if not _frontage_fits(lot, building_type):
		return false
	if _requires_attachment_space(building_type) and not bool(lot.constraints.get("allow_attachment_space", false)):
		return false
	return true


func _footprint_fits(lot: LotInstance, building_type: BuildingTypeDefinition) -> bool:
	var min_size: Vector2 = _get_min_footprint(building_type)
	if lot.build_area.size.x < min_size.x or lot.build_area.size.y < min_size.y:
		return false
	return true


func _lot_rules_fit(lot: LotInstance, building_type: BuildingTypeDefinition) -> bool:
	var rules: Dictionary = building_type.lot_rules
	var min_lot_width: float = float(rules.get("min_lot_width", 0.0))
	var min_lot_depth: float = float(rules.get("min_lot_depth", 0.0))
	if min_lot_width > 0.0 and float(lot.frontage.get("width", 0.0)) < min_lot_width:
		return false
	if min_lot_depth > 0.0 and min(lot.rect.size.x, lot.rect.size.y) < min_lot_depth:
		return false
	var allowed = rules.get("allowed_districts", PackedStringArray())
	if not _string_array_is_empty(allowed):
		if not _lot_has_any_tag(lot, allowed):
			return false
	return true


func _frontage_fits(lot: LotInstance, building_type: BuildingTypeDefinition) -> bool:
	var preferred: String = _get_preferred_frontage(building_type)
	var required: String = String(building_type.lot_rules.get("required_frontage", building_type.entrance_rules.get("required_frontage", "")))
	var allowed = building_type.lot_rules.get("allowed_frontages", PackedStringArray())
	var lot_kind: String = String(lot.frontage.get("kind", ""))
	if required != "":
		return _frontage_matches(lot, required)
	if not _string_array_is_empty(allowed):
		return _string_array_has(allowed, lot_kind)
	if preferred == "gate":
		return lot.context_tags.has("near_gate")
	if preferred == "square":
		return lot_kind == "square"
	return true


func _score_lot_for_building(
	spec: SiteSpec,
	profile: BuildingProfileDefinition,
	lot: LotInstance,
	building_type: BuildingTypeDefinition,
	request: Dictionary
) -> float:
	var score: float = 0.0
	var preferred_districts: PackedStringArray = _get_preferred_districts(building_type)
	for tag in preferred_districts:
		var tag_string: String = String(tag)
		if lot.has_tag(tag_string):
			score += 0.22
		score += lot.get_score(tag_string) * 0.28
	for role_tag in _get_role_score_tags(building_type.id):
		var role_tag_string: String = String(role_tag)
		score += lot.get_score(role_tag_string) * 0.18

	var preferred_frontage: String = _get_preferred_frontage(building_type)
	if preferred_frontage != "" and _frontage_matches(lot, preferred_frontage):
		score += 0.22
	if bool(lot.constraints.get("allow_attachment_space", false)) and _benefits_from_attachment_space(building_type):
		score += 0.16
	if String(request.get("request_source", "")) == SOURCE_SPECIAL_FEATURE_REQUIRED:
		score += _special_feature_context_bonus(lot, String(request.get("special_feature", "")), building_type.id)

	var raw_bias = profile.district_bias.get(building_type.id, {})
	var bias: Dictionary = {}
	if raw_bias is Dictionary:
		bias = raw_bias
	for key in bias.keys():
		var tag_name: String = String(key)
		score += lot.get_score(tag_name) * float(bias[key])
	score += _tie_break_value(spec.seed, String(request.get("request_id", "")), lot.id) * 0.01
	return clampf(score, 0.0, 1.0)


func _validate_output(spec: SiteSpec, profile: BuildingProfileDefinition, lots: Array[LotInstance]) -> void:
	var instance_ids: Dictionary = {}
	var assigned_by_type: Dictionary = {}
	var available_empty_count: int = 0
	for lot in lots:
		var status: String = String(lot.assignment.get("status", STATUS_UNASSIGNED))
		if status == STATUS_ASSIGNED:
			var building_type_id: String = String(lot.assignment.get("building_type_id", ""))
			var instance_id: String = String(lot.assignment.get("building_instance_id", ""))
			if building_type_id == "" or instance_id == "":
				errors.append("Assigned lot '" + lot.id + "' is missing assignment ids.")
			if not registry.has_building_type(building_type_id):
				errors.append("Assigned lot '" + lot.id + "' references unknown building type '" + building_type_id + "'.")
			if instance_ids.has(instance_id):
				errors.append("Duplicate building instance id '" + instance_id + "'.")
			instance_ids[instance_id] = true
			assigned_by_type[building_type_id] = int(assigned_by_type.get(building_type_id, 0)) + 1
		elif status == STATUS_EMPTY:
			available_empty_count += 1

	if int(assigned_by_type.get("tavern", 0)) == 0 and _profile_expects_building(profile, "tavern"):
		_add_warning(WARNING_UNSATISFIED_REQUIRED_BUILDING, spec, "", "tavern", "Town profile expects at least one tavern but none were assigned.")
	if available_empty_count == 0:
		_add_warning("no_breathing_room", spec, "", "", "All leftover lots were filled or blocked.")


func _make_request(index: int, building_type_id: String, source: String, special_feature: String, priority: int, allow_fallback: bool) -> Dictionary:
	return {
		"request_id": "req_%04d" % index,
		"building_type_id": building_type_id,
		"request_source": source,
		"special_feature": special_feature,
		"priority": priority,
		"allow_fallback": allow_fallback,
		"compatible_count": 0,
		"min_footprint_area": 0.0
	}


func _sort_requests(a: Dictionary, b: Dictionary) -> bool:
	var a_source: String = String(a.get("request_source", ""))
	var b_source: String = String(b.get("request_source", ""))
	var a_source_rank: int = _request_source_rank(a_source)
	var b_source_rank: int = _request_source_rank(b_source)
	if a_source_rank != b_source_rank:
		return a_source_rank < b_source_rank
	var a_priority: int = int(a.get("priority", 0))
	var b_priority: int = int(b.get("priority", 0))
	if a_priority != b_priority:
		return a_priority > b_priority
	var a_compatible: int = int(a.get("compatible_count", 0))
	var b_compatible: int = int(b.get("compatible_count", 0))
	if a_compatible != b_compatible:
		return a_compatible < b_compatible
	var a_area: float = float(a.get("min_footprint_area", 0.0))
	var b_area: float = float(b.get("min_footprint_area", 0.0))
	if not is_equal_approx(a_area, b_area):
		return a_area > b_area
	return String(a.get("request_id", "")) < String(b.get("request_id", ""))


func _sort_lots_by_id(a: LotInstance, b: LotInstance) -> bool:
	return a.id < b.id


func _request_source_rank(source: String) -> int:
	if source == SOURCE_SPECIAL_FEATURE_REQUIRED:
		return 0
	if source == SOURCE_PROFILE_REQUIRED:
		return 1
	if source == SOURCE_PROFILE_OPTIONAL:
		return 2
	return 3


func _warn_unsatisfied_request(spec: SiteSpec, request: Dictionary, building_type_id: String) -> void:
	var source: String = String(request.get("request_source", ""))
	var feature: String = String(request.get("special_feature", ""))
	if source == SOURCE_SPECIAL_FEATURE_REQUIRED:
		_add_warning(WARNING_UNSATISFIED_SPECIAL_FEATURE, spec, feature, building_type_id, "No compatible lot exists for special-feature-required building.")
	elif source == SOURCE_PROFILE_REQUIRED:
		_add_warning(WARNING_UNSATISFIED_REQUIRED_BUILDING, spec, feature, building_type_id, "No compatible lot exists for required building.")
	else:
		_add_warning(WARNING_NO_COMPATIBLE_LOT, spec, feature, building_type_id, "No compatible lot exists for optional building.")


func _add_warning(category: String, spec: SiteSpec, feature_id: String, building_type_id: String, message: String) -> void:
	var town_id: String = ""
	if spec != null:
		town_id = spec.id
	warnings.append({
		"category": category,
		"town_id": town_id,
		"feature_id": feature_id,
		"building_type_id": building_type_id,
		"message": message
	})
	push_warning("BuildingAssignmentService[" + category + "]: " + message)


func _make_result(profile_id: String, requests: Array, success: bool) -> Dictionary:
	return {
		"success": success,
		"profile_id": profile_id,
		"assignments": assignment_records,
		"requests": requests,
		"warnings": warnings,
		"errors": errors
	}


func _get_profile_id(spec: SiteSpec) -> String:
	if spec == null:
		return ""
	return String(spec.generation_params.get("building_profile", ""))


func _get_special_features(spec: SiteSpec) -> PackedStringArray:
	var features: PackedStringArray = PackedStringArray()
	if spec == null:
		return features
	var raw_features = spec.generation_params.get("special_features", PackedStringArray())
	for feature in raw_features:
		var feature_id: String = String(feature)
		if feature_id != "" and not features.has(feature_id):
			features.append(feature_id)
	return features


func _get_building_type(building_type_id: String) -> BuildingTypeDefinition:
	if building_types.has(building_type_id):
		return building_types[building_type_id]
	if registry.has_building_type(building_type_id):
		var building_type: BuildingTypeDefinition = registry.get_building_type(building_type_id)
		building_types[building_type_id] = building_type
		return building_type
	return null


func _get_min_footprint(building_type: BuildingTypeDefinition) -> Vector2:
	if building_type == null:
		return Vector2.ZERO
	var min_size: Vector2 = building_type.footprint_rules.get("min_size", Vector2.ZERO)
	if min_size != Vector2.ZERO:
		return min_size
	var min_width: float = float(building_type.footprint_rules.get("min_width", 0.0))
	var min_depth: float = float(building_type.footprint_rules.get("min_depth", 0.0))
	if min_width > 0.0 or min_depth > 0.0:
		return Vector2(min_width, min_depth)
	var default_size: Vector2 = building_type.footprint_rules.get("default_size", Vector2(100, 80))
	return default_size * 0.72


func _get_preferred_frontage(building_type: BuildingTypeDefinition) -> String:
	var lot_value: String = String(building_type.lot_rules.get("preferred_frontage", ""))
	if lot_value != "":
		return lot_value
	return String(building_type.entrance_rules.get("preferred_frontage", ""))


func _get_preferred_districts(building_type: BuildingTypeDefinition) -> PackedStringArray:
	var preferred: PackedStringArray = building_type.lot_rules.get("preferred_districts", PackedStringArray())
	if not preferred.is_empty():
		return preferred
	var legacy: PackedStringArray = building_type.lot_rules.get("district_tags", PackedStringArray())
	var mapped: PackedStringArray = PackedStringArray()
	for tag in legacy:
		var mapped_tag: String = _map_legacy_district_tag(String(tag))
		if mapped_tag != "" and not mapped.has(mapped_tag):
			mapped.append(mapped_tag)
	return mapped


func _map_legacy_district_tag(tag: String) -> String:
	if tag == "center" or tag == "roadside":
		return "market"
	if tag == "workshop":
		return "work"
	return tag


func _get_role_score_tags(building_type_id: String) -> Array:
	if ROLE_SCORE_TAGS.has(building_type_id):
		var role_tags: Array = ROLE_SCORE_TAGS[building_type_id]
		return role_tags
	var tags: Array = []
	return tags


func _frontage_matches(lot: LotInstance, frontage: String) -> bool:
	var lot_kind: String = String(lot.frontage.get("kind", ""))
	if frontage == "gate":
		return lot.context_tags.has("near_gate")
	if frontage == "road":
		return lot_kind == "road" or lot_kind == "lane"
	return lot_kind == frontage


func _requires_attachment_space(building_type: BuildingTypeDefinition) -> bool:
	return bool(building_type.attachment_rules.get("requires_attachment_space", false))


func _benefits_from_attachment_space(building_type: BuildingTypeDefinition) -> bool:
	if _requires_attachment_space(building_type):
		return true
	if bool(building_type.attachment_rules.get("allows_yard", false)):
		return true
	var accent: String = String(building_type.visual_rules.get("accent", ""))
	return accent == "pen" or accent == "forge_yard" or accent == "forecourt" or accent == "courtyard"


func _special_feature_context_bonus(lot: LotInstance, feature_id: String, building_type_id: String) -> float:
	if feature_id == "market_square":
		if lot.context_tags.has("square_frontage") or lot.has_tag("market"):
			return 0.18
	if feature_id == "stable":
		if lot.has_tag("gate") or lot.has_tag("edge"):
			return 0.16
	if feature_id == "blacksmith":
		if lot.has_tag("work") or lot.has_tag("edge"):
			return 0.16
	if feature_id == "temple":
		if lot.has_tag("civic") or lot.has_tag("prestige"):
			return 0.16
	return 0.0


func _profile_expects_building(profile: BuildingProfileDefinition, building_type_id: String) -> bool:
	if profile.guaranteed_buildings.has(building_type_id):
		return true
	if profile.building_types.has(building_type_id):
		var rules: Dictionary = profile.building_types[building_type_id]
		return int(rules.get("min_count", rules.get("min", 0))) > 0
	return false


func _count_requests_for_type(requests: Array, building_type_id: String) -> int:
	var count: int = 0
	for request in requests:
		if String(request.get("building_type_id", "")) == building_type_id:
			count += 1
	return count


func _request_order_debug_string(requests: Array) -> String:
	var ids: PackedStringArray = PackedStringArray()
	for request in requests:
		ids.append(String(request.get("request_id", "")) + ":" + String(request.get("building_type_id", "")) + ":" + String(request.get("request_source", "")))
	return ", ".join(ids)


func _make_building_instance_id(spec: SiteSpec, index: int) -> String:
	var town_id: String = spec.id
	if town_id == "":
		town_id = spec.site_id
	return "%s_bld_%04d" % [town_id, index]


func _tie_break_value(seed_value: int, request_id: String, lot_id: String) -> float:
	var rng: RandomNumberGenerator = _make_rng(seed_value, "assignment:" + request_id + ":" + lot_id)
	return rng.randf()


func _make_rng(seed_value: int, phase: String) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var derived: int = int(hash(str(seed_value) + ":" + phase))
	if derived < 0:
		derived = -derived
	if derived == 0:
		derived = 1
	rng.seed = derived
	return rng


func _sorted_string_keys(dictionary: Dictionary) -> PackedStringArray:
	var keys: PackedStringArray = PackedStringArray()
	for key in dictionary.keys():
		keys.append(String(key))
	keys.sort()
	return keys


func _string_array_is_empty(value) -> bool:
	for _item in value:
		return false
	return true


func _string_array_has(value, needle: String) -> bool:
	for item in value:
		if String(item) == needle:
			return true
	return false


func _lot_has_any_tag(lot: LotInstance, tags) -> bool:
	for tag in tags:
		if lot.has_tag(String(tag)):
			return true
	return false


func _is_valid_assignment_status(status: String) -> bool:
	return status == STATUS_UNASSIGNED or status == STATUS_RESERVED or status == STATUS_ASSIGNED or status == STATUS_BLOCKED or status == STATUS_EMPTY
