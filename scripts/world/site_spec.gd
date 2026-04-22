class_name SiteSpec
extends RefCounted

var site_id: String
var site_type: String
var display_name: String
var position: Vector2
var seed: int

func _init(
	_site_id: String,
	_site_type: String,
	_display_name: String,
	_position: Vector2,
	_seed: int
) -> void:
	site_id = _site_id
	site_type = _site_type
	display_name = _display_name
	position = _position
	seed = _seed
