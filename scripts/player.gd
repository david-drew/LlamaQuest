extends CharacterBody2D
class_name Player

@export var speed: float = 200.0

# Camera zoom settings
@export var min_zoom: float = 0.5  # Zoomed out
@export var max_zoom: float = 2.0  # Zoomed in
@export var zoom_speed: float = 0.1

@onready var camera: Camera2D = $Camera2D

func _physics_process(_delta: float) -> void:
	handle_movement()
	handle_zoom()

func handle_movement() -> void:
	# get_vector automatically normalizes diagonal movement!
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()

func handle_zoom() -> void:
	if Input.is_action_just_pressed("zoom_in"):
		var new_zoom = clamp(camera.zoom.x + zoom_speed, min_zoom, max_zoom)
		camera.zoom = Vector2(new_zoom, new_zoom)
		
	elif Input.is_action_just_pressed("zoom_out"):
		var new_zoom = clamp(camera.zoom.x - zoom_speed, min_zoom, max_zoom)
		camera.zoom = Vector2(new_zoom, new_zoom)
