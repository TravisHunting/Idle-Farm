extends Node
## Game (autoload): global state + data tables.
## Owns: economy, level, clock/day, weather value, activity cards (drip feed), buffs,
## farmer stats, inventory, the message log, and (de)serialisation of all of that.
## World/grid state is serialised by World; Main glues the two into one save file.

signal log_added(text: String)
signal cards_changed
signal card_arrived(id: String)
signal weather_changed(w: String)
signal coins_changed

const SAVE_PATH := "user://idle_farm_save.json"
const DAY_LENGTH := 480.0            # real seconds per in-game day
const CARD_CAP := 24
const CARD_INTERVAL := Vector2(35.0, 75.0)
const LEVEL_THRESHOLDS := [0, 80, 250, 600, 1300, 2600, 5000, 9000, 15000]
const OFFLINE_CAP := 8.0 * 3600.0

## grow = seconds of *watered* growth to ripen.
const CROPS := {
	"turnip":  {"name": "Turnip",  "grow": 90.0,  "price": 8,   "seed": 2,  "level": 1},
	"carrot":  {"name": "Carrot",  "grow": 140.0, "price": 14,  "seed": 4,  "level": 1},
	"wheat":   {"name": "Wheat",   "grow": 200.0, "price": 22,  "seed": 6,  "level": 2},
	"pumpkin": {"name": "Pumpkin", "grow": 320.0, "price": 48,  "seed": 12, "level": 3},
	"melon":   {"name": "Golden Melon", "grow": 240.0, "price": 150, "seed": 0, "level": 99},
}
const ITEM_PRICES := {"egg": 6, "ore": 30, "wood": 3, "stone": 1, "honey": 12}

## Things the farmer builds by himself. solid = blocks walking. movable = can be rearranged.
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
}

## Activities (cards). weight = how often it is drawn.
const CARDS := {
	"rain":     {"name": "Rain Cloud",    "icon": "ic_rain",    "weight": 10, "desc": "Waters every crop and puts out fires."},
	"sun":      {"name": "Sunshine",      "icon": "ic_sun",     "weight": 8,  "desc": "Crops grow twice as fast for a while."},
	"shoo":     {"name": "Shoo!",         "icon": "ic_shoo",    "weight": 10, "desc": "Scares off every pest and predator."},
	"dog":      {"name": "Watchdog",      "icon": "dog",        "weight": 5,  "desc": "A loyal pup guards the farm for a day."},
	"soup":     {"name": "Hearty Soup",   "icon": "ic_soup",    "weight": 7,  "desc": "Heals the farmer and cures poison."},
	"coffee":   {"name": "Coffee",        "icon": "ic_coffee",  "weight": 8,  "desc": "Restores the farmer's energy."},
	"charm":    {"name": "Lucky Charm",   "icon": "ic_charm",   "weight": 5,  "desc": "Blocks the next harm to the farmer."},
	"fert":     {"name": "Fertilizer",    "icon": "ic_fert",    "weight": 6,  "desc": "Every crop jumps ahead in growth."},
	"gold":     {"name": "Golden Seed",   "icon": "crop_melon", "weight": 3,  "desc": "Plants a rare golden melon."},
	"coins":    {"name": "Lucky Coins",   "icon": "ic_coin",    "weight": 7,  "desc": "A little pile of coins appears."},
	"clear":    {"name": "Clear Skies",   "icon": "ic_clear",   "weight": 6,  "desc": "Ends bad weather. Mood up!"},
	"storm":    {"name": "Summon Storm",  "icon": "ic_storm",   "weight": 4,  "desc": "Chaos! Heavy rain... and lightning."},
	"meteor":   {"name": "Meteorite",     "icon": "ic_meteor",  "weight": 3,  "desc": "Crash a space rock. Ore inside!"},
	"bloom":    {"name": "Spring Bloom",  "icon": "flowerbed",  "weight": 6,  "desc": "Flowers burst up. Mood up."},
	"bees":     {"name": "Bee Swarm",     "icon": "ic_bees",    "weight": 4,  "desc": "Pollinates crops close to harvest."},
	"merchant": {"name": "Merchant",      "icon": "merchant",   "weight": 4,  "desc": "A trader buys produce at a premium."},
	"tree":     {"name": "Sapling",       "icon": "sapling",    "weight": 5,  "desc": "Plants an apple tree somewhere nice."},
	"critters": {"name": "Stir Critters", "icon": "rabbit",     "weight": 3,  "desc": "Chaos! Invite pests. Bounty per shoo."},
	"quake":    {"name": "Tremor",        "icon": "ic_quake",   "weight": 3,  "desc": "Shakes out all weeds... and rocks."},
}

const WEATHER_NAMES := {"sunny": "Sunny", "cloudy": "Cloudy", "rain": "Rain", "storm": "Storm", "heat": "Heatwave"}

var coins := 25
var total_earned := 0
var day := 1
var time_of_day := 0.27
var weather := "sunny"
var cards := {}
var card_timer := 0.0
var next_card_in := 15.0
var inventory := {}
var buffs := {}          # name -> seconds left ("sun", "dog", "bounty")
var charms := 0          # Lucky Charm stacks
var health := 100.0
var energy := 100.0
var mood := 70.0
var poison := 0.0        # seconds of poison left
var log_lines: Array = []
var stats := {"harvested": 0, "shooed": 0, "cards": 0, "faints": 0, "built": 0}
var settings := {"dock": "right"}
var time_scale := 1.0    # debug speed-up
var _defaults := {}


func _ready() -> void:
	_defaults = to_dict().duplicate(true)


## Back to a brand-new game (debug F5).
func reset() -> void:
	from_dict(_defaults.duplicate(true))
	stats = {"harvested": 0, "shooed": 0, "cards": 0, "faints": 0, "built": 0}


func _process(delta: float) -> void:
	var d := delta * time_scale
	var prev := time_of_day
	time_of_day += d / DAY_LENGTH
	if time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
		add_log("Day %d begins." % day)
	if prev < 0.25 and time_of_day >= 0.25:
		add_log("The sun rises.")
	if card_count() < CARD_CAP:
		card_timer += d
		if card_timer >= next_card_in:
			card_timer = 0.0
			next_card_in = randf_range(CARD_INTERVAL.x, CARD_INTERVAL.y)
			add_card(random_card())
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


func max_tilled() -> int:
	return 4 + level() * 3


func crop_unlocked(id: String) -> bool:
	return CROPS[id]["level"] <= level()


func add_item(id: String, n: int = 1) -> void:
	inventory[id] = int(inventory.get(id, 0)) + n


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


# ---------------------------------------------------------------- cards
func card_count() -> int:
	var n := 0
	for k in cards:
		n += int(cards[k])
	return n


func random_card() -> String:
	var total := 0
	for k in CARDS:
		total += int(CARDS[k]["weight"])
	var r := randi() % total
	for k in CARDS:
		r -= int(CARDS[k]["weight"])
		if r < 0:
			return k
	return "rain"


func add_card(id: String) -> bool:
	if card_count() >= CARD_CAP:
		return false
	cards[id] = int(cards.get(id, 0)) + 1
	cards_changed.emit()
	card_arrived.emit(id)
	return true


func take_card(id: String) -> bool:
	if int(cards.get(id, 0)) <= 0:
		return false
	cards[id] = int(cards[id]) - 1
	if cards[id] <= 0:
		cards.erase(id)
	stats["cards"] = int(stats["cards"]) + 1
	cards_changed.emit()
	return true


# ---------------------------------------------------------------- misc
func add_log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 40:
		log_lines.pop_front()
	log_added.emit(text)


func buff(name: String) -> bool:
	return buffs.has(name)


func add_buff(name: String, seconds: float) -> void:
	buffs[name] = maxf(float(buffs.get(name, 0.0)), seconds)


func bump(stat: String, n: int = 1) -> void:
	stats[stat] = int(stats.get(stat, 0)) + n


func to_dict() -> Dictionary:
	return {
		"coins": coins, "total_earned": total_earned, "day": day, "time_of_day": time_of_day,
		"weather": weather, "cards": cards, "card_timer": card_timer, "next_card_in": next_card_in,
		"inventory": inventory, "buffs": buffs, "charms": charms, "health": health, "energy": energy,
		"mood": mood, "poison": poison, "stats": stats, "settings": settings, "log": log_lines,
	}


func from_dict(d: Dictionary) -> void:
	coins = int(d.get("coins", coins))
	total_earned = int(d.get("total_earned", total_earned))
	day = int(d.get("day", day))
	time_of_day = float(d.get("time_of_day", time_of_day))
	weather = String(d.get("weather", weather))
	cards = {}
	var c: Dictionary = d.get("cards", {})
	for k in c:
		if CARDS.has(k):
			cards[k] = int(c[k])
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
	var s: Dictionary = d.get("stats", {})
	for k in s:
		stats[k] = int(s[k])
	var st: Dictionary = d.get("settings", {})
	for k in st:
		settings[k] = st[k]
	log_lines = d.get("log", [])
