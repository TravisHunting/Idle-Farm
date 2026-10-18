extends Node2D
## Draws world particles (dust, water, sparkles). Above entities, below weather.

var world: World


func _draw() -> void:
	if world == null:
		return
	for pt in world.particles:
		var c: Color = pt["c"]
		c.a = clampf(pt["life"] * 2.0, 0.0, 1.0)
		var p: Vector2 = pt["p"]
		draw_rect(Rect2(p.floor(), Vector2(1, 1)), c)
