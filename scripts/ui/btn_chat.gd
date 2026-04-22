extends Button

# Drag the node containing 'npc_dialogue.gd' here in the Godot Inspector
@export var npc_node: Node 
@export var response_label: RichTextLabel

func _ready() -> void:
	npc_node = %NpcNode
	response_label = $"../../ResponseLabel"

func _on_pressed():
	if npc_node == null or not is_instance_valid(npc_node):
		npc_node = get_node_or_null("/root/Main/World/NpcNode")

	if not npc_node:
		push_error("Work Button: No NPC Node assigned!")
		return
		
	# Disable button to prevent spamming
	disabled = true
	var original_text = text
	text = "NPC is thinking..."
	
	# Await the response and push it to the screen
	var reply_text = await npc_node.chat_with_npc()
	response_label.text = reply_text
	
	text = original_text
	disabled = false
