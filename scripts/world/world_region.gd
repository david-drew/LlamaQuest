class_name WorldRegion
extends RefCounted

var region_id: String
var region_type: String
var center: Vector2
var radius: Vector2

func _init(_region_id: String, _region_type: String, _center: Vector2, _radius: Vector2) -> void:
	region_id = _region_id
	region_type = _region_type
	center = _center
	radius = _radius
