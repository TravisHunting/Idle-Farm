extends RefCounted
class_name Farmer
## The autonomous farmer. A utility-scored task picker (_choose) feeds a small state machine:
##   idle -> walk -> work -> (finish) -> idle
##   sleep / inside / rest   = hidden in the house or sitting on a bench
##   nap                     = passed out from exhaustion on the spot (vulnerable)
##   fainted                 = health hit 0; costs a doctor's bill
##   abducted                = taken up by an alien saucer; comes back changed (colony.gd)
##   away                    = (friend only) their player isn't here: at home in the hut
## Stats (health/energy/mood/poison) live in Game so they persist.
## In multiplayer the visiting player has a second farmer (`friend`, World.friend) with a hut of
## his own: same brain, different clothes; he never touches the shared stats and never faints.

const SPEED := 26.0

const LINES := {
	"morning": ["Good morning, farm!", "Rise and shine!", "Another beautiful day!"],
	"till": ["Time to till!", "Fresh soil!", "Dig dig dig."],
	"plant": ["Grow big, little one!", "In you go!", "Seeds of the future."],
	"water": ["Drink up!", "Splish splash.", "Thirsty little guys."],
	"harvest": ["Look at this beauty!", "Harvest time!", "Yum!"],
	"sell": ["Ooh, what did I get?", "Trade you a turnip for that!", "Shiny! Into the chest."],
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
	"fire": ["FIRE! Water, quick!", "Not the crops!"],
	"click": ["Oh! Hello there!", "Hey, you!", "Need something?", "Busy busy!", "Nice to see you!",
		"Did you hear a crow?", "Thanks for the help!"],
	"chop": ["Timber!", "Good wood."],
	"rest": ["Ahh, a little sit-down.", "Just resting my eyes."],
	"plan_silly": ["I'll plant a %s! Trust me.", "A %s-shaped field. Genius.", "Ooh, what about a %s?"],
	"plan": ["New field goes here.", "Right. A %s. Sensible.", "Let's mark out a field."],
	"pave": ["A path! Fancy.", "No more muddy boots.", "Stone by stone."],
	"fence": ["Good fences, good crops.", "Keep those rabbits out!", "A fence. For the vibes."],
	"thorns": ["Ow! Thorns!", "Brambles bite back!"],
	"overgrown": ["So... much... grass.", "Grandpa really let this go.", "I can't even see the soil!"],
	"visit_aliens": ["Hello, neighbours!", "Brought you a turnip!", "Greetings! Er, glorp?"],
	"sabotage": ["Off my land!", "This is MY farm!", "Take that, space weeds!"],
	"honey": ["Sweet! Thanks, big fellas.", "Honey for the chest... er, the pantry.", "Good bugs. GOOD bugs."],
	"smoke": ["Out! Out of my farm!", "Smoke 'em out!", "No more tunnels under MY turnips!"],
	"abducted_back": ["I've seen things...", "They probed my turnips.", "The stars! The STARS!", "How long was I gone?"],
	"plan_pattern": ["I've got a vision: a %s!", "Crop art time! A %s.", "They'll see this %s from the sky!"],
}

var world  # World
var pid := ""            # the player this farmer belongs to (the farmhouse's: the world's first owner)
var friend := false      # the visiting player's farmer: lives in the hut at `home`
var home := Vector2i(-1, -1)
var uid := 0      # stable actor id (World.new_uid), used to match actors across the network
var net_to := Vector2.INF   # on a guest: where the host says the farmer is
## The tool in his hands (only drawn while working); a plain property for Net's actor stream.
var net_tool: String:
	get: return String(task.get("tool", ""))
	set(v):
		if v == "":
			task.erase("tool")
		else:
			task["tool"] = v
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
	uid = w.new_uid()


func cell() -> Vector2i:
	return world.cell_of(pos)


## Where he goes in and out: the farmhouse door, or the step in front of his hut.
func door() -> Vector2i:
	return home + Vector2i(0, 1) if friend and home.x >= 0 else world.DOOR


## The other player's farmer (or null).
func other() -> Farmer:
	return world.farmer if friend else world.friend


## For log lines: "The farmer", or the visiting player's name.
func who() -> String:
	return Game.player_name(pid) if friend else "The farmer"


## His player left: home to the hut until they come back.
func go_away() -> void:
	if state == "away":
		return
	_drop_carry()
	task = {}
	path = []
	hidden = true
	state = "away"
	activity = "Gone home"
	pos = world.feet(door())


func say(text: String, dur: float = 3.0) -> void:
	bubble = text
	bubble_t = dur


func say_line(kind: String, chance: float = 1.0) -> void:
	if randf() <= chance and LINES.has(kind):
		say(LINES[kind].pick_random())


func speed_mult() -> float:
	var m := lerpf(0.75, 1.2, Game.mood / 100.0)
	if Game.has_perk("quick_feet"):
		m *= 1.35
	if world.is_path(cell()):
		m *= 1.25
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
	if not friend:
		_update_stats(d)
	_react_to_weather()
	match state:
		"away":
			_exit_house()
			say("I'm back!")
		"fainted":
			faint_t -= d
			if faint_t <= 0.0:
				_recover()
		"abducted":
			activity = "Abducted by aliens!"
			work_t -= d
			if work_t <= 0.0:
				_return_from_saucer()
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
			work_t -= d * speed_mult() * (1.3 if Game.has_mutation("tentacle") else 1.0)
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
			elif randf() < 0.3:
				say(Game.chest_comment(), 4.0)   # he likes to think about his chest
			else:
				say_line("idle")


func _update_stats(d: float) -> void:
	var heat := Game.weather == "heat"
	var rest := 2.0 if Game.has_perk("early_bird") else 1.0
	match state:
		"sleep":
			Game.energy += 3.0 * d * rest
			Game.health += 0.8 * d
		"inside":
			Game.energy += 1.2 * d * rest
			Game.health += 0.3 * d
		"rest":
			Game.energy += 2.5 * d * rest
			Game.health += 0.25 * d
		"nap":
			Game.energy += 2.0 * d * rest
		"work":
			Game.energy -= 0.45 * d * (1.8 if heat else 1.0)
		"walk":
			Game.energy -= 0.06 * d * (1.8 if heat else 1.0)
	if Game.has_perk("iron_gut"):
		Game.poison = 0.0
	if Game.poison > 0.0:
		Game.poison -= d
		Game.health -= 1.0 * d
		if randf() < d * 0.05:
			say("Ugh... that snake bite...")
	if Game.has_mutation("green") and visible_outside() and not Game.is_night() and Game.weather in ["sunny", "heat"]:
		Game.energy += 0.25 * d
	var baseline := 75.0 if Game.has_relic("stones") else 60.0
	if Game.has_mutation("tentacle"):
		baseline -= 8.0
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
	if friend:
		# the visitor shrugs it off: the shared stats belong to the farmhouse farmer
		hurt_t = 0.6
		say_line("hurt")
		world.float_text("OUCH", pos + Vector2(-8, -24), Color("b13e53"))
		return
	if Game.charms > 0:
		Game.charms -= 1
		say_line("lucky")
		world.puff(pos + Vector2(0, -8), Color("ffcd75"), 12, 26.0)
		world.float_text("BLOCKED!", pos + Vector2(-14, -26), Color("a7f070"))
		Game.add_log("Lucky Charm blocked %s!" % reason)
		return
	if Game.has_perk("tough"):
		amount = maxi(1, amount / 2)
	if Game.has_mutation("chitin"):
		amount = maxi(1, int(amount * 0.6))
	Game.health -= amount
	Game.mood = maxf(0.0, Game.mood - amount * 0.4)
	hurt_t = 0.6
	say_line("hurt")
	world.float_text("-%d" % amount, pos + Vector2(-4, -24), Color("b13e53"))
	Game.add_log("Farmer hurt by %s (-%d HP)." % [reason, amount])
	if Game.health <= 0.0:
		faint()


func faint() -> void:
	if state == "fainted" or friend:
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
	# no money: the doctor takes the shiniest thing in the chest instead (Doc Hollis is free)
	var fee := "" if Game.friends.has("doc") else Game.best_tradeable()
	if fee != "":
		Game.remove_treasure(fee, 1)
	var fee_name: String = String(Game.TREASURES[fee]["name"]).to_lower() if fee != "" else ""
	Game.health = 45.0
	Game.energy = maxf(Game.energy, 50.0)
	Game.poison = 0.0
	Game.mood = maxf(10.0, Game.mood - 15.0)
	pos = world.feet(world.DOOR)
	state = "idle"
	think_t = 1.0
	if fee != "":
		say("Doc took my %s as payment..." % fee_name, 4.0)
		Game.add_log("The doctor took a %s from the chest as payment." % fee_name)
	elif Game.friends.has("doc"):
		say("Doc Hollis patched me up. Free!", 4.0)
	else:
		say("Doc patched me up. Took pity on my empty chest.", 4.0)


## Beamed up by a saucer for a while (colony.gd).
func abduct(seconds: float) -> void:
	if state == "fainted" or friend:
		return
	_drop_carry()
	task = {}
	path = []
	hidden = true
	state = "abducted"
	work_t = seconds
	Game.bump("abductions")


func _return_from_saucer() -> void:
	hidden = false
	state = "idle"
	think_t = 1.0
	var land: Variant = world.colony.random_land_cell() if world.colony else null
	pos = world.feet(land) if land != null else world.feet(world.DOOR)
	Game.energy = maxf(Game.energy, 40.0)
	say_line("abducted_back")
	if world.colony:
		world.colony.farmer_returned()


func on_click() -> void:
	if state == "fainted":
		say("...ugh...")
		return
	if state == "nap":
		say("Wha-? I'm up! I'm up!")
		return
	if state == "abducted":
		return
	say_line("click")
	if not Game.puppet:
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
	var was_in := hidden
	hidden = false
	state = "idle"
	think_t = 0.5
	if world.is_house(cell()) or task.get("kind", "") in ["sleep", "shelter", "rest_home"] or was_in:
		pos = world.feet(door())
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
			cands.append([300, {"kind": "shelter", "cell": door()}])
		else:
			storm_brave_t = 25.0
			say_line("storm_brave")
	if Game.is_night():
		cands.append([250, {"kind": "sleep", "cell": door()}])
	if Game.health < 30.0:
		cands.append([120, {"kind": "sleep", "cell": door()}])
	if Game.energy < 25.0:
		var benches: Array = world.cells_with_obj(["bench"])
		if benches.size() > 0:
			cands.append([100, {"kind": "rest", "cell": benches[0], "adj": true}])
		else:
			cands.append([100, {"kind": "rest_home", "cell": door()}])
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
		var pc: Vector2i = world.nearest(empty, me)
		var crop := _pick_crop(pc)
		if crop != "":
			cands.append([58, {"kind": "plant", "cell": pc, "crop": crop, "dur": 1.2, "tool": "tool_seeds"}])

	var reach: Dictionary = world.reachable_from(me)
	var ore: Array = []
	for c in world.cells_with_obj(["ore"]):
		if _can_reach(c, reach):
			ore.append(c)
	if ore.size() > 0:
		cands.append([60, {"kind": "mine", "cell": world.nearest(ore, me), "adj": true, "dur": 3.0, "tool": "tool_hammer"}])

	# fields: plan one, clear it, till it
	var todo: Array = world.field_todo()
	var tillable: Array = []
	for c in todo[0]:
		if reach.has(c):
			tillable.append(c)
	var tilled_n: int = world.tilled_cells().size()
	if tilled_n >= Game.max_tilled():
		tillable = tillable.filter(world.is_pattern)   # crop pictures get finished past the cap
	if tillable.size() > 0:
		cands.append([50, {"kind": "till", "cell": world.nearest(tillable, me), "dur": 2.0, "tool": "tool_hoe"}])
	elif todo[0].size() + todo[1].size() == 0 and tilled_n + 2 <= Game.max_tilled() and world.fields.size() < 12:
		# a first little field matters more than tidying; after that, expanding is a whim
		cands.append([66 if tilled_n < 6 else 46, {"kind": "plan", "cell": me, "dur": 1.5}])

	# overgrowth: field tiles first, then whatever is nearest the house
	var debris: Array = world.reachable_debris(reach).filter(func(c: Vector2i) -> bool: return not world.in_reserve(c))
	if debris.size() > 0:
		var in_field: Array = []
		for c in debris:
			if world.is_planned(c):
				in_field.append(c)
		var target: Vector2i
		var score := 30.0
		if in_field.size() > 0:
			target = world.nearest(in_field, me)
			score = 57.0
		else:
			target = world.nearest(debris, door() if randf() < 0.6 else me)
			# the wilder the farm, the more he wants it gone
			score = 34.0 + 24.0 * (1.0 - world.cleared_ratio())
		if Game.quirk == "tidy" or Game.has_edict("tame_all"):
			score += 12.0
		var tt: String = world.obj_type(target)
		if tt in World.TREES:
			cands.append([score - 4.0, {"kind": "chop", "cell": target, "adj": true, "dur": 4.0, "tool": "tool_axe"}])
		else:
			var def: Dictionary = World.CLEARABLE[tt]
			cands.append([score, {"kind": "clear", "cell": target, "adj": world.is_solid(target),
				"dur": def["dur"], "tool": def["tool"]}])

	# paths between the house, the bin and the fields
	if Game.item_count("stone") >= 1 or Game.has_perk("carpenter"):
		var pv: Variant = world.next_path_cell()
		if pv != null and reach.has(pv):
			cands.append([56.0 + (10.0 if Game.quirk == "builder" else 0.0), {"kind": "pave", "cell": pv, "dur": 1.6, "tool": "tool_hoe"}])

	var inv := Game.inventory_count()
	var inv_value := Game.inventory_value()
	var sell_at := 70 if Game.quirk == "thrifty" else 30
	if inv_value >= sell_at or (inv_value >= 8 and Game.is_evening()):
		cands.append([46 + inv * 2, {"kind": "sell", "cell": world.BIN, "adj": true, "dur": 1.5}])

	# get a little field going before spending money on buildings
	var bld: Dictionary = _pick_build() if tilled_n >= 4 else {}
	if not bld.is_empty() and _can_reach(bld["cell"], reach):
		var bs := 30.0 + randf() * 25.0
		if bld["what"] == "fence":
			bs = 55.0 + (10.0 if Game.quirk == "builder" else 0.0)
		cands.append([bs, bld])

	for c in world.objs:
		var o: Dictionary = world.objs[c]
		if Game.STRUCTS.has(o["type"]) and Game.STRUCTS[o["type"]]["level"] < 99:
			var maxhp: int = Game.STRUCTS[o["type"]]["hp"]
			if not _can_reach(c, reach):
				continue
			if o["hp"] < maxhp * 0.6:
				cands.append([38, {"kind": "repair", "cell": c, "adj": true, "dur": 2.5, "tool": "tool_hammer"}])
				break

	var movable: Array = []
	var decor: Array = []
	for c in world.objs:
		var t2: String = world.objs[c]["type"]
		if not _can_reach(c, reach):
			continue
		if Game.STRUCTS.has(t2) and Game.STRUCTS[t2]["movable"]:
			movable.append(c)
		if t2 in ["flowerbed", "sign", "bench"]:
			decor.append(c)
	if movable.size() > 0:
		cands.append([9, {"kind": "pickup", "cell": movable.pick_random(), "adj": true, "dur": 1.5}])
	if decor.size() > 0:
		cands.append([3, {"kind": "demolish", "cell": decor.pick_random(), "adj": true, "dur": 2.0, "tool": "tool_hammer"}])

	if Game.item_count("wood") < 6:
		var trees: Array = []
		for c in world.cells_with_obj(World.TREES):
			if _can_reach(c, reach) and not world.is_planned(c) and not world.in_reserve(c):
				trees.append(c)
		if trees.size() > 0:
			cands.append([24, {"kind": "chop", "cell": world.nearest(trees, me), "adj": true, "dur": 4.0, "tool": "tool_axe"}])

	# the alien village next door: a friendly visit, or (when relations are bad) a bit of sabotage
	var col: Colony = world.colony
	if col != null and col.active() and col.has_village() and not Game.is_night():
		if col.rel() > 30.0 and randf() < 0.12:
			cands.append([30, {"kind": "visit_aliens", "cell": col.center_cell(), "adj": true, "dur": 2.5}])
		elif col.hostile() and Game.health > 50.0 and randf() < 0.18:
			var targets: Array = []
			for c in col.buildings():
				if world.obj_type(c) in ["a_moss", "a_pylon", "a_pod", "a_dish"] and _can_reach(c, reach):
					targets.append(c)
			if targets.size() > 0:
				cands.append([34, {"kind": "sabotage", "cell": world.nearest(targets, world.DOOR), "adj": world.is_solid(world.nearest(targets, world.DOOR)),
					"dur": 3.0, "tool": "tool_hammer"}])

	# the Brood's mounds: collect honey from friendly ones, smoke out hostile ones
	var sw: Swarm = world.swarm
	if sw != null and sw.active() and not Game.is_night():
		var ms: Array = []
		for c in sw.mounds():
			if _can_reach(c, reach):
				ms.append(c)
		if ms.size() > 0:
			var mc: Vector2i = world.nearest(ms, me)
			if sw.rel_farm() > 30.0 and randf() < 0.1:
				cands.append([28, {"kind": "honey", "cell": mc, "adj": true, "dur": 2.0, "tool": "tool_bucket"}])
			elif sw.hostile() and Game.health > 45.0 and randf() < 0.2:
				cands.append([36, {"kind": "smoke", "cell": mc, "adj": true, "dur": 3.5, "tool": "tool_bucket"}])

	var wander := Vector2i(clampi(me.x + randi_range(-3, 3), 0, world.COLS - 1), clampi(me.y + randi_range(-3, 3), 0, world.ROWS - 1))
	if world.is_walkable(wander) and not world.is_house(wander):
		cands.append([26 if Game.quirk == "dreamer" else 12, {"kind": "wander", "cell": wander, "dur": randf_range(1.0, 3.0)}])

	if cands.is_empty():
		return
	# two farmers: don't both go for the same tile
	var mate := other()
	var taken: Variant = mate.task.get("cell") if mate and not mate.hidden else null
	var best: Dictionary = {}
	var best_s := -1e9
	for cd in cands:
		if taken != null and cd[1]["cell"] == taken and not cd[1]["kind"] in ["sleep", "shelter", "rest_home", "sell", "drink", "rest"]:
			continue
		var s: float = float(cd[0]) + randf() * 14.0
		if s > best_s:
			best_s = s
			best = cd[1]
	_start(best)


func _can_reach(c: Vector2i, reach: Dictionary) -> bool:
	if reach.has(c):
		return true
	for d in World.DIRS:
		if reach.has(c + d):
			return true
	return false


## What to sow on cell c: the field's plan (one crop / a silly mix / his whim).
## Seeds are free: he saves them from the last harvest.
func _pick_crop(c: Vector2i = Vector2i(-1, -1)) -> String:
	var opts: Array = []
	for id in Game.CROPS:
		if id != "melon" and Game.crop_unlocked(id):
			opts.append(id)
	var art: String = world.pattern_crop(c)
	if art != "":
		return art if art in opts else opts.pick_random()
	if Game.buff("favor") and Game.favor_crop in opts and randf() < 0.75:
		return Game.favor_crop
	if Game.quirk == "sunny" and "sunflower" in opts and randf() < 0.6:
		return "sunflower"
	var fi: int = world.field_index(c)
	if fi >= 0:
		var plan: String = world.fields[fi]["crop"]
		if plan == "mixed":
			return opts.pick_random()
		if plan in opts:
			return plan
	# lean towards the fanciest crop he can afford
	if randf() < 0.55:
		return opts[opts.size() - 1]
	return opts.pick_random()


func _pick_build() -> Dictionary:
	var lv := Game.level()
	var opts: Array = []
	var weights: Array = []
	var crops_n: int = world.crops.size()
	for id in Game.STRUCTS:
		var def: Dictionary = Game.STRUCTS[id]
		if def["level"] > lv or def.get("card", false) or world.count_obj(id) >= def["max"]:
			continue
		if id == "scarecrow" and Game.has_edict("crow_pact"):
			continue
		if not Game.can_afford(def):
			continue
		var w := 1.0
		match id:
			"scarecrow": w = 5.0 if crops_n > 3 and world.count_obj("scarecrow") < 1 else 1.0
			"well": w = 4.0
			"coop": w = 3.0
			"rod": w = 2.0
			"fence": w = 6.0 if world.next_fence_cell() != null else 0.0
			"compost": w = 2.0
			"flowerbed": w = 1.5 if world.path_count() > 4 else 0.3
			"beehive": w = 2.0 if crops_n > 4 else 0.3
		if w <= 0.0:
			continue
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
	var c: Variant = world.pick_build_cell(pick)
	if c == null:
		return {}
	return {"kind": "build", "what": pick, "cell": c, "adj": true, "dur": 4.0 if pick != "fence" else 1.8, "tool": "tool_hammer"}


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
		"build":
			if t["what"] == "fence":
				say_line("fence", 0.3)
			else:
				say("Let's build a %s!" % Game.STRUCTS[t["what"]]["name"])
		"demolish": say_line("demolish", 0.7)
		"pickup": say_line("rearrange", 0.7)
		"clear": say_line("clear", 0.2)
		"shoo": say_line("shoo", 0.8)
		"extinguish": say_line("fire", 0.8)
		"sleep": say_line("night", 0.6)
		"shelter": say_line("storm_shelter")
		"rest", "rest_home": say_line("rest", 0.6)
		"chop": say_line("chop", 0.3)
		"pave": say_line("pave", 0.2)
		"visit_aliens": say_line("visit_aliens", 0.7)
		"honey": say_line("honey", 0.7)
		"smoke": say_line("smoke", 0.9)
		"sabotage": say_line("sabotage", 0.8)


func _describe(t: Dictionary) -> String:
	var c: Vector2i = t["cell"]
	match t["kind"]:
		"till":
			var fi: int = world.field_index(c)
			if fi >= 0:
				return "Tilling the %s field" % String(world.fields[fi]["shape"]).replace("_", " ")
			return "Tilling soil"
		"plan": return "Planning a new field"
		"pave": return "Laying a path"
		"plant": return "Planting %s" % Game.CROPS[t["crop"]]["name"].to_lower()
		"water":
			if world.crops.has(c):
				return "Watering %s" % Game.CROPS[world.crops[c]["type"]]["name"].to_lower()
			return "Watering"
		"harvest": return "Harvesting"
		"clear_crop": return "Clearing a dead crop"
		"clear": return "Clearing %s" % _debris_name(world.obj_type(c))
		"mine": return "Mining meteor ore"
		"sell": return "Trading produce"
		"build": return "Building a %s" % Game.STRUCTS[t["what"]]["name"]
		"repair": return "Repairing the %s" % _sname(world.obj_type(c))
		"demolish": return "Tearing down the %s" % _sname(world.obj_type(c))
		"pickup": return "Moving the %s" % _sname(world.obj_type(c))
		"place": return "Placing the %s" % _sname(carrying)
		"shoo":
			if t["target"] is Alien:
				return "Chasing off an alien %s" % t["target"].caste
			if t["target"] is Insect:
				return "Swatting a giant %s" % t["target"].caste
			return "Chasing off a %s" % t["target"].kind
		"visit_aliens": return "Visiting the alien village"
		"honey": return "Collecting giant honey"
		"smoke": return "Smoking out a bug mound!"
		"sabotage": return "Wrecking alien stuff"
		"extinguish": return "Fighting a fire!"
		"sleep": return "Heading to bed"
		"shelter": return "Running for shelter!"
		"rest", "rest_home": return "Taking a break"
		"drink": return "Drinking at the well"
		"chop": return "Chopping a tree"
		"wander": return "Strolling around"
	return "Pondering"


func _debris_name(t: String) -> String:
	match t:
		"tallgrass": return "tall grass"
		"weed": return "weeds"
		"bramble": return "brambles"
	return "a " + t if t != "ash" else "ash"


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
			if a.kind == "snake" and not a.dead and world.cell_of(a.pos) == next and not Game.has_mutation("compound_eyes") and not friend:
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
			Game.add_log("%s went to bed." % who())
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
			var k: String = task["kind"]
			if Game.has_perk("strong_arms") and k in ["clear", "chop", "mine"]:
				work_t *= 0.5
			if Game.has_perk("carpenter") and k in ["build", "repair", "pave"]:
				work_t *= 0.5


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
	# fleeing critters leave something behind (always, with a Bounty posted)
	if Game.CRITTER_SOUVENIRS.has(a.kind) and (Game.buff("bounty") or randf() < 0.3):
		world.loot(Game.CRITTER_SOUVENIRS[a.kind], 1, pos)
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
		"plan":
			var art := 0
			for fl in world.fields:
				if fl.has("paint"):
					art += 1
			# now and then a crop picture instead of a plain field
			var f: Dictionary = {}
			if art < 2 and randf() < (0.5 if Game.quirk == "artsy" else 0.28):
				f = world.plan_pattern()
			if not f.is_empty():
				say(LINES["plan_pattern"].pick_random().replace("%s", f["shape"]), 3.5)
				Game.add_log("%s marked out a %s crop picture." % [who(), f["shape"]])
				for cc in f["cells"]:
					world.puff(world.center(cc), Color("e0c08a"), 2, 6.0)
			else:
				f = world.plan_field()
			if not f.is_empty() and not f.has("paint"):
				var shape: String = String(f["shape"]).replace("_", " ")
				if f["shape"] in World.SILLY:
					say(LINES["plan_silly"].pick_random().replace("%s", shape), 3.5)
				else:
					say(LINES["plan"].pick_random().replace("%s", shape), 3.0)
				Game.add_log("%s marked out a %s-shaped field." % [who(), shape])
				for cc in f["cells"]:
					world.puff(world.center(cc), Color("e0c08a"), 2, 6.0)
		"pave":
			if world.is_free_grass(c) and (Game.item_count("stone") >= 1 or Game.has_perk("carpenter")):
				if not Game.has_perk("carpenter"):
					Game.add_item("stone", -1)
				world.ground[world.idx(c)] = World.G_PATH
				world.puff(world.center(c), Color("c9a26b"), 6)
		"plant":
			if world.is_tilled(c) and not world.crops.has(c) and not world.objs.has(c):
				var crop: String = task["crop"]
				world.plant(c, crop)
				world.puff(world.center(c), Color("5a3626"), 4, 10.0)
				Game.bump("planted")
		"water":
			if world.is_tilled(c):
				world.wet[world.idx(c)] = 1.0
				world.puff(world.center(c), Color("41a6f6"), 8, 14.0, 4.0)
				if Game.has_perk("big_can"):
					for dd in World.DIRS8:
						if world.is_tilled(c + dd):
							world.wet[world.idx(c + dd)] = 1.0
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
				elif type == "sunflower" and randf() < 0.5:
					world.loot("sunflower_seeds", randi_range(1, 3), pos)
		"clear_crop":
			if world.crops.has(c) and world.crops[c].get("dead", false):
				world.crops.erase(c)
		"clear":
			var t: String = world.obj_type(c)
			if World.CLEARABLE.has(t):
				var def: Dictionary = World.CLEARABLE[t]
				var drops: Dictionary = def["drops"]
				for k in drops:
					Game.add_item(k, int(drops[k]))
				world.remove_obj(c)
				world.puff(world.center(c), Color("94b0c2") if t in ["rock", "boulder"] else Color("38b764"), 8)
				if drops.size() > 0:
					var k0: String = drops.keys()[0]
					world.float_text("+%d %s" % [drops[k0], k0.to_upper()], pos + Vector2(-14, -24), Color("e0c08a"))
				if randf() < float(def.get("thorns", 0.0)):
					say_line("thorns")
					hurt(4, "thorny brambles")
				if randf() < 0.03 and world.cleared_ratio() < 0.5:
					say_line("overgrown")
				# grandpa's junk turns up in the undergrowth
				if randf() < 0.06:
					world.loot(["old_bottle", "old_bottle", "rusty_key", "arrowhead", "marble"].pick_random(), 1, pos)
					say(["Ooh, what's this?", "Into the chest you go!", "Grandpa's junk... MY junk now."].pick_random())
		"mine":
			if world.obj_type(c) == "ore":
				world.remove_obj(c)
				Game.add_item("ore", 2)
				world.float_text("+2 ORE", pos + Vector2(-12, -24), Color("73eff7"))
				world.puff(world.center(c), Color("73eff7"), 10)
				if randf() < 0.2:
					world.loot("geode", 1, pos)
		"chop":
			if world.obj_type(c) in World.TREES:
				world.remove_obj(c)
				world.place_obj(c, "stump")
				Game.add_item("wood", 4)
				world.float_text("+4 WOOD", pos + Vector2(-14, -24), Color("e0c08a"))
				world.puff(world.center(c) + Vector2(0, -8), Color("2a8a4a"), 14, 22.0)
				if randf() < 0.12:
					world.loot("birds_nest", 1, pos)
		"sell":
			# the village trader empties the bin and leaves trinkets in exchange
			var tr: Dictionary = Game.trade_goods()
			if int(tr["worth"]) > 0:
				world.float_text("+%d WORTH" % tr["worth"], world.center(world.BIN) + Vector2(-16, -18))
				Game.add_log("Traded produce for %s." % Game.describe(tr["got"]))
		"build":
			var what: String = task["what"]
			var bdef: Dictionary = Game.STRUCTS[what]
			if world.is_free_grass(c) and Game.can_afford(bdef) and (not bdef["solid"] or world.keeps_connected(c)):
				Game.pay_for(bdef)
				world.place_obj(c, what)
				Game.bump("built")
				Game.mood = minf(100.0, Game.mood + 5.0)
				world.puff(world.center(c), Color("c28a5a"), 10)
				if what != "fence":
					Game.add_log("Built a %s." % Game.STRUCTS[what]["name"])
				if what == "coop":
					for i in 2:
						world.add_animal(Animal.new(world, "chicken", world.feet(c) + Vector2(randf_range(-10, 10), 10)))
		"repair":
			var o: Dictionary = world.obj_at(c)
			if not o.is_empty() and Game.STRUCTS.has(o["type"]):
				o["hp"] = Game.STRUCTS[o["type"]]["hp"]
				say("Good as new!")
		"demolish":
			var t2: String = world.obj_type(c)
			if Game.STRUCTS.has(t2):
				# half the materials are salvaged
				var m: Dictionary = Game.STRUCTS[t2].get("mats", {})
				for k in m:
					Game.add_item(k, int(m[k]) / 2)
				world.remove_obj(c)
				world.puff(world.center(c), Color("c28a5a"), 10)
				Game.add_log("Tore down the %s." % Game.STRUCTS[t2]["name"])
		"pickup":
			var o2: Dictionary = world.obj_at(c)
			if not o2.is_empty() and Game.STRUCTS.has(o2["type"]) and Game.STRUCTS[o2["type"]]["movable"]:
				carrying = o2["type"]
				carry_data = o2
				world.remove_obj(c)
				var dest: Variant = world.pick_build_cell(carrying)
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
		"visit_aliens":
			if world.colony:
				world.colony.farmer_visited()
			Game.mood = minf(100.0, Game.mood + 4.0)
		"sabotage":
			if world.colony:
				world.colony.farmer_sabotage(c)
		"honey":
			if world.swarm:
				world.swarm.farmer_harvest_honey(c)
				say_line("honey", 0.5)
		"smoke":
			if world.swarm:
				world.swarm.farmer_smoke(c)
	_idle()


# ---------------------------------------------------------------- drawing
func draw(ci: CanvasItem) -> void:
	if hidden:
		if state == "sleep" or state == "rest":
			var z := Art.tex("zzz")
			var off := Vector2(fmod(anim_t * 4.0, 8.0), -fmod(anim_t * 6.0, 12.0))
			ci.draw_texture(z, home_px() + off, Color(1, 1, 1, 0.8))
		return
	# shadow
	ci.draw_rect(Rect2(pos.x - 5, pos.y, 10, 2), Color(0, 0, 0, 0.25))
	var mod := Color.WHITE
	var look := "friend_" if friend else "farmer_"
	if Game.poison > 0.0 and not friend:
		mod = Color(0.75, 1.0, 0.7)
	if hurt_t > 0.0 and int(hurt_t * 20.0) % 2 == 0:
		mod = Color(1, 0.4, 0.4)
	if state == "fainted" or state == "nap":
		ci.draw_set_transform(pos + Vector2(0, -3), PI * 0.5 if flip else -PI * 0.5, Vector2.ONE)
		ci.draw_texture(Art.tex(look + "idle"), Vector2(-8, -8), mod)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		if state == "nap":
			ci.draw_texture(Art.tex("zzz"), pos + Vector2(4, -16 - fmod(anim_t * 5.0, 6.0)))
		else:
			for i in 3:
				var a := anim_t * 3.0 + i * TAU / 3.0
				ci.draw_rect(Rect2(pos + Vector2(cos(a) * 6.0 - 0.5, -12 + sin(a) * 2.0), Vector2(1, 1)), Color("ffcd75"))
		return
	var frame := look + "idle"
	var bob := 0.0
	match state:
		"walk":
			frame = look + ("walk1" if int(anim_t * 6.0) % 2 == 0 else "walk2")
			bob = -1.0 if int(anim_t * 6.0) % 2 == 0 else 0.0
		"work":
			frame = look + ("work" if int(anim_t * 4.0) % 2 == 0 else "idle")
		"rest":
			bob = 2.0
	if Game.has_mutation("green") and not friend:
		mod *= Color(0.72, 1.0, 0.68)
	if Game.has_mutation("glow") and Game.darkness() > 0.2 and not friend:
		ci.draw_circle(pos + Vector2(0, -7), 10.0, Color(0.6, 1.0, 0.6, 0.12 * Game.darkness()))
	ci.draw_set_transform(pos, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture(Art.tex(frame), Vector2(-8, -15 + bob), mod)
	if not friend:
		_draw_mutations(ci, bob)
	if state == "work" and task.has("tool"):
		var up := int(anim_t * 4.0) % 2 == 0
		ci.draw_texture(Art.tex(task["tool"]), Vector2(3, -22 if up else -16))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if carrying != "":
		var tx := Art.tex(carrying)
		ci.draw_texture_rect(tx, Rect2(pos.x - 6, pos.y - 30, 12, 12 * tx.get_height() / maxf(1.0, tx.get_width())), false)


## Where his snoring shows while he sleeps inside.
func home_px() -> Vector2:
	if friend and home.x >= 0:
		return Vector2(home * 16) + Vector2(10, -10)
	return world.house_px() + Vector2(22, 4)


## Little extras the aliens left him with (drawn in the farmer's local, flipped space).
func _draw_mutations(ci: CanvasItem, bob: float) -> void:
	var lime := Color("a7f070")
	if Game.has_mutation("antenna"):
		var wob := int(anim_t * 3.0) % 2
		ci.draw_rect(Rect2(-3, -19 + bob, 1, 4), Color("38b764"))
		ci.draw_rect(Rect2(2, -19 + bob, 1, 4), Color("38b764"))
		ci.draw_rect(Rect2(-4 + wob, -20 + bob, 2, 1), lime)
		ci.draw_rect(Rect2(2 - wob, -20 + bob, 2, 1), lime)
	if Game.has_mutation("third_eye"):
		ci.draw_rect(Rect2(-1, -11 + bob, 2, 1), Color("b13e53") if int(anim_t * 0.7) % 4 == 0 else Color("73eff7"))
	if Game.has_mutation("tentacle"):
		var sw := sin(anim_t * 4.0)
		ci.draw_rect(Rect2(5, -6 + bob, 1, 3), lime)
		ci.draw_rect(Rect2(6 + roundf(sw), -3 + bob, 1, 3), lime)
		ci.draw_rect(Rect2(7 + roundf(sw), -1 + bob, 1, 1), Color("38b764"))
	if Game.has_mutation("chitin"):
		ci.draw_rect(Rect2(-5, -7 + bob, 2, 2), Color("8b5a3c"))
		ci.draw_rect(Rect2(3, -7 + bob, 2, 2), Color("8b5a3c"))
		ci.draw_rect(Rect2(-5, -7 + bob, 1, 1), Color("c28a5a"))
	if Game.has_mutation("compound_eyes"):
		ci.draw_rect(Rect2(-4, -11 + bob, 2, 2), Color("b13e53"))
		ci.draw_rect(Rect2(2, -11 + bob, 2, 2), Color("b13e53"))
		ci.draw_rect(Rect2(-4, -11 + bob, 1, 1), Color("ef7d57"))
	if Game.has_mutation("hive_mind") and int(anim_t * 2.0) % 3 == 0:
		ci.draw_rect(Rect2(-6, -17 + bob, 1, 1), Color("73eff7"))
		ci.draw_rect(Rect2(5, -16 + bob, 1, 1), Color("73eff7"))


# ---------------------------------------------------------------- save
func to_dict() -> Dictionary:
	return {"uid": uid, "pid": pid, "home": "%d,%d" % [home.x, home.y], "away": state == "away",
		"x": pos.x, "y": pos.y, "carrying": carrying, "carry": carry_data,
		"sleep": state == "sleep", "fainted": state == "fainted", "faint_t": faint_t,
		"abducted": work_t if state == "abducted" else 0.0}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	uid = int(d.get("uid", uid))
	pid = String(d.get("pid", ""))
	var hm := String(d.get("home", "-1,-1")).split(",")
	if hm.size() == 2:
		home = Vector2i(int(hm[0]), int(hm[1]))
	pos = Vector2(float(d.get("x", pos.x)), float(d.get("y", pos.y)))
	carrying = String(d.get("carrying", ""))
	carry_data = d.get("carry", {})
	if carrying != "":
		_drop_carry()
	if bool(d.get("away", false)):
		hidden = true
		state = "away"
		activity = "Gone home"
	elif bool(d.get("sleep", false)):
		hidden = true
		state = "sleep"
		task = {"kind": "sleep", "cell": door()}
	elif bool(d.get("fainted", false)):
		state = "fainted"
		faint_t = float(d.get("faint_t", 20.0))
	elif float(d.get("abducted", 0.0)) > 0.0:
		abduct(float(d["abducted"]))


# ---------------------------------------------------------------- multiplayer
## What a guest needs to draw this actor (Net's actor stream). Timers in Net.DECAYING also run
## down on the guest by themselves.
func net_fields() -> Array:
	return ["pos", "state", "flip", "hidden", "bubble", "bubble_t", "carrying", "hurt_t", "activity", "net_tool",
		"pid", "home"]


## A guest's stand-in for update(): animate, run timers down, glide towards the host's position.
func net_tick(d: float) -> void:
	anim_t += d
	bubble_t -= d
	hurt_t = maxf(0.0, hurt_t - d)
	if net_to.x != INF:
		pos = pos.lerp(net_to, minf(1.0, d * 8.0))
