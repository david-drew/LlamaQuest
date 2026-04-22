class_name WorldNetwork
extends RefCounted

var network_id: String
var network_type: String
var points: PackedVector2Array
var width: float
var sub_seed: int

func _init(
	_network_id: String,
	_network_type: String,
	_points: PackedVector2Array,
	_width: float = 10.0,
	_sub_seed: int = 0
) -> void:
	network_id = _network_id
	network_type = _network_type
	points = _points
	width = _width
	sub_seed = _sub_seed
