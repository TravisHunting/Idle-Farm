extends Node
## CardSystem: draws choice cards from Deck into the card box, evaluates requirements, applies
## effects, runs delayed consequences (Game.pending), relic passives, the townsfolk's morning
## visits and the dark totems.
## UI (hud.gd) calls: card(id), choice_lines(card, "a"), can_choose(card, "a"),
## choose(where, slot, "a") where `where` is "box" or "stash".

signal chosen(card_id: String, which: String)

const RARITY_WEIGHT := {1: 10.0, 2: 5.0, 3: 2.5, 4: 1.2}
const RARITY_NAMES := {0: "Fate", 1: "Common", 2: "Uncommon", 3: "Rare", 4: "Legendary"}
const RARITY_COLORS := {0: Color("b13e53"), 1: Color("94b0c2"), 2: Color("38b764"), 3: Color("b45cff"), 4: Color("ffcd75")}
const WEATHER_WORDS := {"sunny": "sunshine", "cloudy": "clouds", "rain": "rain", "storm": "a storm", "heat": "a heatwave"}
const WHISPERS := ["...the soil remembers...", "Did the book just say my name?", "So many teeth in that dream.",
	"I should plant something. Deep.", "Who's counting the stars?"]
const FRIEND_LINES := {
	"gus": ["Brought you some turnips!", "Morning, neighbour!"],
	"betty": ["Fresh pie! Still warm!", "Eat up, you look thin."],
	"smith": ["Let me fix that for you.", "Hmph. Sloppy hinges."],
	"mayor": ["The council appreciates you!", "Keep up the good work!"],
	"kids": ["We'll pull the weeds!", "Race you to the brambles!"],
	"doc": ["Say ahh.", "Any aches? No? Good."],
}
## Ring of spots around the dark altar where the totems stand.
const TOTEM_SPOTS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(-1, 1), Vector2i(1, 1)]

var world: World
var director: Node
var _by_id := {}
var _ensure_t := 0.0
var _whisper_t := 60.0
var _last_tod := 0.0


func _ready() -> void:
	for c in Deck.CARDS:
		_by_id[c["id"]] = c
	Game.title_of = _title_of
	Game.draw_requested.connect(_on_draw_requested)
	Game.new_day.connect(_on_new_day)
	_last_tod = Game.time_of_day


func _title_of(id: String) -> String:
	return String(card(id).get("title", id))


func _on_draw_requested() -> void:
	draw_card()


func card(id: String) -> Dictionary:
	return _by_id.get(id, {})


# ---------------------------------------------------------------- drawing
## A card can only show up once its prerequisites ("needs", level, weirdness) are met.
func eligible(c: Dictionary) -> bool:
	if int(c.get("rarity", 1)) <= 0:
		return false
	if c.get("once", false) and Game.played.has(c["id"]):
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
		if Game.has_card(c["id"]) or not eligible(c):
			continue
		var w: float = RARITY_WEIGHT.get(int(c["rarity"]), 1.0)
		w /= 1.0 + int(Game.seen.get(c["id"], 0)) * 0.6
		if Game.has_relic("tome") and float(c.get("weird", 0)) > 0.0:
			w *= 1.5
		# cards whose prerequisites just came true get a nudge so the player sees them soon
		if c.has("needs") and not Game.seen.has(c["id"]):
			w *= 1.6
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
		"no_obj":
			return [world.count_obj(r[1]) == 0, "no %s yet" % _obj_name(r[1])]
		"relic":
			return [Game.has_relic(r[1]), "the %s" % Game.RELICS[r[1]]["name"]]
		"no_relic":
			return [not Game.has_relic(r[1]), "no %s" % Game.RELICS[r[1]]["name"]]
		"perk":
			return [Game.has_perk(r[1]), "the %s ability" % Game.PERKS[r[1]]["name"]]
		"no_perk":
			return [not Game.has_perk(r[1]), "not %s yet" % Game.PERKS[r[1]]["name"]]
		"friend":
			return [Game.friends.has(r[1]), "%s as a friend" % Game.FRIENDS[r[1]]["name"]]
		"no_friend":
			return [not Game.friends.has(r[1]), "not friends with %s" % Game.FRIENDS[r[1]]["name"]]
		"friends":
			return [Game.friends.size() >= int(r[1]), "%d townsfolk friends (%d)" % [r[1], Game.friends.size()]]
		"totems":
			return [Game.totems >= int(r[1]), "%d/%d dark totems (%d)" % [r[1], Game.TOTEMS_MAX, Game.totems]]
		"no_totems":
			return [Game.totems < int(r[1]), "fewer than %d totems" % r[1]]
		"played":
			return [Game.played.has(r[1]), "played %s" % _title_of(r[1])]
		"not_played":
			return [not Game.played.has(r[1]), "never played %s" % _title_of(r[1])]
		"chose":
			return [String(Game.played.get(r[1], "")) == String(r[2]), "chose %s" % card(r[1]).get(r[2], {}).get("label", "?")]
		"day":
			return [Game.day >= int(r[1]), "day %d (%d)" % [r[1], Game.day]]
		"cleared":
			var pc := int(world.cleared_ratio() * 100.0)
			return [pc >= int(r[1]), "%d%% of the farm cleared (%d%%)" % [r[1], pc]]
		"overgrown":
			var pc2 := int((1.0 - world.cleared_ratio()) * 100.0)
			return [pc2 >= int(r[1]), "%d%% still overgrown (%d%%)" % [r[1], pc2]]
		"fields":
			return [world.fields.size() >= int(r[1]), "%d fields (%d)" % [r[1], world.fields.size()]]
		"paths":
			var pn: int = world.path_count()
			return [pn >= int(r[1]), "%d path tiles (%d)" % [r[1], pn]]
		"pond":
			return [world.ground.count(World.G_WATER) > 0, "a pond"]
		"quirk":
			return [Game.quirk == r[1], "a %s farmer" % Game.QUIRKS[r[1]]["name"].to_lower()]
		"weather":
			return [Game.weather == r[1], "%s right now" % WEATHER_WORDS.get(r[1], r[1])]
		"night":
			return [Game.is_night(), "night time"]
		"day_time":
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
			return [Game.inventory_count() >= int(r[1]), "produce to trade"]
		"treasure":
			var tn := Game.treasure_count(r[1])
			return [tn >= int(r[2]), "%d %s in the chest (%d)" % [r[2], String(Game.TREASURES[r[1]]["name"]).to_lower(), tn]]
		"wealth":
			return [Game.wealth() >= int(r[1]), "a chest worth %d (%d)" % [r[1], Game.wealth()]]
		"item":
			var have := Game.item_count(r[1])
			return [have >= int(r[2]), "%d %s (%d)" % [r[2], Game.ITEM_NAMES.get(r[1], r[1]), have]]
		# ---- the alien colony (colony.gd)
		"aliens":
			var ap: int = world.colony.population() if world.colony else 0
			return [ap >= int(r[1]), "%d aliens on the farm (%d)" % [r[1], ap]]
		"no_aliens":
			var none: bool = world.colony == null or (not world.colony.active() and world.colony.population() == 0)
			return [none, "no aliens around"]
		"alien_rel":
			var rv := int(world.colony.rel()) if world.colony else 0
			return [rv >= int(r[1]), "alien relations %+d (%+d)" % [r[1], rv]]
		"alien_rel_below":
			var rv2 := int(world.colony.rel()) if world.colony else 0
			return [rv2 < int(r[1]), "alien relations below %+d (%+d)" % [r[1], rv2]]
		"alien_land":
			var al: int = world.alien_land.size()
			return [al >= int(r[1]), "%d tiles of alien creep (%d)" % [r[1], al]]
		"alien_building":
			return [world.count_obj(r[1]) > 0, "an alien %s" % Colony.BUILDINGS.get(r[1], {}).get("name", r[1])]
		"mutation":
			return [Game.has_mutation(r[1]), "the farmer's %s" % String(Game.MUTATIONS[r[1]]["name"]).to_lower()]
		"no_mutation":
			return [not Game.has_mutation(r[1]), "no %s" % String(Game.MUTATIONS[r[1]]["name"]).to_lower()]
		"mutations":
			return [Game.mutations.size() >= int(r[1]), "%d mutation%s (%d)" % [r[1], "" if int(r[1]) == 1 else "s", Game.mutations.size()]]
		# ---- the Brood (swarm.gd)
		"insects":
			var ip: int = world.swarm.population() if world.swarm else 0
			return [ip >= int(r[1]), "%d giant insects (%d)" % [r[1], ip]]
		"no_insects":
			var none2: bool = world.swarm == null or (not world.swarm.active() and world.swarm.members().is_empty())
			return [none2, "no giant insects around"]
		"brood_rel":
			var bv := int(world.swarm.rel_farm()) if world.swarm else 0
			return [bv >= int(r[1]), "brood relations %+d (%+d)" % [r[1], bv]]
		"brood_rel_below":
			var bv2 := int(world.swarm.rel_farm()) if world.swarm else 0
			return [bv2 < int(r[1]), "brood relations below %+d (%+d)" % [r[1], bv2]]
		"brood_war":
			return [world.swarm != null and world.swarm.at_war(), "the brood at war with the aliens"]
		"mounds":
			var mn: int = world.count_obj("i_mound")
			return [mn >= int(r[1]), "%d bug mound%s (%d)" % [r[1], "" if int(r[1]) == 1 else "s", mn]]
		"water":
			var wn: int = world.ground.count(World.G_WATER)
			return [wn >= int(r[1]), "%d tiles of water (%d)" % [r[1], wn]]
	return [true, ""]


## Costs hidden inside effects become requirements automatically.
func auto_reqs(fx: Array) -> Array:
	var out: Array = []
	for e in fx:
		match e[0]:
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
			"totem":
				if int(e[1]) < 0:
					out.append(["totems", -int(e[1])])
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


## Plays the card in box/stash slot `i`.
func choose(where: String, i: int, which: String) -> bool:
	var id := Game.card_at(where, i)
	var c := card(id)
	if c.is_empty() or not can_choose(c, which):
		return false
	var ch: Dictionary = c[which]
	Game.take_card(where, i)
	Game.played[id] = which
	Game.add_log("%s: %s." % [c["title"], ch["label"]])
	if c.get("visitor", false):
		var crowd := int(c.get("crowd", 1))
		for k in crowd:
			var v: Animal = director.spawn_animal("visitor", Vector2(-14 - k * 12, world.feet(world.DOOR).y + 30 + k * 10))
			v.sprite = c["art"] if k == 0 else "v_villager"
			v.reply = ch.get("reply", "...") if k == 0 else ""
			if k > 0:
				v.tint = [Color("f7c6a0"), Color("f19ec2"), Color("a7f070"), Color("73eff7")][k % 4]
	apply(ch.get("fx", []))
	world.prune_fields()
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
		"trinkets":
			var got: Dictionary = world.loot_trinkets(Game.scaled_reward(int(e[1])), fp)
			if not got.is_empty():
				Game.add_log("Into the chest: %s." % Game.describe(got))
		"loot":
			world.loot(e[1], int(e[2]) if e.size() > 2 else 1, fp)
		"uproot":
			var cs2 := _alive_crops("", false)
			cs2.shuffle()
			for i in mini(int(e[1]), cs2.size()):
				world.crops.erase(cs2[i])
				world.puff(world.center(cs2[i]), Color("8b5a3c"), 5)
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
			if not Game.has_perk("iron_gut"):
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
				world.crops[alive3[i]]["type"] = String(e[2]) if e.size() > 2 else "glowshroom"
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
			var tr: Dictionary = Game.trade_goods(float(e[1]))
			if int(tr["worth"]) > 0:
				world.float_text("+%d WORTH" % tr["worth"], fp + Vector2(-16, -26))
				Game.add_log("Traded the produce for %s." % Game.describe(tr["got"]))
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
			for c in world.cells_with_obj(["weed", "tallgrass"]):
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
		# ---- farm-shaping effects
		"clear":
			var n5: int = world.clear_overgrowth(int(e[1]))
			if n5 > 0:
				Game.add_log("%d patches of overgrowth cleared away." % n5)
		"overgrow":
			world.overgrow(int(e[1]))
		"field":
			_field(String(e[1]), String(e[2]) if e.size() > 2 else "", int(e[3]) if e.size() > 3 else 25)
		"path":
			var laid := 0
			for i in int(e[1]):
				var pc: Variant = world.next_path_cell(true)
				if pc == null:
					break
				world.remove_obj(pc)
				world.ground[world.idx(pc)] = World.G_PATH
				world.puff(world.center(pc), Color("c9a26b"), 5, 12.0)
				laid += 1
			if laid > 0:
				Game.add_log("%d tiles of footpath laid." % laid)
		"fence":
			var built := 0
			for i in int(e[1]):
				var fc: Variant = world.pick_build_cell("fence")
				if fc == null:
					break
				world.place_obj(fc, "fence")
				world.puff(world.center(fc), Color("c28a5a"), 4, 10.0)
				built += 1
			if built > 0:
				Game.add_log("%d fence posts went up." % built)
		"build":
			for i in (int(e[2]) if e.size() > 2 else 1):
				if world.count_obj(e[1]) >= int(Game.STRUCTS[e[1]]["max"]):
					break
				var bc: Variant = world.place_struct_auto(e[1])
				if bc == null:
					world.clear_overgrowth(4)
					bc = world.place_struct_auto(e[1])
				if bc != null:
					Game.add_log("A %s appeared on the farm." % Game.STRUCTS[e[1]]["name"])
		"demolish":
			var gone: Array = world.cells_with_obj([e[1]])
			gone.shuffle()
			for c in gone.slice(0, int(e[2]) if e.size() > 2 else gone.size()):
				world.remove_obj(c)
				world.puff(world.center(c), Color("c28a5a"), 10)
		"trees":
			_plant_trees(int(e[1]))
		"pond":
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			world._dig_pond(rng, int(e[1]) if e.size() > 1 else 4)
		"perk":
			if not Game.has_perk(e[1]):
				Game.perks[e[1]] = true
				Game.add_log("New ability: %s! %s" % [Game.PERKS[e[1]]["name"], Game.PERKS[e[1]]["desc"]])
				world.float_text(String(Game.PERKS[e[1]]["name"]).to_upper(), fp + Vector2(-20, -34), Color("a7f070"))
				world.puff(fp + Vector2(0, -8), Color("a7f070"), 14, 22.0)
		"lose_perk":
			if Game.has_perk(e[1]):
				Game.perks.erase(e[1])
				Game.add_log("Ability lost: %s." % Game.PERKS[e[1]]["name"])
		"friend":
			if not Game.friends.has(e[1]):
				Game.friends[e[1]] = true
				Game.add_log("%s is now a friend of the farm! %s" % [Game.FRIENDS[e[1]]["name"], Game.FRIENDS[e[1]]["desc"]])
		"lose_friend":
			if Game.friends.has(e[1]):
				Game.friends.erase(e[1])
				Game.add_log("%s won't be visiting any more." % Game.FRIENDS[e[1]]["name"])
		"totem":
			if int(e[1]) > 0:
				for i in int(e[1]):
					gain_totem()
			else:
				for i in -int(e[1]):
					_lose_totem()
		"alien":
			_alien_fx(e)
		"brood":
			_brood_fx(e)


## ["alien", op, arg]: steer the alien colony (colony.gd).
func _alien_fx(e: Array) -> void:
	var col: Colony = world.colony
	if col == null:
		return
	var arg: Variant = e[2] if e.size() > 2 else null
	match String(e[1]):
		"arrive":
			col.arrive(String(arg) if arg != null else "")
		"rel":
			col.change_rel(float(arg))
		"aggro":
			Game.colony["aggro"] = clampf(float(Game.colony.get("aggro", 0.5)) + float(arg), 0.0, 1.0)
		"food":
			col.add_food(float(arg))
		"matter":
			Game.colony["matter"] = float(Game.colony.get("matter", 0.0)) + float(arg)
		"cede":
			var n := col.cede(int(arg))
			if n > 0:
				Game.add_log("%d tiles of the farm now belong to the aliens." % n)
		"reclaim":
			var n2 := col.reclaim(int(arg))
			Game.add_log("The creep pulls back (%d tiles)." % n2)
		"abduct":
			if world.farmer:
				world.farmer.abduct(randf_range(60.0, 140.0))
				Game.add_log("The farmer floated up into the light...")
		"mutate":
			var m := col.mutate_farmer(String(arg) if arg != null else "")
			if m != "":
				Game.add_log("The farmer changed: %s. %s" % [Game.MUTATIONS[m]["name"], Game.MUTATIONS[m]["desc"]])
		"cure":
			col.cure_farmer()
		"burn_moss":
			var moss: Array = world.cells_with_obj(["a_moss"])
			for c in moss:
				director.ignite(c)
			Game.add_log("The glow moss goes up in flames (%d patches)." % moss.size())
		"delay":
			Game.colony["arrive_t"] = float(Game.colony.get("arrive_t", 0.0)) + float(arg)
		"gift":
			col.envoy_arrived_gift()
		"boon":
			col.boon(String(arg) if arg != null else "")
		"bane":
			col.bane(String(arg) if arg != null else "")


## ["brood", op, arg]: steer the mutant insects (swarm.gd).
func _brood_fx(e: Array) -> void:
	var sw: Swarm = world.swarm
	if sw == null:
		return
	var arg: Variant = e[2] if e.size() > 2 else null
	match String(e[1]):
		"arrive":
			sw.arrive(String(arg) if arg != null else "")
		"rel":
			sw.change_rel(float(arg))
		"rel_aliens":
			sw.change_rel(0.0, float(arg))
		"temper":
			Game.brood["temper"] = clampf(float(Game.brood.get("temper", 0.5)) + float(arg), 0.0, 1.0)
		"food":
			sw.add_food(float(arg))
		"swarm":
			sw.launch_swarm(String(arg) if arg != null else "")
		"flight":
			sw.boon("flight")
		"sinkhole":
			var land: Array = world.insect_land.keys()
			var at: Vector2i = land.pick_random() if land.size() > 0 else Vector2i(world.COLS / 2, world.ROWS - 4)
			sw.sinkhole(at, int(arg) if arg != null else 2)
		"fill":
			# the farmer fills tunnels in, nearest the house first
			var land2: Array = world.insect_land.keys()
			land2.sort_custom(func(a, b): return Vector2(a).distance_to(Vector2(world.DOOR)) < Vector2(b).distance_to(Vector2(world.DOOR)))
			for c in land2.slice(0, int(arg)):
				if world.obj_type(c) != "i_mound":
					world.insect_land.erase(c)
					if world.obj_type(c) in ["i_web", "i_hole", "i_comb"]:
						world.remove_obj(c)
		"burn_webs":
			for c in world.cells_with_obj(["i_web"]):
				director.ignite(c)
		"cure_fungus":
			for c in world.cells_with_obj(["i_fungus"]):
				world.remove_obj(c)
				world.puff(world.center(c), Color("ef7d57"), 6)
		"boon":
			sw.boon(String(arg) if arg != null else "")
		"bane":
			sw.bane(String(arg) if arg != null else "")


func _spawn(kind: String) -> void:
	match kind:
		"boar":
			director.run_event("boar")
		"crow":
			director.spawn_animal("crow", Vector2(randf_range(0, world.COLS * 16), -20))
		"butterfly", "wisp":
			director.spawn_animal(kind, Vector2(randf_range(10, 180), randf_range(20, world.ROWS * 16 - 16)))
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


## Sows n crops: empty tilled tiles first, then a fresh little field.
func _plant(crop: String, n: int) -> void:
	var spots: Array = []
	for c in world.tilled_cells():
		if not world.crops.has(c) and not world.objs.has(c):
			spots.append(c)
	if spots.size() < n:
		var fl: Dictionary = world.plan_field("", crop, maxi(2, n - spots.size()))
		if not fl.is_empty():
			for c in fl["cells"]:
				if world.objs.has(c):
					world.remove_obj(c)
				world.set_tilled(c, true)
				spots.append(c)
	spots.shuffle()
	for i in mini(n, spots.size()):
		world.plant(spots[i], crop)
		world.wet[world.idx(spots[i])] = 1.0
		world.puff(world.center(spots[i]), Color("a7f070"), 6, 14.0)


## Lays out a whole field at once: clears it, tills it and (unless crop is "none") sows it.
func _field(shape: String, crop: String, capacity: int) -> void:
	var fl: Dictionary = world.plan_field(shape, crop if crop != "none" else "", capacity)
	if fl.is_empty():
		world.clear_overgrowth(8)
		fl = world.plan_field(shape, crop if crop != "none" else "", capacity)
	if fl.is_empty():
		return
	for c in fl["cells"]:
		if world.objs.has(c):
			world.remove_obj(c)
		world.set_tilled(c, true)
		world.wet[world.idx(c)] = 1.0
		world.puff(world.center(c), Color("8b5a3c"), 5, 12.0)
		if crop != "none":
			var plant: String = crop
			if plant == "" or plant == "mixed" or plant == "any" or not Game.CROPS.has(plant):
				var opts: Array = []
				for id in Game.CROPS:
					if id != "melon" and Game.crop_unlocked(id):
						opts.append(id)
				plant = opts.pick_random()
			world.plant(c, plant)
	Game.add_log("A %s-shaped field appeared!" % String(fl["shape"]).replace("_", " "))


func _plant_trees(n: int) -> void:
	var cells: Array = []
	for c in world.free_grass_cells():
		if not world.is_planned(c) and world.keeps_connected(c):
			cells.append(c)
	if cells.size() < n:
		world.clear_overgrowth(n * 2, Vector2i(world.COLS - 1, world.ROWS - 1))
		cells = []
		for c in world.free_grass_cells():
			if not world.is_planned(c):
				cells.append(c)
	# orchards like the edges of the farm
	var keys := {}
	for c in cells:
		keys[c] = _edge_dist(c)
	cells.sort_custom(func(a, b): return keys[a] < keys[b])
	var planted := 0
	for c in cells:
		if planted >= n:
			break
		if not world.is_free_grass(c) or not world.keeps_connected(c):
			continue
		world.place_obj(c, "tree", {"apple": true})
		world.puff(world.center(c), Color("38b764"), 12, 20.0)
		planted += 1
	if planted > 0:
		Game.add_log("%d apple trees took root." % planted)


func _edge_dist(c: Vector2i) -> float:
	return mini(mini(c.x, world.COLS - 1 - c.x), world.ROWS - 1 - c.y) + randf() * 1.5


# ---------------------------------------------------------------- dark totems
## The first totem raises the dark altar; the rest stand in a ring around it.
func gain_totem() -> void:
	if Game.totems >= Game.TOTEMS_MAX:
		return
	var altar: Array = world.cells_with_obj(["altar"])
	if altar.is_empty():
		var spot: Variant = _altar_spot()
		if spot == null:
			return
		world.remove_obj(spot)
		world.place_obj(spot, "altar")
		world.puff(world.center(spot), Color("5d275d"), 18, 26.0)
		altar = [spot]
		Game.add_log("A dark altar pushed up out of the soil.")
	var a: Vector2i = altar[0]
	var placed := false
	for off in TOTEM_SPOTS:
		var c: Vector2i = a + off
		if world.in_bounds(c) and world.obj_type(c) != "totem" and (world.is_free_grass(c) or world.is_clearable(c)) \
				and not world.is_tilled(c) and world.keeps_connected(c):
			world.remove_obj(c)
			world.place_obj(c, "totem")
			world.puff(world.center(c), Color("b45cff"), 14, 22.0)
			placed = true
			break
	if not placed:
		var free: Array = world.free_grass_cells()
		if free.size() > 0:
			var c2: Vector2i = world.nearest(free, a)
			world.place_obj(c2, "totem")
	Game.totems += 1
	Game.add_weird(4.0)
	Game.add_log("Dark totem %d of %d stands by the altar." % [Game.totems, Game.TOTEMS_MAX])
	if director:
		director.shake.emit(2.0)


func _lose_totem() -> void:
	if Game.totems <= 0:
		return
	Game.totems -= 1
	var ts: Array = world.cells_with_obj(["totem"])
	if ts.size() > 0:
		world.remove_obj(ts[0])
		world.puff(world.center(ts[0]), Color("94b0c2"), 10)


func _altar_spot() -> Variant:
	var best: Variant = null
	var bs := -1e9
	for c in world.free_or_overgrown_cells():
		if world.is_planned(c) or c.x < 2 or c.x > world.COLS - 3 or c.y > world.ROWS - 2:
			continue
		var s: float = Vector2(c).distance_to(Vector2(world.DOOR)) + randf() * 3.0
		for off in TOTEM_SPOTS:
			if not world.in_bounds(c + off) or world.is_tilled(c + off) or world.is_water(c + off):
				s -= 3.0
		if s > bs:
			bs = s
			best = c
	return best


# ---------------------------------------------------------------- relics
const RELIC_STRUCTS := ["idol", "obelisk", "stones", "saucer"]
const RELIC_ACTORS := {"homunculus": "homunculus", "goat": "goat", "black_cat": "cat", "hatchling": "hatchling"}


func gain_relic(id: String) -> void:
	if Game.has_relic(id):
		return
	Game.relics[id] = true
	Game.add_log("Relic gained: %s." % Game.RELICS[id]["name"])
	if id in RELIC_STRUCTS:
		var cells: Array = []
		for c in world.free_grass_cells():
			if not world.is_planned(c) and not (c.y <= world.house.y + 2 and absi(c.x - world.house.x) <= 3):
				cells.append(c)
		if cells.size() < 3:
			world.clear_overgrowth(6, Vector2i(world.COLS / 2, world.ROWS / 2))
			cells = world.free_grass_cells()
		if cells.size() > 0:
			var focus := world.DOOR + Vector2i(0, 4)
			var tl: Array = world.tilled_cells()
			if tl.size() > 0:
				focus = tl[0]
			var c2: Vector2i = world.nearest(cells, focus) if id == "idol" else cells.pick_random()
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
	if Game.totems > 0:
		Game.add_weird(0.5 * Game.totems)
	if Game.has_relic("saucer"):
		Game.add_item("ore", 2)
		Game.add_log("The saucer's hull flaked off 2 ore.")
	if Game.has_relic("horseshoe"):
		Game.charms = mini(5, Game.charms + 1)
	if Game.has_mutation("third_eye"):
		Game.add_weird(1.0)
	if Game.has_relic("cursed_coin"):
		var got: Dictionary = Game.gain_trinkets(Game.scaled_reward(20))
		Game.mood = maxf(0.0, Game.mood - 10.0)
		Game.add_log("The cursed coin left %s in the chest. The farmer feels uneasy." % Game.describe(got))


## Townsfolk friends drop by in the morning, each with their gift.
func friends_visit() -> void:
	var k := 0
	for id in Game.friends:
		var def: Dictionary = Game.FRIENDS[id]
		var v: Animal = director.spawn_animal("visitor", Vector2(-14 - k * 14, world.feet(world.DOOR).y + 24 + k * 10))
		v.sprite = def["sprite"]
		v.tint = Color(def["tint"])
		v.reply = FRIEND_LINES[id].pick_random()
		k += 1
		match id:
			"gus":
				_plant("turnip", 3)
			"betty":
				Game.energy = minf(100.0, Game.energy + 40.0)
				Game.mood = minf(100.0, Game.mood + 10.0)
			"smith":
				for c in world.objs:
					var o: Dictionary = world.objs[c]
					if Game.STRUCTS.has(o["type"]):
						o["hp"] = Game.STRUCTS[o["type"]]["hp"]
				Game.add_item("stone", 3)
			"mayor":
				Game.gain_trinkets(Game.scaled_reward(25))
			"kids":
				world.clear_overgrowth(5)
			"doc":
				Game.health = minf(100.0, Game.health + 25.0)
				Game.poison = 0.0
				if not Game.mutations.is_empty() and randf() < 0.2 and world.colony:
					world.colony.cure_farmer()
	if k > 0:
		Game.add_log("The townsfolk dropped by (%d)." % k)


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
	# dawn: bone flute, friends
	if _last_tod < 0.25 and Game.time_of_day >= 0.25:
		if Game.has_relic("bone_flute"):
			var n := 0
			for a in world.threats():
				a.scare()
				n += 1
			Game.add_log("The bone flute shrieks at dawn. %d critters flee." % n)
	if _last_tod < 0.3 and Game.time_of_day >= 0.3:
		friends_visit()
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
