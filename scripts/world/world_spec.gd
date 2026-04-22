class_name WorldSpec
extends RefCounted

var seed: int
var extents: Vector2
var regions: Array[WorldRegion] = []
var networks: Array[WorldNetwork] = []
var sites: Array[SiteSpec] = []
var sub_seeds: Dictionary = {}

func _init(_seed: int, _extents: Vector2) -> void:
	seed = _seed
	extents = _extents
