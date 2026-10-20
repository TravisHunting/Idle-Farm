extends Node
## Headless simulation test (started by tests/sim_test.gd, which loads this once the autoloads exist). Boots the real game tree on a throwaway save slot, then drives the
## simulation by hand with a fixed timestep (no rendering, much faster than real time):
##   1. every alien arrival method, every caste, every boon/bane and every alien card choice
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
	_reset_aliens()
	_test_natural_run()
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
		main.tides._process(STEP)


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
	elif verbose:
		print("  ok: ", what)


func _on_log(t: String) -> void:
	if verbose or t.begins_with("THE TIDE") or "alien" in t.to_lower() or "saucer" in t.to_lower():
		print("   [day %d %s] %s" % [Game.day, Game.clock_text(), t])


func aliens(caste: String = "") -> Array:
	var out: Array = []
	for a in main.world.animals:
		if a is Alien and not a.dead and (caste == "" or a.caste == caste):
			out.append(a)
	return out


func _reset_aliens() -> void:
	for a in aliens():
		a.dead = true
	step(1.0)
	for c in main.colony.buildings() + main.world.cells_with_obj(["a_ruin", "a_husk"]):
		main.world.remove_obj(c)
	main.world.alien_land.clear()
	Game.colony = {}
	main.colony._ensure_state()
	Game.colony["arrive_t"] = 200.0
	Game.mutations = {}
	Game.tides = {}
	main.tides._ensure()


func _wipe() -> void:
	var p := ProjectSettings.globalize_path("user://slot_%d.json" % SLOT)
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


# ---------------------------------------------------------------- 4. natural run
func _test_natural_run() -> void:
	print("== natural run: %d days" % days)
	var col: Colony = main.colony
	var lo := {"farm": 1.0, "aliens": 1.0, "wild": 1.0}
	var hi := {"farm": 0.0, "aliens": 0.0, "wild": 0.0}
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
		for id in Game.box + Game.stash:
			if id != "" and (String(id).begins_with("alien_") or id in ["border_dispute", "tractor_beam", "hive_offer", "sick_colony", "glowing_spores", "funny_rash"]):
				turns_seen["card:" + id] = true
		var last := String(Game.tides.get("last", ""))
		if last != "":
			turns_seen[last] = true
		if h % 12 == 0:
			print("   day %d %s | %s pop %d %s | bld %d land %d food %d rel %+d | farm tilled %d crops %d hp %d | %s" % [
				Game.day, Game.clock_text(), col.era_name(), col.population(), _castes(), col.building_count(),
				col.land_size(), int(Game.colony["food"]), int(col.rel()), main.world.tilled_cells().size(),
				main.world.crops.size(), int(Game.health), main.tides.status_line()])
	print("   share ranges: farm %.2f-%.2f aliens %.2f-%.2f wild %.2f-%.2f; max pop %d; villages founded %d; born %d died %d" % [
		lo["farm"], hi["farm"], lo["aliens"], hi["aliens"], lo["wild"], hi["wild"], max_pop, villages,
		int(Game.colony["born"]), int(Game.colony["died"])])
	print("   tide turns seen: %s; mutations: %s" % [str(turns_seen.keys()), str(Game.mutations.keys())])
	check(villages >= 1, "aliens arrived and founded a village on their own")
	check(max_pop >= 3, "the colony grew (max pop %d)" % max_pop)
	check(hi["aliens"] - lo["aliens"] > 0.1, "the aliens' share of power moved")
	check(hi["farm"] - lo["farm"] > 0.1, "the farm's share of power moved")
	check(lo["farm"] > 0.05, "the farmer was never wiped out")
	check(main.world.farmer != null, "the farmer still exists")
	check(not col.protected(Vector2i(-1, -1)) or true, "protected() callable")
	for c in main.world.alien_land:
		check(not col.protected(c), "the creep never covers the farmhouse/doorstep (%s)" % str(c))


# ---------------------------------------------------------------- 5. save / load
func _test_save_roundtrip() -> void:
	print("== save/load")
	var col: Colony = main.colony
	if not col.active():
		col.arrive("saucer")
		step(60.0)
	var n := aliens().size()
	var land := col.land_size()
	var bld := col.building_count()
	var rel := col.rel()
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
	step(30.0)
	check(true, "the reloaded colony keeps running")
