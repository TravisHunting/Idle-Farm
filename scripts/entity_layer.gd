extends Node2D
## Draws all objects, the farmer and animals, y-sorted, in one pass.

var world: World


func _draw() -> void:
	if world == null:
		return
	var items: Array = []  # [sort_y, kind, ref]
	items.append([world.house.y * 16 + 31.0, "house", null])
	for c in world.objs:
		items.append([c.y * 16 + 15.0, "obj", c])
	if world.farmer:
		items.append([world.farmer.pos.y, "farmer", world.farmer])
	if world.friend:
		items.append([world.friend.pos.y, "farmer", world.friend])
	for a in world.animals:
		var y: float = a.pos.y
		if a.kind in ["crow", "butterfly", "bee"]:
			y += 20.0  # flyers draw above things around them
		elif a is Alien and a.caste == "ship":
			y += 1000.0
		elif a is Insect and a.flying():
			y += 24.0
		items.append([y, "animal", a])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		match it[1]:
			"house":
				draw_texture(Art.tex("house"), world.house_px())
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
	if t == "fence":
		_draw_fence(c, mod)
		return
	if t == "totem":
		mod = mod.lerp(Color(1.0, 0.7, 1.0), 0.5 + 0.5 * sin(world._anim_t * 2.0 + c.x))
	if t in ["a_spire", "a_pylon", "a_moss", "a_husk"] and Game.darkness() > 0.3:
		var r := 9.0 if t == "a_spire" else 6.0
		draw_circle(world.center(c) + Vector2(0, -4), r, Color(0.45, 1.0, 0.8, 0.10 * Game.darkness()))
	_draw_sprite(c, _tex_name(o), mod)
	if t == "mailbox" and String(o.get("pid", "")) == Game.my_pid and Chores.unread(Game.my_pid):
		# a letter from grandpa (news about the chores) waiting: a bobbing "!"
		var bob := floorf(sin(world._anim_t * 5.0) * 1.5)
		Art.draw_text(self, "!", Vector2(c.x * 16 + 7, c.y * 16 - 4 + bob), Color("ffcd75"), Color(0, 0, 0, 0.7))


## Fences join up with their neighbours: a post per tile, rails towards adjacent fences.
func _draw_fence(c: Vector2i, mod: Color) -> void:
	var x := c.x * 16
	var y := c.y * 16
	var wood := Color("c28a5a") * mod
	var dark := Color("8b5a3c") * mod
	var right := world.obj_type(c + Vector2i(1, 0)) == "fence"
	var left := world.obj_type(c + Vector2i(-1, 0)) == "fence"
	var down := world.obj_type(c + Vector2i(0, 1)) == "fence"
	var up := world.obj_type(c + Vector2i(0, -1)) == "fence"
	if left:
		draw_rect(Rect2(x, y + 7, 8, 1), wood)
		draw_rect(Rect2(x, y + 10, 8, 1), wood)
	if right:
		draw_rect(Rect2(x + 8, y + 7, 8, 1), wood)
		draw_rect(Rect2(x + 8, y + 10, 8, 1), wood)
	if up:
		draw_rect(Rect2(x + 7, y - 2, 1, 9), dark)
	if down:
		draw_rect(Rect2(x + 7, y + 12, 1, 6), dark)
	if not (left or right or up or down):
		draw_rect(Rect2(x + 3, y + 8, 10, 1), wood)
	# the post
	draw_rect(Rect2(x + 6, y + 5, 3, 9), wood)
	draw_rect(Rect2(x + 6, y + 5, 3, 1), Color("e0c08a") * mod)
	draw_rect(Rect2(x + 8, y + 6, 1, 8), dark)


func _tex_name(o: Dictionary) -> String:
	var t: String = o.get("type", "")
	if t == "tree":
		return "tree_apple" if o.get("apple", false) else "tree"
	if t == "a_moss":
		return "a_moss" if float(o.get("g", 0.0)) >= 1.0 else "a_moss_young"
	if t == "i_mound":
		return "i_mound%d" % clampi(int(o.get("stage", 1)), 1, 3)
	if t == "mailbox":
		# flag up while that player has cards waiting in their box
		var h: Dictionary = Game.hands.get(String(o.get("pid", "")), {})
		for id in h.get("box", []):
			if id != "":
				return "mailbox_flag"
	return t


func _draw_sprite(c: Vector2i, name_: String, mod: Color) -> void:
	var tx := Art.tex(name_)
	var p := Vector2(c.x * 16 + 8 - tx.get_width() / 2, c.y * 16 + 16 - tx.get_height())
	draw_texture(tx, p.floor(), mod)
