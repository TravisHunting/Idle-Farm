extends Node2D
## Draws all objects, the farmer and animals, y-sorted, in one pass.

var world: World


func _draw() -> void:
	if world == null:
		return
	var items: Array = []  # [sort_y, kind, ref]
	items.append([31.0, "house", null])
	for c in world.objs:
		items.append([c.y * 16 + 15.0, "obj", c])
	if world.farmer:
		items.append([world.farmer.pos.y, "farmer", world.farmer])
	for a in world.animals:
		var y: float = a.pos.y
		if a.kind in ["crow", "butterfly", "bee"]:
			y += 20.0  # flyers draw above things around them
		items.append([y, "animal", a])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		match it[1]:
			"house":
				draw_texture(Art.tex("house"), Vector2(0, 0))
			"obj":
				_draw_obj(it[2])
			"farmer", "animal":
				it[2].draw(self)


func _draw_obj(c: Vector2i) -> void:
	var o: Dictionary = world.objs[c]
	var t: String = o["type"]
	if t == "fire":
		var under: Dictionary = o.get("under", {})
		if not under.is_empty():
			_draw_sprite(c, _tex_name(under), Color(0.5, 0.4, 0.35))
		var fr := "fire1" if int(world._anim_t * 6.0 + c.x) % 2 == 0 else "fire2"
		_draw_sprite(c, fr, Color.WHITE)
		return
	var mod := Color.WHITE
	if Game.STRUCTS.has(t) and o["hp"] < Game.STRUCTS[t]["hp"] * 0.5:
		mod = Color(1.0, 0.75, 0.7)
	_draw_sprite(c, _tex_name(o), mod)


func _tex_name(o: Dictionary) -> String:
	var t: String = o.get("type", "")
	if t == "tree":
		return "tree_apple" if o.get("apple", false) else "tree"
	return t


func _draw_sprite(c: Vector2i, name_: String, mod: Color) -> void:
	var tx := Art.tex(name_)
	var p := Vector2(c.x * 16 + 8 - tx.get_width() / 2, c.y * 16 + 16 - tx.get_height())
	draw_texture(tx, p.floor(), mod)
