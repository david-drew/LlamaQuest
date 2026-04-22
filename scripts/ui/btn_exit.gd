extends Button

@onready var dialog_panel = %DialogPanel

func _on_pressed() -> void:
	dialog_panel.visible = false
