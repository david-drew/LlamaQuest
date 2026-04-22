extends Button

@onready var event_gen = get_node("/root/Main/Systems/EventGenerator")
@onready var world_manager = get_node("/root/Main/Systems/WorldManager")
@onready var history_summarizer = get_node("/root/Main/Systems/HistorySummarizer")
@onready var date_ui = %DateLabel
@onready var notification_ui = %EventsLabel 
@onready var fade_rect: ColorRect = %Fader

@export var fade_duration: float = 3.0 

func fade_screen_to_black() -> void:
	if not fade_rect: 
		print("ERR: Fader not found!!!!")
		return
	
	fade_rect.visible = true
	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 1.0, fade_duration)
	await tween.finished

func fade_screen_in():
	if not fade_rect: return
	
	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 0.0, fade_duration)
	await tween.finished
	fade_rect.visible = false

func transition_to_next_day():
	# 1. Start the fade and WAIT for it to finish
	await fade_screen_to_black()
	
	# 2. Summarize yesterday's history and wait for Qwen
	await history_summarizer.trigger_summarization() 
	
	# 3. Ask the LLM what happens overnight
	var daily_event = await event_gen.generate_world_event("Oakhaven Village")
	date_ui.text = world_manager.get_date()
	
	if not daily_event.has("error"):
		# Update UI with the event
		notification_ui.text = "New Event: " + daily_event["title"] + "\n" + daily_event["description"]
		world_manager.apply_event(daily_event["event_category"], daily_event["system_target"])
	else:
		# Fallback if the event generation fails
		notification_ui.text = "Player woke up feeling refreshed!"
		print(notification_ui.text)
		
	# 4. Now that EVERYTHING is done, fade back in
	await fade_screen_in()

func _on_pressed() -> void:
	# Disable the button here to prevent double-clicking!
	if self is Button: disabled = true
	
	# We also await this function so the button stays disabled until the entire sequence is complete.
	await transition_to_next_day()
	
	if self is Button: disabled = false
