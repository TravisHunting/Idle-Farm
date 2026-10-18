extends Node
## Game (autoload): global state + data tables.
## Owns: economy, level, clock/day, weather value, the card box + stash (timed arrivals),
## weirdness, relics, unlocked crops, buffs, farmer stats, inventory, the message log,
## pending (delayed) card consequences, and (de)serialisation of all of that.
## World/grid state is serialised by World; Main glues the two into one save slot file.
## Card *content* lives in deck.gd; card *logic* (requirements/effects) in cards.gd.

signal log_added(text: String)
signal cards_changed
signal card_arrived(id: String)
signal card_trashed(id: String)
signal draw_requested
signal weather_changed(w: String)
signal coins_changed
signal new_day(day: int)

const SLOT_COUNT := 3
const SETTINGS_PATH := "user://settings.json"
const DAY_LENGTH := 480.0            # real seconds per in-game day
const BOX_SIZE := 3                  # new cards enter the box on the left, the far-right one is trashed
const STASH_SIZE := 3                # cards the player keeps safe
const CARD_MINUTES := [1, 2, 3, 5, 10, 15, 20, 30, 60]   # settings choices for the arrival cadence
const DEFAULT_CARD_MINUTES := 10
const LEVEL_THRESHOLDS := [0, 80, 250, 600, 1300, 2600, 5000, 9000, 15000]
const OFFLINE_CAP := 8.0 * 3600.0

## grow = seconds of *watered* growth to ripen. special = only via cards (unlock).
const CROPS := {
	"turnip":     {"name": "Turnip",     "grow": 90.0,  "price": 8,   "seed": 2,  "level": 1},
	"sunflower":  {"name": "Sunflower",  "grow": 120.0, "price": 11,  "seed": 3,  "level": 1},
	"carrot":     {"name": "Carrot",     "grow": 140.0, "price": 14,  "seed": 4,  "level": 1},
	"wheat":      {"name": "Wheat",      "grow": 200.0, "price": 22,  "seed": 6,  "level": 2},
	"pumpkin":    {"name": "Pumpkin",    "grow": 320.0, "price": 48,  "seed": 12, "level": 3},
	"glowshroom": {"name": "Glowshroom", "grow": 130.0, "price": 30,  "seed": 5,  "level": 99},
	"moonflower": {"name": "Moonflower", "grow": 200.0, "price": 45,  "seed": 6,  "level": 99},
	"starfruit":  {"name": "Starfruit",  "grow": 260.0, "price": 95,  "seed": 15, "level": 99},
	"melon":      {"name": "Golden Melon", "grow": 240.0, "price": 150, "seed": 999, "level": 99},
}
const ITEM_PRICES := {"egg": 6, "ore": 30, "wood": 3, "stone": 1, "honey": 12}
const ITEM_NAMES := {"egg": "egg", "ore": "ore", "wood": "wood", "stone": "stone", "honey": "honey"}

## Things the farmer builds by himself. solid = blocks walking. movable = can be rearranged.
## mats = building materials (from clearing the overgrowth) used on top of the coin cost.
## relic = only appears through cards (level 99 so he never builds it).
const STRUCTS := {
	"fence":     {"name": "fence",     "cost": 0,  "mats": {"wood": 1}, "level": 1, "max": 40, "solid": true,  "movable": false, "hp": 60},
	"scarecrow": {"name": "scarecrow", "cost": 20, "mats": {"wood": 2}, "level": 1, "max": 3,  "solid": true,  "movable": true,  "hp": 80},
	"flowerbed": {"name": "flower bed", "cost": 6, "level": 1, "max": 6,  "solid": false, "movable": true,  "hp": 40},
	"bench":     {"name": "bench",     "cost": 4,  "mats": {"wood": 3}, "level": 1, "max": 2,  "solid": true,  "movable": true,  "hp": 60},
	"sign":      {"name": "farm sign", "cost": 2,  "mats": {"wood": 2}, "level": 1, "max": 1,  "solid": true,  "movable": true,  "hp": 50},
	"compost":   {"name": "compost heap", "cost": 0, "mats": {"wood": 4}, "level": 1, "max": 1, "solid": true, "movable": false, "hp": 60},
	"well":      {"name": "well",      "cost": 30, "mats": {"stone": 6}, "level": 2, "max": 1,  "solid": true,  "movable": false, "hp": 200},
	"lamp":      {"name": "lamp post", "cost": 25, "level": 2, "max": 3,  "solid": true,  "movable": true,  "hp": 80},
	"coop":      {"name": "chicken coop", "cost": 60, "mats": {"wood": 8}, "level": 2, "max": 1, "solid": true, "movable": false, "hp": 150},
	"beehive":   {"name": "beehive",   "cost": 50, "level": 3, "max": 2,  "solid": true,  "movable": true,  "hp": 60},
	"rod":       {"name": "lightning rod", "cost": 55, "level": 3, "max": 1, "solid": true, "movable": false, "hp": 999},
	"altar":     {"name": "dark altar", "cost": 0, "level": 99, "max": 1, "solid": true, "movable": false, "hp": 999},
	"totem":     {"name": "dark totem", "cost": 0, "level": 99, "max": 6, "solid": true, "movable": false, "hp": 999},
	"idol":      {"name": "stone idol", "cost": 0, "level": 99, "max": 1, "solid": true, "movable": false, "hp": 999},
	"obelisk":   {"name": "black obelisk", "cost": 0, "level": 99, "max": 1, "solid": true, "movable": false, "hp": 999},
	"stones":    {"name": "standing stones", "cost": 0, "level": 99, "max": 1, "solid": true, "movable": false, "hp": 999},
	"saucer":    {"name": "crashed saucer", "cost": 0, "level": 99, "max": 1, "solid": true, "movable": false, "hp": 999},
}

## Relics: permanent oddities won through cards. Passive effects are implemented in cards.gd
## (daily/nightly hooks) plus a few checks elsewhere (search for Game.has_relic).
const RELICS := {
	"tome":       {"name": "Fleshy Tome", "icon": "r_tome", "desc": "Whispers at night. Weirdness grows daily."},
	"homunculus": {"name": "Wizened Homunculus", "icon": "r_homunculus", "desc": "Waters dry crops. Steals eggs."},
	"black_cat":  {"name": "Black Cat", "icon": "r_cat", "desc": "Lucky finds are far more common."},
	"goat":       {"name": "Many-Eyed Goat", "icon": "r_goat", "desc": "Eats weeds. Watches. Always watches."},
	"crow_crown": {"name": "Crown of Crows", "icon": "r_crown", "desc": "Crows no longer raid the crops."},
	"lantern":    {"name": "Grandpa's Lantern", "icon": "r_lantern", "desc": "Foxes stay away at night."},
	"idol":       {"name": "Stone Idol", "icon": "r_idol", "desc": "Nearby crops grow faster."},
	"obelisk":    {"name": "Black Obelisk", "icon": "r_obelisk", "desc": "Draws lightning. Hums. +Weird daily."},
	"stones":     {"name": "Standing Stones", "icon": "r_stones", "desc": "The farmer is happier."},
	"saucer":     {"name": "Crashed Saucer", "icon": "r_saucer", "desc": "Yields alien ore every day."},
	"star_map":   {"name": "Star Map", "icon": "r_starmap", "desc": "Starfruit can be grown."},
	"horseshoe":  {"name": "Witch's Horseshoe", "icon": "r_horseshoe", "desc": "+1 Lucky Charm every morning."},
	"bone_flute": {"name": "Bone Flute", "icon": "r_flute", "desc": "Scares off all critters each dawn."},
	"cursed_coin": {"name": "Cursed Coin", "icon": "r_coin", "desc": "Pays out daily. Sours the mood."},
	"living_scarecrow": {"name": "Living Scarecrow", "icon": "r_scarecrow", "desc": "Scarecrows chase off pests."},
}

## Building materials: kept for building (fences, paths...) rather than sold.
const MATERIALS := ["wood", "stone"]

## Permanent farmer abilities won through cards (hooks in farmer.gd / world.gd / cards.gd).
const PERKS := {
	"strong_arms": {"name": "Strong Arms", "desc": "Clears overgrowth and chops twice as fast."},
	"green_thumb": {"name": "Green Thumb", "desc": "Crops grow 30% faster."},
	"quick_feet":  {"name": "Quick Feet", "desc": "Walks 35% faster."},
	"tough":       {"name": "Tough as Boots", "desc": "Takes half damage."},
	"big_can":     {"name": "Giant Watering Can", "desc": "Watering soaks the tiles around too."},
	"haggler":     {"name": "Silver Tongue", "desc": "Produce sells for 30% more."},
	"carpenter":   {"name": "Carpenter", "desc": "Builds twice as fast; fences and paths are free."},
	"early_bird":  {"name": "Early Bird", "desc": "Rests twice as fast."},
	"iron_gut":    {"name": "Iron Gut", "desc": "Immune to poison."},
	"pied_piper":  {"name": "Pied Piper", "desc": "Critters flee when he gets close. No bites."},
}

## Townsfolk who befriend the farm through cards. Each drops by every morning with a gift.
const FRIENDS := {
	"gus":    {"name": "Farmer Gus", "icon": "r_gus", "sprite": "v_villager", "tint": "f7c6a0", "desc": "Plants a few turnips every morning."},
	"betty":  {"name": "Betty the Baker", "icon": "r_pie", "sprite": "v_villager", "tint": "f19ec2", "desc": "Brings pie each morning: energy & mood."},
	"smith":  {"name": "Old Smith", "icon": "r_anvil", "sprite": "v_villager", "tint": "94b0c2", "desc": "Mends every building and brings stone."},
	"mayor":  {"name": "The Mayor", "icon": "r_sash", "sprite": "v_suit", "tint": "ffcd75", "desc": "Pays a daily farm subsidy."},
	"kids":   {"name": "Village Kids", "icon": "r_kids", "sprite": "v_villager", "tint": "a7f070", "desc": "Pull up weeds and brush every morning."},
	"doc":    {"name": "Doc Hollis", "icon": "r_doc", "sprite": "v_villager", "tint": "f4f4f4", "desc": "Free house calls. Heals daily."},
}

## The farmer's personality, rolled when a farm is founded.
const QUIRKS := {
	"tidy":      {"name": "Tidy", "desc": "Can't stand overgrowth; clears first."},
	"artsy":     {"name": "Artsy", "desc": "Plants his fields in silly shapes."},
	"builder":   {"name": "Handy", "desc": "Loves building fences and paths."},
	"dreamer":   {"name": "Dreamer", "desc": "Wanders and chats a lot."},
	"sunny":     {"name": "Sunflower Nut", "desc": "Plants sunflowers whenever he can."},
	"thrifty":   {"name": "Thrifty", "desc": "Sells only when the cart is full."},
}

const TOTEMS_MAX := 6

const WEATHER_NAMES := {"sunny": "Sunny", "cloudy": "Cloudy", "rain": "Rain", "storm": "Storm", "heat": "Heatwave"}

var running := false     # false while the welcome screen is up
var slot := 1
var coins := 25
var total_earned := 0
var day := 1
var time_of_day := 0.27
var weather := "sunny"
var box: Array = ["", "", ""]     # card box: new cards push in from the left, the right one is trashed
var stash: Array = ["", "", ""]   # cards the player keeps safe ("" = empty slot)
var card_timer := 0.0             # seconds since the last arrival
var perks := {}          # id -> true (farmer abilities)
var friends := {}        # id -> true (townsfolk)
var totems := 0          # dark totems found (0..TOTEMS_MAX)
var played := {}         # card id -> "a"/"b" (last choice made)
var quirk := ""          # the farmer's personality
var farm_name := ""
var inventory := {}
var buffs := {}          # name -> seconds left
var charms := 0          # Lucky Charm stacks
var health := 100.0
var energy := 100.0
var mood := 70.0
var poison := 0.0        # seconds of poison left
var weird := 0.0         # 0..100, the farm's strangeness
var relics := {}         # id -> true
var unlocked := {}       # special crop id -> true
var favor_crop := ""     # the farmer prefers planting this (while buff "favor" lasts)
var pending: Array = []  # [{t: seconds, fx: [...], note: ""}]
var seen := {}           # card id -> times drawn
var log_lines: Array = []
var stats := {"harvested": 0, "shooed": 0, "cards": 0, "faints": 0, "built": 0}
var settings := {"dock": "right", "card_minutes": DEFAULT_CARD_MINUTES}
var time_scale := 1.0    # debug speed-up
var play_seconds := 0.0
var _defaults := {}


func _ready() -> void:
	_defaults = to_dict().duplicate(true)
	_load_settings()


## Back to a brand-new game.
func reset() -> void:
	var keep := settings.duplicate()
	from_dict(_defaults.duplicate(true))
	settings = keep
	stats = {"harvested": 0, "shooed": 0, "cards": 0, "faints": 0, "built": 0}
	box = ["", "", ""]
	stash = ["", "", ""]
	relics = {}
	unlocked = {}
	pending = []
	seen = {}
	log_lines = []
	perks = {}
	friends = {}
	totems = 0
	played = {}


func _process(delta: float) -> void:
	if not running:
		return
	var d := delta * time_scale
	play_seconds += delta
	var prev := time_of_day
	time_of_day += d / DAY_LENGTH
	if time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
		add_log("Day %d begins." % day)
		new_day.emit(day)
	if prev < 0.25 and time_of_day >= 0.25:
		add_log("The sun rises.")
	card_timer += d
	if card_timer >= card_interval():
		card_timer = 0.0
		draw_requested.emit()
	for k in buffs.keys():
		buffs[k] -= d
		if buffs[k] <= 0.0:
			buffs.erase(k)


# ---------------------------------------------------------------- time
func is_night() -> bool:
	return time_of_day < 0.23 or time_of_day > 0.87


func is_evening() -> bool:
	return time_of_day > 0.75 and time_of_day <= 0.87


func clock_text() -> String:
	var mins := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [mins / 60, (mins % 60) / 10 * 10]


## 0 = full day, 1 = deepest night. Smooth dusk/dawn.
func darkness() -> float:
	var t := time_of_day
	if t >= 0.27 and t <= 0.80:
		return 0.0
	if t > 0.80 and t <= 0.90:
		return (t - 0.80) / 0.10
	if t > 0.20 and t < 0.27:
		return 1.0 - (t - 0.20) / 0.07
	return 1.0


func set_weather(w: String) -> void:
	if w == weather:
		return
	weather = w
	weather_changed.emit(w)


# ---------------------------------------------------------------- economy
func level() -> int:
	var lv := 1
	for i in LEVEL_THRESHOLDS.size():
		if total_earned >= LEVEL_THRESHOLDS[i]:
			lv = i + 1
	return lv


func level_progress() -> float:
	var lv := level()
	if lv >= LEVEL_THRESHOLDS.size():
		return 1.0
	var a: int = LEVEL_THRESHOLDS[lv - 1]
	var b: int = LEVEL_THRESHOLDS[lv]
	return clampf(float(total_earned - a) / float(b - a), 0.0, 1.0)


func add_coins(n: int) -> void:
	var before := level()
	coins = maxi(0, coins + n)
	if n > 0:
		total_earned += n
	coins_changed.emit()
	if level() > before:
		add_log("Farm level %d! New things unlocked." % level())


## Card coin rewards scale up with farm level.
func scaled_reward(n: int) -> int:
	return int(n * (1.0 + 0.2 * (level() - 1)))


func max_tilled() -> int:
	return 8 + level() * 5


func crop_unlocked(id: String) -> bool:
	return CROPS[id]["level"] <= level() or unlocked.has(id)


func add_item(id: String, n: int = 1) -> void:
	inventory[id] = maxi(0, int(inventory.get(id, 0)) + n)
	if inventory[id] == 0:
		inventory.erase(id)


func item_count(id: String) -> int:
	return int(inventory.get(id, 0))


## Sellable goods only (building materials are kept for building).
func inventory_count() -> int:
	var n := 0
	for k in inventory:
		if not k in MATERIALS:
			n += int(inventory[k])
	return n


func item_price(id: String) -> int:
	if CROPS.has(id):
		return CROPS[id]["price"]
	return ITEM_PRICES.get(id, 1)


func inventory_value(mult: float = 1.0) -> int:
	var v := 0.0
	if has_perk("haggler"):
		mult *= 1.3
	for k in inventory:
		if not k in MATERIALS:
			v += item_price(k) * int(inventory[k]) * mult
	return int(v)


## Sells all produce (not materials); returns coins earned.
func sell_goods(mult: float = 1.0) -> int:
	var v := inventory_value(mult)
	for k in inventory.keys():
		if not k in MATERIALS:
			inventory.erase(k)
	if v > 0:
		add_coins(v)
	return v


func can_afford(def: Dictionary) -> bool:
	if coins < int(def.get("cost", 0)):
		return false
	if has_perk("carpenter") and int(def.get("cost", 0)) == 0:
		return true
	var m: Dictionary = def.get("mats", {})
	for k in m:
		if item_count(k) < int(m[k]):
			return false
	return true


func pay_for(def: Dictionary) -> void:
	add_coins(-int(def.get("cost", 0)))
	if has_perk("carpenter") and int(def.get("cost", 0)) == 0:
		return
	var m: Dictionary = def.get("mats", {})
	for k in m:
		add_item(k, -int(m[k]))


# ---------------------------------------------------------------- cards / weird / relics
func card_interval() -> float:
	return float(settings.get("card_minutes", DEFAULT_CARD_MINUTES)) * 60.0


func next_card_left() -> float:
	return maxf(0.0, card_interval() - card_timer)


## A new card enters the box on the left and pushes the others right (into the first gap);
## with no gap, the far-right card falls out and is trashed.
func add_card(id: String) -> bool:
	if id == "":
		return false
	var gap := box.find("")
	if gap < 0:
		var gone: String = box[BOX_SIZE - 1]
		gap = BOX_SIZE - 1
		add_log("A card fell out of the box: %s." % gone_title(gone))
		card_trashed.emit(gone)
	for i in range(gap, 0, -1):
		box[i] = box[i - 1]
	box[0] = id
	seen[id] = int(seen.get(id, 0)) + 1
	cards_changed.emit()
	card_arrived.emit(id)
	return true


## Set by cards.gd so Game can name a card without knowing the deck.
var title_of: Callable


func gone_title(id: String) -> String:
	return String(title_of.call(id)) if title_of.is_valid() else id


func has_card(id: String) -> bool:
	return id != "" and (id in box or id in stash)


func card_at(where: String, i: int) -> String:
	var arr: Array = box if where == "box" else stash
	return String(arr[i]) if i >= 0 and i < arr.size() else ""


## Empties a slot after a card was played.
func take_card(where: String, i: int) -> void:
	var arr: Array = box if where == "box" else stash
	if i >= 0 and i < arr.size() and arr[i] != "":
		arr[i] = ""
		stats["cards"] = int(stats["cards"]) + 1
		cards_changed.emit()


## Moves (or swaps) a card between any two slots of the box/stash.
func move_card(from_where: String, fi: int, to_where: String, ti: int) -> void:
	if from_where == to_where and fi == ti:
		return
	var a: Array = box if from_where == "box" else stash
	var b: Array = box if to_where == "box" else stash
	if fi < 0 or ti < 0 or fi >= a.size() or ti >= b.size():
		return
	var tmp: String = b[ti]
	b[ti] = a[fi]
	a[fi] = tmp
	cards_changed.emit()


func card_count() -> int:
	var n := 0
	for id in box + stash:
		if id != "":
			n += 1
	return n


func has_perk(id: String) -> bool:
	return perks.has(id)


func add_weird(n: float) -> void:
	var before := int(weird / 10.0)
	weird = clampf(weird + n, 0.0, 100.0)
	if int(weird / 10.0) > before:
		add_log("The farm feels... stranger. (Weirdness %d)" % int(weird))


func has_relic(id: String) -> bool:
	return relics.has(id)


# ---------------------------------------------------------------- misc
func add_log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 40:
		log_lines.pop_front()
	log_added.emit(text)


func buff(name_: String) -> bool:
	return buffs.has(name_)


func add_buff(name_: String, seconds: float) -> void:
	buffs[name_] = maxf(float(buffs.get(name_, 0.0)), seconds)


func bump(stat: String, n: int = 1) -> void:
	stats[stat] = int(stats.get(stat, 0)) + n


func save_settings() -> void:
	var fa := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(settings))


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(p) == TYPE_DICTIONARY:
		for k in p:
			settings[k] = p[k]


func slot_path(n: int) -> String:
	return "user://slot_%d.json" % n


func to_dict() -> Dictionary:
	return {
		"coins": coins, "total_earned": total_earned, "day": day, "time_of_day": time_of_day,
		"weather": weather, "box": box, "stash": stash, "card_timer": card_timer,
		"perks": perks, "friends": friends, "totems": totems, "played": played, "quirk": quirk,
		"farm_name": farm_name,
		"inventory": inventory, "buffs": buffs, "charms": charms, "health": health, "energy": energy,
		"mood": mood, "poison": poison, "stats": stats, "log": log_lines, "weird": weird,
		"relics": relics, "unlocked": unlocked, "favor_crop": favor_crop, "pending": pending,
		"seen": seen, "play_seconds": play_seconds,
	}


func from_dict(d: Dictionary) -> void:
	coins = int(d.get("coins", coins))
	total_earned = int(d.get("total_earned", total_earned))
	day = int(d.get("day", day))
	time_of_day = float(d.get("time_of_day", time_of_day))
	weather = String(d.get("weather", weather))
	box = _slots(d.get("box", d.get("hand", [])), BOX_SIZE)
	stash = _slots(d.get("stash", []), STASH_SIZE)
	card_timer = float(d.get("card_timer", 0.0))
	perks = d.get("perks", {})
	friends = d.get("friends", {})
	totems = int(d.get("totems", 0))
	played = d.get("played", {})
	quirk = String(d.get("quirk", ""))
	farm_name = String(d.get("farm_name", ""))
	inventory = {}
	var inv: Dictionary = d.get("inventory", {})
	for k in inv:
		inventory[k] = int(inv[k])
	buffs = d.get("buffs", {})
	charms = int(d.get("charms", 0))
	health = float(d.get("health", 100.0))
	energy = float(d.get("energy", 100.0))
	mood = float(d.get("mood", 70.0))
	poison = float(d.get("poison", 0.0))
	weird = float(d.get("weird", 0.0))
	relics = d.get("relics", {})
	unlocked = d.get("unlocked", {})
	favor_crop = String(d.get("favor_crop", ""))
	pending = d.get("pending", [])
	seen = d.get("seen", {})
	play_seconds = float(d.get("play_seconds", 0.0))
	var s: Dictionary = d.get("stats", {})
	for k in s:
		stats[k] = int(s[k])
	log_lines = d.get("log", [])


func _slots(src: Array, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(String(src[i]) if i < src.size() and src[i] != null else "")
	return out
