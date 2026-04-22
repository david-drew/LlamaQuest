class_name WorldNetwork
extends RefCounted

var network_id: String
var network_type: String
var points: PackedVector2Array

func _init(_network_id: String, _network_type: String, _points: PackedVector2Array) -> void:
	network_id = _network_id
	network_type = _network_type
	points = _points
