class_name TownRenderStyles
extends RefCounted

const GROUND_DEFAULT := Color(0.63, 0.48, 0.29, 1.0)
const GROUND_GRASSLAND := Color(0.58, 0.50, 0.32, 1.0)
const ROAD := Color(0.35, 0.32, 0.28, 1.0)
const SQUARE := Color(0.57, 0.51, 0.39, 1.0)
const WALL := Color(0.22, 0.22, 0.23, 1.0)
const GATE := Color(0.46, 0.34, 0.19, 1.0)
const RESERVED := Color(0.34, 0.57, 0.76, 0.18)
const BUILD_AREA := Color(1.0, 1.0, 1.0, 0.20)
const LOT_ASSIGNED := Color(0.05, 0.05, 0.05, 0.55)
const LOT_EMPTY := Color(1.0, 1.0, 1.0, 0.12)
const LOT_RESERVED := Color(0.95, 0.72, 0.18, 0.55)
const LOT_BLOCKED := Color(0.90, 0.12, 0.08, 0.55)
const DISTRICT_HINT := Color(0.78, 0.18, 0.86, 0.10)
const BAND := Color(0.1, 0.45, 0.95, 0.12)
const DOOR := Color(0.16, 0.08, 0.03, 1.0)
const SPAWN := Color(0.1, 0.95, 0.25, 1.0)
const EXIT := Color(0.95, 0.25, 0.1, 1.0)
const LABEL := Color(0.05, 0.04, 0.03, 1.0)


static func ground_color(biome: String) -> Color:
	if biome == "grassland" or biome == "":
		return GROUND_GRASSLAND
	if biome == "forest":
		return Color(0.38, 0.48, 0.30, 1.0)
	if biome == "desert":
		return Color(0.70, 0.59, 0.38, 1.0)
	return GROUND_DEFAULT


static func building_color(building_type_id: String) -> Color:
	if building_type_id == "house":
		return Color(0.80, 0.52, 0.25, 1.0)
	if building_type_id == "tavern":
		return Color(0.63, 0.32, 0.18, 1.0)
	if building_type_id == "inn":
		return Color(0.05, 0.55, 0.85, 1.0)
	if building_type_id == "general_store":
		return Color(0.33, 0.42, 0.18, 1.0)
	if building_type_id == "temple":
		return Color(0.69, 0.77, 0.87, 1.0)
	if building_type_id == "stable":
		return Color(0.55, 0.27, 0.07, 1.0)
	if building_type_id == "blacksmith":
		return Color(0.55, 0.05, 0.04, 1.0)
	if building_type_id == "guard_post":
		return Color(0.44, 0.50, 0.56, 1.0)
	if building_type_id == "workshop":
		return Color(0.70, 0.48, 0.45, 1.0)
	if building_type_id == "apothecary":
		return Color(0.56, 0.42, 0.72, 1.0)
	if building_type_id == "manor":
		return Color(0.86, 0.63, 0.14, 1.0)
	return Color(0.56, 0.40, 0.32, 1.0)


static func attachment_color(accent: String) -> Color:
	if accent == "pen" or accent == "forge_yard" or accent == "storage":
		return Color(0.34, 0.25, 0.16, 0.72)
	if accent == "garden":
		return Color(0.14, 0.46, 0.19, 0.72)
	if accent == "forecourt" or accent == "courtyard":
		return Color(0.78, 0.69, 0.50, 0.72)
	if accent == "stall" or accent == "porch":
		return Color(0.78, 0.63, 0.40, 0.72)
	return Color(0.45, 0.36, 0.27, 0.56)


static func lot_status_color(status: String) -> Color:
	if status == "assigned":
		return LOT_ASSIGNED
	if status == "reserved":
		return LOT_RESERVED
	if status == "blocked":
		return LOT_BLOCKED
	return LOT_EMPTY
