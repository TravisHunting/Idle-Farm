extends Node
## Card impact audit (started by tests/impact_test.gd). Boots the real game on throwaway slot 9, lets
## the farm settle for a day, then plays N random card choices (effects applied directly, so every
## card can be measured whatever its requirements). For each one it measures:
##   card     tiles the choice changed at once (ground, object, crop type / death, creep, tunnels, bare)
##            + actors it added
##   ambient  tiles the rest of the simulation changed in the next 5 in-game minutes
##   kept     share of the card's tiles still as the card left them one in-game day later
## and prints the averages, the weakest choices and the share of choices with a real cost.
## Options: trials=N (default 40), seed=N, warmup=seconds (default one day), verbose.
## Exit code 0 always (it reports, it doesn't judge) unless the game fails to boot.

const SLOT := 9
const STEP := 0.25
const AMBIENT_WINDOW := 300.0

var main: Node
var trials := 40
var warmup := Game.DAY_LENGTH
var verbose := false
var _parts := {}   # what the ambient changes were: ground / obj:<type> / crop / land
var _hush_sum := 0.0   # tiles the rest of the farm changed during each card's hush


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("trials="):
			trials = int(a.substr(7))
		elif a.begins_with("seed="):
			seed(int(a.substr(5)))
		elif a.begins_with("warmup="):
			warmup = float(a.substr(7))
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
	print("== farm: %s (%s), quirk %s" % [Game.farm_name, main.world.biome, Game.quirk])
	step(warmup)

	var pool: Array = []
	for c in Deck.CARDS:
		if int(c.get("rarity", 1)) > 0:
			pool.append(c)
	pool.shuffle()
	var rows: Array = []
	for i in mini(trials, pool.size()):
		var c: Dictionary = pool[i]
		var which: String = ["a", "b"].pick_random()
		rows.append(_measure(c, which))

	var card_sum := 0.0
	var amb_sum := 0.0
	var kept_sum := 0.0
	var kept_n := 0
	var zero := 0
	for r in rows:
		card_sum += float(r["card"])
		amb_sum += float(r["ambient"])
		if int(r["tiles"]) > 0:
			kept_sum += float(r["kept"])
			kept_n += 1
		if int(r["card"]) == 0:
			zero += 1
	var n := maxf(1.0, rows.size())
	rows.sort_custom(func(a, b): return int(a["card"]) < int(b["card"]))
	print("== weakest choices (tiles + actors changed):")
	for r in rows.slice(0, 12):
		print("   %3d  %s / %s" % [r["card"], r["title"], r["label"]])
	print("== strongest choices:")
	for r in rows.slice(maxi(0, rows.size() - 6)):
		print("   %3d  %s / %s" % [r["card"], r["title"], r["label"]])
	var ambs: Array = rows.map(func(r): return int(r["ambient"]))
	ambs.sort()
	print("== ambient median %d per 5 min (cataclysms skew the mean)" % ambs[ambs.size() / 2])
	print("== MOMENT  card %.1f vs the rest of the farm %.1f during the %ds hush: the card is %d%% of what changes" \
		% [card_sum / n, _hush_sum / n, int(Game.HUSH_SECONDS), int(100.0 * card_sum / maxf(1.0, card_sum + _hush_sum))])
	var costs := _deck_costs()
	print("== IMPACT  card %.1f per choice | ambient %.1f per 5 min | ratio %.2f | kept after a day %d%% | no visible change %d/%d" \
		% [card_sum / n, amb_sum / n, (card_sum / n) / maxf(1.0, amb_sum / n), int(100.0 * kept_sum / maxf(1.0, kept_n)), zero, rows.size()])
	var parts: Array = _parts.keys()
	parts.sort_custom(func(a, b): return int(_parts[a]) > int(_parts[b]))
	var top: Array = []
	for p in parts.slice(0, 10):
		top.append("%s %d" % [p, _parts[p]])
	print("== AMBIENT by kind: " + ", ".join(top))
	print("== DECK    choices with a real cost: %d/%d (%d%%)" % [costs[0], costs[1], int(100.0 * costs[0] / maxf(1.0, costs[1]))])
	_wipe()
	get_tree().quit(0)


func _measure(c: Dictionary, which: String) -> Dictionary:
	var w: World = main.world
	var s0 := signature()
	var uids := {}
	for a in w.animals:
		uids[a.uid] = true
	main.cards.play_out(c[which].get("fx", []), c["title"], c[which]["label"], Color.WHITE)
	var s1 := signature()
	var changed := diff(s0, s1)
	var actors := 0
	for a in w.animals:
		if not uids.has(a.uid) and not a.dead:
			actors += 1
	# the card's own moment: the hush after it (Game.HUSH_SECONDS), while the spotlight is up
	step(Game.HUSH_SECONDS)
	var sh := signature()
	_hush_sum += diff(s1, sh).size()
	step(AMBIENT_WINDOW - Game.HUSH_SECONDS)
	var s2 := signature()
	var ambient := diff(s1, s2).size()
	for i in diff(s1, s2):
		var a: PackedStringArray = s1[i].split("|")
		var b: PackedStringArray = s2[i].split("|")
		for k in 4:
			if a[k] != b[k]:
				var part: String = ["ground", "object", "crop", "land"][k]
				if k == 1:
					part = "obj:" + (a[1] if a[1] != "" else b[1])
				elif k == 3:
					for j in 3:
						if a[3][j] != b[3][j]:
							part = ["creep", "tunnels", "bare"][j]
				_parts[part] = int(_parts.get(part, 0)) + 1
	step(Game.DAY_LENGTH - AMBIENT_WINDOW)
	var s3 := signature()
	var kept := 0
	for i in changed:
		if s3[i] == s1[i]:
			kept += 1
	var row := {"title": c["title"], "label": c[which]["label"], "card": changed.size() + actors, "tiles": changed.size(),
		"ambient": ambient, "kept": float(kept) / maxf(1.0, changed.size())}
	if verbose:
		print("   %-22s %-20s card %3d (+%d actors)  ambient %3d  kept %d%%" % [c["title"], c[which]["label"], changed.size(),
			actors, ambient, int(100.0 * row["kept"])])
	return row


## What a player can see on every tile (World.signature: no growth or wetness).
func signature() -> PackedStringArray:
	return main.world.signature()


func diff(a: PackedStringArray, b: PackedStringArray) -> Array:
	var out: Array = []
	for i in a.size():
		if a[i] != b[i]:
			out.append(i)
	return out


## [choices with a downside, all choices]: a cost, a risk, or something taken away.
func _deck_costs() -> Array:
	var with_cost := 0
	var total := 0
	for c in Deck.CARDS:
		if int(c.get("rarity", 1)) <= 0:
			continue
		for which in ["a", "b"]:
			total += 1
			if _has_cost(c[which].get("fx", [])):
				with_cost += 1
	return [with_cost, total]


func _has_cost(fx: Array) -> bool:
	for e in fx:
		match String(e[0]):
			"item", "heal", "energy", "mood", "charm", "chicken", "totem":
				if float(e[e.size() - 1]) < 0.0:
					return true
			"wither", "uproot", "take_ripe", "take_crop", "poison", "overgrow", "lose_relic", "lose_perk", "lose_friend", "demolish", "burn", "gamble", "lose_edict":
				return true
			"spawn":
				if String(e[1]) in ["crow", "rabbit", "fox", "boar", "snake", "wasps"]:
					return true
			"event":
				if String(e[1]) in ["crows", "rabbits", "fox", "boar", "snake", "wasps", "weeds"]:
					return true
			"alien", "brood":
				# a faction moving in, land given up, or relations / tempers souring
				if String(e[1]) in ["cede", "abduct", "bane", "mutate", "swarm", "sinkhole", "arrive"] \
						or (String(e[1]) == "rel" and float(e[2]) < 0.0) or (String(e[1]) in ["aggro", "temper"] and float(e[2]) > 0.0):
					return true
			"weather":
				if String(e[1]) in ["storm", "heat"]:
					return true
			"edict":
				return true   # every edict is a trade-off (see Game.EDICTS)
			"delay":
				if _has_cost(e[2]):
					return true
	return false


func step(seconds: float) -> void:
	for i in int(seconds / STEP):
		Game._process(STEP)
		main.world._process(STEP)
		main.director._process(STEP)
		main.cards._process(STEP)
		main.colony._process(STEP)
		main.swarm._process(STEP)
		main.tides._process(STEP)
		main.chores._process(STEP)
		main.edicts._process(STEP)


func _wipe() -> void:
	var p := ProjectSettings.globalize_path(Game.slot_path(SLOT))
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
