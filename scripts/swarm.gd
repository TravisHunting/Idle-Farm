extends Node
class_name Swarm
## The Brood: mutant insects. Individuals (insect.gd) live in World.animals; this node runs the
## faction as a whole and keeps its state in Game.brood (so it saves with the slot).
##
##  origin      the Brood is not sent from anywhere: the farm makes it. "Radiation" builds up from
##              weirdness, the alien creep, glowing crops, meteor ore and the obelisk, and one day
##              something mutates: a wasp nest splits open, a beehive turns into a mound, a cocoon
##              hangs in a tree. Failing that, a locust cloud blows in on the wind.
##  life cycle  fast generations: egg -> grub -> cocoon -> whatever the brood is short of. Hunger
##              breeds locusts (they turn gregarious), war breeds mantises, the creep breeds glowing
##              insects. A brood without a queen raises one; young queens fly off to found mounds.
##  the map     mounds (3 sizes) claim land; workers dig it into tunnels (World.insect_land), eat
##              the weeds, undermine the farmer's fields when relations are bad. Spinners wall off
##              cells with webs that trap critters. Wax walls go up on a war front. Locust swarms
##              cross the farm and strip a whole band bare (World.bare). Tunnels flooded by rain
##              collapse into sinkholes: permanent ponds that swallow whatever stood on them.
##  relations   two of them: with the farm (rel_farm) and with the aliens (rel_aliens). Friendly
##              glowflies pollinate crops / glow moss; ants bring honey. At war with the aliens
##              there is a front line that moves cell by cell, mantises tear down alien buildings,
##              wardens zap insects. Common enemies pull factions together; friends of enemies
##              push them apart. Each new queen brings her own temper.
## Tides (tides.gd) calls boon()/bane() to keep the balance of power moving.

const CLAIM := {1: 1.6, 2: 2.5, 3: 3.4}
const MOUND_HP := {1: 120, 2: 220, 3: 360}
const QUEEN_NAMES := ["Bzzara", "Klikka", "Thraxa", "Vespera", "Mandibla", "Chitinna", "Skrrix", "Mothra", "Antheia", "Zizzle"]
const FOOD_PER_ADULT := 1.0 / 150.0
const MAX_WATER := 48
const MAX_WEBS := 16
const BARE_TIME := 900.0
const MAX_POP := 40          # everything alive, eggs included
const MAX_MOUNDS := 6
const MAX_QUEENS := 4
const WILD_FOOD := ["weed", "tallgrass", "bush", "bramble", "flowerbed"]

var world: World
var director: Node
var cards: Node
var colony: Colony
var _acc := 0.0
var _swarm_eaten := 0


func _ready() -> void:
	_ensure_state()


func _ensure_state() -> void:
	var b: Dictionary = Game.brood
	var defaults := {"active": false, "food": 0.0, "rel_farm": 0.0, "rel_aliens": 0.0, "temper": randf_range(0.2, 0.7),
		"pressure": 0.0, "arrive_t": Game.DAY_LENGTH * randf_range(2.5, 4.5), "swarm_t": 400.0, "flight_t": 600.0,
		"egg_t": 30.0, "outreach_t": 500.0, "born": 0, "died": 0, "gen": 0, "name": "", "queen": "", "site": {},
		"sinkholes": 0}
	for k in defaults:
		if not b.has(k):
			b[k] = defaults[k]


# ---------------------------------------------------------------- queries
func members() -> Array:
	var out: Array = []
	for a in world.animals:
		if a is Insect and not a.dead and a.caste != "migrant" and a.state != "carried":
			out.append(a)
	return out


func population() -> int:
	var n := 0
	for a in members():
		if a.is_adult():
			n += 1
	return n


func count_caste(c: String) -> int:
	var n := 0
	for a in members():
		if a.caste == c:
			n += 1
	return n


func active() -> bool:
	return bool(Game.brood.get("active", false))


func rel_farm() -> float:
	return float(Game.brood.get("rel_farm", 0.0))


func rel_aliens() -> float:
	return float(Game.brood.get("rel_aliens", 0.0))


func hostile() -> bool:
	return rel_farm() < -30.0


func at_war() -> bool:
	return rel_aliens() < -30.0 and colony != null and colony.active() and active()


func allied() -> bool:
	return rel_aliens() > 30.0 and colony != null and colony.active() and active()


func mounds() -> Array:
	return world.cells_with_obj(["i_mound"])


func mound_stage(c: Vector2i) -> int:
	return int(world.objs[c].get("stage", 1)) if world.obj_type(c) == "i_mound" else 0


func capacity() -> int:
	var cap := 3
	for m in mounds():
		cap += mound_stage(m) * 3
	return mini(cap, MAX_POP)


func land_size() -> int:
	return world.insect_land.size()


func random_land_cell() -> Variant:
	return world.insect_land.keys().pick_random() if not world.insect_land.is_empty() else null


func home_pos(p: Vector2) -> Vector2:
	var ms := mounds()
	if ms.is_empty():
		return p
	return world.feet(world.nearest(ms, world.cell_of(p)))


func queens() -> Array:
	var out: Array = []
	for a in members():
		if a.caste == "queen":
			out.append(a)
	return out


func brood_name() -> String:
	var n := String(Game.brood.get("name", ""))
	return n if n != "" else "the Brood"


func era_name() -> String:
	if not active():
		return "Dormant"
	if at_war():
		return "At war"
	if queens().is_empty():
		return "Leaderless"
	if count_caste("locust") >= 4 and float(Game.brood["food"]) < population():
		return "Swarming"
	if float(Game.brood["food"]) <= 0.5:
		return "Starving"
	if population() <= 3:
		return "Founding"
	return "Thriving"


func power() -> float:
	var p := 0.0
	for a in members():
		p += 2.5 if a.is_adult() else 0.7
	for m in mounds():
		p += mound_stage(m) * 5.0
	return p + land_size() * 0.4 + world.count_obj("i_web") * 0.5 + world.count_obj("i_comb") * 1.0


func protected(c: Vector2i) -> bool:
	if colony:
		return colony.protected(c)
	return world.is_house(c) or Vector2(c).distance_to(Vector2(world.DOOR)) < 3.6


# ---------------------------------------------------------------- simulation
func _process(delta: float) -> void:
	if not Game.running or world == null:
		return
	_acc += delta * Game.time_scale
	if _acc >= 2.0:
		tick(_acc)
		_acc = 0.0


func tick(dt: float) -> void:
	if not Game.brood.has("sinkholes"):
		_ensure_state()
	var b: Dictionary = Game.brood
	var mem := members()
	_update_bare(dt)
	_tunnel_water(dt)
	if mem.is_empty():
		if _incoming():
			return   # a locust cloud passing over
		if active():
			_collapse()
		_abandoned(dt)
		_build_pressure(dt)
		return
	if not active():
		b["active"] = true
		b["gen"] = int(b["gen"]) + 1
		b["food"] = maxf(float(b["food"]), 10.0)
	var pop := 0
	for a in mem:
		if a.is_adult():
			pop += 1
	_economy(dt, mem, pop)
	_crowding(dt, pop)
	_homeless_queens()
	_breed(dt, mem, pop)
	_plan_building(pop)
	_update_land(dt)
	_critters(dt, mem)
	_war(dt)
	_relations(dt)
	_swarming(dt, pop)
	_nuptials(dt, pop)
	_outreach(dt)
	_age_webs(dt)


func _incoming() -> bool:
	for a in world.animals:
		if a is Insect and not a.dead and a.caste == "migrant":
			return true
	return false


func _economy(dt: float, mem: Array, pop: int) -> void:
	var b: Dictionary = Game.brood
	var eat := 0.0
	for a in mem:
		match a.caste:
			"egg", "pupa": pass
			"grub": eat += 0.6
			"queen": eat += 2.0
			_: eat += 1.0
	# fungus gardens inside the mounds, fed with chewed-up leaves
	var garden := 0.0
	for m in mounds():
		garden += mound_stage(m) * 0.006
	b["food"] = clampf(float(b["food"]) + garden * dt - eat * FOOD_PER_ADULT * dt, -1.0, 30.0 + pop * 2.0)
	if float(b["food"]) < 0.0:
		b["food"] = 0.0
		# hunger kills the old and the young first; the survivors turn into locusts (see emerge)
		if randf() < dt * 0.02 * maxf(1.0, pop / 6.0):
			var victim: Insect = null
			for a in mem:
				if a.caste in ["grub", "egg", "worker", "locust"] and (victim == null or a.age > victim.age):
					victim = a
			if victim:
				victim.die("hunger")


## A queen without a mound (out of a cocoon, or whose mound was lost) flies off to dig one.
func _homeless_queens() -> void:
	for q in queens():
		if q.state == "flight" or (world.in_bounds(q.hive) and world.obj_type(q.hive) == "i_mound"):
			continue
		var ms := mounds()
		if ms.size() > 0 and randf() < 0.5:
			q.hive = world.nearest(ms, world.cell_of(q.pos))
			continue
		q.state = "flight"
		q.waypoints = [world.feet(_mound_site(world.cell_of(q.pos)))]


## A crowded brood turns on itself: rival queens fight, and great migrations carry half the
## insects off the farm for good, leaving empty mounds to crumble.
func _crowding(dt: float, pop: int) -> void:
	var qs := queens()
	if qs.size() > MAX_QUEENS:
		var loser: Insect = qs.pick_random()
		loser.die("a queen's duel")
		Game.add_log("Two insect queens fought to the death. Queen %s lost." % loser.queen_name)
	if pop > 20 and randf() < dt * 0.0004 * (pop - 20):
		great_migration()


func great_migration() -> void:
	var leavers: Array = []
	for a in members():
		if a.is_adult() and a.caste != "queen" and randf() < 0.55:
			leavers.append(a)
	var y := randf_range(80.0, world.ROWS * 16 - 30.0)
	var left := randf() < 0.5
	for a in leavers:
		a.set_caste("migrant")
		a.cargo = 0.0
		a.waypoints = _route_across(y + randf_range(-16, 16), left)
	# the mound furthest from the rest is left behind
	var ms := mounds()
	if ms.size() > 1:
		var lone: Vector2i = ms.pick_random()
		world.remove_obj(lone)
		world.place_obj(lone, "i_hole", {"t": 900.0})
		for a in members():
			if a.hive == lone and a.caste in ["egg", "grub", "pupa", "queen"]:
				a.die("abandonment")
	Game.brood["food"] = float(Game.brood["food"]) * 0.4
	Game.brood["temper"] = randf()
	Game.add_log("A great migration! %d insects of %s take to the air and leave the farm for good." % [leavers.size(), brood_name()])


func _breed(dt: float, mem: Array, pop: int) -> void:
	var b: Dictionary = Game.brood
	b["egg_t"] = float(b["egg_t"]) - dt
	if float(b["egg_t"]) > 0.0:
		return
	b["egg_t"] = randf_range(25.0, 55.0)
	var young := mem.size() - pop
	if mem.size() >= capacity() or float(b["food"]) < 3.0 or young > pop + 3:
		return
	for q in queens():
		if q.state == "flight" or not world.in_bounds(q.hive) or world.obj_type(q.hive) != "i_mound":
			continue
		var n := randi_range(1, 3)
		for i in n:
			var e := Insect.new(world, "egg", world.feet(q.hive) + Vector2(randf_range(-7, 7), randf_range(0, 4)))
			e.hive = q.hive
			world.add_animal(e)
		b["food"] = float(b["food"]) - n * 1.2
		b["born"] = int(b["born"]) + n


## A cocoon opens: out comes whatever the brood is short of.
func emerge(p: Insect) -> void:
	var b: Dictionary = Game.brood
	var counts := {}
	var pop := 0
	for a in members():
		if a.is_adult():
			counts[a.caste] = int(counts.get(a.caste, 0)) + 1
			pop += 1
	pop += 1
	p.glow = (colony != null and colony.near_land(p.pos, 3)) or randf() < Game.weird / 250.0
	var want := "worker"
	var food := float(b["food"])
	if int(counts.get("queen", 0)) == 0:
		want = "queen"
	elif pop >= 12 and int(counts.get("queen", 0)) < mini(MAX_QUEENS, mounds().size() + 1) and food > 25.0 and randf() < 0.2:
		want = "queen"
	else:
		var shares := {"soldier": 0.15 + (0.25 if at_war() or hostile() else 0.0),
			"locust": 0.3 if food < pop * 1.5 else 0.08, "spinner": 0.1, "glowfly": 0.12}
		var pick := "worker"
		var worst := 0.0
		for k in shares:
			var gap: float = float(shares[k]) * pop - float(counts.get(k, 0))
			if gap > worst:
				worst = gap
				pick = k
		if int(counts.get("worker", 0)) < maxi(1, int(pop * 0.35)):
			pick = "worker"
		want = pick
	p.set_caste(want)
	world.puff(p.pos + Vector2(0, -4), Color("ffcd75") if not p.glow else Color("73eff7"), 6, 10.0)
	if want == "queen":
		p.queen_name = QUEEN_NAMES.pick_random()
		if queens().size() <= 1:
			_new_queen(p)
		else:
			Game.add_log("A young queen, %s, has hatched in %s's mound." % [p.queen_name, brood_name()])


## Every new ruling queen brings her own temper.
func _new_queen(q: Insect) -> void:
	var b: Dictionary = Game.brood
	var first := String(b.get("queen", "")) == ""
	b["queen"] = q.queen_name
	if b["name"] == "":
		b["name"] = "the Brood of %s" % q.queen_name
	if not first:
		b["temper"] = randf()
		var how := "gentle" if float(b["temper"]) < 0.35 else ("ravenous" if float(b["temper"]) > 0.65 else "restless")
		Game.add_log("Queen %s rules the insects now. She seems %s." % [q.queen_name, how])


func _collapse() -> void:
	var b: Dictionary = Game.brood
	b["active"] = false
	b["site"] = {}
	b["queen"] = ""
	b["food"] = 0.0
	b["arrive_t"] = Game.DAY_LENGTH * randf_range(1.5, 3.0)
	b["temper"] = randf_range(0.1, 0.8)
	b["rel_farm"] = rel_farm() * 0.3
	b["rel_aliens"] = rel_aliens() * 0.3
	Game.add_log("The last of %s is gone. The tunnels fall silent." % brood_name())
	b["name"] = ""


## Empty mounds crumble; abandoned tunnels fill in (or cave in, in the rain).
func _abandoned(dt: float) -> void:
	for m in mounds():
		if randf() < dt * 0.006:
			var o: Dictionary = world.objs[m]
			o["stage"] = int(o.get("stage", 1)) - 1
			if int(o["stage"]) <= 0:
				world.remove_obj(m)
				world.place_obj(m, "i_hole", {"t": 600.0})
	for c in world.insect_land.keys():
		if randf() < dt * 0.02:
			world.insect_land.erase(c)


# ---------------------------------------------------------------- origin
## Radiation builds up from the strange things on the farm until something mutates.
func _build_pressure(dt: float) -> void:
	var b: Dictionary = Game.brood
	var glowing := 0
	for c in world.crops:
		if String(world.crops[c]["type"]) in World.GLOWING:
			glowing += 1
	var rad := 0.02 + Game.weird * 0.004 + world.alien_land.size() * 0.003 + glowing * 0.01 \
		+ world.count_obj("ore") * 0.01 + world.count_obj("obelisk") * 0.05 + world.count_animals("wasps") * 0.04
	b["pressure"] = float(b["pressure"]) + rad * dt
	b["arrive_t"] = float(b["arrive_t"]) - dt
	if float(b["pressure"]) >= 30.0 or float(b["arrive_t"]) <= 0.0:
		b["pressure"] = 0.0
		b["arrive_t"] = Game.DAY_LENGTH * randf_range(1.5, 3.0)
		arrive("")


## Brings the Brood into being. method "" = whatever the farm offers.
func arrive(method: String) -> void:
	if method == "":
		if world.count_animals("wasps") > 0:
			method = "wasps"
		elif world.count_obj("beehive") > 0 and randf() < 0.7:
			method = "hive"
		elif world.cells_with_obj(World.TREES).size() > 0 and randf() < 0.5:
			method = "cocoon"
		else:
			method = "locusts"
	match method:
		"wasps":
			var nest: Animal = null
			for a in world.animals:
				if a.kind == "wasps" and not a.dead:
					nest = a
					break
			var at: Vector2 = nest.pos if nest else world.center(world.DOOR) + Vector2(60, 120)
			if nest:
				nest.dead = true
			var q := _spawn("queen", at)
			q.state = "flight"
			q.waypoints = [world.feet(_mound_site(world.cell_of(at)))]
			for i in 2:
				_spawn("worker", at + Vector2(randf_range(-8, 8), 4))
			world.puff(at, Color("ffcd75"), 14, 20.0)
			Game.add_log("The wasp nest swelled up and split open. Something BIG crawled out, and it brought friends.")
		"hive":
			var hives: Array = world.cells_with_obj(["beehive"])
			var h: Vector2i = hives.pick_random() if hives.size() > 0 else _mound_site(world.DOOR + Vector2i(0, 6))
			world.remove_obj(h)
			var q2 := _spawn("queen", world.feet(h))
			found_mound(h, q2)
			for i in 3:
				_spawn("worker", world.feet(h) + Vector2(randf_range(-8, 8), 4)).hive = h
			Game.add_log("The beehive hums louder and louder... and turns into a heaving mound of giant bees.")
		"cocoon":
			var trees: Array = world.cells_with_obj(World.TREES)
			var t: Vector2i = trees.pick_random() if trees.size() > 0 else Vector2i(world.COLS / 2, world.ROWS - 4)
			var p := Insect.new(world, "pupa", world.feet(t) + Vector2(6, -6))
			p.grow_at = randf_range(80.0, 140.0)
			world.add_animal(p)
			Game.add_log("A cocoon the size of a pumpkin is hanging from a tree. It twitches.")
		"locusts":
			var y := randf_range(80.0, world.ROWS * 16 - 30.0)
			var left := randf() < 0.5
			for i in randi_range(6, 9):
				var m := Insect.new(world, "migrant", Vector2(-20 - i * 6 if left else world.COLS * 16 + 20 + i * 6, y + randf_range(-14, 14)))
				m.waypoints = _route_across(y + randf_range(-10, 10), left)
				world.add_animal(m)
			Game.add_log("A cloud of locusts is blowing in on the wind!")
			if world.farmer:
				world.farmer.say("Is that a CLOUD? It's buzzing!", 3.0)


func _spawn(caste: String, p: Vector2) -> Insect:
	var a := Insect.new(world, caste, p)
	if caste == "queen":
		a.queen_name = QUEEN_NAMES.pick_random()
	world.add_animal(a)
	return a


## A place for a new mound: alien ruins first, then old wood, far from other mounds.
func _mound_site(near: Vector2i) -> Vector2i:
	var best := near
	var bs := -1e9
	var ms := mounds()
	for y in range(3, world.ROWS):
		for x in world.COLS:
			var c := Vector2i(x, y)
			if protected(c) or world.is_water(c) or world.is_tilled(c) or world.is_path(c) or world.crops.has(c) \
					or world.alien_land.has(c):
				continue
			var t := world.obj_type(c)
			if t != "" and not world.is_clearable(c):
				continue
			var s := randf() * 4.0 - Vector2(c).distance_to(Vector2(near)) * 0.3
			if t == "a_ruin":
				s += 8.0
			elif t in ["stump", "log"] or t in World.TREES:
				s += 3.0
			for m in ms:
				if Vector2(m).distance_to(Vector2(c)) < 4.0:
					s -= 20.0
			if s > bs:
				bs = s
				best = c
	return best


func found_mound(c: Vector2i, q: Insect) -> void:
	var t := world.obj_type(c)
	if t == "a_ruin":
		Game.add_log("A queen has burrowed into the alien ruins. The old pod is a mound now.")
	world.remove_obj(c)
	world.crops.erase(c)
	if world.is_tilled(c):
		world.set_tilled(c, false)
	world.alien_land.erase(c)
	world.place_obj(c, "i_mound", {"stage": 1, "hp": MOUND_HP[1]})
	if q:
		q.hive = c
		q.state = "idle"
		q.home = world.feet(c)
		if String(Game.brood.get("queen", "")) == "" or queens().size() <= 1:
			_new_queen(q)
	_dig(c)
	for d in World.DIRS:
		_dig(c + d)
	world.puff(world.center(c), Color("8b5a3c"), 14, 18.0)
	if not active():
		Game.brood["active"] = true
	Game.add_log("%s dug a new mound." % brood_name().capitalize())


func flight_landed(q: Insect) -> void:
	var c := world.cell_of(q.pos)
	if world.obj_type(c) == "i_mound" or protected(c) or world.is_water(c):
		c = _mound_site(c)
	found_mound(c, q)


# ---------------------------------------------------------------- jobs
func worker_job(a: Insect) -> Variant:
	var b: Dictionary = Game.brood
	var me := world.cell_of(a.pos)
	var site: Dictionary = b["site"]
	if not site.is_empty() and randf() < 0.7:
		return {"kind": "build", "cell": _key_cell(site["cell"]), "t": 0.0}
	var hungry := float(b["food"]) < population() * 2.0 + 6.0
	if hungry or randf() < 0.35:
		var j: Variant = _forage_job(me)
		if j != null:
			return j
	if at_war() and randf() < 0.3:
		var wall: Variant = _comb_spot()
		if wall != null:
			return {"kind": "comb", "cell": wall, "t": 4.0}
	var dig: Variant = _dig_spot(me)
	if dig != null:
		return {"kind": "dig", "cell": dig, "t": 2.5}
	return _forage_job(me)


func _forage_job(me: Vector2i) -> Variant:
	var friendly := rel_farm() > -10.0
	var crops: Array = []
	for c in world.crops:
		if not world.crops[c].get("dead", false):
			crops.append(c)
	if crops.size() > 0 and (friendly or randf() < 0.35):
		var c2: Vector2i = world.nearest(crops, me)
		if Vector2(c2).distance_to(Vector2(me)) < 9.0:
			return {"kind": "nectar" if friendly else "raid", "cell": c2, "t": 2.0}
	var wild: Array = []
	for c in world.objs:
		var t: String = world.objs[c]["type"]
		if (t in WILD_FOOD or (t == "a_moss" and rel_aliens() < 10.0)) and Vector2(c).distance_to(Vector2(me)) < 7.0:
			wild.append(c)
	if wild.size() > 0:
		return {"kind": "graze", "cell": world.nearest(wild, me), "t": 2.0}
	return null


func job_valid(job: Dictionary) -> bool:
	var c: Vector2i = job["cell"]
	match job["kind"]:
		"build":
			var site: Dictionary = Game.brood["site"]
			return not site.is_empty() and _key_cell(site["cell"]) == c
		"nectar", "raid":
			return world.crops.has(c) and not world.crops[c].get("dead", false)
		"graze":
			return world.objs.has(c)
		"dig":
			return not world.insect_land.has(c)
		"comb":
			return not world.objs.has(c)
	return false


## Returns food the worker carries home (0 = nothing to haul).
func finish_job(a: Insect, job: Dictionary) -> float:
	var c: Vector2i = job["cell"]
	match job["kind"]:
		"nectar":
			var cr: Dictionary = world.crops[c]
			cr["growth"] = minf(1.0, float(cr["growth"]) + 0.08)
			world.puff(world.center(c), Color("ffcd75"), 3, 8.0)
			return 2.5
		"raid":
			var cr2: Dictionary = world.crops[c]
			world.crops.erase(c)
			world.puff(world.center(c), Color("a7f070"), 5, 10.0)
			_farm_grudge(1.5)
			if randf() < 0.3:
				Game.add_log("A giant ant carried off a whole %s!" % String(Game.CROPS.get(cr2["type"], {}).get("name", "crop")).to_lower())
			return 3.0 + 3.0 * float(cr2["growth"])
		"graze":
			var t := world.obj_type(c)
			world.remove_obj(c)
			world.puff(world.center(c), Color("38b764"), 4, 8.0)
			if t == "a_moss":
				_alien_grudge(2.0)
				if colony:
					colony.add_food(-2.0)
				return 3.0
			return 1.5
		"dig":
			_dig(c)
		"comb":
			if Game.brood["food"] >= 3.0 and _can_wall(c):
				Game.brood["food"] = float(Game.brood["food"]) - 3.0
				world.place_obj(c, "i_comb", {"hp": 90})
	return 0.0


func _dig_spot(me: Vector2i) -> Variant:
	var claim := claimed()
	var best: Variant = null
	var bd := 1e9
	for c in claim:
		if world.insect_land.has(c) or world.is_water(c):
			continue
		if world.alien_land.has(c) and not at_war():
			continue
		var touching := false
		for d in World.DIRS:
			if world.insect_land.has(c + d):
				touching = true
				break
		if not touching:
			continue
		var dd := Vector2(c).distance_squared_to(Vector2(me)) + randf() * 2.0
		if dd < bd:
			bd = dd
			best = c
	return best


## The ants tunnel under a cell: weeds are eaten, and if the brood resents the farmer his
## fields are undermined.
func _dig(c: Vector2i) -> void:
	if not world.in_bounds(c) or protected(c) or world.is_water(c) or world.insect_land.has(c):
		return
	if world.alien_land.has(c):
		if not at_war():
			return
		world.alien_land.erase(c)
	world.insect_land[c] = true
	var t := world.obj_type(c)
	if t in ["weed", "tallgrass"]:
		world.remove_obj(c)
		add_food(0.5)
	if world.is_tilled(c) and rel_farm() < -10.0:
		world.set_tilled(c, false)
		world.prune_fields()
		_farm_grudge(1.0)
		Game.mood = maxf(0.0, Game.mood - 1.0)
	world.puff(world.center(c), Color("8b5a3c"), 2, 6.0)


func _comb_spot() -> Variant:
	for c in world.insect_land:
		if world.objs.has(c) or protected(c):
			continue
		for d in World.DIRS:
			if world.alien_land.has(c + d):
				if _can_wall(c):
					return c
	return null


func _can_wall(c: Vector2i) -> bool:
	return not world.objs.has(c) and not world.crops.has(c) and not world.is_path(c) and not protected(c) \
		and world.keeps_connected(c)


func build_progress(d: float) -> void:
	var site: Dictionary = Game.brood["site"]
	if site.is_empty():
		return
	site["done"] = float(site.get("done", 0.0)) + d
	if float(site["done"]) < float(site.get("work", 30.0)):
		return
	var c := _key_cell(site["cell"])
	Game.brood["site"] = {}
	if site["type"] == "grow":
		if world.obj_type(c) == "i_mound":
			var o: Dictionary = world.objs[c]
			o["stage"] = mini(3, int(o.get("stage", 1)) + 1)
			o["hp"] = MOUND_HP[o["stage"]]
			world.puff(world.center(c), Color("8b5a3c"), 12, 16.0)
			if int(o["stage"]) == 3:
				Game.add_log("%s's mound towers over the farm now." % brood_name().capitalize())
	else:
		found_mound(c, null)


func _plan_building(pop: int) -> void:
	var b: Dictionary = Game.brood
	if not b["site"].is_empty():
		return
	var food := float(b["food"])
	var ms := mounds()
	if ms.is_empty():
		return
	for m in ms:
		var st := mound_stage(m)
		if st < 3 and food > 12.0 + st * 10.0 and pop >= st * 4:
			b["food"] = food - (8.0 + st * 6.0)
			b["site"] = {"type": "grow", "cell": "%d,%d" % [m.x, m.y], "done": 0.0, "work": 25.0 + st * 15.0}
			return
	if pop + 3 >= capacity() and food > 18.0 and ms.size() < MAX_MOUNDS:
		var near: Vector2i = ms.pick_random()
		var c := _mound_site(near + Vector2i(randi_range(-3, 3), randi_range(-3, 3)))
		b["food"] = food - 10.0
		b["site"] = {"type": "mound", "cell": "%d,%d" % [c.x, c.y], "done": 0.0, "work": 30.0}


func add_food(n: float) -> void:
	Game.brood["food"] = float(Game.brood["food"]) + n


# ---------------------------------------------------------------- territory, tunnels, sinkholes
func claimed() -> Dictionary:
	var out := {}
	for m in mounds():
		var r: float = CLAIM.get(mound_stage(m), 1.6)
		var ri := int(ceilf(r))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var n: Vector2i = m + Vector2i(dx, dy)
				if world.in_bounds(n) and Vector2(dx, dy).length() <= r and not protected(n):
					out[n] = true
	return out


func _update_land(dt: float) -> void:
	var claim := claimed()
	var gone := 0
	for c in world.insect_land.keys():
		if gone >= 2:
			break
		if not claim.has(c) and randf() < dt * 0.1:
			world.insect_land.erase(c)
			gone += 1


## Rain soaks into the tunnels. Where they are dense, the ground caves in: a sinkhole, which
## floods into a pond and swallows whatever stood there (crops, fences, alien pods, insects).
func _tunnel_water(dt: float) -> void:
	if not (Game.weather == "rain" or Game.weather == "storm") or world.insect_land.size() < 6:
		return
	var chance := dt * (0.004 if Game.weather == "rain" else 0.01)
	if randf() > chance * minf(4.0, world.insect_land.size() / 10.0):
		return
	var dense: Array = []
	for c in world.insect_land:
		var n := 0
		for d in World.DIRS8:
			if world.insect_land.has(c + d):
				n += 1
		if n >= 5 and world.obj_type(c) != "i_mound":
			dense.append(c)
	if dense.size() > 0:
		sinkhole(dense.pick_random(), randi_range(1, 3))


func sinkhole(c: Vector2i, size: int) -> int:
	if world.ground.count(World.G_WATER) >= MAX_WATER:
		return 0
	var cells: Array = [c]
	for i in size * 3:
		if cells.size() >= size:
			break
		var n: Vector2i = cells.pick_random() + World.DIRS.pick_random()
		if world.in_bounds(n) and not n in cells:
			cells.append(n)
	var k := 0
	var lost: Array = []
	for p in cells:
		if protected(p) or world.is_water(p) or world.is_house(p) or world.obj_type(p) in ["bin", "i_mound"]:
			continue
		var t := world.obj_type(p)
		if t != "" and not t in ["weed", "tallgrass", "ash", "i_hole", "i_husk"]:
			lost.append(t)
		world.remove_obj(p)
		world.crops.erase(p)
		world.ground[world.idx(p)] = World.G_WATER
		world.wet[world.idx(p)] = 1.0
		world.insect_land.erase(p)
		world.alien_land.erase(p)
		world.bare.erase(p)
		world.puff(world.center(p), Color("8b5a3c"), 12, 22.0)
		for a in world.animals:
			var aloft: bool = (a is Insect and a.flying()) or (a is Alien and a.caste == "ship")
			if (a is Insect or a is Alien) and not a.dead and world.cell_of(a.pos) == p and not aloft:
				a.die("a sinkhole")
		k += 1
	if k > 0:
		world.prune_fields()
		Game.brood["sinkholes"] = int(Game.brood.get("sinkholes", 0)) + 1
		if director:
			director.shake.emit(3.0)
		var what := ""
		if lost.size() > 0:
			what = " It swallowed a %s." % _obj_name(lost[0])
		Game.add_log("The ground caved in over the tunnels! A sinkhole filled with water.%s" % what)
		if world.farmer and world.farmer.visible_outside():
			world.farmer.say(["WHOA! The ground!", "Where did THAT pond come from?!", "Bugs. It's always bugs."].pick_random(), 3.0)
	return k


func _obj_name(t: String) -> String:
	if Game.STRUCTS.has(t):
		return Game.STRUCTS[t]["name"]
	if colony and Colony.BUILDINGS.has(t):
		return "alien " + String(Colony.BUILDINGS[t]["name"])
	return t.replace("i_", "").replace("a_", "")


func _update_bare(dt: float) -> void:
	for c in world.bare.keys():
		world.bare[c] = float(world.bare[c]) - dt
		if float(world.bare[c]) <= 0.0:
			world.bare.erase(c)


# ---------------------------------------------------------------- webs, critters, chickens
func web_spot(a: Insect) -> Variant:
	if world.count_obj("i_web") >= MAX_WEBS:
		return null
	var cands: Array = []
	for c in world.insect_land:
		if _can_wall(c) and not world.is_tilled(c):
			for d in World.DIRS:
				if not world.insect_land.has(c + d):
					cands.append(c)
					break
	return world.nearest(cands, world.cell_of(a.pos)) if cands.size() > 0 else null


func spin(c: Vector2i) -> void:
	if not _can_wall(c) or world.count_obj("i_web") >= MAX_WEBS:
		return
	world.place_obj(c, "i_web", {"t": randf_range(700.0, 1300.0), "hp": 20})
	world.puff(world.center(c), Color("f4f4f4"), 4, 8.0)


func _age_webs(dt: float) -> void:
	for c in world.cells_with_obj(["i_web", "i_hole", "i_husk", "i_fungus"]):
		var o: Dictionary = world.objs[c]
		o["t"] = float(o.get("t", 800.0)) - dt
		if float(o["t"]) <= 0.0:
			world.remove_obj(c)


## Webs trap critters, hens gobble grubs, grubs nibble roots.
func _critters(dt: float, mem: Array) -> void:
	for a in world.animals:
		if a.dead or a is Insect or a is Alien or not a.is_threat():
			continue
		if world.obj_type(world.cell_of(a.pos)) == "i_web":
			a.dead = true
			add_food(3.0)
			world.puff(a.pos, Color("f4f4f4"), 6, 10.0)
			if randf() < 0.4:
				Game.add_log("A %s blundered into a giant web. The spinners ate well." % a.kind)
	var hens: Array = []
	for a in world.animals:
		if a.kind == "chicken" and not a.dead and not a.hidden:
			hens.append(a)
	for g in mem:
		if g.caste != "grub":
			continue
		for h in hens:
			if h.pos.distance_to(g.pos) < 26.0 and randf() < dt * 0.05:
				g.die("a hungry hen")
				h.say("*GOBBLE*", 1.5)
				Game.add_log("A hen gobbled up a giant grub!")
				break
		if rel_farm() < 20.0:
			var gc := world.cell_of(g.pos)
			for d in World.DIRS8 + [Vector2i.ZERO]:
				if world.crops.has(gc + d):
					world.damage_crop(gc + d, 0.0, dt * 0.6)


# ---------------------------------------------------------------- soldiers & war
func soldier_target(s: Insect) -> Variant:
	var best: Variant = null
	var bd := 64.0
	if at_war():
		for a in world.animals:
			if a is Alien and not a.dead and a.caste != "ship" and a.caste != "egg":
				var dd: float = a.pos.distance_to(s.pos)
				if dd < bd and near_land(a.pos, 2):
					bd = dd
					best = a
		if best != null:
			return best
		var targets: Array = []
		for c in colony.buildings():
			if near_land(world.feet(c), 2):
				targets.append(c)
		if targets.size() > 0:
			return world.nearest(targets, world.cell_of(s.pos))
	for a in world.threats():
		if a is Insect or a is Alien:
			continue
		var dd2: float = a.pos.distance_to(s.pos)
		if dd2 < bd and near_land(a.pos, 2):
			bd = dd2
			best = a
	if best != null:
		return best
	var f := world.farmer
	if hostile() and f != null and f.visible_outside() and near_land(f.pos, 0) and f.pos.distance_to(s.pos) < 80.0:
		return f
	return null


func strike(s: Insect, foe: Variant) -> void:
	var mult := 1.5 if s.glow else 1.0
	if foe is Alien:
		world.puff(foe.pos + Vector2(0, -6), Color("a7f070"), 6, 12.0)
		s.say("*SNIP*", 1.0)
		if randf() < 0.45 * mult:
			foe.die("a mantis")
			add_food(4.0)
		else:
			foe.scare()
		_alien_grudge(0.5)
	elif foe is Farmer:
		s.state = "sting"
		foe.hurt(int(6 * mult), "a giant mantis")
		if randf() < 0.05 and colony:
			var m := colony.mutate_farmer("chitin" if randf() < 0.5 else "compound_eyes")
			if m != "":
				Game.add_log("The sting is changing the farmer: %s. %s" % [Game.MUTATIONS[m]["name"], Game.MUTATIONS[m]["desc"]])
	elif foe is Animal:
		foe.dead = true
		add_food(3.0)
		world.puff(foe.pos, Color("8b5a3c"), 6, 10.0)
	elif foe is Vector2i and world.objs.has(foe):
		var o: Dictionary = world.objs[foe]
		o["hp"] = int(o.get("hp", 50)) - int(18 * mult)
		world.puff(world.center(foe), Color("a7f070"), 4, 10.0)
		if int(o["hp"]) <= 0:
			var t: String = o["type"]
			world.remove_obj(foe)
			if t != "a_moss":
				world.place_obj(foe, "a_ruin")
			Game.add_log("Mantises tore down an alien %s!" % Colony.BUILDINGS.get(t, {}).get("name", "building"))
			_alien_grudge(4.0)


func near_land(p: Vector2, r: int) -> bool:
	var c := world.cell_of(p)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if world.insect_land.has(c + Vector2i(dx, dy)):
				return true
	return false


## A moving front: where creep meets tunnels, each side pushes with whatever is nearby.
func _war(dt: float) -> void:
	if not at_war():
		return
	var front: Array = []
	for c in world.insect_land:
		for d in World.DIRS:
			if world.alien_land.has(c + d):
				front.append([c, c + d])
	front.shuffle()
	var flips := 0
	for pair in front:
		if flips >= int(ceilf(dt / 2.0)):
			break
		var mine: Vector2i = pair[0]
		var theirs: Vector2i = pair[1]
		var p := world.center(mine)
		var bugs := 0.0
		var greys := 0.0
		for a in world.animals:
			if a.dead or a.pos.distance_to(p) > 56.0:
				continue
			if a is Insect and a.is_adult():
				bugs += 2.0 if a.caste == "soldier" else 0.5
			elif a is Alien and a.is_adult():
				greys += 2.0 if a.caste == "warden" else 0.5
		if bugs > greys * 1.2 and world.obj_type(theirs) == "":
			world.alien_land.erase(theirs)
			_dig(theirs)
			flips += 1
		elif greys > bugs * 1.2 and world.obj_type(mine) in ["", "i_web", "i_hole"]:
			world.insect_land.erase(mine)
			world.remove_obj(mine)
			colony._creep(mine)
			flips += 1


# ---------------------------------------------------------------- relations & outreach
func _farm_grudge(n: float) -> void:
	Game.brood["rel_farm"] = clampf(rel_farm() - n * 0.5, -100.0, 100.0)


func _alien_grudge(n: float) -> void:
	Game.brood["rel_aliens"] = clampf(rel_aliens() - n, -100.0, 100.0)


func change_rel(farm: float, aliens: float = 0.0, why: String = "") -> void:
	var was_war := at_war()
	var b: Dictionary = Game.brood
	b["rel_farm"] = clampf(rel_farm() + farm, -100.0, 100.0)
	b["rel_aliens"] = clampf(rel_aliens() + aliens, -100.0, 100.0)
	if why != "":
		Game.add_log(why)
	if not was_war and at_war():
		Game.add_log("WAR! %s and the aliens of %s are fighting for the land." % [brood_name().capitalize(), colony._village_name()])


## Relations drift towards what the queen's temper and the situation suggest. Enemies of the
## farmer find each other; a friend of your enemy is your enemy.
func _relations(dt: float) -> void:
	var b: Dictionary = Game.brood
	var temper := float(b["temper"])
	var tf := 30.0 - temper * 80.0
	var ta := 20.0 - temper * 60.0
	if colony and colony.active():
		var alien_farm := colony.rel()
		if alien_farm < -20.0 and rel_farm() < -20.0:
			ta += 40.0   # common enemy
		elif alien_farm > 30.0 and rel_farm() < -20.0:
			ta -= 40.0   # the aliens side with the farmer
		elif alien_farm < -20.0 and rel_farm() > 30.0:
			ta -= 30.0
		# the aliens remember insects eating their moss and the war's dead
		if at_war():
			Game.colony["rel"] = clampf(alien_farm + (3.0 if rel_farm() < 0.0 else -1.0) * 0.002 * dt, -100.0, 100.0)
		land_pressure(dt)
	var was_war := at_war()
	b["rel_farm"] = clampf(rel_farm() + (tf - rel_farm()) * 0.0015 * dt + (randf() - 0.5) * 0.1 * dt, -100.0, 100.0)
	b["rel_aliens"] = clampf(rel_aliens() + (ta - rel_aliens()) * 0.0015 * dt + (randf() - 0.5) * 0.12 * dt, -100.0, 100.0)
	b["temper"] = clampf(temper + (randf() - 0.5) * 0.002 * dt, 0.0, 1.0)
	if not was_war and at_war():
		Game.add_log("WAR! %s and the aliens of %s are fighting for the land." % [brood_name().capitalize(), colony._village_name()])
	elif was_war and not at_war() and active() and colony.active():
		Game.add_log("The insects and the aliens have stopped fighting. For now.")


## Crowded borders sour things: the more creep and tunnels touch, the worse it gets.
func land_pressure(dt: float) -> void:
	var touching := 0
	for c in world.insect_land:
		for d in World.DIRS:
			if world.alien_land.has(c + d):
				touching += 1
	if touching > 4:
		Game.brood["rel_aliens"] = rel_aliens() - dt * 0.004 * touching


func _outreach(dt: float) -> void:
	var b: Dictionary = Game.brood
	b["outreach_t"] = float(b["outreach_t"]) - dt
	if float(b["outreach_t"]) > 0.0:
		return
	b["outreach_t"] = Game.DAY_LENGTH * randf_range(0.7, 1.4)
	if population() < 3:
		return
	if rel_farm() > 30.0:
		Game.add_item("honey", randi_range(2, 4))
		if randf() < 0.25:
			world.loot("royal_jelly")
		Game.add_log("Giant ants left honeycomb on the doorstep. A gift from %s." % brood_name())
		if cards and randf() < 0.4 and not Game.has_card("brood_envoy"):
			Game.add_card("brood_envoy")
	elif rel_farm() < -40.0 and count_caste("locust") >= 3 and randf() < 0.5:
		launch_swarm("farm")
	elif cards and colony and colony.active() and active() and not Game.has_card("brood_war") and randf() < 0.3:
		Game.add_card("brood_war")


# ---------------------------------------------------------------- pollination
func pollinate_target(_g: Insect) -> Variant:
	if rel_farm() >= 0.0 and world.crops.size() > 0 and randf() < 0.7:
		return world.crops.keys().pick_random()
	if rel_aliens() >= 0.0:
		var moss: Array = world.cells_with_obj(["a_moss"])
		if moss.size() > 0:
			return moss.pick_random()
	return null


func pollinate(c: Vector2i, d: float) -> void:
	if world.crops.has(c) and rel_farm() >= 0.0:
		var cr: Dictionary = world.crops[c]
		if not cr.get("dead", false):
			cr["growth"] = minf(1.0, float(cr["growth"]) + d * 0.004)
	elif world.obj_type(c) == "a_moss" and rel_aliens() >= 0.0:
		var o: Dictionary = world.objs[c]
		o["g"] = minf(1.0, float(o.get("g", 0.0)) + d * 0.006)


# ---------------------------------------------------------------- swarms & flights
func _swarming(dt: float, pop: int) -> void:
	var b: Dictionary = Game.brood
	b["swarm_t"] = float(b["swarm_t"]) - dt
	if float(b["swarm_t"]) > 0.0:
		return
	b["swarm_t"] = randf_range(300.0, 700.0)
	var locusts := count_caste("locust")
	if locusts >= 3 and (float(b["food"]) < pop * 1.5 or randf() < 0.25):
		launch_swarm("")


## The locusts take to the air and cross the farm, stripping a band bare.
## aim: farm (the fields), aliens (the village), wild (the thickest overgrowth), "" (hungriest).
func launch_swarm(aim: String = "") -> int:
	var flyers: Array = []
	for a in members():
		if a.caste == "locust" and a.state != "swarm":
			flyers.append(a)
	if flyers.size() < 2:
		# a swarm needs numbers: workers turn gregarious
		for a in members():
			if a.caste == "worker" and flyers.size() < 4:
				a.set_caste("locust")
				flyers.append(a)
	if flyers.is_empty():
		return 0
	var y := _aim_row(aim)
	var left := randf() < 0.5
	var home: Vector2 = home_pos(flyers[0].pos)
	for a in flyers:
		a.state = "swarm"
		a.waypoints = [Vector2(-20 if left else world.COLS * 16 + 20, y + randf_range(-12, 12))] + _route_across(y + randf_range(-10, 10), left) + [home]
	_swarm_eaten = 0
	var where: String = {"farm": "the fields", "aliens": "the alien village", "wild": "the thickets"}.get(aim, "the farm")
	Game.add_log("THE LOCUSTS ARE SWARMING! %d of them, heading for %s." % [flyers.size(), where])
	if world.farmer and world.farmer.visible_outside():
		world.farmer.say("LOCUSTS! Cover the turnips!", 3.0)
	return flyers.size()


func _aim_row(aim: String) -> float:
	var cells: Array = []
	match aim:
		"farm":
			cells = world.crops.keys() if world.crops.size() > 0 else world.tilled_cells()
		"aliens":
			cells = world.alien_land.keys()
		"wild":
			cells = world.cells_with_obj(["weed", "tallgrass", "bush", "bramble"])
		_:
			cells = world.crops.keys() + world.cells_with_obj(["a_moss", "tallgrass", "bush"])
	if cells.is_empty():
		return randf_range(60.0, world.ROWS * 16 - 20.0)
	var c: Vector2i = cells.pick_random()
	return world.center(c).y


func _route_across(y: float, left: bool) -> Array:
	var out: Array = []
	for i in 7:
		var x := (i + 0.5) / 7.0 * world.COLS * 16
		out.append(Vector2(x if left else world.COLS * 16 - x, clampf(y + randf_range(-14, 14), 30, world.ROWS * 16 - 6)))
	out.append(Vector2(world.COLS * 16 + 24 if left else -24, y))
	return out


## A swarm passes over cell c: crops, overgrowth, flowers and glow moss are eaten to the dirt.
func strip(c: Vector2i, by: Insect) -> void:
	if protected(c) or world.bare.has(c) and not world.crops.has(c):
		return
	var food := 0.0
	if world.crops.has(c):
		world.crops.erase(c)
		food += 3.0
		_farm_grudge(0.4)
	var t := world.obj_type(c)
	if t in WILD_FOOD:
		world.remove_obj(c)
		food += 1.0
	elif t == "a_moss":
		world.remove_obj(c)
		food += 3.0
		_alien_grudge(1.5)
		if colony:
			colony.add_food(-2.0)
	if world.ground[world.idx(c)] == World.G_GRASS and not world.objs.has(c):
		world.bare[c] = BARE_TIME
	if food > 0.0:
		_swarm_eaten += 1
		world.puff(world.center(c), Color("ffcd75"), 3, 8.0)
		if by.caste == "migrant":
			by.cargo += food
			# a fat migrant may drop out of the cloud and found a brood
			if by.cargo > 5.0 and not active() and queens().is_empty() and randf() < 0.5:
				migrant_settles(by)
		else:
			add_food(food)


## A migrant locust drops out of the cloud and becomes a queen.
func migrant_settles(m: Insect) -> void:
	m.set_caste("queen")
	m.queen_name = QUEEN_NAMES.pick_random()
	m.state = "flight"
	m.waypoints = [world.feet(_mound_site(world.cell_of(m.pos)))]
	add_food(m.cargo + 8.0)
	m.cargo = 0.0
	Game.add_log("One fat locust dropped out of the cloud. She's digging in.")


func _nuptials(dt: float, pop: int) -> void:
	var b: Dictionary = Game.brood
	b["flight_t"] = float(b["flight_t"]) - dt
	if float(b["flight_t"]) > 0.0:
		return
	b["flight_t"] = randf_range(500.0, 1000.0)
	var qs := queens()
	if qs.size() < 2 or pop < 10 or mounds().size() >= MAX_MOUNDS:
		return
	# the youngest queen flies off with a few workers
	var young: Insect = qs[0]
	for q in qs:
		if q.age < young.age:
			young = q
	nuptial_flight(young)


func nuptial_flight(q: Insect) -> void:
	var site := _mound_site(world.cell_of(q.pos) + Vector2i(randi_range(-6, 6), randi_range(-6, 6)))
	q.state = "flight"
	q.waypoints = [world.feet(site) + Vector2(0, -20), world.feet(site)]
	Game.add_log("Queen %s takes to the air on her wedding flight. A new mound is coming." % q.queen_name)


# ---------------------------------------------------------------- the farmer
func farmer_harvest_honey(c: Vector2i) -> void:
	Game.add_item("honey", 2)
	change_rel(2.0)
	world.puff(world.center(c), Color("ffcd75"), 6, 10.0)


func farmer_smoke(c: Vector2i) -> void:
	if world.obj_type(c) != "i_mound":
		return
	var o: Dictionary = world.objs[c]
	o["hp"] = int(o.get("hp", 100)) - 60
	world.puff(world.center(c), Color("94b0c2"), 16, 18.0)
	for a in members():
		if a.pos.distance_to(world.feet(c)) < 30.0 and a.caste in ["worker", "grub", "egg"] and randf() < 0.4:
			a.die("smoke")
	_farm_grudge(8.0)
	if int(o["hp"]) <= 0:
		var st := int(o.get("stage", 1))
		world.remove_obj(c)
		world.place_obj(c, "i_hole", {"t": 900.0})
		Game.add_log("The farmer smoked out a mound! The tunnels beneath it cave in.")
		sinkhole(c, st)


# ---------------------------------------------------------------- big swings (tides, cards)
func boon(kind: String = "") -> String:
	var b: Dictionary = Game.brood
	if not active():
		arrive("")
		return "arrival"
	if kind == "":
		kind = ["swarm", "flight", "bloom", "molt"].pick_random()
	match kind:
		"swarm":
			Game.add_log("THE TIDE TURNS: the locusts are restless...")
			launch_swarm("")
		"flight":
			var qs := queens()
			if qs.size() > 0:
				var q := _spawn("queen", world.feet(qs[0].hive if world.in_bounds(qs[0].hive) else world.cell_of(qs[0].pos)))
				nuptial_flight(q)
				Game.add_log("THE TIDE TURNS: a royal hatching in %s!" % brood_name())
		"bloom":
			add_food(40.0)
			b["egg_t"] = 0.0
			Game.add_log("THE TIDE TURNS: %s gorges itself. The mounds are bursting with eggs." % brood_name().capitalize())
		"molt":
			for a in members():
				if a.is_adult():
					a.glow = true
					a.lifespan += 400.0
			Game.add_log("THE TIDE TURNS: the insects molt, and come out glowing.")
	return kind


func bane(kind: String = "") -> String:
	var mem := members()
	if mem.is_empty():
		return ""
	if kind == "":
		kind = ["frost", "cordyceps", "flood", "queen"].pick_random()
	match kind:
		"frost":
			var n := 0
			for a in mem:
				if (a.caste in Insect.FLYERS or a.caste in ["grub", "egg"]) and randf() < 0.6:
					a.die("frost")
					n += 1
			Game.add_log("THE TIDE TURNS: a sudden frost. %d insects froze stiff." % n)
		"cordyceps":
			var n2 := 0
			for a in mem:
				if a.is_adult() and a.caste != "queen" and randf() < 0.35:
					var c := world.cell_of(a.pos)
					a.die("cordyceps")
					n2 += 1
					if not world.objs.has(c) and not protected(c):
						world.place_obj(c, "i_fungus", {"t": randf_range(600.0, 1000.0)})
			# the spores drift onto the aliens too
			for a in world.animals:
				if a is Alien and not a.dead and a.caste in ["spawn", "egg"] and near_land(a.pos, 3) and randf() < 0.4:
					a.die("cordyceps")
			Game.add_log("THE TIDE TURNS: cordyceps! %d insects sprouted orange fungus stalks." % n2)
		"flood":
			var dense: Array = world.insect_land.keys()
			dense.shuffle()
			var holes := 0
			for c in dense.slice(0, randi_range(2, 4)):
				holes += sinkhole(c, randi_range(1, 3))
			Game.add_log("THE TIDE TURNS: groundwater floods the tunnels (%d tiles caved in)." % holes)
		"queen":
			var qs := queens()
			if qs.size() > 0:
				qs[0].die("old age")
				Game.add_log("THE TIDE TURNS: Queen %s is dead. The brood mills about in confusion." % qs[0].queen_name)
	return kind


## World calls this when an insect leaves the actor list.
func on_gone(a: Insect) -> void:
	if a.caste == "migrant" or a.death_cause == "":
		return
	Game.brood["died"] = int(Game.brood["died"]) + 1
	if a.caste == "queen":
		Game.add_log("Queen %s has died (%s)." % [a.queen_name, a.death_cause])
		var rest := queens()
		if rest.size() > 0:
			_new_queen(rest[0])
		else:
			Game.brood["queen"] = ""
	var c := world.cell_of(a.pos)
	if a.is_adult() and world.in_bounds(c) and not world.objs.has(c) and not world.crops.has(c) and not protected(c) \
			and not world.is_water(c) and randf() < 0.5:
		world.place_obj(c, "i_husk", {"t": randf_range(300.0, 700.0)})
	if a.death_cause in ["a mantis"]:
		return
	if a.death_cause in ["a hungry hen", "a sinkhole"] and randf() < 0.3:
		world.loot("chitin", 1, a.pos)


func on_scared(_a: Insect) -> void:
	_farm_grudge(1.0)


func _key_cell(k: String) -> Vector2i:
	var parts := k.split(",")
	if parts.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func status_line() -> String:
	if not active():
		return "NO BROOD (YET)"
	return "%s: %d INSECTS, %d MOUNDS, TUNNELS %d, %s" % [brood_name().to_upper(), population(), mounds().size(), land_size(), era_name().to_upper()]
