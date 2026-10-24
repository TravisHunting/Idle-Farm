extends Node
class_name Tides
## The Tides: keeps the farm from ever settling into equilibrium.
## Four factions compete for the farm: the FARM (the farmer's fields, buildings and friends),
## the ALIENS (colony.gd), the BROOD of mutant insects (swarm.gd) and the WILD (overgrowth and
## critters). Every few seconds the tides
## measure each faction's power and keep a short history of their shares. Every few minutes
## they roll a turn of fate:
##   hubris    a faction that has dominated for a while gets knocked down (and the weakest
##             faction gets a lift)
##   upheaval  if the shares have barely moved lately, something big happens to anyone
##   ripple    otherwise, now and then, a smaller boon or bane
## Ordinary turns never push the farm below a floor. CATACLYSMS are different: every day or
## two the tides may roll one, aimed mostly at whoever dominates (or at anyone when things have
## gone stale), and a cataclysm can wipe a faction out entirely:
##   aliens   a hive-sickness kills every alien, or the homeworld recalls the whole colony
##   insects  the long frost: every insect dies, the mounds go cold, the tunnels cave in
##   wild     the scorching: every weed, bush and tree burns off, critters fall silent for a while
##   farm     the dark harvest: fields, crops, the coop, fences, wooden buildings and the hens are
##            lost. The farmer himself always survives in his house and starts again.
## Every faction can come back: aliens and insects re-arrive, the wild creeps in from the edges
## when the silence ends, the farmer plans new fields. Extinctions and returns are tracked
## (Game.tides.alive / extinct) and logged.
## State lives in Game.tides so it saves with the slot.

const FACTIONS := ["farm", "aliens", "insects", "wild"]
const NAMES := {"farm": "the farm", "aliens": "the aliens", "insects": "the brood", "wild": "the wild"}
const SAMPLE_EVERY := 20.0
const HISTORY := 30
const FARM_FLOOR := 0.18

var world: World
var director: Node
var cards: Node
var colony: Colony
var swarm: Swarm
var _sample_t := 3.0


func _ready() -> void:
	_ensure()


func _ensure() -> void:
	var t: Dictionary = Game.tides
	if not t.has("hist"):
		t["hist"] = []
	if not t.has("check_t"):
		t["check_t"] = randf_range(240.0, 420.0)
	if not t.has("dom"):
		t["dom"] = {"who": "", "n": 0}
	if not t.has("last"):
		t["last"] = ""
	if not t.has("cata_t"):
		t["cata_t"] = Game.DAY_LENGTH * randf_range(1.5, 3.0)
	if not t.has("alive"):
		t["alive"] = {}
	if not t.has("extinct"):
		t["extinct"] = {}
	if not t.has("cataclysms"):
		t["cataclysms"] = 0


func _process(delta: float) -> void:
	if not Game.simulating() or world == null:
		return
	var d := delta * Game.time_scale
	if not Game.tides.has("cata_t"):
		_ensure()
	_sample_t -= d
	if _sample_t <= 0.0:
		_sample_t = SAMPLE_EVERY
		_sample()
	Game.tides["check_t"] = float(Game.tides["check_t"]) - d
	if float(Game.tides["check_t"]) <= 0.0:
		Game.tides["check_t"] = randf_range(200.0, 420.0)
		turn()
	if Game.tides.get("silenced", false) and not Game.buff("silent_wild"):
		# the silence ends: the wild floods back in from the edges
		Game.tides["silenced"] = false
		world.overgrow(18)
		Game.add_buff("wild_return", Game.DAY_LENGTH)
		cards.apply([["trees", 2], ["spawn", "rabbit", 2], ["spawn", "crow", 2]])
		Game.add_log("The silence breaks. Seeds blow in, burrows reopen: the wild is coming back.")
	Game.tides["cata_t"] = float(Game.tides["cata_t"]) - d
	if float(Game.tides["cata_t"]) <= 0.0:
		Game.tides["cata_t"] = Game.DAY_LENGTH * randf_range(1.2, 2.6)
		roll_cataclysm()


# ---------------------------------------------------------------- power
func power() -> Dictionary:
	var farm := 0.0
	farm += world.tilled_cells().size() * 1.0
	for c in world.crops:
		if not world.crops[c].get("dead", false):
			farm += 0.6
	for c in world.objs:
		var t: String = world.objs[c]["type"]
		if Game.STRUCTS.has(t):
			farm += 2.0
	farm += world.path_count() * 0.3 + Game.friends.size() * 3.0 + Game.health / 20.0
	farm += world.count_animals("chicken") * 1.0
	var wild := 0.0
	for c in world.objs:
		var t2: String = world.objs[c]["type"]
		if t2 in World.DEBRIS or t2 in World.TREES:
			wild += 0.6
	for a in world.threats():
		if not a is Alien and not a is Insect:
			wild += 2.0
	var aliens := colony.power() if colony else 0.0
	var insects := swarm.power() if swarm else 0.0
	return {"farm": maxf(1.0, farm), "aliens": aliens, "insects": insects, "wild": maxf(1.0, wild)}


func shares() -> Dictionary:
	var p := power()
	var total := 0.0
	for k in p:
		total += float(p[k])
	var out := {}
	for k in p:
		out[k] = float(p[k]) / maxf(1.0, total)
	return out


func _sample() -> void:
	var h: Array = Game.tides["hist"]
	h.append(shares())
	while h.size() > HISTORY:
		h.pop_front()
	_track_survival()


## Is the faction on the farm at all? (The farm "falls" when nothing but the farmer is left.)
func alive(who: String) -> bool:
	match who:
		"aliens":
			return colony != null and not colony.members().is_empty()
		"insects":
			return swarm != null and not swarm.members().is_empty()
		"wild":
			# living wild only: rocks and ash don't count
			var n := 0
			for c in world.objs:
				var t: String = world.objs[c]["type"]
				if t in ["weed", "tallgrass", "bush", "bramble", "stump", "log"] or t in World.TREES:
					n += 1
			for a in world.threats():
				if not a is Alien and not a is Insect:
					n += 2
			return n >= 4
		"farm":
			if world.tilled_cells().size() > 0 or world.crops.size() > 0:
				return true
			for c in world.objs:
				if Game.STRUCTS.has(world.objs[c]["type"]) and int(Game.STRUCTS[world.objs[c]["type"]]["level"]) < 99:
					return true
			return false
	return true


const GONE_LINES := {
	"aliens": ["THE ALIENS ARE GONE. Not one is left on the farm.", "The aliens have returned to the farm!"],
	"insects": ["THE BROOD IS GONE. The mounds are silent.", "Giant insects are back on the farm!"],
	"wild": ["THE WILD IS GONE. Not a weed, not a critter.", "The wild is creeping back in."],
	"farm": ["THE FARM HAS FALLEN. Only the farmer and his house remain.", "The farm lives again: the farmer has broken new ground."],
}


func _track_survival() -> void:
	var al: Dictionary = Game.tides["alive"]
	var ex: Dictionary = Game.tides["extinct"]
	for k in FACTIONS:
		var now := alive(k)
		var before: bool = bool(al.get(k, now))
		if before and not now:
			ex[k] = int(ex.get(k, 0)) + 1
			Game.add_log(GONE_LINES[k][0])
		elif not before and now:
			Game.add_log(GONE_LINES[k][1])
		al[k] = now


# ---------------------------------------------------------------- cataclysms
## Picks a target: mostly the strongest, more so the longer the balance has been stale.
func roll_cataclysm(force: String = "") -> String:
	var s := shares()
	var who := force
	if who == "":
		var stale := movement() < 0.2
		var weights := {}
		var total := 0.0
		for k in FACTIONS:
			if not alive(k):
				continue
			var w: float = pow(float(s[k]) + 0.05, 2.0) * (2.0 if stale else 1.0)
			if k == "farm":
				w *= 0.6   # the farm is the heart of the game: hit it a bit less often
			weights[k] = w
			total += w
		# not every roll lands: quiet farms are hit more often
		var chance := 0.55 + (0.3 if stale else 0.0)
		if total <= 0.0 or randf() > chance:
			return ""
		var r := randf() * total
		for k in weights:
			r -= float(weights[k])
			if r <= 0.0:
				who = k
				break
	if who == "" or not alive(who):
		return ""
	Game.tides["cataclysms"] = int(Game.tides["cataclysms"]) + 1
	Game.tides["last"] = "cataclysm:" + who
	director.shake.emit(5.0)
	match who:
		"aliens": _wipe_aliens()
		"insects": _wipe_insects()
		"wild": _wipe_wild()
		"farm": _wipe_farm()
	return who


func _wipe_aliens() -> void:
	if randf() < 0.5:
		var n := 0
		for a in colony.members():
			a.die("the hive-sickness")
			n += 1
		Game.add_log("CATACLYSM: a hive-sickness sweeps through the aliens. All %d of them perish in one night." % n)
	else:
		colony.ship("exodus", colony.center_pos(), [])
		for a in colony.members():
			if a.caste == "egg":
				a.die("abandonment")
			else:
				a.state = "leave"
				a.exit_pos = Vector2(a.pos.x + randf_range(-30, 30), -70)
				a.speed = 45.0
		Game.colony["era"] = "exodus"
		Game.add_log("CATACLYSM: the sky splits open with light. The homeworld recalls EVERY alien, now.")


func _wipe_insects() -> void:
	var n := 0
	for a in swarm.members():
		a.die("the long frost")
		n += 1
	for m in swarm.mounds():
		world.remove_obj(m)
		world.place_obj(m, "i_hole", {"t": 1200.0})
	var land: Array = world.insect_land.keys()
	land.shuffle()
	for c in land.slice(0, 3):
		swarm.sinkhole(c, randi_range(1, 2))
	for c in world.cells_with_obj(["i_web"]):
		world.remove_obj(c)
	Game.set_weather("cloudy")
	Game.add_log("CATACLYSM: the long frost. Every insect on the farm (%d) froze in the night. The tunnels cave in." % n)


func _wipe_wild() -> void:
	var n := 0
	for c in world.objs.keys():
		var t: String = world.objs[c]["type"]
		if t in ["weed", "tallgrass", "bush", "bramble", "stump", "log"] or t in World.TREES:
			world.remove_obj(c)
			if t in World.TREES and randf() < 0.5:
				world.place_obj(c, "ash")
			n += 1
	for a in world.animals:
		if not a.dead and a.kind in Animal.THREATS:
			a.dead = true
	for y in world.ROWS:
		for x in world.COLS:
			var c2 := Vector2i(x, y)
			if world.is_free_grass(c2) and randf() < 0.6:
				world.bare[c2] = randf_range(400.0, 900.0)
	Game.add_buff("silent_wild", Game.DAY_LENGTH * randf_range(1.0, 2.0))
	Game.tides["silenced"] = true
	Game.set_weather("heat")
	Game.add_log("CATACLYSM: the scorching. %d patches of wild burned off; not a critter stirs. The wild is gone... for now." % n)


func _wipe_farm() -> void:
	var lost := 0
	for c in world.crops.keys():
		world.crops.erase(c)
		lost += 1
	for c in world.tilled_cells():
		world.set_tilled(c, false)
		if randf() < 0.5:
			world.place_obj(c, ["weed", "tallgrass"].pick_random())
	world.fields.clear()
	for c in world.objs.keys():
		var t: String = world.objs[c]["type"]
		if Game.STRUCTS.has(t) and int(Game.STRUCTS[t]["level"]) < 99:
			world.remove_obj(c)
			world.place_obj(c, "ash")
			lost += 1
	for a in world.animals:
		if a.kind in ["chicken", "dog"]:
			a.dead = true
	for k in Game.inventory.keys():
		if not k in Game.MATERIALS:
			Game.inventory.erase(k)
	Game.mood = maxf(5.0, Game.mood - 40.0)
	if world.farmer:
		world.farmer.say("It's all gone... Right. Start again.", 5.0)
	Game.set_weather("storm")
	Game.add_log("CATACLYSM: the dark harvest. Blight, flood and fire take every field, every crop and every building. Only the farmer and his house survive.")


func extinction_line() -> String:
	var ex: Dictionary = Game.tides.get("extinct", {})
	var parts: Array = []
	for k in FACTIONS:
		if int(ex.get(k, 0)) > 0:
			parts.append("%s x%d" % [{"insects": "BROOD"}.get(k, String(k).to_upper()), int(ex[k])])
	return "WIPED OUT: " + (", ".join(parts) if parts.size() > 0 else "NOBODY YET")


## How much the balance has moved over the last n samples (sum of share changes).
func movement(n: int = 12) -> float:
	var h: Array = Game.tides["hist"]
	var m := 0.0
	var start := maxi(1, h.size() - n)
	for i in range(start, h.size()):
		for k in FACTIONS:
			m += absf(float(h[i].get(k, 0.0)) - float(h[i - 1].get(k, 0.0)))
	return m


## Which faction is gaining the most lately ("" if nobody).
func trend() -> String:
	var h: Array = Game.tides["hist"]
	if h.size() < 4:
		return ""
	var a: Dictionary = h[maxi(0, h.size() - 8)]
	var b: Dictionary = h[h.size() - 1]
	var best := ""
	var bd := 0.03
	for k in FACTIONS:
		var dd := float(b.get(k, 0.0)) - float(a.get(k, 0.0))
		if dd > bd:
			bd = dd
			best = k
	return best


# ---------------------------------------------------------------- turns of fate
func turn() -> void:
	var s := shares()
	var dom := ""
	var weak := ""
	for k in FACTIONS:
		if not _present(k) and float(s[k]) < 0.01:
			continue
		if dom == "" or float(s[k]) > float(s[dom]):
			dom = k
		if weak == "" or float(s[k]) < float(s[weak]):
			weak = k
	var dd: Dictionary = Game.tides["dom"]
	if float(s[dom]) > 0.5:
		if dd["who"] == dom:
			dd["n"] = int(dd["n"]) + 1
		else:
			dd["who"] = dom
			dd["n"] = 1
	else:
		dd["who"] = ""
		dd["n"] = 0
	var hist_n: int = Game.tides["hist"].size()
	if dd["who"] != "" and int(dd["n"]) >= 2:
		# hubris: the dominant faction falls, the weakest rises
		_bane(dom)
		if weak != dom:
			_boon(weak)
		dd["n"] = 0
		Game.tides["last"] = "hubris:" + dom
	elif hist_n >= 10 and movement() < 0.12:
		# too calm: shake something hard
		var who: String = FACTIONS.pick_random()
		if not _present(who):
			_boon(who)
		elif randf() < 0.5 or (who == "farm" and float(s["farm"]) < FARM_FLOOR):
			_boon(who)
		else:
			_bane(who)
		Game.tides["last"] = "upheaval:" + who
	elif randf() < 0.45:
		var who2: String = FACTIONS.pick_random()
		if randf() < 0.5:
			_boon(who2)
		else:
			_bane(who2)
		Game.tides["last"] = "ripple:" + who2


## The aliens and the brood can be absent from the farm entirely.
func _present(who: String) -> bool:
	match who:
		"aliens": return colony != null and colony.active()
		"insects": return swarm != null and swarm.active()
	return true


func _boon(who: String) -> void:
	match who:
		"aliens":
			colony.boon()
		"insects":
			swarm.boon()
		"farm":
			match ["harvest", "work_party", "reclaim", "second_wind"].pick_random():
				"harvest":
					director.do_action("fert")
					director.do_action("bees")
					Game.add_log("THE TIDE TURNS: a bumper season for the farm!")
				"work_party":
					world.clear_overgrowth(12)
					cards.apply([["build", "scarecrow", 1], ["fence", 4], ["action", "repair"]])
					Game.add_log("THE TIDE TURNS: the whole village turns up for a work party!")
				"reclaim":
					if colony.active() and colony.land_size() > 0:
						var n := colony.reclaim(6)
						Game.add_log("THE TIDE TURNS: the farmer takes back %d tiles from the creep." % n)
					else:
						world.clear_overgrowth(16)
						Game.add_log("THE TIDE TURNS: the wild gives ground. 16 patches cleared.")
				"second_wind":
					Game.health = 100.0
					Game.energy = 100.0
					Game.mood = minf(100.0, Game.mood + 30.0)
					Game.charms = mini(5, Game.charms + 2)
					Game.add_log("THE TIDE TURNS: the farmer feels ten years younger.")
		"wild":
			match ["surge", "migration", "seedfall"].pick_random():
				"surge":
					world.overgrow(18)
					Game.add_log("THE TIDE TURNS: the wild surges back. Weeds and brambles everywhere!")
				"migration":
					cards.apply([["spawn", "rabbit", 3], ["spawn", "crow", 3], ["spawn", "fox", 1]])
					Game.add_log("THE TIDE TURNS: a great migration passes through the farm.")
				"seedfall":
					cards.apply([["trees", 3]])
					world.overgrow(8, ["bush", "bramble"])
					Game.add_log("THE TIDE TURNS: the forest creeps in from the edges.")


func _bane(who: String) -> void:
	match who:
		"aliens":
			if colony.bane() == "":
				_bane("wild")
		"insects":
			if swarm.bane() == "":
				_bane("wild")
		"farm":
			if shares()["farm"] < FARM_FLOOR:
				return   # the farmer is never knocked out
			match ["blight", "storm", "stampede", "fire"].pick_random():
				"blight":
					cards.apply([["wither", maxi(1, world.crops.size() / 3)]])
					Game.add_log("THE TIDE TURNS: blight! A third of the crops wither.")
				"storm":
					director.do_action("storm")
					Game.add_log("THE TIDE TURNS: a great storm rolls over the farm.")
				"stampede":
					director.run_event("boar")
					director.run_event("boar")
					Game.add_log("THE TIDE TURNS: a boar stampede!")
				"fire":
					var hosts: Array = world.cells_with_obj(["fence", "bench", "scarecrow", "beehive", "coop", "tree", "a_pod", "i_web"])
					if hosts.size() > 0:
						director.ignite(hosts.pick_random())
					Game.add_log("THE TIDE TURNS: a spark in the dry grass...")
		"wild":
			match ["dieback", "wildfire"].pick_random():
				"dieback":
					var n := world.clear_overgrowth(14, Vector2i(world.COLS / 2, world.ROWS - 3))
					Game.add_log("THE TIDE TURNS: a hard frost kills back the wild (%d patches)." % n)
				"wildfire":
					var trees: Array = world.cells_with_obj(World.TREES + ["bramble", "bush"])
					if trees.size() > 0:
						director.ignite(trees.pick_random())
					Game.add_log("THE TIDE TURNS: wildfire in the thickets!")


func status_line() -> String:
	var s := shares()
	var t := trend()
	var parts: Array = []
	for k in FACTIONS:
		parts.append("%s %d%%" % [{"insects": "BROOD"}.get(k, String(k).to_upper()), int(float(s[k]) * 100.0)])
	return " ".join(parts) + ((" - " + String(NAMES[t]).to_upper() + " RISING") if t != "" else "")
