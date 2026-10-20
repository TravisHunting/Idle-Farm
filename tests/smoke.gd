extends SceneTree

func _initialize() -> void:
	print("Game autoload: ", root.get_node_or_null("Game") != null, " Art: ", root.get_node_or_null("Art") != null)
	quit()
