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
## The farm can be pushed around but never knocked out: below a floor it only gets boons.
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


func _process(delta: float) -> void:
	if not Game.running or world == null:
		return
	var d := delta * Game.time_scale
	if not Game.tides.has("check_t"):
		_ensure()
	_sample_t -= d
	if _sample_t <= 0.0:
		_sample_t = SAMPLE_EVERY
		_sample()
	Game.tides["check_t"] = float(Game.tides["check_t"]) - d
	if float(Game.tides["check_t"]) <= 0.0:
		Game.tides["check_t"] = randf_range(200.0, 420.0)
		turn()


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
