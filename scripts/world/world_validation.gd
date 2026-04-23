class_name WorldValidation
extends RefCounted

const HUGE_DISTANCE: float = 1000000000.0


static func validate_world(spec: WorldSpec) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if spec == null:
		errors.append("WorldSpec is null.")
		return errors

	var base_errors: PackedStringArray = spec.validate()
	for error in base_errors:
		errors.append(error)

	if spec.sites.is_empty():
		errors.append("WorldSpec must contain at least one site.")
	if not _has_town_site(spec):
		errors.append("WorldSpec must contain at least one town site.")

	_append_unique_region_id_errors(spec, errors)
	_append_unique_network_id_errors(spec, errors)
	_append_unique_site_id_errors(spec, errors)
	_append_site_reference_errors(spec, errors)
	_append_town_errors(spec, errors)
	return errors


static func make_debug_dump(spec: WorldSpec) -> String:
	if spec == null:
		return "WorldSpec: null"

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[WorldSpec] id=%s seed=%s regions=%d networks=%d sites=%d" % [
		spec.id,
		str(spec.world_seed),
		spec.regions.size(),
		spec.networks.size(),
		spec.sites.size()
	])
	for site in spec.sites:
		if site == null:
			continue
		lines.append("  site id=%s type=%s subtype=%s pos=%s seed=%s networks=%s" % [
			_get_site_id(site),
			site.site_type,
			site.subtype,
			str(site.position),
			str(site.seed),
			str(site.connections)
		])
	var output: String = ""
	for i in range(lines.size()):
		if i > 0:
			output += "\n"
		output += lines[i]
	return output


static func _append_unique_region_id_errors(spec: WorldSpec, errors: PackedStringArray) -> void:
	var ids: Dictionary = {}
	for region in spec.regions:
		if region == null:
			errors.append("WorldSpec.regions contains a null region.")
			continue
		var region_id: String = String(region.region_id)
		if region_id == "":
			errors.append("WorldRegion.region_id is required.")
			continue
		if ids.has(region_id):
			errors.append("Duplicate WorldRegion id '" + region_id + "'.")
		ids[region_id] = true


static func _append_unique_network_id_errors(spec: WorldSpec, errors: PackedStringArray) -> void:
	var ids: Dictionary = {}
	for network in spec.networks:
		if network == null:
			errors.append("WorldSpec.networks contains a null network.")
			continue
		var network_id: String = String(network.network_id)
		if network_id == "":
			errors.append("WorldNetwork.network_id is required.")
			continue
		if ids.has(network_id):
			errors.append("Duplicate WorldNetwork id '" + network_id + "'.")
		ids[network_id] = true


static func _append_unique_site_id_errors(spec: WorldSpec, errors: PackedStringArray) -> void:
	var ids: Dictionary = {}
	for site in spec.sites:
		if site == null:
			continue
		var site_id: String = _get_site_id(site)
		if site_id == "":
			errors.append("SiteSpec id is required.")
			continue
		if ids.has(site_id):
			errors.append("Duplicate SiteSpec id '" + site_id + "'.")
		ids[site_id] = true


static func _append_site_reference_errors(spec: WorldSpec, errors: PackedStringArray) -> void:
	var network_ids: Dictionary = _collect_network_ids(spec)
	var site_ids: Dictionary = _collect_site_ids(spec)
	var extents: Vector2 = _get_extents(spec)

	for site in spec.sites:
		if site == null:
			continue
		var site_id: String = _get_site_id(site)
		if not _is_position_in_bounds(site.position, extents):
			errors.append("Site '" + site_id + "' is outside world bounds.")
		_validate_network_refs(site, "roads", network_ids, errors)
		_validate_network_refs(site, "rivers", network_ids, errors)
		var adjacent_sites: Array = site.connections.get("adjacent_sites", [])
		for raw_adjacent_id in adjacent_sites:
			var adjacent_id: String = String(raw_adjacent_id)
			if not site_ids.has(adjacent_id):
				errors.append("Site '" + site_id + "' references missing adjacent site '" + adjacent_id + "'.")


static func _append_town_errors(spec: WorldSpec, errors: PackedStringArray) -> void:
	for site in spec.sites:
		if site == null:
			continue
		if site.site_type != "town":
			continue
		var site_id: String = _get_site_id(site)
		if _is_point_in_region_type(site.position, spec.regions, "lake"):
			errors.append("Town site '" + site_id + "' is inside a lake region.")
		if site.access_points.is_empty():
			errors.append("Town site '" + site_id + "' must include at least one access point.")
		if String(site.generation_params.get("building_profile", "")) == "":
			errors.append("Town site '" + site_id + "' must include generation_params.building_profile.")
		if site.seed == 0:
			errors.append("Town site '" + site_id + "' must have a nonzero seed.")


static func _validate_network_refs(
	site: SiteSpec,
	key: String,
	network_ids: Dictionary,
	errors: PackedStringArray
) -> void:
	var refs: Array = site.connections.get(key, [])
	for raw_network_id in refs:
		var network_id: String = String(raw_network_id)
		if not network_ids.has(network_id):
			errors.append("Site '" + _get_site_id(site) + "' references missing network '" + network_id + "'.")


static func _has_town_site(spec: WorldSpec) -> bool:
	for site in spec.sites:
		if site != null and site.site_type == "town":
			return true
	return false


static func _collect_network_ids(spec: WorldSpec) -> Dictionary:
	var ids: Dictionary = {}
	for network in spec.networks:
		if network == null:
			continue
		if String(network.network_id) != "":
			ids[String(network.network_id)] = true
	return ids


static func _collect_site_ids(spec: WorldSpec) -> Dictionary:
	var ids: Dictionary = {}
	for site in spec.sites:
		if site == null:
			continue
		var site_id: String = _get_site_id(site)
		if site_id != "":
			ids[site_id] = true
	return ids


static func _get_site_id(site: SiteSpec) -> String:
	if site.id != "":
		return site.id
	return site.site_id


static func _get_extents(spec: WorldSpec) -> Vector2:
	if spec.extents != Vector2.ZERO:
		return spec.extents
	return Vector2(spec.size)


static func _is_position_in_bounds(pos: Vector2, extents: Vector2) -> bool:
	var half_width: float = extents.x * 0.5
	var half_height: float = extents.y * 0.5
	if pos.x < -half_width:
		return false
	if pos.x > half_width:
		return false
	if pos.y < -half_height:
		return false
	if pos.y > half_height:
		return false
	return true


static func _is_point_in_region_type(pos: Vector2, regions: Array, region_type: String) -> bool:
	for region in regions:
		if region == null:
			continue
		if String(region.region_type) != region_type:
			continue
		if _point_in_region_ellipse(pos, region):
			return true
	return false


static func _point_in_region_ellipse(pos: Vector2, region) -> bool:
	if region.radius.x <= 0.01:
		return false
	if region.radius.y <= 0.01:
		return false
	var local: Vector2 = pos - region.center
	var x_term: float = (local.x * local.x) / (region.radius.x * region.radius.x)
	var y_term: float = (local.y * local.y) / (region.radius.y * region.radius.y)
	return x_term + y_term <= 1.0
