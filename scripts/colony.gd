extends Node
class_name Colony
## The alien faction. Individuals (alien.gd) live in World.animals; this node runs the colony
## as a whole and keeps its state in Game.colony (so it saves with the slot):
##
##  arrivals    egg (falls from the sky), saucer (drops colonists), stranger (walks in and founds
##              a village), lurker (sneaks in at night and mutates a chicken). With no aliens on
##              the farm a new arrival is always on its way, so they keep coming back.
##  life cycle  eggs hatch, spawnlings mature into a caste the colony needs, adults grow old,
##              the oldest elder is the matriarch, everyone dies eventually (and leaves a husk).
##  economy     food (glow moss, raids, hunting, gifts) feeds everyone; matter (overgrowth the
##              creep absorbs, lightning on the spire) pays for buildings. Hunger kills.
##  village     pods (housing), hatchery (eggs), glow moss (food), spire (big claim, catches
##              lightning), dish (outreach), pylons (border claims). Buildings claim land; the
##              creep (World.alien_land) spreads over claimed land, eats overgrowth, un-tills
##              the farmer's fields and mutates his crops. It never reaches the farmhouse.
##  relations   Game.colony.rel (-100..100) drifts with temperament, the farmer's mutations,
##              raids, gifts and cards. Friendly: envoys bring gifts and trades. Hostile: scouts
##              raid crops, wardens zap trespassers, saucers abduct at night.
##  eras        founding / growing / expanding / golden / decline / hostile / exodus.
##  the call    a colony that has lived on the farm long enough hears from home: either everyone
##              leaves for the stars (the village falls to ruin) or a second wave arrives.
## Tides (tides.gd) calls boon()/bane() to keep the balance of power moving.

signal changed

const BUILDINGS := {
	"a_pod":      {"name": "pod",      "cost": 6,  "work": 22.0, "hp": 60,  "claim": 1.5, "house": 3},
	"a_hatchery": {"name": "hatchery", "cost": 10, "work": 32.0, "hp": 70,  "claim": 1.5, "house": 2},
	"a_moss":     {"name": "glow moss", "cost": 1, "work": 5.0,  "hp": 20,  "claim": 0.0, "house": 0},
	"a_spire":    {"name": "spire",    "cost": 18, "work": 55.0, "hp": 220, "claim": 3.6, "house": 2},
	"a_dish":     {"name": "dish",     "cost": 12, "work": 38.0, "hp": 80,  "claim": 1.5, "house": 0},
	"a_pylon":    {"name": "pylon",    "cost": 8,  "work": 28.0, "hp": 150, "claim": 2.6, "house": 0},
}
const SOLID := ["a_pod", "a_hatchery", "a_spire", "a_dish", "a_pylon"]
const ERAS := {"none": "No aliens", "founding": "Founding", "growing": "Growing", "expanding": "Expanding",
	"golden": "Golden age", "decline": "Decline", "hostile": "Hostile", "exodus": "Exodus"}
const SYLLABLES := ["zib", "vorp", "qua", "glee", "xan", "oop", "blib", "zor", "nix", "ulu", "kree", "mip", "thra", "yog"]
const VILLAGE_NAMES := ["New Zorp", "Glimmerhive", "Crater Hollow", "Spore Point", "Little Andromeda", "Blipton",
	"The Hum", "Moss Moon", "Outpost Q", "Glorpshire"]
const FOOD_PER_ADULT := 1.0 / 110.0   # food per second
const MOSS_GROW := 170.0
const MOSS_FOOD := 2.5

var world: World
var director: Node
var cards: Node
var _acc := 0.0
var _queen: Alien = null


func _ready() -> void:
	_ensure_state()


func _ensure_state() -> void:
	var c: Dictionary = Game.colony
	var defaults := {"active": false, "food": 0.0, "matter": 0.0, "rel": 0.0, "morale": 0.0, "aggro": randf_range(0.2, 0.6),
		"era": "none", "site": {}, "arrive_t": Game.DAY_LENGTH * randf_range(1.2, 2.4), "arrivals": 0, "gen": 0,
		"born": 0, "died": 0, "built": 0, "outreach_t": 300.0, "egg_t": 90.0, "starve": 0.0, "name": "",
		"center": "", "grudge": 0.0, "events": [], "age": 0.0, "call_at": Game.DAY_LENGTH * randf_range(5.0, 10.0)}
	for k in defaults:
		if not c.has(k):
			c[k] = defaults[k]


# ---------------------------------------------------------------- queries
func members() -> Array:
	var out: Array = []
	for a in world.animals:
		if a is Alien and not a.dead and not a.caste in Alien.TRANSIENT and a.state != "carried":
			out.append(a)
	return out


func population() -> int:
	var n := 0
	for a in members():
		if a.caste != "egg":
			n += 1
	return n


func count_caste(c: String) -> int:
	var n := 0
	for a in members():
		if a.caste == c:
			n += 1
	return n


func active() -> bool:
	return bool(Game.colony.get("active", false))


func rel() -> float:
	return float(Game.colony.get("rel", 0.0))


func hostile() -> bool:
	return rel() < -30.0 and not Game.has_mutation("hive_mind")


func era() -> String:
	return String(Game.colony.get("era", "none"))


func era_name() -> String:
	return String(ERAS.get(era(), era()))


func has_village() -> bool:
	return String(Game.colony.get("center", "")) != ""


func center_cell() -> Vector2i:
	return _key_cell(String(Game.colony.get("center", "")))


func center_pos() -> Vector2:
	return world.feet(center_cell()) if has_village() else world.feet(Vector2i(world.COLS / 2, world.ROWS - 3))


func buildings() -> Array:
	return world.cells_with_obj(BUILDINGS.keys())


func building_count(t: String = "") -> int:
	if t == "":
		var n := 0
		for c in buildings():
			if world.obj_type(c) != "a_moss":
				n += 1
		return n
	return world.count_obj(t)


func housing() -> int:
	var h := 3
	for c in buildings():
		h += int(BUILDINGS[world.obj_type(c)]["house"])
	return h


func land_size() -> int:
	return world.alien_land.size()


func on_land(p: Vector2) -> bool:
	return world.alien_land.has(world.cell_of(p))


func near_land(p: Vector2, r: int) -> bool:
	var c := world.cell_of(p)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if world.alien_land.has(c + Vector2i(dx, dy)):
				return true
	return false


func random_land_cell() -> Variant:
	if world.alien_land.is_empty():
		return null
	return world.alien_land.keys().pick_random()


## The matriarch: the oldest elder. Every new matriarch brings her own temperament, so a
## succession can turn a peaceful colony warlike (or the other way round).
func queen() -> Alien:
	if _queen != null and (_queen.dead or _queen.caste != "elder"):
		_queen = null
	if _queen == null:
		var best := -1.0
		for a in members():
			if a.caste == "elder" and a.age > best:
				best = a.age
				_queen = a
		if _queen != null and String(Game.colony.get("queen", "")) != _queen.alien_name:
			var first := String(Game.colony.get("queen", "")) == ""
			Game.colony["queen"] = _queen.alien_name
			if not first:
				var t := randf()
				Game.colony["aggro"] = t
				var how := "peaceful" if t < 0.35 else ("warlike" if t > 0.65 else "watchful")
				Game.add_log("%s is the new matriarch of %s. She seems %s." % [_queen.alien_name, _village_name(), how])
	return _queen


func needs_builders() -> bool:
	return not Game.colony["site"].is_empty() and count_caste("worker") == 0


## Raw strength of the colony (for the tides).
func power() -> float:
	var p := 0.0
	for a in members():
		p += 1.0 if a.caste in ["egg", "spawn", "mutant"] else 3.0
	return p + building_count() * 4.0 + land_size() * 0.4 + float(Game.colony["food"]) * 0.05


## The farmhouse (and a visitor's hut) and their doorsteps always stay the farmers'.
func protected(c: Vector2i) -> bool:
	return world.is_house(c) or world.is_doorstep(c) or c == world.BIN or c == world.BIN_FRONT \
		or Vector2(c).distance_to(Vector2(world.DOOR)) < 3.6 or Vector2(c).distance_to(Vector2(world.BIN)) < 2.3


func make_name() -> String:
	var n: String = SYLLABLES.pick_random()
	if randf() < 0.6:
		n += SYLLABLES.pick_random()
	return n.capitalize()


# ---------------------------------------------------------------- simulation
func _process(delta: float) -> void:
	if not Game.simulating() or world == null:
		return
	_acc += delta * Game.time_scale
	if _acc >= 2.0:
		tick(_acc)
		_acc = 0.0


func tick(dt: float) -> void:
	if not Game.colony.has("events"):
		_ensure_state()   # a save from before the aliens, or a fresh slot
	var col: Dictionary = Game.colony
	var mem := members()
	var pop := 0
	var eggs := 0
	for a in mem:
		if a.caste == "egg":
			eggs += 1
		else:
			pop += 1
	var incoming := _incoming()
	if mem.is_empty() and not incoming:
		if active():
			_collapse()
		_decay_ruins(dt)
		col["arrive_t"] = float(col["arrive_t"]) - dt * (1.0 + Game.weird / 40.0)
		if float(col["arrive_t"]) <= 0.0:
			col["arrive_t"] = Game.DAY_LENGTH * randf_range(0.8, 1.8)
			arrive("")
		_update_land(dt, mem)
		return
	if not active() and not mem.is_empty():
		col["age"] = 0.0
		col["call_at"] = Game.DAY_LENGTH * randf_range(5.0, 10.0)
		col["active"] = true
		col["era"] = "founding"
		col["gen"] = int(col["gen"]) + 1
		col["food"] = maxf(float(col["food"]), 12.0)
		col["matter"] = maxf(float(col["matter"]), 8.0)
	_economy(dt, mem, pop)
	_crowding(dt, pop)
	_breed(dt, mem, pop, eggs)
	_plan_building()
	_update_land(dt, mem)
	_grow_moss(dt)
	_update_relations(dt)
	_update_era(pop)
	if not Game.hushed():
		_outreach(dt)
	_age_husks(dt)
	_the_call(dt, pop)
	changed.emit()


func _incoming() -> bool:
	for a in world.animals:
		if a is Alien and not a.dead and (a.caste in Alien.TRANSIENT or a.caste == "stranger"):
			return true
	return false


func _economy(dt: float, mem: Array, pop: int) -> void:
	var col: Dictionary = Game.colony
	var eat := 0.0
	for a in mem:
		match a.caste:
			"egg": eat += 0.0
			"spawn", "mutant": eat += 0.5
			"elder": eat += 1.2
			_: eat += 1.0
	col["food"] = float(col["food"]) - eat * FOOD_PER_ADULT * dt
	col["food"] = minf(float(col["food"]), 20.0 + pop * 5.0)
	if Game.has_mutation("hive_mind") and float(col["food"]) < 4.0 and Game.inventory_count() > 0:
		# the farmer and the hive share their larders now
		for k in Game.inventory.keys():
			if Game.CROPS.has(k) and Game.item_count(k) > 0:
				Game.add_item(k, -1)
				col["food"] = float(col["food"]) + 4.0
				break
	if float(col["food"]) <= 0.0:
		col["food"] = 0.0
		col["starve"] = float(col["starve"]) + dt
		col["morale"] = clampf(float(col["morale"]) - 0.004 * dt, -1.0, 1.0)
		col["aggro"] = clampf(float(col["aggro"]) + 0.001 * dt, 0.0, 1.0)
		if float(col["starve"]) > 45.0 and pop > 0:
			col["starve"] = 0.0
			var weakest: Alien = null
			for a in mem:
				if a.caste in ["egg", "spawn", "elder"] and (weakest == null or a.age > weakest.age):
					weakest = a
			if weakest == null:
				weakest = mem.pick_random()
			weakest.die("hunger")
	else:
		col["starve"] = maxf(0.0, float(col["starve"]) - dt)
	# a full larder is turned into building matter
	var spare := float(col["food"]) - (15.0 + pop * 2.0)
	if spare > 0.0:
		var k := minf(spare, dt * 0.25)
		col["food"] = float(col["food"]) - k
		col["matter"] = float(col["matter"]) + k
	# morale follows the larder, with a mind of its own
	var mt := 0.0
	if float(col["food"]) <= 0.0:
		mt = -0.6
	elif float(col["food"]) > pop * 3.0:
		mt = 0.3
	col["morale"] = clampf(float(col["morale"]) + (mt - float(col["morale"])) * 0.002 * dt + (randf() - 0.5) * 0.012 * dt, -1.0, 1.0)


## Big colonies get restless: crowding sours morale and temper, can split the colony on its own,
## and a border too big for the people left to hold falls to ruin.
func _crowding(dt: float, pop: int) -> void:
	var col: Dictionary = Game.colony
	if pop > 14:
		var over := (pop - 14) / 6.0
		col["aggro"] = clampf(float(col["aggro"]) + dt * 0.0003 * over, 0.0, 1.0)
		col["morale"] = clampf(float(col["morale"]) - dt * 0.0004 * over, -1.0, 1.0)
		if randf() < dt * 0.0002 * (pop - 14) and era() != "exodus":
			if randf() < 0.5:
				bane("schism")
			else:
				civil_war()
			return
	if land_size() > pop * 5 + 10 and randf() < dt * 0.02:
		var edge: Array = []
		for c in buildings():
			if world.obj_type(c) in ["a_pylon", "a_moss", "a_dish"] and c != center_cell():
				edge.append(c)
		if edge.size() > 0:
			var c2: Vector2i = edge.pick_random()
			var t := world.obj_type(c2)
			world.remove_obj(c2)
			if t != "a_moss":
				world.place_obj(c2, "a_ruin")
				Game.add_log("Too few aliens to hold the border: a %s of %s falls to ruin." % [BUILDINGS[t]["name"], _village_name()])


## After some days on the farm the colony hears from home.
func _the_call(dt: float, pop: int) -> void:
	var col: Dictionary = Game.colony
	col["age"] = float(col.get("age", 0.0)) + dt
	if float(col["age"]) < float(col.get("call_at", 1e9)) or pop < 4:
		return
	col["age"] = 0.0
	col["call_at"] = Game.DAY_LENGTH * randf_range(4.0, 9.0)
	if randf() < 0.5 or era() == "decline":
		# everyone goes home
		col["era"] = "exodus"
		var n := 0
		for a in members():
			if a.caste != "egg":
				n += 1
		for i in 2:
			ship("exodus", center_pos() + Vector2(randf_range(-30, 30), randf_range(-10, 10)), range(n))
		for a in members():
			if a.caste == "egg":
				a.die("abandonment")
		Game.add_log("A great light over %s: the homeworld is calling them back. The aliens are leaving!" % _village_name())
		if world.farmer:
			world.farmer.say("They're... going? All of them?", 4.0)
	else:
		boon("mothership")
		Game.colony["aggro"] = clampf(float(Game.colony["aggro"]) + randf_range(-0.3, 0.4), 0.0, 1.0)
		Game.add_log("%s has called for reinforcements. A second wave is coming!" % _village_name())


## Wardens turn on each other. Some die, buildings burn, the survivors pick a new temper.
func civil_war() -> void:
	var col: Dictionary = Game.colony
	var n := 0
	for a in members():
		if a.caste != "egg" and a != queen() and randf() < 0.3:
			world.puff(a.pos + Vector2(0, -6), Color("73eff7"), 8, 16.0)
			a.die("civil war")
			n += 1
	var bs: Array = buildings()
	bs.shuffle()
	for c in bs.slice(0, bs.size() / 4):
		if c != center_cell():
			director.ignite(c)
	col["aggro"] = randf()
	col["morale"] = -0.5
	col["rel"] = rel() * 0.5
	Game.add_log("Civil war in %s! %d aliens fell; fires are burning." % [_village_name(), n])


func _breed(dt: float, mem: Array, pop: int, eggs: int) -> void:
	var col: Dictionary = Game.colony
	col["egg_t"] = float(col["egg_t"]) - dt * (1.6 if building_count("a_hatchery") > 0 else 1.0) * (1.0 + float(col["morale"]) * 0.3)
	if float(col["egg_t"]) > 0.0:
		return
	col["egg_t"] = randf_range(70.0, 140.0)
	if pop + eggs >= housing() or eggs >= 3 or float(col["food"]) < 4.0 + pop * 0.8:
		return
	var mother: Alien = queen()
	if mother == null:
		for a in mem:
			if a.caste == "mutant" or (a.is_adult() and randf() < 0.35):
				mother = a
				break
	if mother == null:
		return
	col["food"] = float(col["food"]) - 4.0
	lay_egg(mother.pos + Vector2(randf_range(-8, 8), randf_range(2, 8)))
	if randf() < 0.3:
		mother.say("*lays an egg*", 2.0)


func lay_egg(p: Vector2) -> Alien:
	var c := world.cell_of(p)
	var hatch := world.cells_with_obj(["a_hatchery"])
	if hatch.size() > 0:
		p = world.feet(hatch.pick_random()) + Vector2(randf_range(-7, 7), randf_range(1, 4))
	elif not world.alien_land.has(c) and world.alien_land.size() > 0:
		p = world.feet(random_land_cell())
	var e := Alien.new(world, "egg", p)
	world.add_animal(e)
	return e


## A new spawnling grows up: it becomes whatever the colony is short of. A lone hatchling
## (the egg that fell from the sky) becomes the founding matriarch instead.
func mature(a: Alien) -> void:
	if not has_village() and queen() == null:
		a.set_caste("elder")
		a.age = maxf(a.age, a.lifespan * 0.73)
		world.puff(a.pos + Vector2(0, -6), Color("ffcd75"), 10, 14.0)
		Game.add_log("The hatchling has grown into a matriarch. She is building a home.")
		found_village(world.cell_of(a.pos))
		return
	var counts := {"worker": 0, "scout": 0, "warden": 0, "envoy": 0}
	for m in members():
		if counts.has(m.caste):
			counts[m.caste] += 1
	var adults: int = counts["worker"] + counts["scout"] + counts["warden"] + counts["envoy"] + 1
	var want := "worker"
	if counts["envoy"] == 0 and adults >= 3:
		want = "envoy"
	elif counts["worker"] < maxi(1, adults * 0.4):
		want = "worker"
	elif counts["warden"] < adults * (0.35 if hostile() or float(Game.colony["aggro"]) > 0.6 else 0.2):
		want = "warden"
	elif counts["scout"] < adults * 0.25:
		want = "scout"
	else:
		want = ["worker", "worker", "scout", "warden"].pick_random()
	a.set_caste(want)
	world.puff(a.pos + Vector2(0, -6), Color("a7f070"), 6, 12.0)
	if randf() < 0.4:
		Game.add_log("%s the spawnling grew up into a %s." % [a.alien_name, want])


func on_elder(a: Alien) -> void:
	a.set_caste("elder")
	if queen() == a:
		Game.add_log("%s is the colony's matriarch now." % a.alien_name)


func on_hatch(a: Alien) -> void:
	Game.colony["born"] = int(Game.colony["born"]) + 1
	if not has_village() and population() <= 1:
		Game.add_log("Something hatched out of the strange egg!")
		if world.farmer:
			world.farmer.say("It... it's looking at me.", 3.0)


## The lurker's chicken turns into the first colonist (or another worker).
func mutant_transform(a: Alien) -> void:
	world.puff(a.pos + Vector2(0, -6), Color("b45cff"), 14, 20.0)
	var into := "elder" if queen() == null else "worker"
	a.set_caste(into)
	a.age = maxf(a.age, a.lifespan * 0.73) if into == "elder" else a.age
	Game.add_log("The strange chicken split its skin. An alien %s stepped out!" % into)
	if not has_village():
		found_village(world.cell_of(a.pos))


## Called by World when an alien leaves the actor list (died, or flew/walked away).
func on_gone(a: Alien) -> void:
	if a == _queen:
		_queen = null
		if a.death_cause != "":
			Game.add_log("The matriarch %s has died. The colony wails." % a.alien_name)
			Game.colony["morale"] = clampf(float(Game.colony["morale"]) - 0.4, -1.0, 1.0)
	if a.caste in Alien.TRANSIENT or a.death_cause == "":
		return
	Game.colony["died"] = int(Game.colony["died"]) + 1
	var c := world.cell_of(a.pos)
	if a.caste != "egg" and world.in_bounds(c) and not world.objs.has(c) and not world.crops.has(c) and not protected(c) \
			and not world.is_water(c):
		world.place_obj(c, "a_husk", {"t": randf_range(500.0, 1100.0)})
	if a.death_cause in ["hunger", "a fox", "fire"] or randf() < 0.15:
		Game.add_log("%s the alien %s died of %s." % [a.alien_name, a.caste, a.death_cause])


func _collapse() -> void:
	var col: Dictionary = Game.colony
	col["active"] = false
	col["era"] = "none"
	col["site"] = {}
	col["center"] = ""
	col["food"] = 0.0
	col["matter"] = 0.0
	col["arrive_t"] = Game.DAY_LENGTH * randf_range(1.0, 2.5)
	col["aggro"] = randf_range(0.1, 0.8)
	col["rel"] = float(col["rel"]) * 0.3
	Game.add_log("The last alien is gone. %s stands empty." % _village_name())
	if world.farmer:
		world.farmer.say("It's... quiet over there now.", 4.0)


## Empty villages fall to ruin, and the creep dries up.
func _decay_ruins(dt: float) -> void:
	for c in buildings():
		if randf() < dt * 0.01:
			var t := world.obj_type(c)
			world.remove_obj(c)
			if t != "a_moss":
				world.place_obj(c, "a_ruin")
			world.puff(world.center(c), Color("566c86"), 6)


func _age_husks(dt: float) -> void:
	for c in world.cells_with_obj(["a_husk"]):
		var o: Dictionary = world.objs[c]
		o["t"] = float(o.get("t", 600.0)) - dt
		if float(o["t"]) <= 0.0:
			world.remove_obj(c)
			world.puff(world.center(c), Color("73eff7"), 5, 10.0)


func _village_name() -> String:
	var n := String(Game.colony.get("name", ""))
	return n if n != "" else "the alien village"


# ---------------------------------------------------------------- arrivals
## Brings aliens to the farm. method "" = pick one that fits right now.
func arrive(method: String) -> void:
	if method == "":
		var opts := {"egg": 3, "saucer": 3, "stranger": 2}
		if Game.is_night() and world.count_animals("chicken") > 0:
			opts["lurker"] = 4
		if Game.has_relic("saucer"):
			opts["saucer"] = 6
		var total := 0
		for k in opts:
			total += int(opts[k])
		var r := randi() % total
		for k in opts:
			r -= int(opts[k])
			if r < 0:
				method = k
				break
	Game.colony["arrivals"] = int(Game.colony["arrivals"]) + 1
	match method:
		"egg":
			var cell: Variant = _landing_cell()
			if cell == null:
				return
			if director and director.weather_fx:
				director.weather_fx.meteor(world.center(cell))
			director.shake.emit(2.0)
			world.remove_obj(cell)
			world.puff(world.center(cell), Color("b45cff"), 16, 30.0)
			var e := lay_egg(world.feet(cell))
			e.grow_at = e.age + randf_range(150.0, 240.0)
			Game.add_log("Something fell from the sky and landed in the long grass. An egg. It's warm.")
			if world.farmer:
				world.farmer.say("Was that a shooting star?", 3.0)
		"saucer":
			var cell2: Variant = _landing_cell()
			if cell2 == null:
				return
			ship("drop", world.feet(cell2), ["elder", "worker", "worker"] + (["warden"] if randf() < 0.5 else ["scout"]))
			Game.add_log("A saucer is coming down over the farm!")
			if world.farmer:
				world.farmer.say("Is that... a SAUCER?!", 3.0)
		"stranger":
			var s := Alien.new(world, "stranger", Vector2(-14 if randf() < 0.5 else world.COLS * 16 + 14, world.feet(world.DOOR).y + 30))
			world.add_animal(s)
			Game.add_log("A stranger in a long coat is walking up the lane.")
		"lurker":
			if not Game.is_night():
				# it waits for dark
				var wait := (0.9 - Game.time_of_day) * Game.DAY_LENGTH if Game.time_of_day < 0.9 else 5.0
				Game.pending.append({"t": maxf(5.0, wait), "fx": [["alien", "arrive", "lurker"]], "note": ""})
				return
			var l := Alien.new(world, "lurker", director._edge_pos())
			world.add_animal(l)
			Game.add_log("Something is moving low through the grass tonight...")


func _landing_cell() -> Variant:
	var best: Variant = null
	var bs := -1e9
	for i in 60:
		var c := Vector2i(randi() % world.COLS, randi_range(4, world.ROWS - 1))
		if protected(c) or world.is_water(c) or world.crops.has(c) or world.is_tilled(c) or world.is_path(c):
			continue
		var t := world.obj_type(c)
		if t != "" and not world.is_clearable(c):
			continue
		var s: float = Vector2(c).distance_to(Vector2(world.DOOR)) + randf() * 4.0
		if s > bs:
			bs = s
			best = c
	return best


## Sends a saucer. mission: drop (colonists in cargo), abduct (a chicken or the farmer), exodus.
func ship(mission: String, at: Vector2, cargo: Array = []) -> Alien:
	var s := Alien.new(world, "ship", Vector2(at.x + randf_range(-60, 60), -60))
	s.home = at
	s.mission = mission
	s.cargo_list = cargo
	world.add_animal(s)
	return s


func ship_arrived(s: Alien) -> void:
	var col: Dictionary = Game.colony
	match s.mission:
		"drop", "mothership":
			for c in s.cargo_list:
				var a := Alien.new(world, c, s.home + Vector2(randf_range(-10, 10), randf_range(-3, 5)))
				if c == "elder":
					a.age = a.lifespan * 0.74
				else:
					a.age = randf_range(0.0, a.lifespan * 0.3)
				world.add_animal(a)
			world.puff(s.home, Color("73eff7"), 14, 20.0)
			col["food"] = float(col["food"]) + 10.0 + s.cargo_list.size() * 3.0
			col["matter"] = float(col["matter"]) + 8.0
			if not has_village():
				found_village(world.cell_of(s.home))
			Game.add_log("%d aliens climbed out of the saucer's light." % s.cargo_list.size())
		"abduct":
			var f := world.farmer
			if s.cargo_list.has("farmer") and f != null and f.state != "fainted" and f.state != "abducted":
				var from_bed := f.state == "sleep"
				f.abduct(randf_range(90.0, 200.0))
				Game.add_log("A beam of light took the FARMER%s! The farm will have to manage..." % (" right out of bed" if from_bed else ""))
			else:
				for a in world.animals:
					if a.kind == "chicken" and not a.dead and a.pos.distance_to(s.home) < 40.0:
						a.dead = true
						col["food"] = float(col["food"]) + 6.0
						Game.add_log("A beam of light took a chicken.")
						break
			world.puff(s.home, Color("73eff7"), 10, 16.0)
		"exodus":
			var n := 0
			for a in members():
				if n >= s.cargo_list.size():
					break
				if a.caste != "egg" and a.state != "leave" and (a != queen() or s.cargo_list.size() >= members().size()):
					a.state = "leave"
					a.exit_pos = Vector2(s.home.x, -60)
					a.speed = 40.0
					n += 1
			if n > 0:
				Game.add_log("%d aliens boarded the saucer and left for the stars." % n)


func stranger_settles(s: Alien, c: Vector2i) -> void:
	world.puff(s.pos + Vector2(0, -8), Color("b45cff"), 18, 24.0)
	s.set_caste("envoy")
	s.age = s.lifespan * 0.3
	Game.colony["rel"] = maxf(rel(), 15.0)
	Game.add_log("The stranger took off his coat. He was an alien all along! He's building a home.")
	found_village(c)
	# a little starter family follows him in
	for i in 2:
		lay_egg(world.feet(c) + Vector2(randf_range(-8, 8), 6))


## Founds the village at c: the first pod goes up for free.
func found_village(c: Vector2i) -> void:
	var col: Dictionary = Game.colony
	if has_village():
		return
	if protected(c) or not world.in_bounds(c):
		var alt: Variant = village_spot()
		if alt == null:
			return
		c = alt
	world.remove_obj(c)
	world.crops.erase(c)
	if world.is_tilled(c):
		world.set_tilled(c, false)
	world.place_obj(c, "a_pod", {"hp": BUILDINGS["a_pod"]["hp"]})
	col["center"] = "%d,%d" % [c.x, c.y]
	col["name"] = VILLAGE_NAMES.pick_random()
	col["active"] = true
	if era() == "none":
		col["era"] = "founding"
	_claim_now(c, 1)
	Game.add_log("The aliens founded a village: %s." % col["name"])
	Game.add_weird(3.0)


func village_spot() -> Variant:
	var best: Variant = null
	var bs := -1e9
	for y in range(3, world.ROWS):
		for x in world.COLS:
			var c := Vector2i(x, y)
			if not _buildable(c):
				continue
			var s := Vector2(c).distance_to(Vector2(world.DOOR)) * 1.0 + randf() * 5.0
			if x == 0 or x == world.COLS - 1 or y >= world.ROWS - 2:
				s += 2.0
			if s > bs:
				bs = s
				best = c
	return best


## What the lurker goes for: a chicken; with no chickens, a crop.
func lurker_target() -> Variant:
	var chickens: Array = []
	for a in world.animals:
		if a.kind == "chicken" and not a.dead and a.state != "carried":
			chickens.append(a)
	if chickens.size() > 0:
		return chickens.pick_random()
	var cs: Array = world.crops.keys()
	return cs.pick_random() if cs.size() > 0 else null


func lurker_strikes(l: Alien, t: Variant) -> void:
	if t is Animal and t.kind == "chicken" and not t.dead:
		t.dead = true
		var m := Alien.new(world, "mutant", t.home if t.hidden else t.pos)
		m.home = t.home
		m.age = 0.0
		m.grow_at = randf_range(80.0, 140.0)
		world.add_animal(m)
		world.puff(m.pos + Vector2(0, -4), Color("b45cff"), 12, 18.0)
		Game.add_log("Something got into the coop. One of the hens looks... different.")
		Game.mood = maxf(0.0, Game.mood - 6.0)
	elif t is Vector2i and world.crops.has(t):
		world.crops.erase(t)
		lay_egg(world.feet(t))
		world.puff(world.center(t), Color("b45cff"), 10, 16.0)
		Game.add_log("A crop was dug out overnight. Something left an egg in the hole.")


# ---------------------------------------------------------------- jobs
## Hands a worker its next job: {kind, cell, t} or null.
func worker_job(a: Alien) -> Variant:
	var site: Dictionary = Game.colony["site"]
	if not site.is_empty():
		return {"kind": "build", "cell": _key_cell(site["cell"]), "t": 0.0}
	var ripe: Array = []
	for c in world.cells_with_obj(["a_moss"]):
		if float(world.objs[c].get("g", 0.0)) >= 1.0:
			ripe.append(c)
	if ripe.size() > 0:
		return {"kind": "harvest", "cell": world.nearest(ripe, world.cell_of(a.pos)), "t": 2.0}
	# overgrowth on the creep: cleared for matter
	var debris: Array = []
	for c in world.alien_land:
		if world.objs.has(c) and world.is_clearable(c):
			debris.append(c)
	if debris.size() > 0 and randf() < 0.7:
		return {"kind": "clear", "cell": world.nearest(debris, world.cell_of(a.pos)), "t": 3.0}
	return null


func job_valid(job: Dictionary) -> bool:
	var c: Vector2i = job["cell"]
	match job["kind"]:
		"build":
			var site: Dictionary = Game.colony["site"]
			return not site.is_empty() and _key_cell(site["cell"]) == c
		"harvest":
			return world.obj_type(c) == "a_moss"
		"clear":
			return world.objs.has(c) and world.is_clearable(c)
	return false


func finish_job(a: Alien, job: Dictionary) -> void:
	var c: Vector2i = job["cell"]
	match job["kind"]:
		"harvest":
			world.objs[c]["g"] = 0.0
			add_food(MOSS_FOOD, "moss")
			world.puff(world.center(c), Color("a7f070"), 5, 10.0)
		"clear":
			var t := world.obj_type(c)
			world.remove_obj(c)
			Game.colony["matter"] = float(Game.colony["matter"]) + (3.0 if t in World.TREES or t in ["boulder", "log", "a_ruin"] else 1.0)
			world.puff(world.center(c), Color("38b764"), 5, 12.0)


func build_progress(d: float) -> void:
	var site: Dictionary = Game.colony["site"]
	if site.is_empty():
		return
	site["done"] = float(site.get("done", 0.0)) + d
	if float(site["done"]) >= float(BUILDINGS[site["type"]]["work"]):
		var c := _key_cell(site["cell"])
		var t: String = site["type"]
		Game.colony["site"] = {}
		if not _buildable(c, true):
			return
		world.remove_obj(c)
		world.crops.erase(c)
		var extra := {"hp": BUILDINGS[t]["hp"]}
		if t == "a_moss":
			extra["g"] = 0.0
		world.place_obj(c, t, extra)
		world.puff(world.center(c), Color("a7f070"), 12, 18.0)
		Game.colony["built"] = int(Game.colony["built"]) + 1
		if t != "a_moss":
			Game.add_log("The aliens finished a %s." % BUILDINGS[t]["name"])
		_claim_now(c, int(ceilf(float(BUILDINGS[t]["claim"]) * 0.5)))


## Decides what to build next and where.
func _plan_building() -> void:
	var col: Dictionary = Game.colony
	if not col["site"].is_empty() or not has_village():
		return
	var pop := population()
	var want := ""
	var moss := building_count("a_moss")
	if pop + 1 >= housing():
		want = "a_pod"
	elif moss < maxi(2, pop / 2 + 1) and float(col["food"]) < 15.0 + pop * 4.0:
		want = "a_moss"
	elif building_count("a_hatchery") == 0 and pop >= 4:
		want = "a_hatchery"
	elif building_count("a_spire") == 0 and pop >= 6:
		want = "a_spire"
	elif building_count("a_dish") == 0 and pop >= 5 and rel() > 10.0:
		want = "a_dish"
	elif building_count("a_pylon") < 1 + pop / 6 and pop >= 5 and (era() == "expanding" or hostile() or randf() < 0.2):
		want = "a_pylon"
	elif moss < pop:
		want = "a_moss"
	if want == "" or float(col["matter"]) < float(BUILDINGS[want]["cost"]):
		return
	var c: Variant = _site_for(want)
	if c == null:
		return
	col["matter"] = float(col["matter"]) - float(BUILDINGS[want]["cost"])
	col["site"] = {"type": want, "cell": "%d,%d" % [c.x, c.y], "done": 0.0}


func _site_for(t: String) -> Variant:
	var center := center_cell()
	var cands: Array = []
	var pool: Array = world.alien_land.keys()
	if t == "a_pylon":
		# pylons push the border out
		pool = _frontier(2)
	for c in pool:
		if not _buildable(c):
			continue
		if t != "a_moss" and _next_to_solid(c):
			continue
		cands.append(c)
	if cands.is_empty():
		for c in _frontier(1):
			if _buildable(c):
				cands.append(c)
	if cands.is_empty():
		return null
	if t == "a_pylon":
		var focus := world.DOOR if era() == "expanding" or hostile() else center
		return world.nearest(cands, focus)
	if t == "a_moss":
		return cands.pick_random()
	return world.nearest(cands, center)


func _buildable(c: Vector2i, allow_debris: bool = true) -> bool:
	if not world.in_bounds(c) or protected(c) or world.is_water(c) or world.is_path(c) or world.insect_land.has(c):
		return false
	if world.crops.has(c):
		return false
	if world.objs.has(c):
		return allow_debris and world.is_clearable(c) and world.obj_type(c) != "a_ruin"
	return true


func _next_to_solid(c: Vector2i) -> bool:
	for d in World.DIRS:
		if world.obj_type(c + d) in SOLID:
			return true
	return false


## Cells just outside the creep (up to r steps).
func _frontier(r: int) -> Array:
	var out := {}
	for c in world.alien_land:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n: Vector2i = c + Vector2i(dx, dy)
				if world.in_bounds(n) and not world.alien_land.has(n) and not protected(n):
					out[n] = true
	return out.keys()


func _grow_moss(dt: float) -> void:
	var night := 1.5 if Game.is_night() else 1.0
	for c in world.cells_with_obj(["a_moss"]):
		var o: Dictionary = world.objs[c]
		o["g"] = minf(1.0, float(o.get("g", 0.0)) + dt / MOSS_GROW * night)


func add_food(n: float, _why: String = "") -> void:
	Game.colony["food"] = float(Game.colony["food"]) + n


# ---------------------------------------------------------------- territory
## Land within a building's claim radius belongs to the colony; the creep spreads over it a few
## cells at a time and recedes from land nothing claims any more.
func claimed() -> Dictionary:
	var out := {}
	for c in buildings():
		var r: float = BUILDINGS[world.obj_type(c)]["claim"]
		out[c] = true
		var ri := int(ceilf(r))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var n: Vector2i = c + Vector2i(dx, dy)
				if world.in_bounds(n) and Vector2(dx, dy).length() <= r and not protected(n):
					out[n] = true
	return out


func _claim_now(c: Vector2i, r: int) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n: Vector2i = c + Vector2i(dx, dy)
			if world.in_bounds(n) and not protected(n) and not world.is_water(n):
				_creep(n)


func _update_land(dt: float, mem: Array) -> void:
	var claim := claimed()
	# spread
	var steps := int(ceilf(dt / 2.0)) * (2 if era() == "expanding" else 1)
	# the creep moves slowly: a border that crawls reads as a border, not as flicker
	if randf() > 0.4:
		steps = 0
	if not mem.is_empty() and steps > 0:
		var front: Array = []
		for c in claim:
			if world.alien_land.has(c) or world.is_water(c):
				continue
			for d in World.DIRS:
				if world.alien_land.has(c + d) or world.obj_type(c + d) in BUILDINGS:
					front.append(c)
					break
		front.shuffle()
		for c in front.slice(0, steps):
			if world.crops.has(c) and not hostile() and rel() > 20.0 and randf() < 0.7:
				continue   # friendly aliens leave the farmer's crops alone (mostly)
			_creep(c)
	# recede
	var gone := 0
	for c in world.alien_land.keys():
		if gone >= steps + (2 if mem.is_empty() else 0):
			break
		if not claim.has(c) and randf() < 0.25:
			world.alien_land.erase(c)
			gone += 1


## The creep takes a cell: overgrowth becomes matter, fields go fallow, crops turn strange.
func _creep(c: Vector2i) -> void:
	if world.alien_land.has(c) or protected(c) or world.is_water(c) or world.insect_land.has(c):
		return
	world.alien_land[c] = true
	var t := world.obj_type(c)
	if t != "" and world.is_clearable(c) and t != "a_ruin":
		world.remove_obj(c)
		Game.colony["matter"] = float(Game.colony["matter"]) + (2.0 if t in World.TREES or t in ["boulder", "log"] else 1.0)
	elif t in ["fence", "scarecrow", "flowerbed", "sign", "bench"] and hostile():
		world.remove_obj(c)
		Game.colony["matter"] = float(Game.colony["matter"]) + 2.0
		Game.add_log("The aliens dismantled a %s on their land." % Game.STRUCTS[t]["name"])
	if world.crops.has(c) or world.is_tilled(c):
		# the farmer does not take kindly to losing his fields
		Game.colony["rel"] = clampf(rel() - 1.5, -100.0, 100.0)
		Game.mood = maxf(0.0, Game.mood - 1.0)
	if world.crops.has(c):
		var cr: Dictionary = world.crops[c]
		if not cr.get("dead", false) and randf() < 0.6:
			cr["type"] = "glowshroom"
			world.puff(world.center(c), Color("73eff7"), 5, 10.0)
		else:
			world.crops.erase(c)
			add_food(2.0, "crop")
	if world.is_tilled(c):
		world.set_tilled(c, false)
		world.prune_fields()
	world.puff(world.center(c), Color("b45cff"), 2, 6.0)


## Cards / tides: the colony takes n more cells (towards the farmhouse).
func cede(n: int) -> int:
	var front := _frontier(1)
	front.sort_custom(func(a, b): return Vector2(a).distance_to(Vector2(world.DOOR)) < Vector2(b).distance_to(Vector2(world.DOOR)))
	var k := 0
	for c in front:
		if k >= n:
			break
		if world.is_water(c):
			continue
		_creep(c)
		k += 1
	# ceded land stays claimed: a pylon goes up on it for free
	if k > 0 and has_village():
		var spot: Variant = null
		for c in front.slice(0, k):
			if _buildable(c) and not _next_to_solid(c):
				spot = c
				break
		if spot != null:
			world.remove_obj(spot)
			world.place_obj(spot, "a_pylon", {"hp": BUILDINGS["a_pylon"]["hp"]})
	return k


## Cards / tides: the farmer pushes the creep back: the border building nearest the
## farmhouse falls and n cells of creep wither.
func reclaim(n: int) -> int:
	var bs: Array = []
	for c in buildings():
		if world.obj_type(c) != "a_spire" and _key_cell(Game.colony["center"]) != c:
			bs.append(c)
	if bs.size() > 0:
		var b: Vector2i = world.nearest(bs, world.DOOR)
		var t := world.obj_type(b)
		world.remove_obj(b)
		if t != "a_moss":
			world.place_obj(b, "a_ruin")
		world.puff(world.center(b), Color("c28a5a"), 12, 18.0)
	var land: Array = world.alien_land.keys()
	land.sort_custom(func(a, b): return Vector2(a).distance_to(Vector2(world.DOOR)) < Vector2(b).distance_to(Vector2(world.DOOR)))
	var k := 0
	for c in land:
		if k >= n:
			break
		if world.obj_type(c) in BUILDINGS:
			continue
		world.alien_land.erase(c)
		k += 1
	return k


# ---------------------------------------------------------------- relations & outreach
func change_rel(n: float, why: String = "") -> void:
	var before := rel()
	Game.colony["rel"] = clampf(before + n, -100.0, 100.0)
	if why != "":
		Game.add_log(why)
	if before >= -30.0 and rel() < -30.0 and active():
		Game.add_log("The aliens of %s have turned hostile!" % _village_name())
	elif before < 20.0 and rel() >= 20.0 and active():
		Game.add_log("The aliens of %s consider the farmer a friend." % _village_name())


func _update_relations(dt: float) -> void:
	var col: Dictionary = Game.colony
	var target := 35.0 - float(col["aggro"]) * 85.0 + float(col["morale"]) * 15.0
	if Game.has_mutation("antenna"):
		target += 25.0
	if Game.has_mutation("green"):
		target += 10.0
	if Game.has_mutation("hive_mind"):
		target += 40.0
	target -= float(col["grudge"])
	col["grudge"] = maxf(0.0, float(col["grudge"]) - dt * 0.01)
	col["rel"] = clampf(rel() + (target - rel()) * 0.0015 * dt + (randf() - 0.5) * 0.08 * dt, -100.0, 100.0)
	col["aggro"] = clampf(float(col["aggro"]) + (randf() - 0.5) * 0.002 * dt, 0.0, 1.0)


func _update_era(pop: int) -> void:
	var col: Dictionary = Game.colony
	var e := "growing"
	var food := float(col["food"])
	if pop <= 2 and building_count() <= 1:
		e = "founding"
	elif hostile():
		e = "hostile"
	elif food <= 0.5 or float(col["morale"]) < -0.4:
		e = "decline"
	elif food > 15.0 + pop * 4.0 and float(col["morale"]) > 0.2 and rel() > 20.0:
		e = "golden"
	elif pop >= housing() - 1 or pop >= 8:
		e = "expanding"
	if era() == "exodus" and randf() < 0.9:
		e = "exodus"
	if e != era():
		col["era"] = e
		var msgs := {"growing": "%s is growing.", "expanding": "%s is expanding its borders!",
			"golden": "%s is in a golden age. Strange music drifts over the fields.",
			"decline": "%s is struggling. The glow is fading.", "hostile": "%s bristles with wardens.",
			"founding": "%s is just getting started."}
		if msgs.has(e):
			Game.add_log(msgs[e] % _village_name())


func wants_raid() -> bool:
	if Game.has_mutation("hive_mind") or world.crops.is_empty():
		return false
	if hostile():
		return randf() < 0.5
	var hungry := float(Game.colony["food"]) < 3.0 + population()
	return hungry and rel() < 30.0 and randf() < 0.25


func raid_target() -> Variant:
	var cs: Array = []
	for c in world.crops:
		if not world.crops[c].get("dead", false):
			cs.append(c)
	if cs.is_empty():
		return null
	return world.nearest(cs, center_cell())


## A scout reached a crop. Returns the food it carries home.
func on_raid(a: Alien, c: Vector2i) -> float:
	if not world.crops.has(c):
		return 0.0
	var cr: Dictionary = world.crops[c]
	var food := 2.0 + 4.0 * float(cr["growth"])
	world.crops.erase(c)
	world.puff(world.center(c), Color("a7f070"), 5, 10.0)
	Game.colony["grudge"] = maxf(0.0, float(Game.colony["grudge"]) - 1.0)
	Game.mood = maxf(0.0, Game.mood - 3.0)
	if randf() < 0.4:
		Game.add_log("An alien scout made off with a %s!" % String(Game.CROPS.get(cr["type"], {}).get("name", "crop")).to_lower())
	if world.farmer and world.farmer.visible_outside() and randf() < 0.5:
		world.farmer.say(["Hey! Put that back!", "Thief! Green thief!", "Not my %s!" % cr["type"]].pick_random(), 2.5)
	return food


func on_scared(_a: Alien) -> void:
	Game.colony["grudge"] = float(Game.colony["grudge"]) + 1.5


func _outreach(dt: float) -> void:
	var col: Dictionary = Game.colony
	col["outreach_t"] = float(col["outreach_t"]) - dt * (1.5 if building_count("a_dish") > 0 else 1.0)
	if float(col["outreach_t"]) > 0.0:
		return
	col["outreach_t"] = randf_range(0.6, 1.4) * Game.DAY_LENGTH
	if population() < 2:
		return
	# hostile colonies send saucers at night instead of envoys
	if hostile():
		if Game.is_night() and (building_count("a_spire") > 0 or building_count("a_dish") > 0):
			var f := world.farmer
			var take_farmer := f != null and f.state != "fainted" and f.state != "abducted" and randf() < 0.35
			var spot: Vector2 = (f.pos if f.visible_outside() else world.feet(world.DOOR)) if take_farmer else world.feet(world.DOOR) + Vector2(20, 30)
			for a in world.animals:
				if a.kind == "chicken" and not a.dead and not take_farmer:
					spot = a.home
					break
			ship("abduct", spot, ["farmer"] if take_farmer else [])
			Game.add_log("A saucer hums low over the farm in the dark...")
		elif cards and not Game.has_card("alien_ultimatum") and randf() < 0.5:
			Game.add_card("alien_ultimatum")
		return
	var envoy: Alien = null
	for a in members():
		if a.caste == "envoy" and a.state != "visit":
			envoy = a
			break
	if envoy == null:
		return
	var r := rel()
	if r > 50.0 and randf() < 0.15 and world.farmer and world.farmer.visible_outside():
		ship("abduct", world.farmer.pos, ["farmer"])
		Game.add_log("A friendly saucer comes to take the farmer on a little trip.")
		return
	if r > 20.0:
		envoy.mission = "gift"
	elif r > -5.0:
		envoy.mission = "trade" if Game.inventory_count() > 0 else "chat"
	else:
		envoy.mission = "demand"
	envoy.state = "visit"
	if cards and randf() < 0.45 and not Game.has_card("alien_envoy"):
		Game.add_card("alien_envoy")


func envoy_arrived(a: Alien) -> void:
	var f := world.farmer
	match a.mission:
		"gift":
			a.say(["A gift. For the turnip-maker.", "From the stars, with love.", "Take. We are friends."].pick_random(), 4.0)
			var gifts := ["alien_bolt", "alien_bolt", "star_shard", "geode"]
			if rel() > 60.0 and randf() < 0.3:
				gifts = ["alien_gift"]
			world.loot(gifts.pick_random(), 1, a.pos)
			Game.add_item("ore", randi_range(1, 3))
			change_rel(2.0)
			if rel() > 60.0 and randf() < 0.15 and not Game.has_mutation("antenna"):
				mutate_farmer("antenna")
				Game.add_log("The envoy gave the farmer a little antenna. It's a compliment, apparently.")
		"trade":
			var tr: Dictionary = Game.trade_goods(1.4)
			if int(tr["worth"]) > 0:
				add_food(float(tr["worth"]) * 0.25, "trade")
				a.say("Your produce for our shinies. Fair?", 4.0)
				Game.add_log("An alien envoy traded the produce for %s." % Game.describe(tr["got"]))
				change_rel(4.0)
			else:
				a.say("Nothing to trade? We wait.", 3.0)
		"demand":
			a.say(["Tribute. Or else.", "The hive is hungry, Farmer.", "Give crops. Now."].pick_random(), 4.0)
			var ripe: Array = world.ripe_cells()
			if ripe.size() > 0:
				for c in ripe.slice(0, 3):
					world.crops.erase(c)
					add_food(5.0, "tribute")
				Game.add_log("The aliens took their tribute from the ripe crops.")
				change_rel(5.0)
			else:
				change_rel(-6.0, "The envoy left empty-handed, muttering.")
		_:
			a.say(["We are watching your weather.", "What is... a 'Tuesday'?", "Your chicken fears us."].pick_random(), 4.0)
			change_rel(1.0)
	if f != null and f.visible_outside():
		f.say(["Er, thank you?", "You again!", "Hello, little green friend."].pick_random(), 3.0)


## A gift from the colony (cards), with or without an envoy at the door.
func envoy_arrived_gift() -> void:
	var gifts := ["alien_bolt", "star_shard", "geode"]
	if rel() > 50.0:
		gifts.append("alien_gift")
	world.loot(gifts.pick_random())
	Game.add_item("ore", randi_range(2, 4))


## The farmer walked over to say hello.
func farmer_visited() -> void:
	change_rel(3.0)
	var anyone: Array = members()
	if anyone.size() > 0:
		var a: Alien = anyone.pick_random()
		if a.caste != "egg":
			a.say(["Farmer-friend!", "*waves tentacle*", "Welcome, welcome."].pick_random(), 3.0)
	if randf() < 0.2:
		world.loot("alien_bolt")


## The farmer smashed something of theirs.
func farmer_sabotage(c: Vector2i) -> void:
	var t := world.obj_type(c)
	if not BUILDINGS.has(t):
		return
	var o: Dictionary = world.objs[c]
	o["hp"] = int(o.get("hp", 50)) - 45
	world.puff(world.center(c), Color("c28a5a"), 8, 14.0)
	Game.colony["grudge"] = float(Game.colony["grudge"]) + 4.0
	if int(o["hp"]) <= 0:
		world.remove_obj(c)
		if t != "a_moss":
			world.place_obj(c, "a_ruin")
		Game.add_log("The farmer tore down an alien %s!" % BUILDINGS[t]["name"])


## The farmer came back from the saucer. He's not quite the same.
func farmer_returned() -> void:
	var m := mutate_farmer("")
	change_rel(12.0)
	if m != "":
		Game.add_log("The farmer is back, dazed. He has a new... feature: %s." % Game.MUTATIONS[m]["name"])


## Gives the farmer a mutation (id "" = a random one he doesn't have). Returns its id.
func mutate_farmer(id: String) -> String:
	if id == "":
		var opts: Array = []
		for k in Game.MUTATIONS:
			if not Game.has_mutation(k) and k != "hive_mind":
				opts.append(k)
		if opts.is_empty():
			return ""
		id = opts.pick_random()
	if Game.has_mutation(id):
		return ""
	Game.mutations[id] = true
	Game.add_weird(4.0)
	var f := world.farmer
	if f:
		world.puff(f.pos + Vector2(0, -8), Color("a7f070"), 14, 20.0)
		world.float_text(String(Game.MUTATIONS[id]["name"]).to_upper(), f.pos + Vector2(-20, -34), Color("a7f070"))
	return id


func cure_farmer() -> String:
	if Game.mutations.is_empty():
		return ""
	var id: String = Game.mutations.keys().pick_random()
	Game.mutations.erase(id)
	Game.add_log("The farmer is cured of his %s." % String(Game.MUTATIONS[id]["name"]).to_lower())
	return id


## Lightning hit the spire: free power.
func spire_struck() -> void:
	Game.colony["matter"] = float(Game.colony["matter"]) + 6.0
	Game.colony["morale"] = clampf(float(Game.colony["morale"]) + 0.1, -1.0, 1.0)


# ---------------------------------------------------------------- big swings (tides, cards)
func boon(kind: String = "") -> String:
	var col: Dictionary = Game.colony
	if not active() and population() == 0:
		arrive("saucer" if randf() < 0.5 else "")
		return "arrival"
	if kind == "":
		kind = ["mothership", "hatching", "golden", "bounty"].pick_random()
	match kind:
		"mothership":
			var at: Vector2 = center_pos() + Vector2(randf_range(-20, 20), 10)
			var cargo: Array = []
			for i in randi_range(3, 5):
				cargo.append(["worker", "warden", "scout", "worker"].pick_random())
			ship("mothership", at, cargo)
			Game.add_log("THE TIDE TURNS: a mothership is bringing more aliens to %s!" % _village_name())
		"hatching":
			for i in randi_range(3, 5):
				lay_egg(center_pos() + Vector2(randf_range(-20, 20), randf_range(-6, 10)))
			add_food(15.0)
			Game.add_log("THE TIDE TURNS: hatching season in %s. Eggs everywhere." % _village_name())
		"golden":
			add_food(30.0)
			col["matter"] = float(col["matter"]) + 20.0
			col["morale"] = 0.8
			Game.add_log("THE TIDE TURNS: %s blooms with light. A golden age!" % _village_name())
		"bounty":
			col["matter"] = float(col["matter"]) + 25.0
			for c in world.cells_with_obj(["a_moss"]):
				world.objs[c]["g"] = 1.0
			Game.add_log("THE TIDE TURNS: a star-seed shower. The glow moss ripens all at once.")
	return kind


func bane(kind: String = "") -> String:
	var col: Dictionary = Game.colony
	var mem := members()
	if mem.is_empty():
		return ""
	if kind == "":
		kind = ["plague", "schism", "famine", "homesick", "queen"].pick_random()
	match kind:
		"plague":
			var n := 0
			for a in mem:
				if randf() < 0.4:
					a.die("a plague")
					n += 1
			Game.add_log("THE TIDE TURNS: a space plague sweeps %s. %d aliens perish." % [_village_name(), n])
		"schism":
			var adults: Array = []
			for a in mem:
				if a.caste != "egg" and a != queen():
					adults.append(a)
			var leave_n := int(adults.size() * randf_range(0.3, 0.55))
			col["food"] = float(col["food"]) * 0.5
			col["matter"] = float(col["matter"]) * 0.4
			col["aggro"] = 1.0 - float(col["aggro"])
			col["rel"] = -rel() * 0.6
			ship("exodus", center_pos(), range(leave_n))
			# the leavers take their pods apart for the trip
			var bs: Array = buildings()
			bs.shuffle()
			for c in bs.slice(0, int(bs.size() * 0.3)):
				if c != center_cell():
					var t := world.obj_type(c)
					world.remove_obj(c)
					if t != "a_moss":
						world.place_obj(c, "a_ruin")
			Game.add_log("THE TIDE TURNS: a schism splits %s! Some are leaving; the rest have changed their minds about the farmer." % _village_name())
		"famine":
			col["food"] = 0.0
			for c in world.cells_with_obj(["a_moss"]):
				if randf() < 0.6:
					world.remove_obj(c)
			Game.add_log("THE TIDE TURNS: the glow moss is rotting. %s goes hungry." % _village_name())
		"homesick":
			var n2 := mini(randi_range(2, 3), mem.size())
			col["era"] = "exodus"
			ship("exodus", center_pos(), range(n2))
			Game.add_log("THE TIDE TURNS: some aliens are homesick for the stars.")
		"queen":
			var q := queen()
			if q != null:
				q.die("old age")
			col["morale"] = -0.6
			Game.add_log("THE TIDE TURNS: the matriarch of %s has passed." % _village_name())
	return kind


# ---------------------------------------------------------------- misc
func _key_cell(k: String) -> Vector2i:
	var parts := k.split(",")
	if parts.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func status_line() -> String:
	if not active():
		return "NO ALIENS (YET)"
	return "%s: %d ALIENS, LAND %d, %s" % [_village_name().to_upper(), population(), land_size(), era_name().to_upper()]
