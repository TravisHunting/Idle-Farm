extends RefCounted
class_name Farmer
## The autonomous farmer. A utility-scored task picker (_choose) feeds a small state machine:
##   idle -> walk -> work -> (finish) -> idle
##   sleep / inside / rest   = hidden in the house or sitting on a bench
##   nap                     = passed out from exhaustion on the spot (vulnerable)
##   fainted                 = health hit 0; costs a doctor's bill
## Stats (health/energy/mood/poison) live in Game so they persist.

const SPEED := 22.0

const LINES := {
	"morning": ["Good morning, farm!", "Rise and shine!", "Another beautiful day!"],
	"till": ["Time to till!", "Fresh soil!", "Dig dig dig."],
	"plant": ["Grow big, little one!", "In you go!", "Seeds of the future."],
	"water": ["Drink up!", "Splish splash.", "Thirsty little guys."],
	"harvest": ["Look at this beauty!", "Harvest time!", "Yum!"],
	"sell": ["Cha-ching!", "Off to market!", "Fair price, I'd say."],
	"build": ["Hammer time!", "This'll look great.", "Building something nice!"],
	"demolish": ["Doesn't spark joy.", "Out with the old!", "Hmm, that has to go."],
	"rearrange": ["Wouldn't this look better over there?", "Feng shui time!", "Let's move this."],
	"place": ["Much better!", "Perfect spot.", "Yep, right there."],
	"clear": ["Pesky weeds!", "Clearing the way.", "Heave-ho!"],
	"shoo": ["Shoo! Shoo!", "Get outta here!", "Not my crops!", "Scram!"],
	"hurt": ["Ouch!", "Yowch!", "That smarts!", "Owie..."],
	"lucky": ["Phew, lucky!", "Whoa, that was close!"],
	"tired": ["So... tired...", "I need a break.", "Yawn..."],
	"storm_brave": ["A little storm won't stop me!", "Just one more row..."],
	"storm_shelter": ["Yikes, lightning! Inside!", "Better wait this out."],
	"heat": ["Phew, it's hot!", "Scorcher today...", "Need some shade..."],
	"night": ["Time for bed.", "What a day.", "Nighty night, farm."],
	"idle": ["What a lovely day.", "La la la~", "I should build something...", "Hmm hm hmm.",
		"Crops are coming along!", "Wonder what's for dinner.", "Nice breeze today.", "I love this farm."],
	"broke": ["Wallet's empty...", "Grandpa's spare seeds it is."],
	"fire": ["FIRE! Water, quick!", "Not the crops!"],
	"click": ["Oh! Hello there!", "Hey, you!", "Need something?", "Busy busy!", "Nice to see you!",
		"Did you hear a crow?", "Thanks for the help!"],
	"chop": ["Timber!", "Good wood."],
	"rest": ["Ahh, a little sit-down.", "Just resting my eyes."],
}

var world  # World
var pos := Vector2.ZERO
var state := "idle"
var task: Dictionary = {}
var path: Array = []
var work_t := 0.0
var think_t := 1.0
var anim_t := 0.0
var flip := false
var bubble := ""
var bubble_t := 0.0
var carrying := ""
var carry_data: Dictionary = {}
var hurt_t := 0.0
var activity := "Waking up"
var faint_t := 0.0
var chatter_t := 12.0
var storm_brave_t := 0.0
var repath_t := 0.0
var hidden := false
var _last_weather := ""


func _init(w) -> void:
	world = w


func cell() -> Vector2i:
	return world.cell_of(pos)


func say(text: String, dur: float = 3.0) -> void:
	bubble = text
	bubble_t = dur


func say_line(kind: String, chance: float = 1.0) -> void:
	if randf() <= chance and LINES.has(kind):
		say(LINES[kind].pick_random())


func speed_mult() -> float:
	var m := lerpf(0.75, 1.2, Game.mood / 100.0)
	if Game.energy < 15.0:
		m *= 0.6
	if Game.poison > 0.0:
		m *= 0.75
	return m


func visible_outside() -> bool:
	return not hidden and state != "fainted"


# ---------------------------------------------------------------- update
func update(d: float) -> void:
	anim_t += d
	bubble_t -= d
	hurt_t -= d
	chatter_t -= d
	_update_stats(d)
	_react_to_weather()
	match state:
		"fainted":
			faint_t -= d
			if faint_t <= 0.0:
				_recover()
		"nap":
			work_t -= d
			if work_t <= 0.0 or Game.energy > 55.0:
				state = "idle"
				say("Huh? Did I doze off?")
		"sleep":
			activity = "Sleeping"
			if not Game.is_night() and Game.energy >= 60.0:
				_exit_house()
				say_line("morning")
		"inside":
			activity = "Sheltering inside"
			work_t -= d
			if work_t <= 0.0 and Game.weather != "storm":
				_exit_house()
				say("Is it over?")
		"rest":
			work_t -= d
			if work_t <= 0.0 or Game.energy >= 95.0:
				_exit_house()
		"idle":
			think_t -= d
			if think_t <= 0.0:
				_choose()
		"walk":
			_walk(d)
		"work":
			work_t -= d * speed_mult()
			if task.get("kind", "") == "extinguish" and randf() < d * 0.12:
				hurt(6, "a nasty burn")
			if work_t <= 0.0:
				_finish()
	if chatter_t <= 0.0:
		chatter_t = randf_range(25.0, 60.0)
		if bubble_t <= 0.0 and state in ["idle", "walk", "work"]:
			if Game.weather == "heat":
				say_line("heat")
			elif Game.energy < 25.0:
				say_line("tired")
			else:
				say_line("idle")


func _update_stats(d: float) -> void:
	var heat := Game.weather == "heat"
	match state:
		"sleep":
			Game.energy += 3.0 * d
			Game.health += 0.8 * d
		"inside":
			Game.energy += 1.2 * d
			Game.health += 0.3 * d
		"rest":
			Game.energy += 2.5 * d
			Game.health += 0.25 * d
		"nap":
			Game.energy += 2.0 * d
		"work":
			Game.energy -= 0.45 * d * (1.8 if heat else 1.0)
		"walk":
			Game.energy -= 0.06 * d * (1.8 if heat else 1.0)
	if Game.poison > 0.0:
		Game.poison -= d
		Game.health -= 1.0 * d
		if randf() < d * 0.05:
			say("Ugh... that snake bite...")
	var baseline := 75.0 if Game.has_relic("stones") else 60.0
	Game.mood += (baseline - Game.mood) * 0.002 * d
	Game.energy = clampf(Game.energy, 0.0, 100.0)
	Game.health = clampf(Game.health, 0.0, 100.0)
	Game.mood = clampf(Game.mood, 0.0, 100.0)
	if state == "fainted":
		return
	if heat and state == "work" and Game.energy < 20.0 and randf() < d * 0.03:
		hurt(12, "heatstroke")
	if Game.energy <= 0.0 and state in ["idle", "walk", "work"]:
		_drop_carry()
		state = "nap"
		work_t = 25.0
		activity = "Passed out from exhaustion!"
		say("Zzz... so... tired...")
		Game.add_log("The farmer collapsed from exhaustion!")
	if Game.health <= 0.0:
		faint()


func _react_to_weather() -> void:
	if Game.weather == _last_weather:
		return
	_last_weather = Game.weather
	if not visible_outside():
		return
	match Game.weather:
		"rain":
			say("Free watering!")
		"heat":
			say_line("heat")
		"storm":
			say("Uh oh, thunder...")


# ---------------------------------------------------------------- damage
func hurt(amount: int, reason: String) -> void:
	if state == "fainted":
		return
	if Game.charms > 0:
		Game.charms -= 1
		say_line("lucky")
		world.puff(pos + Vector2(0, -8), Color("ffcd75"), 12, 26.0)
		world.float_text("BLOCKED!", pos + Vector2(-14, -26), Color("a7f070"))
		Game.add_log("Lucky Charm blocked %s!" % reason)
		return
	Game.health -= amount
	Game.mood = maxf(0.0, Game.mood - amount * 0.4)
	hurt_t = 0.6
	say_line("hurt")
	world.float_text("-%d" % amount, pos + Vector2(-4, -24), Color("b13e53"))
	Game.add_log("Farmer hurt by %s (-%d HP)." % [reason, amount])
	if Game.health <= 0.0:
		faint()


func faint() -> void:
	if state == "fainted":
		return
	_drop_carry()
	hidden = false
	state = "fainted"
	faint_t = 40.0
	task = {}
	path = []
	activity = "Fainted!"
	say("@ x_x @", 4.0)
	Game.bump("faints")
	Game.add_log("The farmer fainted! Help him out next time...")


func _recover() -> void:
	var bill := int(Game.coins * 0.3)
	Game.add_coins(-bill)
	Game.health = 45.0
	Game.energy = maxf(Game.energy, 50.0)
	Game.poison = 0.0
	Game.mood = maxf(10.0, Game.mood - 15.0)
	pos = world.feet(world.DOOR)
	state = "idle"
	think_t = 1.0
	say("Doc patched me up... -%d coins." % bill, 4.0)
	Game.add_log("Doctor's bill: -%d coins." % bill)


func on_click() -> void:
	if state == "fainted":
		say("...ugh...")
		return
	if state == "nap":
		say("Wha-? I'm up! I'm up!")
		return
	say_line("click")
	Game.mood = minf(100.0, Game.mood + 1.0)


func _drop_carry() -> void:
	if carrying == "":
		return
	var cells: Array = world.free_grass_cells()
	if cells.size() > 0:
		world.objs[world.nearest(cells, cell())] = carry_data
	carrying = ""
	carry_data = {}


func _exit_house() -> void:
	hidden = false
	state = "idle"
	think_t = 0.5
	if world.is_house(cell()) or task.get("kind", "") in ["sleep", "shelter", "rest_home"]:
		pos = world.feet(world.DOOR)
	task = {}


# ---------------------------------------------------------------- choosing
func _choose() -> void:
	think_t = randf_range(0.4, 1.2)
	var me := cell()
	var cands: Array = []
	var raining := Game.weather == "rain" or Game.weather == "storm"

	if storm_brave_t > 0.0:
		storm_brave_t -= 1.0
	if Game.weather == "storm" and storm_brave_t <= 0.0:
		if randf() < 0.65 or Game.health < 50.0:
			cands.append([300, {"kind": "shelter", "cell": world.DOOR}])
		else:
			storm_brave_t = 25.0
			say_line("storm_brave")
	if Game.is_night():
		cands.append([250, {"kind": "sleep", "cell": world.DOOR}])
	if Game.health < 30.0:
		cands.append([120, {"kind": "sleep", "cell": world.DOOR}])
	if Game.energy < 25.0:
		var benches: Array = world.cells_with_obj(["bench"])
		if benches.size() > 0:
			cands.append([100, {"kind": "rest", "cell": benches[0], "adj": true}])
		else:
			cands.append([100, {"kind": "rest_home", "cell": world.DOOR}])
	var wells: Array = world.cells_with_obj(["well"])
	if Game.energy < 55.0 and wells.size() > 0:
		cands.append([45, {"kind": "drink", "cell": wells[0], "adj": true, "dur": 2.0, "tool": "tool_bucket"}])

	var fires: Array = world.cells_with_obj(["fire"])
	if fires.size() > 0:
		cands.append([140, {"kind": "extinguish", "cell": world.nearest(fires, me), "adj": true, "dur": 2.5, "tool": "tool_bucket"}])

	var th: Variant = null
	var bd := 1e9
	for a in world.threats():
		if a.kind == "snake":
			continue  # hidden in the grass, he never sees them
		var dd: float = a.pos.distance_to(pos)
		if dd < bd:
			bd = dd
			th = a
	if th != null:
		var s := 85
		match th.kind:
			"fox": s = 90
			"boar": s = 60
			"wasps": s = 40
		cands.append([s, {"kind": "shoo", "target": th, "cell": world.cell_of(th.pos)}])

	var ripe: Array = world.ripe_cells()
	if ripe.size() > 0:
		cands.append([70, {"kind": "harvest", "cell": world.nearest(ripe, me), "dur": 1.4, "tool": "tool_sickle"}])

	var dead: Array = []
	var dry: Array = []
	for c in world.crops:
		var cr: Dictionary = world.crops[c]
		if cr.get("dead", false):
			dead.append(c)
		elif cr["growth"] < 1.0 and world.wet[world.idx(c)] < 0.25:
			dry.append(c)
	if dead.size() > 0:
		cands.append([52, {"kind": "clear_crop", "cell": world.nearest(dead, me), "dur": 1.2, "tool": "tool_sickle"}])
	if dry.size() > 0 and not raining:
		var t: Vector2i = world.nearest(dry, me)
		var urgency: float = (100.0 - world.crops[t]["health"]) * 0.3
		cands.append([62 + urgency, {"kind": "water", "cell": t, "dur": 0.8 if wells.size() > 0 else 1.3, "tool": "tool_can"}])

	var empty: Array = []
	for c in world.tilled_cells():
		if not world.crops.has(c) and not world.objs.has(c):
			empty.append(c)
	if empty.size() > 0:
		var crop := _pick_crop()
		if crop != "":
			cands.append([58, {"kind": "plant", "cell": world.nearest(empty, me), "crop": crop, "dur": 1.2, "tool": "tool_seeds"}])

	var ore: Array = world.cells_with_obj(["ore"])
	if ore.size() > 0:
		cands.append([60, {"kind": "mine", "cell": world.nearest(ore, me), "adj": true, "dur": 3.0, "tool": "tool_hammer"}])
	var debris: Array = world.cells_with_obj(["weed", "rock", "stump", "ash"])
	if debris.size() > 0:
		var dc: Vector2i = world.nearest(debris, me)
		var dt: String = world.obj_type(dc)
		var dur := {"weed": 1.0, "rock": 2.5, "stump": 3.5, "ash": 1.0}
		var tool := {"weed": "tool_sickle", "rock": "tool_hammer", "stump": "tool_axe", "ash": "tool_hoe"}
		cands.append([34 + (8 if debris.size() > 10 else 0), {"kind": "clear", "cell": dc, "adj": world.is_solid(dc),
			"dur": dur[dt], "tool": tool[dt]}])

	if world.tilled_cells().size() < Game.max_tilled():
		var tc: Variant = _pick_till_cell()
		if tc != null:
			cands.append([48, {"kind": "till", "cell": tc, "dur": 2.0, "tool": "tool_hoe"}])

	var inv := Game.inventory_count()
	var inv_value := Game.inventory_value()
	if inv_value >= 30 or (inv_value >= 8 and (Game.is_evening() or Game.coins < 10)):
		cands.append([46 + inv * 2, {"kind": "sell", "cell": world.BIN, "adj": true, "dur": 1.5}])

	# get a little field going before spending money on buildings
	var b: Dictionary = _pick_build() if world.tilled_cells().size() >= 4 else {}
	if not b.is_empty():
		cands.append([30 + randf() * 25.0, b])

	for c in world.objs:
		var o: Dictionary = world.objs[c]
		if Game.STRUCTS.has(o["type"]):
			var maxhp: int = Game.STRUCTS[o["type"]]["hp"]
			if o["hp"] < maxhp * 0.25:
				cands.append([40, {"kind": "demolish", "cell": c, "adj": true, "dur": 2.5, "tool": "tool_hammer"}])
				break
			elif o["hp"] < maxhp * 0.6 and Game.coins >= 5:
				cands.append([38, {"kind": "repair", "cell": c, "adj": true, "dur": 2.5, "tool": "tool_hammer"}])
				break

	var movable: Array = []
	var decor: Array = []
	for c in world.objs:
		var t2: String = world.objs[c]["type"]
		if Game.STRUCTS.has(t2) and Game.STRUCTS[t2]["movable"]:
			movable.append(c)
		if t2 in ["flowerbed", "sign", "bench", "fence"]:
			decor.append(c)
	if movable.size() > 0:
		cands.append([9, {"kind": "pickup", "cell": movable.pick_random(), "adj": true, "dur": 1.5}])
	if decor.size() > 0:
		cands.append([3, {"kind": "demolish", "cell": decor.pick_random(), "adj": true, "dur": 2.0, "tool": "tool_hammer"}])

	var trees: Array = world.cells_with_obj(["tree"])
	if trees.size() > 2 or (trees.size() > 0 and Game.coins < 15):
		cands.append([22 if Game.coins < 15 else 6, {"kind": "chop", "cell": world.nearest(trees, me), "adj": true, "dur": 4.0, "tool": "tool_axe"}])

	var wander := Vector2i(clampi(me.x + randi_range(-3, 3), 0, world.COLS - 1), clampi(me.y + randi_range(-3, 3), 2, world.ROWS - 1))
	if world.is_walkable(wander):
		cands.append([12, {"kind": "wander", "cell": wander, "dur": randf_range(1.0, 3.0)}])

	if cands.is_empty():
		return
	var best: Dictionary = {}
	var best_s := -1e9
	for cd in cands:
		var s: float = float(cd[0]) + randf() * 14.0
		if s > best_s:
			best_s = s
			best = cd[1]
	_start(best)


func _pick_crop() -> String:
	var opts: Array = []
	for id in Game.CROPS:
		if id == "melon" or not Game.crop_unlocked(id):
			continue
		if Game.coins >= int(Game.CROPS[id]["seed"]) + 2:
			opts.append(id)
	if Game.buff("favor") and Game.favor_crop in opts and randf() < 0.75:
		return Game.favor_crop
	if opts.is_empty():
		if Game.coins < 4 and world.crops.size() < 3:
			return "turnip"  # grandpa's spare seeds: never soft-lock
		return ""
	# lean towards the fanciest crop he can afford
	if randf() < 0.55:
		return opts[opts.size() - 1]
	return opts.pick_random()


func _pick_till_cell() -> Variant:
	var tilled: Array = world.tilled_cells()
	var cands: Array = []
	var focus := Vector2(6, 8)
	if tilled.size() > 0:
		focus = Vector2.ZERO
		for t in tilled:
			focus += Vector2(t)
		focus /= tilled.size()
		for t in tilled:
			for dd in world.DIRS:
				var n: Vector2i = t + dd
				if n.y >= 3 and world.is_free_grass(n):
					cands.append(n)
	if cands.is_empty():
		for c in world.free_grass_cells():
			if c.y >= 3 and c.x >= 1 and c.x <= world.COLS - 2:
				cands.append(c)
	if cands.is_empty():
		return null
	var best: Variant = null
	var bd := 1e9
	for c in cands:
		var dd: float = Vector2(c).distance_to(focus) + randf() * 0.6
		if dd < bd:
			bd = dd
			best = c
	return best


func _pick_build() -> Dictionary:
	var lv := Game.level()
	var opts: Array = []
	var weights: Array = []
	var crops_n: int = world.crops.size()
	for id in Game.STRUCTS:
		var def: Dictionary = Game.STRUCTS[id]
		if def["level"] > lv or world.count_obj(id) >= def["max"]:
			continue
		if Game.coins < int(def["cost"]) + 8:
			continue
		var w := 1.0
		match id:
			"scarecrow": w = 5.0 if crops_n > 3 else 0.5
			"well": w = 4.0
			"coop": w = 3.0
			"rod": w = 2.0
			"fence": w = 2.0
			"beehive": w = 2.0 if crops_n > 4 else 0.3
		opts.append(id)
		weights.append(w)
	if opts.is_empty():
		return {}
	var total := 0.0
	for w in weights:
		total += w
	var r := randf() * total
	var pick: String = opts[0]
	for i in opts.size():
		r -= weights[i]
		if r <= 0.0:
			pick = opts[i]
			break
	var c: Variant = _pick_build_cell(pick)
	if c == null:
		return {}
	return {"kind": "build", "what": pick, "cell": c, "adj": true, "dur": 4.0, "tool": "tool_hammer"}


func _pick_build_cell(id: String) -> Variant:
	var free: Array = world.free_grass_cells()
	var cands: Array = []
	var tilled: Array = world.tilled_cells()
	for c in free:
		var ok := true
		match id:
			"fence":
				ok = c.x == 0 or c.x == world.COLS - 1 or c.y == world.ROWS - 1
			"scarecrow", "beehive":
				ok = false
				for t in tilled:
					if Vector2(t).distance_to(Vector2(c)) <= 2.0:
						ok = true
						break
			"sign", "bench", "lamp":
				ok = c.y <= 5
			_:
				ok = c.y >= 2
		if ok:
			cands.append(c)
	cands.shuffle()
	for c in cands.slice(0, 8):
		if _keeps_connected(c):
			return c
	return null


## True if putting something solid on c does not cut the farm in two.
func _keeps_connected(c: Vector2i) -> bool:
	var before := _reach_count(Vector2i(-99, -99))
	var after := _reach_count(c)
	return after >= before - 1


func _reach_count(block: Vector2i) -> int:
	var start: Vector2i = world.DOOR
	var seen := {start: true}
	var q: Array = [start]
	while q.size() > 0:
		var c: Vector2i = q.pop_front()
		for dd in world.DIRS:
			var n: Vector2i = c + dd
			if seen.has(n) or n == block or not world.is_walkable(n):
				continue
			seen[n] = true
			q.append(n)
	return seen.size()


# ---------------------------------------------------------------- doing
func _start(t: Dictionary) -> void:
	task = t
	var target: Vector2i = t["cell"]
	var p: Variant = world.find_path(cell(), target, t.get("adj", false))
	if p == null:
		task = {}
		think_t = 0.8
		return
	path = p
	state = "walk"
	repath_t = 0.6
	activity = _describe(t)
	match t["kind"]:
		"till": say_line("till", 0.25)
		"plant": say_line("plant", 0.25)
		"water": say_line("water", 0.2)
		"harvest": say_line("harvest", 0.3)
		"sell": say_line("sell", 0.4)
		"build": say("Let's build a %s!" % Game.STRUCTS[t["what"]]["name"])
		"demolish": say_line("demolish", 0.7)
		"pickup": say_line("rearrange", 0.7)
		"clear": say_line("clear", 0.2)
		"shoo": say_line("shoo", 0.8)
		"extinguish": say_line("fire", 0.8)
		"sleep": say_line("night", 0.6)
		"shelter": say_line("storm_shelter")
		"rest", "rest_home": say_line("rest", 0.6)
		"chop": say_line("chop", 0.3)


func _describe(t: Dictionary) -> String:
	var c: Vector2i = t["cell"]
	match t["kind"]:
		"till": return "Tilling soil"
		"plant": return "Planting %s" % Game.CROPS[t["crop"]]["name"].to_lower()
		"water":
			if world.crops.has(c):
				return "Watering %s" % Game.CROPS[world.crops[c]["type"]]["name"].to_lower()
			return "Watering"
		"harvest": return "Harvesting"
		"clear_crop": return "Clearing a dead crop"
		"clear": return "Clearing %s" % world.obj_type(c)
		"mine": return "Mining meteor ore"
		"sell": return "Selling produce"
		"build": return "Building a %s" % Game.STRUCTS[t["what"]]["name"]
		"repair": return "Repairing the %s" % _sname(world.obj_type(c))
		"demolish": return "Tearing down the %s" % _sname(world.obj_type(c))
		"pickup": return "Moving the %s" % _sname(world.obj_type(c))
		"place": return "Placing the %s" % _sname(carrying)
		"shoo": return "Chasing off a %s" % t["target"].kind
		"extinguish": return "Fighting a fire!"
		"sleep": return "Heading to bed"
		"shelter": return "Running for shelter!"
		"rest", "rest_home": return "Taking a break"
		"drink": return "Drinking at the well"
		"chop": return "Chopping a tree"
		"wander": return "Strolling around"
	return "Pondering"


func _sname(t: String) -> String:
	if Game.STRUCTS.has(t):
		return Game.STRUCTS[t]["name"]
	return t


func _walk(d: float) -> void:
	if task.get("kind", "") == "shoo":
		var a = task["target"]
		if a.dead or a.leaving():
			_idle()
			return
		if pos.distance_to(a.pos) < 14.0:
			_do_shoo(a)
			return
		repath_t -= d
		if repath_t <= 0.0 or path.is_empty():
			repath_t = 0.6
			var p: Variant = world.find_path(cell(), world.cell_of(a.pos), world.is_solid(world.cell_of(a.pos)))
			if p == null:
				_idle()
				return
			path = p
		if path.is_empty():
			_step_towards(a.pos, d)
			return
	if path.is_empty():
		_arrive()
		return
	var next: Vector2i = path[0]
	if world.is_solid(next):
		var p2: Variant = world.find_path(cell(), task["cell"], task.get("adj", false))
		if p2 == null:
			_idle()
			return
		path = p2
		return
	if _step_towards(world.feet(next), d):
		path.pop_front()
		for a in world.animals:
			if a.kind == "snake" and not a.dead and world.cell_of(a.pos) == next:
				a.bite_farmer()


## Moves towards p; returns true on arrival.
func _step_towards(p: Vector2, d: float) -> bool:
	var dir := p - pos
	var step := SPEED * speed_mult() * d
	if absf(dir.x) > 0.5:
		flip = dir.x < 0.0
	if dir.length() <= step:
		pos = p
		return true
	pos += dir.normalized() * step
	return false


func _arrive() -> void:
	var c: Vector2i = task["cell"]
	if c.x * 16 + 8 != int(pos.x) and absf(c.x * 16 + 8 - pos.x) > 1.0:
		flip = c.x * 16 + 8 < pos.x
	match task["kind"]:
		"sleep":
			hidden = true
			state = "sleep"
			Game.add_log("The farmer went to bed.")
		"shelter":
			hidden = true
			state = "inside"
			work_t = 15.0
		"rest_home":
			hidden = true
			state = "rest"
			work_t = 25.0
			activity = "Resting at home"
		"rest":
			state = "rest"
			work_t = 20.0
			activity = "Resting on the bench"
		_:
			state = "work"
			work_t = float(task.get("dur", 1.0))


func _idle() -> void:
	state = "idle"
	task = {}
	path = []
	think_t = randf_range(0.3, 0.9)


func _do_shoo(a) -> void:
	flip = a.pos.x < pos.x
	match a.kind:
		"fox":
			if randf() < 0.35:
				hurt(10, "a fox bite")
		"boar":
			if randf() < 0.5:
				hurt(18, "a charging boar")
		"wasps":
			if randf() < 0.6:
				hurt(6, "wasp stings")
			if randf() < 0.4:
				say("They're still here!")
				state = "work"
				task = {"kind": "wander", "cell": cell(), "dur": 0.8}
				work_t = 0.8
				return
	say_line("shoo", 0.6)
	a.scare()
	Game.bump("shooed")
	if Game.buff("bounty"):
		Game.add_coins(6)
		world.float_text("+6", pos + Vector2(-4, -24))
	state = "work"
	task = {"kind": "wander", "cell": cell(), "dur": 0.7, "tool": "tool_hoe"}
	work_t = 0.7


func _finish() -> void:
	var c: Vector2i = task.get("cell", cell())
	var kind: String = task.get("kind", "")
	match kind:
		"till":
			if world.is_free_grass(c):
				world.set_tilled(c, true)
				world.puff(world.center(c), Color("8b5a3c"), 8)
		"plant":
			if world.is_tilled(c) and not world.crops.has(c) and not world.objs.has(c):
				var crop: String = task["crop"]
				var seed: int = Game.CROPS[crop]["seed"]
				if Game.coins >= seed:
					Game.add_coins(-seed)
				else:
					say_line("broke")
				world.plant(c, crop)
				world.puff(world.center(c), Color("5a3626"), 4, 10.0)
		"water":
			if world.is_tilled(c):
				world.wet[world.idx(c)] = 1.0
				world.puff(world.center(c), Color("41a6f6"), 8, 14.0, 4.0)
		"harvest":
			if world.crops.has(c) and world.crop_stage(world.crops[c]) == 3:
				var type: String = world.crops[c]["type"]
				var n := 1
				if type == "wheat":
					n = 2
				Game.add_item(type, n)
				world.crops.erase(c)
				Game.bump("harvested")
				Game.mood = minf(100.0, Game.mood + 2.0)
				world.float_text("+%d %s" % [n, Game.CROPS[type]["name"]], pos + Vector2(-16, -24), Color("a7f070"))
				world.puff(world.center(c), Color("a7f070"), 6)
				if type == "melon":
					Game.add_log("A golden melon was harvested!")
					say("It's... it's GOLDEN!")
		"clear_crop":
			if world.crops.has(c) and world.crops[c].get("dead", false):
				world.crops.erase(c)
		"clear":
			var t: String = world.obj_type(c)
			match t:
				"rock":
					Game.add_item("stone")
				"stump":
					Game.add_item("wood", 2)
			if t in ["rock", "weed", "stump", "ash"]:
				world.remove_obj(c)
				world.puff(world.center(c), Color("94b0c2") if t == "rock" else Color("38b764"), 8)
		"mine":
			if world.obj_type(c) == "ore":
				world.remove_obj(c)
				Game.add_item("ore", 2)
				world.float_text("+2 ORE", pos + Vector2(-12, -24), Color("73eff7"))
				world.puff(world.center(c), Color("73eff7"), 10)
		"chop":
			if world.obj_type(c) == "tree":
				world.remove_obj(c)
				world.place_obj(c, "stump")
				Game.add_item("wood", 4)
				world.puff(world.center(c) + Vector2(0, -8), Color("2a8a4a"), 14, 22.0)
		"sell":
			var v := Game.inventory_value()
			if v > 0:
				Game.add_coins(v)
				Game.inventory.clear()
				world.float_text("+%d" % v, world.center(world.BIN) + Vector2(-6, -18))
				Game.add_log("Sold produce for %d coins." % v)
		"build":
			var what: String = task["what"]
			var cost: int = Game.STRUCTS[what]["cost"]
			if world.is_free_grass(c) and Game.coins >= cost and _keeps_connected(c):
				Game.add_coins(-cost)
				world.place_obj(c, what)
				Game.bump("built")
				Game.mood = minf(100.0, Game.mood + 5.0)
				world.puff(world.center(c), Color("c28a5a"), 10)
				Game.add_log("Built a %s." % Game.STRUCTS[what]["name"])
				if what == "coop":
					for i in 2:
						world.add_animal(Animal.new(world, "chicken", world.feet(c) + Vector2(randf_range(-10, 10), 10)))
		"repair":
			var o: Dictionary = world.obj_at(c)
			if not o.is_empty() and Game.STRUCTS.has(o["type"]):
				o["hp"] = Game.STRUCTS[o["type"]]["hp"]
				Game.add_coins(-3)
				say("Good as new!")
		"demolish":
			var t2: String = world.obj_type(c)
			if Game.STRUCTS.has(t2):
				var refund := int(Game.STRUCTS[t2]["cost"] * 0.3)
				world.remove_obj(c)
				Game.add_coins(refund)
				world.puff(world.center(c), Color("c28a5a"), 10)
				Game.add_log("Tore down the %s (+%d)." % [Game.STRUCTS[t2]["name"], refund])
		"pickup":
			var o2: Dictionary = world.obj_at(c)
			if not o2.is_empty() and Game.STRUCTS.has(o2["type"]) and Game.STRUCTS[o2["type"]]["movable"]:
				carrying = o2["type"]
				carry_data = o2
				world.remove_obj(c)
				var dest: Variant = _pick_build_cell(carrying)
				if dest == null or dest == c:
					world.objs[c] = carry_data
					carrying = ""
					carry_data = {}
				else:
					_start({"kind": "place", "cell": dest, "adj": true, "dur": 1.0})
					return
		"place":
			if carrying != "":
				var dest2: Vector2i = c
				if not world.is_free_grass(dest2):
					var free: Array = world.free_grass_cells()
					if free.size() > 0:
						dest2 = world.nearest(free, cell())
				world.objs[dest2] = carry_data
				world.puff(world.center(dest2), Color("c28a5a"), 6)
				carrying = ""
				carry_data = {}
				say_line("place", 0.8)
		"drink":
			Game.energy = minf(100.0, Game.energy + 25.0)
			say("Ahh, fresh water!")
		"extinguish":
			var o3: Dictionary = world.obj_at(c)
			if o3.get("type", "") == "fire":
				world.director.extinguish(c)
				say("Phew! Got it.")
		"wander":
			if randf() < 0.15 and bubble_t <= 0.0:
				say_line("idle")
	_idle()


# ---------------------------------------------------------------- drawing
func draw(ci: CanvasItem) -> void:
	if hidden:
		if state == "sleep" or state == "rest":
			var z := Art.tex("zzz")
			var off := Vector2(fmod(anim_t * 4.0, 8.0), -fmod(anim_t * 6.0, 12.0))
			ci.draw_texture(z, Vector2(22, 4) + off, Color(1, 1, 1, 0.8))
		return
	# shadow
	ci.draw_rect(Rect2(pos.x - 5, pos.y, 10, 2), Color(0, 0, 0, 0.25))
	var mod := Color.WHITE
	if Game.poison > 0.0:
		mod = Color(0.75, 1.0, 0.7)
	if hurt_t > 0.0 and int(hurt_t * 20.0) % 2 == 0:
		mod = Color(1, 0.4, 0.4)
	if state == "fainted" or state == "nap":
		ci.draw_set_transform(pos + Vector2(0, -3), PI * 0.5 if flip else -PI * 0.5, Vector2.ONE)
		ci.draw_texture(Art.tex("farmer_idle"), Vector2(-8, -8), mod)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		if state == "nap":
			ci.draw_texture(Art.tex("zzz"), pos + Vector2(4, -16 - fmod(anim_t * 5.0, 6.0)))
		else:
			for i in 3:
				var a := anim_t * 3.0 + i * TAU / 3.0
				ci.draw_rect(Rect2(pos + Vector2(cos(a) * 6.0 - 0.5, -12 + sin(a) * 2.0), Vector2(1, 1)), Color("ffcd75"))
		return
	var frame := "farmer_idle"
	var bob := 0.0
	match state:
		"walk":
			frame = "farmer_walk1" if int(anim_t * 6.0) % 2 == 0 else "farmer_walk2"
			bob = -1.0 if int(anim_t * 6.0) % 2 == 0 else 0.0
		"work":
			frame = "farmer_work" if int(anim_t * 4.0) % 2 == 0 else "farmer_idle"
		"rest":
			bob = 2.0
	ci.draw_set_transform(pos, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture(Art.tex(frame), Vector2(-8, -15 + bob), mod)
	if state == "work" and task.has("tool"):
		var up := int(anim_t * 4.0) % 2 == 0
		ci.draw_texture(Art.tex(task["tool"]), Vector2(3, -22 if up else -16))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if carrying != "":
		var tx := Art.tex(carrying)
		ci.draw_texture_rect(tx, Rect2(pos.x - 6, pos.y - 30, 12, 12 * tx.get_height() / maxf(1.0, tx.get_width())), false)


# ---------------------------------------------------------------- save
func to_dict() -> Dictionary:
	return {"x": pos.x, "y": pos.y, "carrying": carrying, "carry": carry_data,
		"sleep": state == "sleep", "fainted": state == "fainted", "faint_t": faint_t}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	pos = Vector2(float(d.get("x", pos.x)), float(d.get("y", pos.y)))
	carrying = String(d.get("carrying", ""))
	carry_data = d.get("carry", {})
	if carrying != "":
		_drop_carry()
	if bool(d.get("sleep", false)):
		hidden = true
		state = "sleep"
		task = {"kind": "sleep", "cell": world.DOOR}
	elif bool(d.get("fainted", false)):
		state = "fainted"
		faint_t = float(d.get("faint_t", 20.0))
