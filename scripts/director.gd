extends Node
## Director: the "dungeon master". Schedules random events (including weird ones that unlock
## as Game.weird rises), cycles the weather, throws lightning, spreads fire, and implements the
## world "actions" that choice-card effects call (do_action).

signal shake(amount: float)

const WEATHER_NEXT := {
	"sunny": {"sunny": 3, "cloudy": 3, "heat": 2, "rain": 2},
	"cloudy": {"sunny": 4, "rain": 4, "storm": 2},
	"rain": {"cloudy": 4, "sunny": 3, "storm": 3},
	"storm": {"rain": 6, "cloudy": 4},
	"heat": {"sunny": 7, "cloudy": 3},
}
const WEATHER_DUR := {
	"sunny": Vector2(120, 240), "cloudy": Vector2(60, 120), "rain": Vector2(50, 100),
	"storm": Vector2(35, 70), "heat": Vector2(70, 140),
}
const FLAMMABLE := ["fence", "flowerbed", "bench", "sign", "scarecrow", "beehive", "tree", "weed", "stump", "coop"]

var world: World
var weather_fx: Node2D
var cards: Node
var weather_t := 90.0
var event_t := 25.0
var bolt_t := 6.0
var fire_t := 4.0
var _playing_all := false


func _process(delta: float) -> void:
	if not Game.running:
		return
	var d := delta * Game.time_scale
	weather_t -= d
	if weather_t <= 0.0:
		_next_weather()
	event_t -= d
	if event_t <= 0.0:
		event_t = randf_range(30.0, 70.0) / (1.0 + Game.level() * 0.08)
		random_event()
	if Game.weather == "storm":
		bolt_t -= d
		if bolt_t <= 0.0:
			bolt_t = randf_range(5.0, 12.0)
			lightning()
	fire_t -= d
	if fire_t <= 0.0:
		fire_t = 3.0
		_tick_fires()
	# keep a dog around while the Watchdog buff lasts (e.g. after loading)
	if Game.buff("dog") and world.count_animals("dog") == 0:
		_spawn_dog()


# ---------------------------------------------------------------- weather
func _next_weather() -> void:
	var opts: Dictionary = WEATHER_NEXT.get(Game.weather, WEATHER_NEXT["sunny"])
	var total := 0
	for k in opts:
		total += int(opts[k])
	var r := randi() % total
	var pick := "sunny"
	for k in opts:
		r -= int(opts[k])
		if r < 0:
			pick = k
			break
	if pick == "heat" and Game.is_night():
		pick = "sunny"
	set_weather(pick)


func set_weather(w: String, dur: float = -1.0) -> void:
	var range_v: Vector2 = WEATHER_DUR[w]
	weather_t = dur if dur > 0.0 else randf_range(range_v.x, range_v.y)
	if w != Game.weather:
		var msgs := {"sunny": "The sky clears up.", "cloudy": "Clouds roll in.", "rain": "It starts to rain.",
			"storm": "A thunderstorm is brewing!", "heat": "A heatwave hits the farm!"}
		Game.add_log(msgs[w])
	Game.set_weather(w)
	if w == "rain" or w == "storm":
		for c in world.cells_with_obj(["fire"]):
			if randf() < 0.6:
				extinguish(c)


func lightning(force_cell: Variant = null) -> void:
	var c: Vector2i
	var rods: Array = world.cells_with_obj(["rod", "obelisk"])
	var f := world.farmer
	if force_cell != null:
		c = force_cell
	elif rods.size() > 0 and randf() < 0.85:
		c = rods[0]
		if world.obj_type(c) == "obelisk":
			Game.add_log("Lightning strikes the obelisk. It hums happily.")
			Game.add_weird(0.5)
		else:
			Game.add_log("The lightning rod caught a bolt!")
	elif f != null and f.visible_outside() and randf() < 0.22:
		c = f.cell()
	else:
		c = Vector2i(randi() % world.COLS, randi() % world.ROWS)
	if weather_fx:
		weather_fx.strike(world.center(c))
	shake.emit(2.0)
	world.puff(world.center(c), Color("ffcd75"), 12, 30.0)
	if world.obj_type(c) in ["rod", "obelisk"]:
		return
	if f != null and f.visible_outside() and f.pos.distance_to(world.feet(c)) < 20.0:
		f.hurt(25, "a lightning strike")
	if world.is_house(c) or world.obj_type(c) == "bin":
		return
	ignite(c)


func ignite(c: Vector2i) -> void:
	if not world.in_bounds(c) or world.is_house(c):
		return
	var t := world.obj_type(c)
	if t in ["fire", "bin", "rod", "well", "idol", "obelisk", "stones", "saucer"] or t in World.MYSTERY:
		return
	var flammable := world.crops.has(c) or t in FLAMMABLE
	if not flammable:
		if t == "" and not world.is_tilled(c) and randf() < 0.25:
			world.place_obj(c, "ash")
		return
	var under: Dictionary = world.obj_at(c).duplicate()
	if world.crops.has(c):
		world.crops[c]["dead"] = true
	world.objs[c] = {"type": "fire", "hp": 1, "age": 0.0, "under": under}
	Game.add_log("Fire! Something is burning.")


func extinguish(c: Vector2i) -> void:
	var o: Dictionary = world.obj_at(c)
	if o.get("type", "") != "fire":
		return
	var under: Dictionary = o.get("under", {})
	if under.is_empty():
		world.remove_obj(c)
	else:
		under["hp"] = int(under.get("hp", 50)) / 2
		world.objs[c] = under
	world.puff(world.center(c), Color("94b0c2"), 10, 16.0)


func _tick_fires() -> void:
	var fires: Array = world.cells_with_obj(["fire"])
	var raining := Game.weather == "rain" or Game.weather == "storm"
	for c in fires:
		var o: Dictionary = world.objs[c]
		o["age"] = float(o.get("age", 0.0)) + 3.0
		if raining and randf() < 0.5:
			extinguish(c)
			continue
		if o["age"] > 18.0:
			var under: Dictionary = o.get("under", {})
			if not under.is_empty() and Game.STRUCTS.has(under.get("type", "")):
				Game.add_log("The %s burned down." % Game.STRUCTS[under["type"]]["name"])
			world.remove_obj(c)
			world.crops.erase(c)
			world.place_obj(c, "ash")
			continue
		for dd in World.DIRS:
			var n: Vector2i = c + dd
			if randf() < 0.18:
				ignite(n)
		var f := world.farmer
		if f != null and f.visible_outside() and f.pos.distance_to(world.feet(c)) < 10.0 and randf() < 0.5:
			f.hurt(5, "a burn")


# ---------------------------------------------------------------- random events
func random_event(force: String = "") -> void:
	var lv := Game.level()
	var has_crops := world.crops.size() > 0
	var ev := {}
	if has_crops:
		if not Game.has_relic("crow_crown") and not Game.buff("crow_truce"):
			ev["crows"] = 10
		ev["rabbits"] = 6
	if (Game.is_evening() or Game.is_night()) and not Game.has_relic("lantern") and Game.day >= 2:
		ev["fox"] = 5
	if lv >= 2 and not Game.buff("boar_guard"):
		ev["boar"] = 3
	if not Game.is_night():
		ev["snake"] = 3
		ev["butterflies"] = 4
	if world.cells_with_obj(["tree"] + Game.STRUCTS.keys()).size() > 0:
		ev["wasps"] = 3
	ev["weeds"] = 5 if world.cleared_ratio() > 0.7 else 1
	if Game.inventory_count() > 0:
		ev["merchant"] = 2
	ev["lucky"] = 4 if Game.has_relic("black_cat") else 1
	# the strange stuff, unlocked by weirdness
	var w := Game.weird
	if w >= 10 and Game.is_night():
		ev["wisps"] = 3
	if w >= 15:
		ev["knock"] = 2
	if w >= 20 and world.crops.size() >= 3:
		ev["crop_circle"] = 2
	if w >= 25 and has_crops:
		ev["mutation"] = 2
	if w >= 30:
		ev["whispers"] = 2
	if w >= 35 and Game.is_night():
		ev["abduction"] = 2
	var pick := force
	if pick == "":
		var total := 0
		for k in ev:
			total += int(ev[k])
		var r := randi() % total
		for k in ev:
			r -= int(ev[k])
			if r < 0:
				pick = k
				break
	run_event(pick)


func run_event(id: String) -> void:
	var lv := Game.level()
	match id:
		"crows":
			var n := randi_range(1, 2 + lv / 3)
			var scared := 0
			var scarecrows := world.count_obj("scarecrow")
			for i in n:
				if scarecrows > 0 and randf() < 0.35 * scarecrows:
					scared += 1
					continue
				spawn_animal("crow", Vector2(randf_range(0, world.COLS * 16), -20))
			if scared > 0:
				Game.add_log("The scarecrow spooked %d crow%s." % [scared, "s" if scared > 1 else ""])
			if n - scared > 0:
				Game.add_log("Crows are after the crops!")
		"rabbits":
			for i in randi_range(1, 2):
				spawn_animal("rabbit", _edge_pos())
			Game.add_log("Hungry rabbits hop in.")
		"fox":
			spawn_animal("fox", _edge_pos())
			Game.add_log("A sly fox is prowling...")
		"boar":
			var a := spawn_animal("boar", Vector2.ZERO)
			var row := randi_range(3, world.ROWS - 1)
			a.dir = 1.0 if randf() < 0.5 else -1.0
			a.pos = Vector2(-20 if a.dir > 0 else world.COLS * 16 + 20, row * 16 + 13)
			Game.add_log("A wild boar is stampeding!")
			if world.farmer:
				world.farmer.say("Is that... a BOAR?!")
		"snake":
			var cells := world.free_grass_cells() + world.tilled_cells()
			if cells.size() > 0:
				var c: Vector2i = cells.pick_random()
				spawn_animal("snake", world.feet(c))
		"wasps":
			var hosts: Array = world.cells_with_obj(["tree"] + Game.STRUCTS.keys())
			if hosts.size() > 0 and world.count_animals("wasps") < 2:
				var h: Vector2i = hosts.pick_random()
				spawn_animal("wasps", world.feet(h) + Vector2(6, 3))
				Game.add_log("Wasps built a nest near the %s." % _obj_name(h))
		"weeds":
			var cells2 := world.free_grass_cells()
			cells2.shuffle()
			for i in mini(randi_range(2, 4), cells2.size()):
				world.place_obj(cells2[i], "weed")
		"merchant":
			spawn_animal("merchant", Vector2(-16, world.feet(world.BIN_FRONT).y))
			Game.add_log("A travelling merchant arrives.")
		"butterflies":
			for i in randi_range(3, 5):
				spawn_animal("butterfly", Vector2(randf_range(10, 180), randf_range(20, world.ROWS * 16 - 16)))
			Game.mood = minf(100.0, Game.mood + 4.0)
		"wisps":
			for i in randi_range(4, 7):
				spawn_animal("wisp", Vector2(randf_range(10, 180), randf_range(30, world.ROWS * 16 - 16)))
			Game.add_log("Pale wisps drift across the fields.")
			if world.farmer and world.farmer.visible_outside() and randf() < 0.4:
				world.loot("wisp_jar")
				world.farmer.say("Got one! In the jar you go.")
		"knock":
			Game.add_log("Someone knocked three times. Nobody was there. A card lay on the step.")
			cards.draw_card()
		"crop_circle":
			var alive: Array = []
			for c in world.crops:
				if not world.crops[c].get("dead", false):
					alive.append(c)
			alive.shuffle()
			for i in mini(3, alive.size()):
				world.crops[alive[i]]["growth"] = 1.0
			Game.add_item("ore", 1)
			Game.add_weird(2.0)
			Game.add_log("A crop circle appeared overnight. The crops inside are ripe.")
			if alive.size() > 0:
				world.loot("alien_bolt", 1, world.center(alive[0]))
		"mutation":
			for c in world.crops:
				var cr: Dictionary = world.crops[c]
				if not cr.get("dead", false) and cr["type"] != "glowshroom":
					cr["type"] = "glowshroom"
					world.puff(world.center(c), Color("73eff7"), 8)
					Game.add_log("A crop mutated into a glowshroom!")
					break
		"whispers":
			Game.mood = maxf(0.0, Game.mood - 8.0)
			if world.farmer:
				world.farmer.say(["The ground is talking again.", "Who keeps calling my name?", "I dreamt of the field. It was awake."].pick_random(), 4.0)
			Game.add_log("The farmer hears whispers.")
			if randf() < 0.3:
				world.loot("tome_page")
				Game.add_log("A torn page was lying on the doorstep. The ink is still wet.")
		"abduction":
			var chickens: Array = []
			for a in world.animals:
				if a.kind == "chicken" and not a.dead and not a.hidden:
					chickens.append(a)
			var p := Vector2.ZERO
			if chickens.size() > 0:
				var ch = chickens.pick_random()
				p = ch.pos
				ch.dead = true
				Game.add_log("A beam of light took a chicken. It left 2 ore behind.")
			elif world.crops.size() > 0:
				var c2: Vector2i = world.crops.keys().pick_random()
				p = world.center(c2)
				world.crops.erase(c2)
				Game.add_log("A beam of light took a crop. It left 2 ore behind.")
			else:
				return
			if weather_fx:
				weather_fx.beam(p)
			Game.add_item("ore", 2)
			Game.add_weird(2.0)
			if randf() < 0.5:
				world.loot("star_shard", 1, p)
		"lucky":
			if world.farmer:
				var finds := ["marble", "ribbon", "button", "tin_soldier", "arrowhead", "rusty_key"]
				if lv >= 3:
					finds += ["silver_spoon", "pocket_watch"]
				world.loot(finds.pick_random())
				world.farmer.say(["Ooh, something shiny in the dirt!", "Finders keepers!", "For the chest!"].pick_random())


func _obj_name(c: Vector2i) -> String:
	var t := world.obj_type(c)
	return Game.STRUCTS[t]["name"] if Game.STRUCTS.has(t) else t


func _edge_pos() -> Vector2:
	var left := randf() < 0.5
	return Vector2(-14 if left else world.COLS * 16 + 14, randf_range(48, world.ROWS * 16 - 8))


func spawn_animal(kind: String, p: Vector2) -> Animal:
	return world.add_animal(Animal.new(world, kind, p))


func _spawn_dog() -> void:
	var a := spawn_animal("dog", Vector2(-14, world.feet(world.DOOR).y + 16))
	a.say("Woof!")


# ---------------------------------------------------------------- actions (used by card effects)
func do_action(id: String) -> void:
	var f := world.farmer
	var lv := Game.level()
	match id:
		"rain":
			set_weather("rain", 60.0)
			for c in world.cells_with_obj(["fire"]):
				extinguish(c)
			for c in world.tilled_cells():
				world.wet[world.idx(c)] = 1.0
		"sun":
			Game.add_buff("sun", 120.0)
			if Game.weather != "sunny" and Game.weather != "heat":
				set_weather("sunny")
			Game.add_log("Sunshine! Crops grow twice as fast.")
		"shoo":
			var n := 0
			for a in world.threats():
				a.scare()
				n += 1
			Game.bump("shooed", n)
			Game.add_log("SHOO! %d critter%s fled." % [n, "" if n == 1 else "s"])
			if f and n > 0:
				f.say("Whoa, where'd they all go?")
		"dog":
			Game.add_buff("dog", Game.DAY_LENGTH)
			if world.count_animals("dog") == 0:
				_spawn_dog()
			Game.add_log("A watchdog joins the farm for the day.")
		"soup":
			Game.health = minf(100.0, Game.health + 50.0)
			Game.poison = 0.0
			Game.mood = minf(100.0, Game.mood + 5.0)
			if f:
				f.say("Mmm, hearty soup!")
				world.puff(f.pos + Vector2(0, -8), Color("a7f070"), 10)
		"coffee":
			Game.energy = minf(100.0, Game.energy + 60.0)
			Game.mood = minf(100.0, Game.mood + 5.0)
			if f:
				if f.state == "nap":
					f.state = "idle"
				f.say("Ahh, COFFEE! Let's go!")
		"charm":
			Game.charms = mini(3, Game.charms + 1)
			Game.add_log("The farmer feels lucky. (%d charm%s)" % [Game.charms, "" if Game.charms == 1 else "s"])
		"fert":
			for c in world.crops:
				var cr: Dictionary = world.crops[c]
				if not cr.get("dead", false):
					cr["growth"] = minf(1.0, cr["growth"] + 0.35)
					cr["health"] = 100.0
					world.puff(world.center(c), Color("a7f070"), 3, 10.0)
			Game.add_log("Fertilizer! The crops shoot up.")
		"gold":
			var spot: Variant = null
			for c in world.tilled_cells():
				if not world.crops.has(c) and not world.objs.has(c):
					spot = c
					break
			if spot == null:
				var free := world.free_grass_cells()
				if free.size() > 0:
					spot = world.nearest(free, world.DOOR + Vector2i(0, 4))
					world.set_tilled(spot, true)
			if spot != null:
				world.plant(spot, "melon")
				world.wet[world.idx(spot)] = 1.0
				world.puff(world.center(spot), Color("ffcd75"), 14, 20.0)
				Game.add_log("A golden seed sprouts!")
		"trinkets":
			var amt := int((10 + lv * 8) * randf_range(0.8, 1.4))
			var p := f.pos if f and f.visible_outside() else world.center(world.BIN)
			world.loot_trinkets(amt, p)
		"clear":
			set_weather("sunny", 180.0)
			Game.mood = minf(100.0, Game.mood + 10.0)
		"storm":
			set_weather("storm", 45.0)
			bolt_t = 2.0
		"meteor":
			var cells: Array = []
			for y in range(3, world.ROWS):
				for x in world.COLS:
					var c := Vector2i(x, y)
					if world.obj_type(c) != "bin" and not world.obj_type(c) in World.MYSTERY:
						cells.append(c)
			var c2: Vector2i = cells.pick_random()
			if weather_fx:
				weather_fx.meteor(world.center(c2))
			await get_tree().create_timer(0.6).timeout
			shake.emit(4.0)
			world.crops.erase(c2)
			world.remove_obj(c2)
			world.place_obj(c2, "ore")
			world.puff(world.center(c2), Color("ef7d57"), 20, 40.0)
			if f and f.visible_outside() and f.pos.distance_to(world.feet(c2)) < 24.0:
				f.hurt(15, "flying meteor debris")
			Game.add_log("A meteorite crashed into the farm!")
			world.loot("star_shard", 1, world.center(c2))
			if f:
				f.say("WHAT WAS THAT?!")
		"bloom":
			for i in 30:
				var c3 := Vector2i(randi() % world.COLS, randi() % world.ROWS)
				world.gvar[world.idx(c3)] = 3
			for i in 4:
				spawn_animal("butterfly", Vector2(randf_range(10, 180), randf_range(20, world.ROWS * 16 - 16)))
			Game.mood = minf(100.0, Game.mood + 15.0)
			Game.add_log("Flowers bloom all over the farm!")
			if f:
				f.say("How beautiful!")
		"bees":
			var n2 := 0
			for c in world.crops:
				var cr2: Dictionary = world.crops[c]
				if not cr2.get("dead", false) and cr2["growth"] >= 0.45:
					cr2["growth"] = 1.0
					n2 += 1
					var b := spawn_animal("bee", world.center(c))
					b.home = world.center(c)
			Game.add_log("Bees pollinated %d crop%s." % [n2, "" if n2 == 1 else "s"])
		"merchant":
			run_event("merchant")
		"tree":
			var free2 := world.free_grass_cells()
			var edge: Array = []
			for c in free2:
				if c.x == 0 or c.x == world.COLS - 1 or c.y == world.ROWS - 1:
					edge.append(c)
			var pool: Array = edge if edge.size() > 0 else free2
			if pool.size() > 0:
				var c4: Vector2i = pool.pick_random()
				world.place_obj(c4, "tree", {"apple": true})
				world.puff(world.center(c4), Color("38b764"), 12, 20.0)
				Game.add_log("An apple tree sprang up.")
		"critters":
			Game.add_buff("bounty", 90.0)
			for i in 3:
				spawn_animal("crow", Vector2(randf_range(0, world.COLS * 16), -20))
			for i in 2:
				spawn_animal("rabbit", _edge_pos())
			Game.add_log("Critters incoming! Every shoo leaves a souvenir.")
		"repair":
			for c in world.objs:
				var o: Dictionary = world.objs[c]
				if Game.STRUCTS.has(o["type"]):
					o["hp"] = Game.STRUCTS[o["type"]]["hp"]
			Game.add_log("Every building on the farm is good as new.")
		"quake":
			shake.emit(5.0)
			var weeds: Array = world.cells_with_obj(["weed"])
			for c in weeds:
				world.remove_obj(c)
				world.puff(world.center(c), Color("38b764"), 4)
			var free3 := world.free_grass_cells()
			free3.shuffle()
			for i in mini(2, free3.size()):
				world.place_obj(free3[i], "rock")
			Game.add_log("A tremor! %d weeds shaken loose." % weeds.size())
			if f and f.visible_outside():
				f.say("Whoa whoa whoa!")
