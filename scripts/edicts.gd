class_name Edicts
extends Node
## Edicts: lasting rules a card lays down over the farm (Game.EDICTS, state in Game.edicts).
## A one-off card effect is soon lost among everything else going on; an edict keeps steering
## the simulation every day, and every time it kicks in the log (and now and then the farmer)
## names it, so a choice made days ago stays visible as the reason things are the way they are.
## Each edict has a rival (the other choice on the same card): enacting one revokes the other.
## Card effects: ["edict", id], ["lose_edict", id | "" = a random one]. Requirements: ["edict", id],
## ["no_edict", id], ["edicts", n]. Hooks elsewhere (search for Game.has_edict): director (weather,
## events), world (wild reserve, weed regrowth), farmer (reserve, scarecrows, tidiness), animal (crows,
## rabbits), tides (the wild's boons).

var world: World
var director: Node
var colony: Colony
var swarm: Swarm
var _t := 0.0
var _talk_t := 150.0
var _last_tod := 0.0


func _ready() -> void:
	_last_tod = Game.time_of_day


func _process(delta: float) -> void:
	if not Game.simulating() or world == null:
		return
	var d := delta * Game.time_scale
	if Game.edicts.is_empty():
		_last_tod = Game.time_of_day
		return
	# dawn: every edict does its daily thing
	if _last_tod < 0.26 and Game.time_of_day >= 0.26:
		for id in Game.edicts.keys():
			_dawn(id)
	_last_tod = Game.time_of_day
	_t -= d
	if _t <= 0.0:
		_t = 5.0
		_enforce()
	_talk_t -= d
	if _talk_t <= 0.0:
		_talk_t = randf_range(200.0, 400.0)
		var f := world.farmer
		if f and f.visible_outside() and f.state != "nap":
			var id: String = Game.edicts.keys().pick_random()
			f.say(Array(Game.EDICTS[id]["lines"]).pick_random(), 4.0)


## Lays down an edict (revoking its rival) and makes the change at once, where it can be seen.
func enact(id: String) -> void:
	if not Game.EDICTS.has(id) or Game.has_edict(id):
		return
	var def: Dictionary = Game.EDICTS[id]
	if Game.has_edict(def["rival"]):
		revoke(def["rival"], true)
	Game.edicts[id] = {"day": Game.day}
	Game.add_log("NEW EDICT: %s. %s" % [def["name"], def["desc"]])
	var f := world.farmer
	match id:
		"rain_covenant":
			director.set_weather("rain", 150.0)
			for c in world.tilled_cells():
				world.wet[world.idx(c)] = 1.0
		"sun_covenant":
			director.set_weather("sunny", 240.0)
			Game.add_buff("sun", 180.0)
		"wild_reserve":
			_make_reserve()
		"tame_all":
			var n := 0
			for c in world.cells_with_obj(World.TREES):
				world.remove_obj(c)
				world.puff(world.center(c), Color("c28a5a"), 10, 18.0)
				Game.add_item("wood", 3)
				n += 1
			world.clear_overgrowth(12)
			if n > 0:
				Game.add_log("Every tree on the farm came down (%d). +%d wood." % [n, n * 3])
		"side_aliens", "side_brood":
			var friend_aliens := id == "side_aliens"
			if friend_aliens and colony and not colony.active() and colony.population() == 0:
				colony.arrive("")
			if not friend_aliens and swarm and not swarm.active() and swarm.members().is_empty():
				swarm.arrive("")
			_enforce()
		"crow_pact":
			for c in world.cells_with_obj(["scarecrow"]):
				world.remove_obj(c)
				world.puff(world.center(c), Color("c28a5a"), 10, 18.0)
			for i in 4:
				director.spawn_animal("crow", Vector2(randf_range(0, World.COLS * 16), -20))
		"hen_republic":
			if world.count_obj("coop") == 0:
				world.place_struct_auto("coop")
			_add_hens(3)
	if f:
		f.say("%s, eh? Right." % def["name"], 3.0)


## Lifts an edict. `replaced` = its rival is taking over (no separate news).
func revoke(id: String, replaced: bool = false) -> void:
	if not Game.has_edict(id):
		return
	Game.edicts.erase(id)
	Game.add_log("%s: the %s no longer holds." % ["REPLACED" if replaced else "EDICT BROKEN", Game.EDICTS[id]["name"]])


func revoke_random() -> void:
	if not Game.edicts.is_empty():
		revoke(Game.edicts.keys().pick_random())


func _note(id: String, text: String) -> void:
	Game.add_log("%s (%s)" % [text, Game.EDICTS[id]["name"]])


func _dawn(id: String) -> void:
	match id:
		"rain_covenant":
			director.set_weather("rain", 100.0)
			_note(id, "Rain at dawn, as promised.")
		"sun_covenant":
			director.set_weather("sunny", 200.0)
			Game.add_buff("sun", 150.0)
			_note(id, "A blazing sunrise. Crops grow twice as fast this morning.")
		"wild_reserve":
			var spots: Array = world.free_grass_cells().filter(world.in_reserve)
			spots.shuffle()
			for c in spots.slice(0, 3):
				world.place_obj(c, ["tallgrass", "bush", "bramble", "weed"].pick_random())
			if spots.size() > 0:
				_note(id, "The reserve grows thicker overnight.")
		"side_aliens":
			if colony and colony.active() and colony.population() > 0:
				Game.add_item("ore", 1)
				_note(id, "The aliens left a lump of ore on the step.")
		"side_brood":
			if swarm and swarm.active() and not swarm.members().is_empty():
				Game.add_item("honey", 3)
				_note(id, "Honeycomb from the brood on the doorstep.")
		"crow_pact":
			for i in 3:
				director.spawn_animal("crow", Vector2(randf_range(0, World.COLS * 16), -20))
			var took := ""
			for t in ["button", "marble", "ribbon", "tin_soldier"]:
				if Game.treasure_count(t) > 0:
					Game.remove_treasure(t, 1)
					took = String(Game.TREASURES[t]["name"]).to_lower()
					break
			_note(id, "The crows came to stand guard%s." % ((" and took a " + took) if took != "" else ""))
		"hen_republic":
			if world.count_animals("chicken") < 12:
				_add_hens(1)
			var young: Array = []
			for c in world.crops:
				if not world.crops[c].get("dead", false) and float(world.crops[c]["growth"]) < 0.35:
					young.append(c)
			young.shuffle()
			for c in young.slice(0, 2):
				world.crops.erase(c)
				world.puff(world.center(c), Color("a7f070"), 4, 8.0)
			_note(id, "A new hen joined the flock%s." % (" and the hens pecked up %d seedlings" % mini(2, young.size()) if young.size() > 0 else ""))


## Every few seconds: the pacts hold relations where they promised.
func _enforce() -> void:
	var aliens_friend := Game.has_edict("side_aliens")
	var brood_friend := Game.has_edict("side_brood")
	if not aliens_friend and not brood_friend:
		return
	if colony:
		var r := colony.rel()
		Game.colony["rel"] = maxf(r, 45.0) if aliens_friend else minf(r, -35.0)
	if swarm and not Game.brood.is_empty():
		var bf := swarm.rel_farm()
		Game.brood["rel_farm"] = maxf(bf, 45.0) if brood_friend else minf(bf, -35.0)
		# a friend of the farm's enemy is no friend: the two factions stay at odds
		Game.brood["rel_aliens"] = minf(float(Game.brood.get("rel_aliens", 0.0)), -45.0)


## The south rows go back to the wild at once: fields there are abandoned and the thicket moves in.
func _make_reserve() -> void:
	var kept: Array = []
	for fl in world.fields:
		var inside := false
		for c in fl["cells"]:
			if world.in_reserve(c):
				inside = true
				break
		if not inside:
			kept.append(fl)
	world.fields = kept
	for y in range(World.ROWS - World.RESERVE_ROWS, World.ROWS):
		for x in World.COLS:
			var c := Vector2i(x, y)
			if world.is_house(c) or world.is_water(c) or world.obj_type(c) == "mailbox":
				continue
			if world.is_tilled(c):
				world.crops.erase(c)
				world.set_tilled(c, false)
			if not world.objs.has(c) and randf() < 0.7:
				var t: String = ["tallgrass", "bush", "bramble", "tallgrass", "weed", "tree"].pick_random()
				if t == "tree":
					world.place_obj(c, "tree", {"apple": randf() < 0.5})
				else:
					world.place_obj(c, t)
				world.puff(world.center(c), Color("38b764"), 4, 10.0)


func _add_hens(n: int) -> void:
	var coops: Array = world.cells_with_obj(["coop"])
	var home: Vector2 = world.feet(coops[0]) + Vector2(0, 10) if coops.size() > 0 else world.feet(world.DOOR) + Vector2(16, 16)
	for i in n:
		var ch: Animal = director.spawn_animal("chicken", home + Vector2(randf_range(-10, 10), randf_range(0, 6)))
		ch.home = home
