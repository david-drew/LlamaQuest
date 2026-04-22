class_name SiteSpec
extends RefCounted

var site_id: String
var site_type: String
var display_name: String
var position: Vector2
var seed: int
var routing_id: String

func _init(
	_site_id: String,
	_site_type: String,
	_display_name: String,
	_position: Vector2,
	_seed: int,
	_routing_id: String = ""
) -> void:
	site_id = _site_id
	site_type = _site_type
	display_name = _display_name
	position = _position
	seed = _seed
	routing_id = _routing_id
