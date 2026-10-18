extends Node
## CardSystem: draws choice cards from Deck, evaluates requirements, applies effects,
## runs delayed consequences (Game.pending) and the passive powers of relics.
## UI (hud.gd) calls: card(id), choice_lines(card, "a"), can_choose(card, "a"), choose(id, "a").

signal chosen(card_id: String, which: String)

const RARITY_WEIGHT := {1: 10.0, 2: 5.0, 3: 2.5, 4: 1.2}
const RARITY_NAMES := {0: "Fate", 1: "Common", 2: "Uncommon", 3: "Rare", 4: "Legendary"}
const RARITY_COLORS := {0: Color("b13e53"), 1: Color("94b0c2"), 2: Color("38b764"), 3: Color("b45cff"), 4: Color("ffcd75")}
const WEATHER_WORDS := {"sunny": "sunshine", "cloudy": "clouds", "rain": "rain", "storm": "a storm", "heat": "a heatwave"}
const WHISPERS := ["...the soil remembers...", "Did the book just say my name?", "So many teeth in that dream.",
	"I should plant something. Deep.", "Who's counting the stars?"]

var world: World
var director: Node
var _by_id := {}
var _ensure_t := 0.0
var _whisper_t := 60.0
var _last_tod := 0.0


func _ready() -> void:
	for c in Deck.CARDS:
		_by_id[c["id"]] = c
	Game.draw_requested.connect(_on_draw_requested)
	Game.new_day.connect(_on_new_day)
	_last_tod = Game.time_of_day


func _on_draw_requested() -> void:
	draw_card()


func card(id: String) -> Dictionary:
	return _by_id.get(id, {})


# ---------------------------------------------------------------- drawing
func eligible(c: Dictionary) -> bool:
	if int(c.get("rarity", 1)) <= 0:
		return false
	if Game.level() < int(c.get("level", 1)) or Game.weird < float(c.get("weird", 0)):
		return false
	for r in c.get("needs", []):
		if not check(r)[0]:
			return false
	return true


func draw_card() -> String:
	var pool: Array = []
	var weights: Array = []
	var total := 0.0
	for c in Deck.CARDS:
		if c["id"] in Game.hand or not eligible(c):
			continue
		var w: float = RARITY_WEIGHT.get(int(c["rarity"]), 1.0)
		w /= 1.0 + int(Game.seen.get(c["id"], 0)) * 0.6
		if Game.has_relic("tome") and float(c.get("weird", 0)) > 0.0:
			w *= 1.5
		pool.append(c["id"])
		weights.append(w)
		total += w
	if pool.is_empty():
		return ""
	var r := randf() * total
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			Game.add_card(pool[i])
			return pool[i]
	Game.add_card(pool[pool.size() - 1])
	return pool[pool.size() - 1]


# ---------------------------------------------------------------- requirements
## Returns [ok: bool, text: String].
func check(r: Array) -> Array:
	var kind: String = r[0]
	match kind:
		"crop":
			var n := _count_crops(r[1], false)
			return [n >= int(r[2]), "%d %s growing (%d/%d)" % [r[2], _crop_word(r[1], int(r[2])), n, r[2]]]
		"ripe":
			var n2 := _count_crops(r[1], true)
			return [n2 >= int(r[2]), "%d ripe %s (%d/%d)" % [r[2], _crop_word(r[1], int(r[2])), n2, r[2]]]
		"obj":
			var n3: int = world.count_obj(r[1])
			var nm := _obj_name(r[1])
			if int(r[2]) == 1:
				return [n3 >= 1, "a %s on the farm" % nm]
			return [n3 >= int(r[2]), "%d %ss (%d/%d)" % [r[2], nm, n3, r[2]]]
		"relic":
			return [Game.has_relic(r[1]), "the %s" % Game.RELICS[r[1]]["name"]]
		"no_relic":
			return [not Game.has_relic(r[1]), "no %s" % Game.RELICS[r[1]]["name"]]
		"weather":
			return [Game.weather == r[1], "%s right now" % WEATHER_WORDS.get(r[1], r[1])]
		"night":
			return [Game.is_night(), "night time"]
		"day":
			return [not Game.is_night(), "day time"]
		"level":
			return [Game.level() >= int(r[1]), "farm level %d" % r[1]]
		"weird":
			return [Game.weird >= float(r[1]), "weirdness %d (%d)" % [r[1], int(Game.weird)]]
		"mood":
			return [Game.mood >= float(r[1]), "mood %d+ (%d)" % [r[1], int(Game.mood)]]
		"health":
			return [Game.health >= float(r[1]), "health %d+ (%d)" % [r[1], int(Game.health)]]
		"chickens":
			var n4: int = world.count_animals("chicken")
			return [n4 >= int(r[1]), "%d chicken%s (%d/%d)" % [r[1], "" if int(r[1]) == 1 else "s", n4, r[1]]]
		"tilled":
			var n5: int = world.tilled_cells().size()
			return [n5 >= int(r[1]), "%d tilled tiles (%d/%d)" % [r[1], n5, r[1]]]
		"charms":
			return [Game.charms >= int(r[1]), "%d lucky charm%s (%d)" % [r[1], "" if int(r[1]) == 1 else "s", Game.charms]]
		"stat":
			var v := int(Game.stats.get(r[1], 0))
			return [v >= int(r[2]), "%d %s (%d)" % [r[2], r[1], v]]
		"inventory":
			return [Game.inventory_count() >= int(r[1]), "produce to sell"]
		"coins":
			return [Game.coins >= int(r[1]), "%d coins (%d)" % [r[1], Game.coins]]
		"item":
			var have := Game.item_count(r[1])
			return [have >= int(r[2]), "%d %s%s (%d)" % [r[2], Game.ITEM_NAMES.get(r[1], r[1]), "" if int(r[2]) == 1 else "s", have]]
	return [true, ""]


## Costs hidden inside effects become requirements automatically.
func auto_reqs(fx: Array) -> Array:
	var out: Array = []
	for e in fx:
		match e[0]:
			"coins":
				if int(e[1]) < 0:
					out.append(["coins", -int(e[1])])
			"item":
				if int(e[2]) < 0:
					out.append(["item", e[1], -int(e[2])])
			"take_ripe":
				out.append(["ripe", e[1], e[2]])
			"take_crop":
				out.append(["crop", e[1], e[2]])
			"chicken":
				if int(e[1]) < 0:
					out.append(["chickens", -int(e[1])])
			"charm":
				if int(e[1]) < 0:
					out.append(["charms", -int(e[1])])
	return out


## [[ok, text], ...] for the choice's requirements + costs.
func choice_lines(c: Dictionary, which: String) -> Array:
	var ch: Dictionary = c[which]
	var out: Array = []
	for r in ch.get("req", []) + auto_reqs(ch.get("fx", [])):
		out.append(check(r))
	return out


func can_choose(c: Dictionary, which: String) -> bool:
	for l in choice_lines(c, which):
		if not l[0]:
			return false
	return true


func choose(id: String, which: String) -> bool:
	var c := card(id)
	if c.is_empty() or not (id in Game.hand) or not can_choose(c, which):
		return false
	var ch: Dictionary = c[which]
	Game.remove_card(id)
	Game.add_log("%s: %s." % [c["title"], ch["label"]])
	if c.get("visitor", false):
		var v: Animal = director.spawn_animal("visitor", Vector2(-14, world.feet(world.DOOR).y + 40))
		v.sprite = c["art"]
		v.reply = ch.get("reply", "...")
	apply(ch.get("fx", []))
	chosen.emit(id, which)
	return true


# ---------------------------------------------------------------- effects
func apply(fx: Array) -> void:
	for e in fx:
		_apply_one(e)


func _apply_one(e: Array) -> void:
	var f := world.farmer
	var fp: Vector2 = f.pos if f else world.center(world.DOOR)
	match e[0]:
		"coins":
			var n := int(e[1])
			if n > 0:
				n = Game.scaled_reward(n)
				world.float_text("+%d" % n, fp + Vector2(-6, -26))
				world.puff(fp + Vector2(0, -10), Color("ffcd75"), 10, 20.0)
			Game.add_coins(n)
		"coins_pct":
			var amt := int(Game.coins * absf(float(e[1])) / 100.0)
			Game.add_coins(amt if float(e[1]) > 0.0 else -amt)
			if float(e[1]) < 0.0:
				world.float_text("-%d" % amt, fp + Vector2(-6, -26), Color("b13e53"))
		"item":
			Game.add_item(e[1], int(e[2]))
			if int(e[2]) > 0:
				world.float_text("+%d %s" % [e[2], String(e[1]).to_upper()], fp + Vector2(-12, -26), Color("73eff7"))
		"heal":
			if int(e[1]) < 0:
				if f:
					f.hurt(-int(e[1]), "a risky choice")
			else:
				Game.health = minf(100.0, Game.health + float(e[1]))
				world.puff(fp + Vector2(0, -8), Color("a7f070"), 8)
		"energy":
			Game.energy = clampf(Game.energy + float(e[1]), 0.0, 100.0)
			if f and float(e[1]) > 0.0 and f.state == "nap":
				f.state = "idle"
		"mood":
			Game.mood = clampf(Game.mood + float(e[1]), 0.0, 100.0)
		"weird":
			Game.add_weird(float(e[1]))
		"poison":
			Game.poison = maxf(Game.poison, float(e[1]))
			if f:
				f.say("Urgh... I don't feel so good.")
		"cure":
			Game.poison = 0.0
		"charm":
			Game.charms = maxi(0, Game.charms + int(e[1]))
		"buff":
			Game.add_buff(e[1], float(e[2]))
		"weather":
			director.set_weather(e[1], float(e[2]))
		"action":
			director.do_action(e[1])
		"event":
			director.run_event(e[1])
		"spawn":
			for i in int(e[2]):
				_spawn(e[1])
		"grow":
			for c in world.crops:
				var cr: Dictionary = world.crops[c]
				if not cr.get("dead", false):
					cr["growth"] = minf(1.0, cr["growth"] + float(e[1]))
					world.puff(world.center(c), Color("a7f070"), 3, 10.0)
		"ripen":
			var alive := _alive_crops("", false)
			alive.shuffle()
			var n2: int = alive.size() if int(e[1]) < 0 else mini(int(e[1]), alive.size())
			for i in n2:
				world.crops[alive[i]]["growth"] = 1.0
				world.puff(world.center(alive[i]), Color("ffcd75"), 5, 12.0)
		"wither":
			var alive2 := _alive_crops("", false)
			alive2.shuffle()
			var n3: int = alive2.size() if int(e[1]) < 0 else mini(int(e[1]), alive2.size())
			for i in n3:
				world.crops[alive2[i]]["dead"] = true
		"mutate":
			var alive3 := _alive_crops("", false)
			alive3.shuffle()
			for i in mini(int(e[1]), alive3.size()):
				world.crops[alive3[i]]["type"] = "glowshroom"
				world.puff(world.center(alive3[i]), Color("73eff7"), 8, 14.0)
		"plant":
			_plant(e[1], int(e[2]))
		"unlock":
			if not Game.unlocked.has(e[1]):
				Game.unlocked[e[1]] = true
				Game.add_log("New crop unlocked: %s!" % Game.CROPS[e[1]]["name"])
		"favor":
			Game.favor_crop = e[1]
			Game.add_buff("favor", float(e[2]))
		"relic":
			gain_relic(e[1])
		"lose_relic":
			lose_relic(e[1])
		"draw":
			for i in int(e[1]):
				draw_card()
		"chicken":
			var n4 := int(e[1])
			if n4 > 0:
				var coops: Array = world.cells_with_obj(["coop"])
				var home: Vector2 = world.feet(coops[0]) + Vector2(0, 10) if coops.size() > 0 else world.feet(world.DOOR) + Vector2(16, 16)
				for i in n4:
					var ch: Animal = director.spawn_animal("chicken", home + Vector2(randf_range(-10, 10), randf_range(0, 6)))
					ch.home = home
			else:
				var left := -n4
				for a in world.animals:
					if left > 0 and a.kind == "chicken" and not a.dead:
						a.dead = true
						world.puff(a.pos, Color("f4f4f4"), 8)
						left -= 1
		"sell":
			var v := Game.inventory_value(float(e[1]))
			if v > 0:
				Game.add_coins(v)
				Game.inventory.clear()
				world.float_text("+%d" % v, fp + Vector2(-6, -26))
		"take_ripe":
			var ripe := _alive_crops(e[1], true)
			for i in mini(int(e[2]), ripe.size()):
				world.crops.erase(ripe[i])
				world.puff(world.center(ripe[i]), Color("a7f070"), 5)
		"take_crop":
			var cs := _alive_crops(e[1], false)
			for i in mini(int(e[2]), cs.size()):
				world.crops.erase(cs[i])
				world.puff(world.center(cs[i]), Color("ffcd75"), 5)
		"water_all":
			for c in world.tilled_cells():
				world.wet[world.idx(c)] = 1.0
		"clear_weeds":
			for c in world.cells_with_obj(["weed"]):
				world.remove_obj(c)
				world.puff(world.center(c), Color("38b764"), 4)
		"burn":
			var cells: Array = world.cells_with_obj([e[1]])
			if cells.size() > 0:
				director.ignite(cells[0])
		"add_card":
			Game.add_card(e[1])
		"say":
			if f:
				f.say(e[1], 4.0)
		"log":
			Game.add_log(e[1])
		"gamble":
			if randf() < float(e[1]):
				world.float_text("LUCKY!", fp + Vector2(-12, -34), Color("a7f070"))
				apply(e[2])
			else:
				world.float_text("UNLUCKY...", fp + Vector2(-18, -34), Color("b13e53"))
				apply(e[3])
		"delay":
			Game.pending.append({"t": float(e[1]), "fx": e[2], "note": e[3] if e.size() > 3 else ""})


func _spawn(kind: String) -> void:
	match kind:
		"boar":
			director.run_event("boar")
		"crow":
			director.spawn_animal("crow", Vector2(randf_range(0, world.COLS * 16), -20))
		"butterfly", "wisp":
			director.spawn_animal(kind, Vector2(randf_range(10, 180), randf_range(20, 240)))
		_:
			director.spawn_animal(kind, director._edge_pos())


func _alive_crops(type: String, ripe_only: bool) -> Array:
	var out: Array = []
	for c in world.crops:
		var cr: Dictionary = world.crops[c]
		if cr.get("dead", false):
			continue
		if type != "" and cr["type"] != type:
			continue
		if ripe_only and cr["growth"] < 1.0:
			continue
		out.append(c)
	return out


func _count_crops(type: String, ripe_only: bool) -> int:
	return _alive_crops(type, ripe_only).size()


func _crop_word(type: String, n: int) -> String:
	if type == "":
		return "crop" if n == 1 else "crops"
	var nm: String = Game.CROPS[type]["name"].to_lower()
	return nm if n == 1 else nm + ("es" if nm.ends_with("h") else "s")


func _obj_name(t: String) -> String:
	if Game.STRUCTS.has(t):
		return Game.STRUCTS[t]["name"]
	return t


func _plant(crop: String, n: int) -> void:
	var spots: Array = []
	for c in world.tilled_cells():
		if not world.crops.has(c) and not world.objs.has(c):
			spots.append(c)
	var free: Array = []
	for c in world.free_grass_cells():
		if c.y >= 3:
			free.append(c)
	var focus := Vector2i(6, 8)
	while spots.size() < n and free.size() > 0:
		var c2: Vector2i = world.nearest(free, focus)
		free.erase(c2)
		world.set_tilled(c2, true)
		spots.append(c2)
	for i in mini(n, spots.size()):
		world.plant(spots[i], crop)
		world.wet[world.idx(spots[i])] = 1.0
		world.puff(world.center(spots[i]), Color("a7f070"), 6, 14.0)


# ---------------------------------------------------------------- relics
const RELIC_STRUCTS := ["idol", "obelisk", "stones", "saucer"]
const RELIC_ACTORS := {"homunculus": "homunculus", "goat": "goat", "black_cat": "cat"}


func gain_relic(id: String) -> void:
	if Game.has_relic(id):
		return
	Game.relics[id] = true
	Game.add_log("Relic gained: %s." % Game.RELICS[id]["name"])
	if id in RELIC_STRUCTS:
		var cells: Array = []
		for c in world.free_grass_cells():
			if c.y >= 3:
				cells.append(c)
		if cells.size() > 0:
			var c2: Vector2i = world.nearest(cells, Vector2i(6, 9)) if id == "idol" else cells.pick_random()
			world.place_obj(c2, id)
			world.puff(world.center(c2), Color("b45cff"), 16, 26.0)
	if id == "star_map":
		Game.unlocked["starfruit"] = true
	_ensure_actors()


func lose_relic(id: String) -> void:
	if not Game.has_relic(id):
		return
	Game.relics.erase(id)
	Game.add_log("Relic lost: %s." % Game.RELICS[id]["name"])
	for c in world.cells_with_obj([id]):
		world.remove_obj(c)
		world.puff(world.center(c), Color("94b0c2"), 12)
	if RELIC_ACTORS.has(id):
		for a in world.animals:
			if a.kind == RELIC_ACTORS[id]:
				a.dead = true


func _ensure_actors() -> void:
	for id in RELIC_ACTORS:
		if Game.has_relic(id) and world.count_animals(RELIC_ACTORS[id]) == 0:
			director.spawn_animal(RELIC_ACTORS[id], world.feet(world.DOOR) + Vector2(18, 10))


func _on_new_day(_d: int) -> void:
	if Game.has_relic("tome"):
		Game.add_weird(1.0)
	if Game.has_relic("obelisk"):
		Game.add_weird(2.0)
	if Game.has_relic("saucer"):
		Game.add_item("ore", 2)
		Game.add_log("The saucer's hull flaked off 2 ore.")
	if Game.has_relic("horseshoe"):
		Game.charms = mini(5, Game.charms + 1)
	if Game.has_relic("cursed_coin"):
		var n := Game.scaled_reward(20)
		Game.add_coins(n)
		Game.mood = maxf(0.0, Game.mood - 10.0)
		Game.add_log("The cursed coin multiplied: +%d. The farmer feels uneasy." % n)


func _process(delta: float) -> void:
	if not Game.running or world == null:
		return
	var d := delta * Game.time_scale
	# delayed consequences
	for p in Game.pending.duplicate():
		p["t"] = float(p["t"]) - d
		if p["t"] <= 0.0:
			Game.pending.erase(p)
			if String(p.get("note", "")) != "":
				Game.add_log(p["note"])
			apply(p["fx"])
	# dawn: bone flute
	if _last_tod < 0.25 and Game.time_of_day >= 0.25 and Game.has_relic("bone_flute"):
		var n := 0
		for a in world.threats():
			a.scare()
			n += 1
		Game.add_log("The bone flute shrieks at dawn. %d critters flee." % n)
	_last_tod = Game.time_of_day
	# night whispers from the tome
	if Game.has_relic("tome") and Game.is_night():
		_whisper_t -= d
		if _whisper_t <= 0.0:
			_whisper_t = randf_range(60.0, 140.0)
			if world.farmer:
				world.farmer.say(WHISPERS.pick_random(), 4.0)
			Game.mood = maxf(0.0, Game.mood - 2.0)
	_ensure_t -= delta
	if _ensure_t <= 0.0:
		_ensure_t = 3.0
		_ensure_actors()
