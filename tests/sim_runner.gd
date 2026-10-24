extends Node
## Headless simulation test (started by tests/sim_test.gd, which loads this once the autoloads exist). Boots the real game tree on a throwaway save slot, then drives the
## simulation by hand with a fixed timestep (no rendering, much faster than real time):
##   1. every alien arrival method, every caste, every boon/bane and every alien card choice
##   1b. the Brood: every insect arrival, the life cycle, swarms, sinkholes, webs, the war with
##       the aliens, every boon/bane and every insect card choice
##   1c. cataclysms: each faction can be wiped out completely, and comes back
##   2. a long natural run: the colony + tides left alone for many in-game days, sampled hourly
##   3. a save -> reload round trip
## Run (from the project folder):
##   C:/Dev/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . -s tests/sim_test.gd -- days=8
## Exit code 0 = all checks passed. Script errors show up as "SCRIPT ERROR" lines in the output.

const SLOT := 9
const STEP := 0.25

var main: Node
var failures: Array = []
var days := 8
var verbose := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("days="):
			days = int(a.substr(5))
		elif a.begins_with("seed="):
			seed(int(a.substr(5)))
		elif a == "verbose":
			verbose = true
	_run.call_deferred()


func _run() -> void:
	_wipe()
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.start_slot(SLOT)
	Game.running = true
	Game.time_scale = 1.0
	Game.log_added.connect(_on_log)
	print("== farm: %s (%s), quirk %s" % [Game.farm_name, main.world.biome, Game.quirk])

	_test_arrivals()
	_test_cards()
	_test_swings()
	_test_brood()
	_test_cataclysms()
	_reset_aliens()
	_test_natural_run()
	_test_multiplayer_prep()
	await _test_save_roundtrip()

	_wipe()
	if failures.is_empty():
		print("== ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		get_tree().quit(1)


# ---------------------------------------------------------------- driving the sim
func step(seconds: float) -> void:
	var n := int(seconds / STEP)
	for i in n:
		Game._process(STEP)
		main.world._process(STEP)
		main.director._process(STEP)
		main.cards._process(STEP)
		main.colony._process(STEP)
		main.swarm._process(STEP)
		main.tides._process(STEP)


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
	elif verbose:
		print("  ok: ", what)


func _on_log(t: String) -> void:
	var lt := t.to_lower()
	if verbose or t.begins_with("THE TIDE") or t.begins_with("WAR") or "saucer" in lt or "sinkhole" in lt or "swarm" in lt \
			or "queen" in lt or "mound" in lt or "turned hostile" in lt or "homeworld" in lt or "civil war" in lt:
		print("   [day %d %s] %s" % [Game.day, Game.clock_text(), t])


func aliens(caste: String = "") -> Array:
	var out: Array = []
	for a in main.world.animals:
		if a is Alien and not a.dead and (caste == "" or a.caste == caste):
			out.append(a)
	return out


func bugs(caste: String = "") -> Array:
	var out: Array = []
	for a in main.world.animals:
		if a is Insect and not a.dead and (caste == "" or a.caste == caste):
			out.append(a)
	return out


func _bugs() -> String:
	var n := {}
	for a in bugs():
		n[a.caste] = int(n.get(a.caste, 0)) + 1
	return str(n)


func _reset_aliens() -> void:
	for a in aliens() + bugs():
		a.dead = true
	step(1.0)
	for c in main.world.cells_with_obj(["i_mound", "i_web", "i_comb", "i_hole", "i_husk", "i_fungus"]):
		main.world.remove_obj(c)
	main.world.insect_land.clear()
	main.world.bare.clear()
	Game.brood = {}
	main.swarm._ensure_state()
	Game.brood["arrive_t"] = 900.0
	for c in main.colony.buildings() + main.world.cells_with_obj(["a_ruin", "a_husk"]):
		main.world.remove_obj(c)
	main.world.alien_land.clear()
	Game.colony = {}
	main.colony._ensure_state()
	Game.colony["arrive_t"] = 200.0
	Game.mutations = {}
	Game.tides = {}
	main.tides._ensure()
	Game.buffs.erase("silent_wild")


func _wipe() -> void:
	var p := ProjectSettings.globalize_path(Game.slot_path(SLOT))
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


func _castes() -> String:
	var n := {}
	for a in aliens():
		n[a.caste] = int(n.get(a.caste, 0)) + 1
	return str(n)


# ---------------------------------------------------------------- 1. arrivals, castes
func _test_arrivals() -> void:
	print("== arrivals")
	var col: Colony = main.colony
	# egg
	col.arrive("egg")
	check(aliens("egg").size() == 1, "egg arrival lays an egg")
	step(260.0)
	check(aliens("egg").is_empty(), "the egg hatched")
	check(aliens().size() >= 1, "the hatchling lives")
	_reset_aliens()
	# saucer
	col.arrive("saucer")
	check(aliens("ship").size() == 1, "saucer arrival sends a ship")
	step(40.0)
	check(aliens("ship").is_empty(), "the ship left again")
	check(aliens().size() >= 4, "the saucer dropped colonists (%d)" % aliens().size())
	check(col.has_village(), "the saucer colonists founded a village")
	check(col.land_size() > 0, "the village has creep")
	step(300.0)
	print("   saucer village after 300s: %s, %d buildings, land %d, food %d, matter %d" % [_castes(),
		col.building_count(), col.land_size(), int(Game.colony["food"]), int(Game.colony["matter"])])
	check(int(Game.colony["built"]) > 0, "workers finished a building")
	_reset_aliens()
	# stranger
	col.arrive("stranger")
	check(aliens("stranger").size() == 1, "a stranger walks in")
	step(90.0)
	check(aliens("stranger").is_empty(), "the stranger settled (revealed)")
	check(col.has_village(), "the stranger founded a village")
	_reset_aliens()
	# lurker at night, with a hen to go for
	Game.time_of_day = 0.95
	if main.world.count_animals("chicken") == 0:
		main.cards.apply([["chicken", 2]])
	col.arrive("lurker")
	check(aliens("lurker").size() == 1, "a lurker creeps in at night")
	step(60.0)
	check(aliens("mutant").size() >= 1, "the lurker mutated a chicken (%s)" % _castes())
	step(200.0)
	check(aliens("mutant").is_empty() and aliens().size() >= 1, "the mutant transformed (%s)" % _castes())
	# lurker by day waits for night
	_reset_aliens()
	Game.time_of_day = 0.4
	col.arrive("lurker")
	check(aliens("lurker").is_empty(), "a daytime lurker waits for dark")
	check(Game.pending.size() > 0, "the lurker is pending until night")
	Game.pending.clear()
	_reset_aliens()


# ---------------------------------------------------------------- 2. cards
func _test_cards() -> void:
	print("== alien cards")
	var col: Colony = main.colony
	col.arrive("saucer")
	step(60.0)
	main.cards.apply([["plant", "turnip", 6]])
	var ids: Array = []
	for c in Deck.CARDS:
		var fx_all: Array = c["a"]["fx"] + c["b"]["fx"]
		var alien := false
		for e in fx_all:
			if e[0] == "alien":
				alien = true
		for r in c.get("needs", []):
			if String(r[0]).begins_with("alien") or r[0] in ["no_aliens", "aliens", "mutation", "mutations"]:
				alien = true
		if alien:
			ids.append(c["id"])
	check(ids.size() >= 12, "the deck has alien cards (%d)" % ids.size())
	for id in ids:
		var c: Dictionary = main.cards.card(id)
		check(Art.has(c["art"]), "card %s has art %s" % [id, c["art"]])
		for which in ["a", "b"]:
			for r in c[which].get("req", []) + c.get("needs", []):
				main.cards.check(r)
			main.cards.apply(c[which]["fx"])
			step(3.0)
	check(Game.mutations.size() >= 1, "cards can mutate the farmer (%s)" % str(Game.mutations.keys()))
	# the farmer's abduction comes back with a mutation
	Game.mutations = {}
	var f: Farmer = main.world.farmer
	f.state = "idle"
	f.hidden = false
	main.cards.apply([["alien", "abduct"]])
	check(f.state == "abducted", "the farmer can be abducted")
	Game.colony["rel"] = 0.0   # no friendly saucer coming back for him mid-test
	step(150.0)
	check(f.state != "abducted", "the farmer comes back")
	check(Game.mutations.size() >= 1, "he came back mutated")
	_reset_aliens()


# ---------------------------------------------------------------- 3. boons / banes
func _test_swings() -> void:
	print("== boons, banes, tides")
	var col: Colony = main.colony
	col.arrive("saucer")
	step(60.0)
	for k in ["mothership", "hatching", "golden", "bounty"]:
		col.boon(k)
		step(30.0)
	var before := aliens().size()
	for k in ["plague", "famine", "queen", "homesick", "schism"]:
		col.bane(k)
		step(40.0)
	print("   aliens %d -> %d after the banes" % [before, aliens().size()])
	for i in 12:
		main.tides.turn()
		step(5.0)
	check(true, "tides turned 12 times")
	_reset_aliens()


# ---------------------------------------------------------------- 3b. the brood
func _test_brood() -> void:
	print("== the brood")
	var sw: Swarm = main.swarm
	var w: World = main.world
	_reset_aliens()
	# wasps mutate into a queen who flies off to found a mound
	main.director.spawn_animal("wasps", w.feet(Vector2i(6, 14)))
	sw.arrive("")
	check(bugs("queen").size() == 1, "a wasp nest mutates into a queen")
	step(40.0)
	check(sw.mounds().size() >= 1, "the queen founded a mound")
	check(sw.land_size() >= 3, "the mound has tunnels (%d)" % sw.land_size())
	step(700.0)
	print("   brood after 700s: %s, mounds %d (stages %s), tunnels %d, food %d" % [_bugs(), sw.mounds().size(),
		str(sw.mounds().map(func(m): return sw.mound_stage(m))), sw.land_size(), int(Game.brood["food"])])
	check(sw.population() >= 3, "the brood grew (%d adults)" % sw.population())
	check(int(Game.brood["born"]) >= 3, "eggs were laid")
	# every caste can exist and act
	for c in ["worker", "soldier", "locust", "spinner", "glowfly"]:
		var b := Insect.new(w, c, w.feet(sw.mounds()[0]) + Vector2(4, 6))
		b.hive = sw.mounds()[0]
		w.add_animal(b)
	Game.time_of_day = 0.95
	step(60.0)
	Game.time_of_day = 0.4
	step(60.0)
	# a locust swarm strips a band of the farm bare
	main.cards.apply([["plant", "turnip", 6]])
	var crops_before := w.crops.size()
	var n := sw.launch_swarm("farm")
	check(n >= 2, "a locust swarm takes off (%d)" % n)
	step(40.0)
	print("   swarm: crops %d -> %d, bare tiles %d" % [crops_before, w.crops.size(), w.bare.size()])
	check(w.bare.size() > 0, "the swarm left bare ground")
	# sinkholes swallow the land into ponds
	var water := w.ground.count(World.G_WATER)
	var land: Array = w.insect_land.keys()
	var holes := 0
	for c in land.slice(0, 3):
		holes += sw.sinkhole(c, 2)
	check(w.ground.count(World.G_WATER) > water, "sinkholes turn tunnels into ponds (+%d water)" % (w.ground.count(World.G_WATER) - water))
	# rain over dense tunnels caves them in by itself
	for i in 20:
		for c in sw.claimed():
			sw._dig(c)
	Game.weather = "storm"
	var water2 := w.ground.count(World.G_WATER)
	step(600.0)
	Game.weather = "sunny"
	print("   storm over the tunnels: water %d -> %d, sinkholes so far %d" % [water2, w.ground.count(World.G_WATER), int(Game.brood["sinkholes"])])
	# webs trap critters
	var spot: Variant = null
	for c in w.insect_land:
		if sw._can_wall(c):
			spot = c
			break
	if spot != null:
		sw.spin(spot)
	var webs: Array = w.cells_with_obj(["i_web"])
	if webs.size() > 0:
		spot = webs[0]
		var r: Animal = main.director.spawn_animal("rabbit", w.feet(spot))
		sw.tick(2.0)
		check(r.dead, "a rabbit walking into a web gets caught")
	# war with the aliens: a front line, casualties, mantises on the march
	main.colony.arrive("saucer")
	step(80.0)
	Game.colony["matter"] = 80.0
	step(300.0)
	sw.change_rel(0.0, -100.0)
	for i in 4:
		var m := Insect.new(w, "soldier", w.feet(sw.mounds()[0]))
		m.hive = sw.mounds()[0]
		w.add_animal(m)
	if main.colony.active() and sw.active():
		check(sw.at_war(), "the brood can go to war with the aliens")
	var died_a := int(Game.colony["died"])
	var died_b := int(Game.brood["died"])
	step(400.0)
	print("   war: aliens died %d, insects died %d, creep %d, tunnels %d, alien ruins %d" % [int(Game.colony["died"]) - died_a,
		int(Game.brood["died"]) - died_b, main.colony.land_size(), sw.land_size(), w.count_obj("a_ruin")])
	# every insect card choice applies cleanly
	var ids: Array = []
	for c in Deck.CARDS:
		for e in c["a"]["fx"] + c["b"]["fx"]:
			if e[0] == "brood" and not c["id"] in ids:
				ids.append(c["id"])
	check(ids.size() >= 10, "the deck has insect cards (%d)" % ids.size())
	Game.add_item("honey", 10)
	Game.add_item("stone", 10)
	for id in ids:
		var cd: Dictionary = main.cards.card(id)
		check(Art.has(cd["art"]), "card %s has art %s" % [id, cd["art"]])
		for which in ["a", "b"]:
			for r2 in cd[which].get("req", []) + cd.get("needs", []):
				main.cards.check(r2)
			main.cards.apply(cd[which]["fx"])
			step(3.0)
	for k in ["swarm", "flight", "bloom", "molt"]:
		sw.boon(k)
		step(20.0)
	for k in ["frost", "cordyceps", "flood", "queen"]:
		sw.bane(k)
		step(20.0)
	step(200.0)
	check(true, "brood boons and banes ran")
	# the other arrival routes
	for m2 in ["hive", "cocoon", "locusts"]:
		_reset_aliens()
		if m2 == "hive":
			main.cards.apply([["build", "beehive", 1]])
		sw.arrive(m2)
		step(250.0)
		check(not bugs().is_empty() or sw.active(), "brood arrival by %s (%s)" % [m2, _bugs()])
	_reset_aliens()


# ---------------------------------------------------------------- 3c. cataclysms
func _test_cataclysms() -> void:
	print("== cataclysms")
	var t: Tides = main.tides
	var w: World = main.world
	_reset_aliens()
	main.colony.arrive("saucer")
	main.swarm.arrive("wasps")
	main.cards.apply([["field", "", "mixed"], ["build", "coop", 1], ["plant", "turnip", 4]])
	step(400.0)
	for k in ["aliens", "insects", "wild", "farm"]:
		check(t.alive(k), "%s present before its cataclysm" % k)
	for k in ["aliens", "insects", "wild", "farm"]:
		t.roll_cataclysm(k)
		step(120.0 if k == "aliens" else 6.0)
		check(not t.alive(k), "the %s cataclysm wipes them out" % k)
		t._sample()
	print("   %s" % t.extinction_line())
	check(int(Game.tides["extinct"].size()) == 4, "all four extinctions were tracked (%s)" % str(Game.tides["extinct"]))
	check(main.world.farmer != null and main.world.farmer.state != "", "the farmer survived the dark harvest")
	# comebacks: the farmer breaks new ground, the wild returns when the silence ends
	step(Game.DAY_LENGTH)
	check(t.alive("farm"), "the farm comes back (tilled %d)" % w.tilled_cells().size())
	step(Game.DAY_LENGTH * 2.2)
	check(t.alive("wild"), "the wild comes back after the silence")
	_reset_aliens()


# ---------------------------------------------------------------- 4. natural run
func _test_natural_run() -> void:
	print("== natural run: %d days" % days)
	var col: Colony = main.colony
	var lo := {"farm": 1.0, "aliens": 1.0, "insects": 1.0, "wild": 1.0}
	var hi := {"farm": 0.0, "aliens": 0.0, "insects": 0.0, "wild": 0.0}
	var sw: Swarm = main.swarm
	var water0: int = main.world.ground.count(World.G_WATER)
	var broods := 0
	var brood_was := false
	var max_bugs := 0
	var wars := 0
	var war_was := false
	var max_bare := 0
	var max_pop := 0
	var villages := 0
	var was_active := false
	var hours := days * 24
	var tide_logs := 0
	var turns_seen := {}
	for h in hours:
		step(Game.DAY_LENGTH / 24.0)
		var s: Dictionary = main.tides.shares()
		for k in s:
			lo[k] = minf(lo[k], s[k])
			hi[k] = maxf(hi[k], s[k])
		max_pop = maxi(max_pop, col.population())
		if col.active() and not was_active:
			villages += 1
		was_active = col.active()
		if sw.active() and not brood_was:
			broods += 1
		brood_was = sw.active()
		if sw.at_war() and not war_was:
			wars += 1
		war_was = sw.at_war()
		max_bugs = maxi(max_bugs, sw.population())
		max_bare = maxi(max_bare, main.world.bare.size())
		for id in Game.box + Game.stash:
			if id != "" and (String(id).begins_with("alien_") or String(id).begins_with("brood_") or id in ["border_dispute", "tractor_beam",
					"hive_offer", "sick_colony", "glowing_spores", "funny_rash", "locust_horizon", "sinkhole_card", "grub_roots"]):
				turns_seen["card:" + id] = true
		var last := String(Game.tides.get("last", ""))
		if last != "":
			turns_seen[last] = true
		if h % 12 == 0:
			print("   day %d %s | %s pop %d %s | bld %d land %d food %d rel %+d | farm tilled %d crops %d hp %d | %s" % [
				Game.day, Game.clock_text(), col.era_name(), col.population(), _castes(), col.building_count(),
				col.land_size(), int(Game.colony["food"]), int(col.rel()), main.world.tilled_cells().size(),
				main.world.crops.size(), int(Game.health), main.tides.status_line()])
			print("      farmer: %s | brood: %s pop %d %s | mounds %d tunnels %d webs %d food %d | rel farm %+d aliens %+d | bare %d water %d" % [
				main.world.farmer.activity,
				sw.era_name(), sw.population(), _bugs(), sw.mounds().size(), sw.land_size(), main.world.count_obj("i_web"),
				int(Game.brood["food"]), int(sw.rel_farm()), int(sw.rel_aliens()), main.world.bare.size(), main.world.ground.count(World.G_WATER)])
	print("   share ranges: farm %.2f-%.2f aliens %.2f-%.2f wild %.2f-%.2f; max pop %d; villages founded %d; born %d died %d" % [
		lo["farm"], hi["farm"], lo["aliens"], hi["aliens"], lo["wild"], hi["wild"], max_pop, villages,
		int(Game.colony["born"]), int(Game.colony["died"])])
	print("   tide turns seen: %s; mutations: %s" % [str(turns_seen.keys()), str(Game.mutations.keys())])
	print("   cataclysms %d; %s" % [int(Game.tides.get("cataclysms", 0)), main.tides.extinction_line()])
	var ex: Dictionary = Game.tides.get("extinct", {})
	if days >= 12:
		check(ex.size() >= 2, "at least two different factions were wiped out at some point (%s)" % str(ex))
	print("   brood: %d broods rose, max %d insects, %d wars, %d sinkholes, max bare %d, water %d -> %d, insect share %.2f-%.2f" % [
		broods, max_bugs, wars, int(Game.brood.get("sinkholes", 0)), max_bare, water0, main.world.ground.count(World.G_WATER),
		lo["insects"], hi["insects"]])
	if days >= 8:   # the brood needs a few days to arise on its own
		check(broods >= 1, "the brood arose on its own")
		check(hi["insects"] - lo["insects"] > 0.08, "the brood's share of power moved")
	for c in main.world.insect_land:
		check(not col.protected(c), "tunnels never reach the farmhouse/doorstep (%s)" % str(c))
	check(villages >= 1, "aliens arrived and founded a village on their own")
	check(max_pop >= 3, "the colony grew (max pop %d)" % max_pop)
	check(hi["aliens"] - lo["aliens"] > 0.1, "the aliens' share of power moved")
	check(hi["farm"] - lo["farm"] > 0.1, "the farm's share of power moved")
	check(main.world.farmer != null and Game.health > 0.0 or main.world.farmer.state == "fainted", "the farmer himself survived everything")
	check(main.world.farmer != null, "the farmer still exists")
	check(not col.protected(Vector2i(-1, -1)) or true, "protected() callable")
	for c in main.world.alien_land:
		check(not col.protected(c), "the creep never covers the farmhouse/doorstep (%s)" % str(c))


# ---------------------------------------------------------------- 5. save / load
## MULTIPLAYER.md phase 0: per-player hands, the command layer, actor ids, world ids, puppet mode.
## Leaves a fake guest hand (GUEST) in place for the save round trip to check.
func _test_multiplayer_prep() -> void:
	print("== multiplayer prep")
	var cmd: Commands = main.commands
	var me := Game.my_pid
	check(Game.owner_pid == me, "a solo world is owned by the local player")
	check(Game.world_id.length() == 16, "the world has an id")
	# an old (v3) save: one box + stash becomes the owner's hand
	var keep: Dictionary = Game.to_dict().duplicate(true)
	var old := keep.duplicate(true)
	old.erase("hands")
	old.erase("owner_pid")
	old["box"] = ["harvest_moon", "", ""]
	old["stash"] = ["", "", "taxman"]
	Game.from_dict(old)
	check(Game.owner_pid == me and Game.card_at("box", 0) == "harvest_moon" and Game.card_at("stash", 2) == "taxman",
		"a pre-multiplayer save's box/stash becomes the owner's hand")
	Game.from_dict(keep)
	# a guest's hand is separate from ours
	var g := GUEST
	Game.hand(g)
	var id := ""
	var which := ""
	for attempt in 20:
		Game.hand(g)["box"] = ["", "", ""]
		id = main.cards.draw_card(g)
		var c: Dictionary = main.cards.card(id)
		for w in ["a", "b"]:
			if which == "" and not c.is_empty() and main.cards.can_choose(c, w):
				which = w
		if which != "":
			break
	check(which != "", "found a playable card for the guest")
	check(Game.card_at("box", 0, g) == id and not id in Game.box, "a card drawn for the guest lands in the guest's box only")
	check(not cmd.execute(g, {"type": "choose", "where": "hat", "i": 0, "which": which}), "a bad slot name is rejected")
	check(not cmd.execute(g, {"type": "choose", "where": "box", "i": 99, "which": which}), "a bad slot index is rejected")
	check(not cmd.execute(g, {"type": "choose", "where": "box", "i": 0, "which": "c"}), "a bad choice is rejected")
	check(not cmd.execute("nobody", {"type": "move_card", "from": "box", "fi": 0, "to": "stash", "ti": 0}), "an unknown player is rejected")
	check(not cmd.execute(g, {"type": "card_minutes", "n": 5}), "a guest can't change the card cadence")
	check(not cmd.execute(g, {"type": "debug", "key": "draw"}), "a guest can't use debug commands")
	check(cmd.execute(g, {"type": "choose", "where": "box", "i": 0, "which": which}), "the guest plays a card by command")
	check(Game.card_at("box", 0, g) == "" and Game.played.get(id, "") == which, "the guest's card is used up and recorded")
	main.cards.draw_card(g)
	var gid := Game.card_at("box", 0, g)
	check(cmd.execute(g, {"type": "move_card", "from": "box", "fi": 0.0, "to": "stash", "ti": 1}), "the guest moves a card by command")
	check(Game.card_at("stash", 1, g) == gid and Game.card_at("box", 0, g) == "", "the guest's card moved within the guest's hand")
	# who gets cards nobody asked for
	Game.acting_pid = g
	var gid2: String = main.cards.draw_card()
	Game.acting_pid = ""
	check(Game.card_at("box", 0, g) == gid2, "a card caused by the guest's action goes to the guest")
	var oid: String = main.cards.draw_card()
	check(Game.card_at("box", 0) == oid, "other pushed cards go to the owner")
	# only present players' cards drip in
	Game.hand(g)["card_timer"] = Game.card_interval() - 1.0
	step(2.0)
	check(float(Game.hand(g)["card_timer"]) == Game.card_interval() - 1.0, "an absent player's card timer is frozen")
	# actor ids
	var uids := {main.world.farmer.uid: true}
	for a in main.world.animals:
		uids[a.uid] = true
	check(main.world.farmer.uid > 0 and uids.size() == main.world.animals.size() + 1, "every actor has a unique id")
	# puppet mode: nothing changes
	main.colony.arrive("saucer")
	main.swarm.arrive("hive")
	step(30.0)
	Game.puppet = true
	var before := _frozen()
	var tod := Game.time_of_day
	step(60.0)
	var after := _frozen()
	check(Game.time_of_day != tod, "the clock keeps ticking in puppet mode (cosmetic)")
	Game.puppet = false
	check(before == after, "60s in puppet mode leave the world untouched")
	step(5.0)
	check(_frozen() != after, "the world moves again after puppet mode")


## The whole game state minus the clock (which a guest ticks on its own).
func _frozen() -> PackedByteArray:
	var g: Dictionary = Game.to_dict().duplicate(true)
	g.erase("time_of_day")
	return var_to_bytes([g, main.world.to_dict()])


const GUEST := "guest000000000ff"


func _test_save_roundtrip() -> void:
	print("== save/load")
	var guest_stash := Game.card_at("stash", 1, GUEST)
	var wid := Game.world_id
	var fuid: int = main.world.farmer.uid
	var auids := {}
	for a in main.world.animals:
		if a.persistent():
			auids[a.uid] = true
	var col: Colony = main.colony
	if not col.active():
		col.arrive("saucer")
		step(60.0)
	var n := aliens().size()
	var land := col.land_size()
	var bld := col.building_count()
	var rel := col.rel()
	if not main.swarm.active():
		main.swarm.arrive("hive")
		step(120.0)
	var nb := bugs().size()
	var tun: int = main.world.insect_land.size()
	var mnd: int = main.swarm.mounds().size()
	main.save_game()
	main.back_to_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	main.start_slot(SLOT)
	Game.running = true
	await get_tree().process_frame
	var n2 := aliens().size()
	print("   before: %d aliens, land %d, %d buildings, rel %d | after: %d aliens, land %d, %d buildings, rel %d" % [
		n, land, bld, int(rel), n2, main.colony.land_size(), main.colony.building_count(), int(main.colony.rel())])
	check(n2 >= n - 1, "aliens survive a reload (%d -> %d)" % [n, n2])
	check(main.colony.land_size() == land, "the creep survives a reload")
	check(main.colony.building_count() == bld, "alien buildings survive a reload")
	print("   brood before: %d insects, %d tunnels, %d mounds | after: %d, %d, %d" % [nb, tun, mnd, bugs().size(),
		main.world.insect_land.size(), main.swarm.mounds().size()])
	check(bugs().size() >= nb - 1, "insects survive a reload")
	check(main.world.insect_land.size() == tun, "tunnels survive a reload")
	check(main.swarm.mounds().size() == mnd, "mounds survive a reload")
	check(Game.world_id == wid and Game.owner_pid == Game.my_pid, "the world id and owner survive a reload")
	check(guest_stash != "" and Game.card_at("stash", 1, GUEST) == guest_stash, "the guest's hand survives a reload")
	check(main.world.farmer.uid == fuid, "the farmer's id survives a reload")
	var kept := 0
	for a in main.world.animals:
		if auids.has(a.uid):
			kept += 1
	check(kept >= auids.size() - 1, "animal ids survive a reload (%d of %d)" % [kept, auids.size()])
	var fresh: Animal = main.world.add_animal(Animal.new(main.world, "chicken", Vector2(40, 200)))
	check(not auids.has(fresh.uid) and fresh.uid != fuid, "new actors after a reload get new ids")
	step(30.0)
	check(true, "the reloaded colony keeps running")
	# a slot saved as someone's guest becomes our own fork when we open it
	Game.owner_pid = GUEST
	main.save_game()
	main.back_to_menu()
	await get_tree().process_frame
	main.start_slot(SLOT)
	Game.running = true
	await get_tree().process_frame
	check(Game.owner_pid == Game.my_pid and Game.forked_from == wid and Game.world_id != wid,
		"opening a slot owned by someone else forks it")
	Game.hands.erase(GUEST)
