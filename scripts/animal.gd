extends RefCounted
class_name Animal
## Every non-farmer creature. Behaviour is switched on `kind`:
##  threats : crow, rabbit (eat crops) · fox (steals chickens / digs crops, bites)
##            boar (charges across a row, tramples, hits the farmer) · snake (hidden, poisons)
##            wasps (nest, stings when the farmer is near)
##  friendly: chicken (lays eggs) · dog (Watchdog card, chases threats) · merchant (buys produce)
##            butterfly · bee (cosmetic)

const THREATS := ["crow", "rabbit", "fox", "boar", "snake", "wasps"]
const FACES_LEFT := ["rabbit", "fox", "boar", "chicken", "dog"]

var world  # World
var kind := ""
var pos := Vector2.ZERO
var state := "enter"
var target: Variant = null      # Vector2i cell, or an Animal for fox->chicken
var exit_pos := Vector2.ZERO
var timer := 0.0
var life := 30.0
var anim_t := 0.0
var flip := false
var dead := false
var speed := 30.0
var hit_farmer := false
var row := 0
var dir := 1.0
var bubble := ""
var bubble_t := 0.0
var tint := Color.WHITE
var hidden := false
var home := Vector2.ZERO
var egg_t := 0.0


func _init(w, k: String, p: Vector2) -> void:
	world = w
	kind = k
	pos = p
	home = p
	anim_t = randf() * 10.0
	match kind:
		"crow":
			speed = 42.0
			life = randf_range(18.0, 30.0)
		"rabbit":
			speed = 26.0
			life = randf_range(20.0, 35.0)
		"fox":
			speed = 30.0
			life = 45.0
		"boar":
			speed = 40.0
			state = "charge"
		"snake":
			life = 70.0
			state = "lurk"
		"wasps":
			life = 120.0
			state = "lurk"
		"chicken":
			speed = 12.0
			state = "wander"
			egg_t = randf_range(50.0, 110.0)
		"dog":
			speed = 40.0
			state = "follow"
		"merchant":
			speed = 18.0
		"butterfly":
			speed = 14.0
			life = randf_range(20.0, 35.0)
			state = "flutter"
			tint = [Color("f19ec2"), Color("ffcd75"), Color("73eff7"), Color("f4f4f4")].pick_random()
		"bee":
			speed = 20.0
			life = randf_range(6.0, 10.0)
			state = "flutter"


func is_threat() -> bool:
	return kind in THREATS and not dead


func leaving() -> bool:
	return state == "leave"


func persistent() -> bool:
	return kind == "chicken" or (kind == "dog" and Game.buff("dog"))


func say(t: String, dur: float = 3.0) -> void:
	bubble = t
	bubble_t = dur


func scare() -> void:
	if dead or state == "leave":
		return
	if kind == "snake" or kind == "wasps":
		world.puff(pos + Vector2(0, -4), Color("94b0c2"), 8)
		dead = true
		return
	if not is_threat():
		return
	if kind == "crow":
		world.puff(pos + Vector2(0, -4), Color("1a1c2c"), 5, 16.0)
	_leave()


func _leave() -> void:
	state = "leave"
	speed *= 1.6
	if kind in ["crow", "butterfly", "bee"]:
		exit_pos = Vector2(pos.x + randf_range(-60, 60), -40)
	else:
		exit_pos = Vector2(-24 if pos.x < world.COLS * 8 else world.COLS * 16 + 24, pos.y)


func _farmer_near(dist: float) -> bool:
	var f = world.farmer
	return f != null and f.visible_outside() and f.pos.distance_to(pos) < dist


func _dog_near(dist: float) -> bool:
	for a in world.animals:
		if a.kind == "dog" and not a.dead and a.pos.distance_to(pos) < dist:
			return true
	return false


## Moves towards p; returns true when there.
func _move(p: Vector2, d: float, spd: float = -1.0) -> bool:
	var v := p - pos
	var s := (speed if spd < 0.0 else spd) * d
	if absf(v.x) > 0.3:
		flip = v.x < 0.0
	if v.length() <= s:
		pos = p
		return true
	pos += v.normalized() * s
	return false


func _random_crop() -> Variant:
	var alive: Array = []
	for c in world.crops:
		if not world.crops[c].get("dead", false):
			alive.append(c)
	if alive.is_empty():
		return null
	return alive.pick_random()


# ---------------------------------------------------------------- update
func update(d: float) -> void:
	anim_t += d
	bubble_t -= d
	match kind:
		"crow", "rabbit": _update_pest(d)
		"fox": _update_fox(d)
		"boar": _update_boar(d)
		"snake": _update_snake(d)
		"wasps": _update_wasps(d)
		"chicken": _update_chicken(d)
		"dog": _update_dog(d)
		"merchant": _update_merchant(d)
		"butterfly", "bee": _update_flutter(d)


func _update_leave(d: float) -> void:
	if _move(exit_pos, d):
		dead = true


func _update_pest(d: float) -> void:
	if state == "leave":
		_update_leave(d)
		return
	life -= d
	if life <= 0.0:
		_leave()
		return
	if _farmer_near(18.0) or _dog_near(26.0):
		scare()
		return
	if target == null or not world.crops.has(target) or world.crops[target].get("dead", false):
		target = _random_crop()
		state = "enter"
		if target == null:
			_leave()
			return
	if state == "enter":
		var hop := kind == "rabbit"
		if _move(world.feet(target) + Vector2(randf_range(-1, 1), 0), d, speed * (0.5 + 0.5 * absf(sin(anim_t * 8.0))) if hop else speed):
			state = "eat"
			timer = 0.0
	elif state == "eat":
		timer += d
		if timer > 2.5:
			timer = 0.0
			world.damage_crop(target, 0.06, 9.0)
			world.puff(world.feet(target) + Vector2(0, -4), Color("a7f070"), 3, 10.0)


func _update_fox(d: float) -> void:
	if state == "leave":
		if target is Animal and target.state == "carried":
			target.pos = pos + Vector2(-6 if not flip else 6, -2)
		_update_leave(d)
		if dead and target is Animal:
			target.dead = true
		return
	life -= d
	if life <= 0.0 or _dog_near(30.0):
		_leave()
		return
	var f = world.farmer
	if f != null and (f.state == "nap") and f.pos.distance_to(pos) < 40.0:
		if _move(f.pos, d):
			f.hurt(10, "a fox bite")
			_leave()
		return
	if target == null:
		for a in world.animals:
			if a.kind == "chicken" and not a.dead and not a.hidden and a.state != "carried":
				target = a
				break
		if target == null:
			target = _random_crop()
		if target == null:
			_leave()
			return
	if target is Animal:
		if target.dead or target.hidden:
			target = null
			return
		if _move(target.pos, d):
			target.state = "carried"
			Game.add_log("A fox snatched a chicken!")
			Game.mood = maxf(0.0, Game.mood - 8.0)
			if f != null:
				f.say("Hey! My chicken!")
			_leave()
	else:
		if not world.crops.has(target):
			target = null
			return
		if _move(world.feet(target), d):
			timer += d
			if timer > 3.0:
				world.crops.erase(target)
				world.puff(world.feet(target), Color("8b5a3c"), 8)
				Game.add_log("A fox dug up a crop.")
				target = null
				timer = 0.0
				if randf() < 0.5:
					_leave()


func _update_boar(d: float) -> void:
	var spd := speed * (2.0 if state == "leave" else 1.0)
	pos.x += dir * spd * d
	flip = dir < 0.0
	var c: Vector2i = world.cell_of(pos)
	if world.in_bounds(c) and pos.x > 0 and pos.x < world.COLS * 16:
		if world.crops.has(c) and randf() < d * 6.0:
			world.crops.erase(c)
			world.puff(world.feet(c), Color("a7f070"), 6)
		var o: Dictionary = world.obj_at(c)
		if not o.is_empty() and Game.STRUCTS.has(o["type"]) and o["type"] != "rod":
			if timer <= 0.0:
				o["hp"] -= 25
				timer = 0.6
				world.puff(world.feet(c), Color("c28a5a"), 6)
				if o["hp"] <= 0:
					Game.add_log("The boar smashed the %s!" % Game.STRUCTS[o["type"]]["name"])
					world.remove_obj(c)
	timer -= d
	if not hit_farmer and _farmer_near(9.0):
		hit_farmer = true
		world.farmer.hurt(20, "a charging boar")
	if (dir > 0.0 and pos.x > world.COLS * 16 + 24) or (dir < 0.0 and pos.x < -24):
		dead = true


func _update_snake(d: float) -> void:
	life -= d
	if life <= 0.0:
		dead = true


func bite_farmer() -> void:
	if dead:
		return
	var f = world.farmer
	if f == null or not f.visible_outside():
		return
	f.say("YEOW! A snake!")
	Game.poison = 25.0
	f.hurt(6, "a snake bite")
	Game.add_log("The farmer stepped on a snake and got poisoned!")
	dead = true


func _update_wasps(d: float) -> void:
	life -= d
	if life <= 0.0:
		dead = true
		return
	timer -= d
	if timer <= 0.0:
		timer = 1.0
		if _farmer_near(22.0) and randf() < 0.3:
			world.farmer.hurt(4, "wasp stings")


func _update_chicken(d: float) -> void:
	if state == "carried":
		return
	var night: bool = Game.time_of_day > 0.9 or Game.time_of_day < 0.22
	if night:
		if _move(home, d):
			hidden = true
		return
	hidden = false
	egg_t -= d
	if egg_t <= 0.0:
		egg_t = randf_range(60.0, 120.0)
		Game.add_item("egg")
		world.float_text("+EGG", pos + Vector2(-8, -14), Color("f4f4f4"))
	timer -= d
	if timer <= 0.0 or target == null:
		timer = randf_range(2.0, 5.0)
		target = home + Vector2(randf_range(-22, 22), randf_range(-8, 20))
		target.x = clampf(target.x, 4, world.COLS * 16 - 4)
		target.y = clampf(target.y, 36, world.ROWS * 16 - 4)
	_move(target, d)


func _update_dog(d: float) -> void:
	if state == "leave":
		_update_leave(d)
		return
	if not Game.buff("dog"):
		say("Woof! Bye!")
		_leave()
		return
	var near_t: Variant = null
	var bd := 1e9
	for a in world.threats():
		var dd: float = a.pos.distance_to(pos)
		if dd < bd:
			bd = dd
			near_t = a
	if near_t != null:
		state = "chase"
		if _move(near_t.pos, d, speed * 1.2) or bd < 12.0:
			near_t.scare()
			Game.bump("shooed")
			say("WOOF!", 1.5)
			if Game.buff("bounty"):
				Game.add_coins(6)
		return
	state = "follow"
	var f = world.farmer
	var goal: Vector2 = f.pos + Vector2(14, 4) if f != null and f.visible_outside() else world.feet(world.DOOR) + Vector2(16, 0)
	if pos.distance_to(goal) > 10.0:
		_move(goal, d, speed * 0.6)


func _update_merchant(d: float) -> void:
	match state:
		"enter":
			if _move(world.feet(world.BIN_FRONT) + Vector2(10, 0), d):
				state = "trade"
				timer = 3.0
		"trade":
			timer -= d
			if timer <= 0.0:
				var v := Game.inventory_value(1.5)
				if v > 0:
					Game.add_coins(v)
					Game.inventory.clear()
					world.float_text("+%d" % v, pos + Vector2(-6, -24))
					Game.add_log("The merchant bought everything for %d coins!" % v)
					say("Splendid produce!")
				else:
					say("Nothing to sell? Next time!")
				if randf() < 0.3:
					var id := Game.random_card()
					if Game.add_card(id):
						Game.add_log("The merchant left a gift: %s." % Game.CARDS[id]["name"])
				_leave()
		"leave":
			_update_leave(d)


func _update_flutter(d: float) -> void:
	if state == "leave":
		_update_leave(d)
		return
	life -= d
	if life <= 0.0:
		_leave()
		return
	timer -= d
	if timer <= 0.0 or target == null:
		timer = randf_range(1.0, 2.5)
		var base: Vector2 = home if kind == "bee" else pos
		target = base + Vector2(randf_range(-30, 30), randf_range(-20, 20))
		target.x = clampf(target.x, 4, world.COLS * 16 - 4)
		target.y = clampf(target.y, 8, world.ROWS * 16 - 4)
	_move(target, d)


# ---------------------------------------------------------------- drawing
func draw(ci: CanvasItem) -> void:
	if hidden or dead:
		return
	match kind:
		"butterfly":
			var up := int(anim_t * 10.0) % 2 == 0
			var y := sin(anim_t * 5.0) * 2.0
			ci.draw_rect(Rect2(pos + Vector2(-1, y - 1), Vector2(1, 2 if up else 1)), tint)
			ci.draw_rect(Rect2(pos + Vector2(1, y - 1), Vector2(1, 2 if up else 1)), tint)
			ci.draw_rect(Rect2(pos + Vector2(0, y - 1), Vector2(1, 2)), Color("1a1c2c"))
			return
		"bee":
			var y2 := sin(anim_t * 12.0) * 1.5
			ci.draw_rect(Rect2(pos + Vector2(-1, y2), Vector2(2, 1)), Color("ffcd75"))
			ci.draw_rect(Rect2(pos + Vector2(0, y2), Vector2(1, 1)), Color("1a1c2c"))
			ci.draw_rect(Rect2(pos + Vector2(0, y2 - 1), Vector2(1, 1)), Color(1, 1, 1, 0.7))
			return
		"wasps":
			var nest := Art.tex("wasp_nest")
			ci.draw_texture(nest, pos + Vector2(-8, -16))
			for i in 4:
				var a := anim_t * (5.0 + i) + i * 1.7
				var p := pos + Vector2(cos(a) * (5 + i), -9 + sin(a * 1.3) * 4)
				ci.draw_rect(Rect2(p, Vector2(1, 1)), Color("ffcd75"))
				ci.draw_rect(Rect2(p + Vector2(1, 0), Vector2(1, 1)), Color("1a1c2c"))
			return
	var frame := kind
	var flying := false
	match kind:
		"crow":
			flying = state != "eat"
			frame = "crow_fly" if flying else "crow"
			if flying and int(anim_t * 8.0) % 2 == 0:
				frame = "crow"
		"rabbit":
			frame = "rabbit_hop" if state != "eat" and int(anim_t * 6.0) % 2 == 0 else "rabbit"
		"fox":
			frame = "fox_run" if int(anim_t * 8.0) % 2 == 0 else "fox"
		"boar":
			frame = "boar_run" if int(anim_t * 10.0) % 2 == 0 else "boar"
		"chicken":
			frame = "chicken2" if int(anim_t * 3.0) % 2 == 0 else "chicken"
		"dog":
			frame = "dog_run" if state != "follow" and int(anim_t * 8.0) % 2 == 0 else "dog"
		"merchant":
			frame = "merchant2" if state != "trade" and int(anim_t * 5.0) % 2 == 0 else "merchant"
		"snake":
			frame = "snake2" if int(anim_t * 3.0) % 2 == 0 else "snake"
	var tx := Art.tex(frame)
	var w := tx.get_width()
	var h := tx.get_height()
	var lift := 0.0
	if flying:
		lift = 10.0 + sin(anim_t * 6.0) * 2.0
	if kind == "snake":
		tint = Color(1, 1, 1, 0.85)
	ci.draw_rect(Rect2(pos.x - w * 0.3, pos.y, w * 0.6, 1), Color(0, 0, 0, 0.2))
	var face_left: bool = kind in FACES_LEFT
	var mirror := flip != face_left
	ci.draw_set_transform(pos + Vector2(0, -lift), 0.0, Vector2(-1.0 if mirror else 1.0, 1.0))
	ci.draw_texture(tx, Vector2(-w / 2.0, -h), tint)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


func to_dict() -> Dictionary:
	return {"kind": kind, "x": pos.x, "y": pos.y, "hx": home.x, "hy": home.y}


func from_dict(d: Dictionary) -> void:
	home = Vector2(float(d.get("hx", pos.x)), float(d.get("hy", pos.y)))
