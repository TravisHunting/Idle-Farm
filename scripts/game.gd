extends Node
## Game (autoload): global state + data tables.
## Owns: economy, level, clock/day, weather value, the hand of choice cards (drip feed),
## weirdness, relics, unlocked crops, buffs, farmer stats, inventory, the message log,
## pending (delayed) card consequences, and (de)serialisation of all of that.
## World/grid state is serialised by World; Main glues the two into one save slot file.
## Card *content* lives in deck.gd; card *logic* (requirements/effects) in cards.gd.

signal log_added(text: String)
signal cards_changed
signal card_arrived(id: String)
signal draw_requested
signal weather_changed(w: String)
signal coins_changed
signal new_day(day: int)

const SLOT_COUNT := 3
const SETTINGS_PATH := "user://settings.json"
const DAY_LENGTH := 480.0            # real seconds per in-game day
const HAND_CAP := 16
const CARD_INTERVAL := Vector2(40.0, 80.0)
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
## relic = only appears through cards (level 99 so he never builds it).
const STRUCTS := {
	"fence":     {"name": "fence",     "cost": 4,  "level": 1, "max": 14, "solid": true,  "movable": false, "hp": 60},
	"scarecrow": {"name": "scarecrow", "cost": 25, "level": 1, "max": 2,  "solid": true,  "movable": true,  "hp": 80},
	"flowerbed": {"name": "flower bed", "cost": 8, "level": 1, "max": 4,  "solid": false, "movable": true,  "hp": 40},
	"bench":     {"name": "bench",     "cost": 15, "level": 1, "max": 1,  "solid": true,  "movable": true,  "hp": 60},
	"sign":      {"name": "farm sign", "cost": 6,  "level": 1, "max": 1,  "solid": true,  "movable": true,  "hp": 50},
	"well":      {"name": "well",      "cost": 45, "level": 2, "max": 1,  "solid": true,  "movable": false, "hp": 200},
	"lamp":      {"name": "lamp post", "cost": 30, "level": 2, "max": 3,  "solid": true,  "movable": true,  "hp": 80},
	"coop":      {"name": "chicken coop", "cost": 90, "level": 2, "max": 1, "solid": true, "movable": false, "hp": 150},
	"beehive":   {"name": "beehive",   "cost": 60, "level": 3, "max": 2,  "solid": true,  "movable": true,  "hp": 60},
	"rod":       {"name": "lightning rod", "cost": 55, "level": 3, "max": 1, "solid": true, "movable": false, "hp": 999},
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

const WEATHER_NAMES := {"sunny": "Sunny", "cloudy": "Cloudy", "rain": "Rain", "storm": "Storm", "heat": "Heatwave"}

var running := false     # false while the welcome screen is up
var slot := 1
var coins := 25
var total_earned := 0
var day := 1
var time_of_day := 0.27
var weather := "sunny"
var hand: Array = []     # choice-card ids waiting to be played
var card_timer := 0.0
var next_card_in := 12.0
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
var settings := {"dock": "right"}
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
	hand = []
	relics = {}
	unlocked = {}
	pending = []
	seen = {}
	log_lines = []


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
	if hand.size() < HAND_CAP:
		card_timer += d
		if card_timer >= next_card_in:
			card_timer = 0.0
			next_card_in = randf_range(CARD_INTERVAL.x, CARD_INTERVAL.y)
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
	return 4 + level() * 3


func crop_unlocked(id: String) -> bool:
	return CROPS[id]["level"] <= level() or unlocked.has(id)


func add_item(id: String, n: int = 1) -> void:
	inventory[id] = maxi(0, int(inventory.get(id, 0)) + n)
	if inventory[id] == 0:
		inventory.erase(id)


func item_count(id: String) -> int:
	return int(inventory.get(id, 0))


func inventory_count() -> int:
	var n := 0
	for k in inventory:
		n += int(inventory[k])
	return n


func item_price(id: String) -> int:
	if CROPS.has(id):
		return CROPS[id]["price"]
	return ITEM_PRICES.get(id, 1)


func inventory_value(mult: float = 1.0) -> int:
	var v := 0.0
	for k in inventory:
		v += item_price(k) * int(inventory[k]) * mult
	return int(v)


# ---------------------------------------------------------------- cards / weird / relics
func add_card(id: String) -> bool:
	if hand.size() >= HAND_CAP or id == "":
		return false
	hand.append(id)
	seen[id] = int(seen.get(id, 0)) + 1
	cards_changed.emit()
	card_arrived.emit(id)
	return true


func remove_card(id: String) -> void:
	var i := hand.find(id)
	if i >= 0:
		hand.remove_at(i)
		stats["cards"] = int(stats["cards"]) + 1
		cards_changed.emit()


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
		"weather": weather, "hand": hand, "card_timer": card_timer, "next_card_in": next_card_in,
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
	hand = []
	for id in d.get("hand", []):
		hand.append(String(id))
	card_timer = float(d.get("card_timer", 0.0))
	next_card_in = float(d.get("next_card_in", 30.0))
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
