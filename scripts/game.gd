extends Node
## Game (autoload): global state + data tables.
## Owns: the farmer's treasure chest (there is no money: produce is traded for trinkets and
## everything that happens leaves souvenirs; treasure found sets the farm level), clock/day, weather value, the card box + stash (timed arrivals),
## weirdness, relics, unlocked crops, buffs, farmer stats, inventory, the message log,
## pending (delayed) card consequences, and (de)serialisation of all of that.
## World/grid state is serialised by World; Main glues the two into one save slot file.
## Card *content* lives in deck.gd; card *logic* (requirements/effects) in cards.gd.

signal log_added(text: String)
signal cards_changed
signal card_arrived(id: String)
signal card_trashed(id: String)
signal draw_requested(pid: String)   # a timed card for that player ("" = owner / acting player)
signal weather_changed(w: String)
signal chest_changed
signal new_day(day: int)

const SLOT_COUNT := 3
const DAY_LENGTH := 480.0            # real seconds per in-game day
const BOX_SIZE := 3                  # new cards enter the box on the left, the far-right one is trashed
const STASH_SIZE := 3                # cards the player keeps safe
const CARD_MINUTES := [1, 2, 3, 5, 10, 15, 20, 30, 60]   # settings choices for the arrival cadence
const DEFAULT_CARD_MINUTES := 10
const SPEEDS := [1, 2, 3, 5, 10]     # settings choices for the game speed (fast forward)
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
## mats = building materials (from clearing the overgrowth) it takes to build one. There is no
## money: buildings only ever cost materials.
## card = only a card puts it on the farm (he never builds one himself): when a well, a coop or a
## lightning rod is there, a choice put it there. relic = card-only too (level 99, never wiped).
const STRUCTS := {
	"fence":     {"name": "fence",     "mats": {"wood": 1}, "level": 1, "max": 40, "solid": true,  "movable": false, "hp": 60},
	"scarecrow": {"name": "scarecrow", "mats": {"wood": 2}, "level": 1, "max": 3,  "solid": true,  "movable": true,  "hp": 80},
	"flowerbed": {"name": "flower bed", "mats": {}, "level": 1, "max": 6,  "solid": false, "movable": true,  "hp": 40},
	"bench":     {"name": "bench",     "mats": {"wood": 3}, "level": 1, "max": 2,  "solid": true,  "movable": true,  "hp": 60},
	"sign":      {"name": "farm sign", "mats": {"wood": 2}, "level": 1, "max": 1,  "solid": true,  "movable": true,  "hp": 50},
	"compost":   {"name": "compost heap", "mats": {"wood": 4}, "level": 1, "card": true, "max": 1, "solid": true, "movable": false, "hp": 60},
	"well":      {"name": "well",      "mats": {"stone": 8}, "level": 2, "card": true, "max": 1,  "solid": true,  "movable": false, "hp": 200},
	"lamp":      {"name": "lamp post", "mats": {"stone": 3, "wood": 2}, "level": 2, "card": true, "max": 3,  "solid": true,  "movable": true,  "hp": 80},
	"coop":      {"name": "chicken coop", "mats": {"wood": 10}, "level": 2, "card": true, "max": 1, "solid": true, "movable": false, "hp": 150},
	"beehive":   {"name": "beehive",   "mats": {"wood": 5}, "level": 3, "card": true, "max": 2,  "solid": true,  "movable": true,  "hp": 60},
	"rod":       {"name": "lightning rod", "mats": {"stone": 6, "wood": 2}, "level": 3, "card": true, "max": 1, "solid": true, "movable": false, "hp": 999},
	"altar":     {"name": "dark altar", "level": 99, "max": 1, "solid": true, "movable": false, "hp": 999},
	"totem":     {"name": "dark totem", "level": 99, "max": 6, "solid": true, "movable": false, "hp": 999},
	"idol":      {"name": "stone idol", "level": 99, "max": 1, "solid": true, "movable": false, "hp": 999},
	"obelisk":   {"name": "black obelisk", "level": 99, "max": 1, "solid": true, "movable": false, "hp": 999},
	"stones":    {"name": "standing stones", "level": 99, "max": 1, "solid": true, "movable": false, "hp": 999},
	"saucer":    {"name": "crashed saucer", "level": 99, "max": 1, "solid": true, "movable": false, "hp": 999},
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
	"cursed_coin": {"name": "Cursed Coin", "icon": "r_coin", "desc": "A trinket turns up daily. Sours the mood."},
	"hatchling":  {"name": "The Hatchling", "icon": "r_hatchling", "desc": "Hatched from the strange egg. Chases off critters."},
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
	"haggler":     {"name": "Silver Tongue", "desc": "Produce trades for 30% more."},
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
	"mayor":  {"name": "The Mayor", "icon": "r_sash", "sprite": "v_suit", "tint": "ffcd75", "desc": "Brings a little gift every morning."},
	"kids":   {"name": "Village Kids", "icon": "r_kids", "sprite": "v_villager", "tint": "a7f070", "desc": "Pull up weeds and brush every morning."},
	"doc":    {"name": "Doc Hollis", "icon": "r_doc", "sprite": "v_villager", "tint": "f4f4f4", "desc": "Free house calls. Heals daily."},
}

## Drastic changes the aliens can make to the farmer (colony.gd: abductions, the lurker, cards).
## Hooks: farmer.gd (draw overlays, green/tentacle/glow), colony.gd (antenna/hive_mind relations),
## alien.gd (third_eye spots lurkers), director.gd (glow keeps foxes off), cards.gd (Doc cures).
const MUTATIONS := {
	"antenna":   {"name": "Antenna", "desc": "Hears the aliens humming. They like him more."},
	"green":     {"name": "Green Skin", "desc": "Photosynthesises: energy comes back in the sun."},
	"third_eye": {"name": "Third Eye", "desc": "Sees lurkers in the dark. The farm gets weirder."},
	"glow":      {"name": "Glowing", "desc": "Glows at night. Foxes keep their distance."},
	"tentacle":  {"name": "Tentacle Arm", "desc": "Works 30% faster. Deeply unsettling."},
	"hive_mind": {"name": "Hive Whispers", "desc": "Shares a larder with the hive. No more raids."},
	"chitin":    {"name": "Chitin Plates", "desc": "From a mantis sting: takes 40% less damage."},
	"compound_eyes": {"name": "Compound Eyes", "desc": "Sees everything. Never steps on a snake."},
}

## The farmer's personality, rolled when a farm is founded.
const QUIRKS := {
	"tidy":      {"name": "Tidy", "desc": "Can't stand overgrowth; clears first."},
	"artsy":     {"name": "Artsy", "desc": "Plants his fields in silly shapes."},
	"builder":   {"name": "Handy", "desc": "Loves building fences and paths."},
	"dreamer":   {"name": "Dreamer", "desc": "Wanders and chats a lot."},
	"sunny":     {"name": "Sunflower Nut", "desc": "Plants sunflowers whenever he can."},
	"thrifty":   {"name": "Thrifty", "desc": "Trades only when the cart is full."},
}

## The farmer's chest. kind: trinket (what produce is traded for), souvenir (left behind by
## things that happen on the farm), keepsake (from the mysteries in sagas.gd; never given away).
## worth = per item; the worth of everything ever found sets the farm level.
const TREASURES := {
	"button":       {"name": "Button", "worth": 1, "kind": "trinket", "desc": "Brass, four holes. A start."},
	"marble":       {"name": "Marble", "worth": 2, "kind": "trinket", "desc": "A blue swirly. The good kind."},
	"ribbon":       {"name": "Ribbon", "worth": 5, "kind": "trinket", "desc": "Red silk. Smells of market day."},
	"tin_soldier":  {"name": "Tin Soldier", "worth": 10, "kind": "trinket", "desc": "Missing a hat. Very brave."},
	"silver_spoon": {"name": "Silver Spoon", "worth": 25, "kind": "trinket", "desc": "Too fancy for soup."},
	"pocket_watch": {"name": "Pocket Watch", "worth": 50, "kind": "trinket", "desc": "Ticks. Usually."},
	"pearl":        {"name": "Pearl", "worth": 100, "kind": "trinket", "desc": "Fat and shiny as a moon."},
	"gemstone":     {"name": "Gemstone", "worth": 250, "kind": "trinket", "desc": "Glitters even at night."},
	"sunflower_seeds": {"name": "Sunflower Seeds", "worth": 1, "kind": "souvenir", "desc": "From his own sunflowers."},
	"crow_feather": {"name": "Crow Feather", "worth": 2, "kind": "souvenir", "desc": "Left by a fleeing crow."},
	"rabbit_fluff": {"name": "Rabbit Fluff", "worth": 2, "kind": "souvenir", "desc": "A tuft from a fleeing tail."},
	"wasp_stinger": {"name": "Wasp Stinger", "worth": 3, "kind": "souvenir", "desc": "Hopefully not still angry."},
	"old_bottle":   {"name": "Old Bottle", "worth": 3, "kind": "souvenir", "desc": "Dug up. Grandpa's, probably."},
	"boar_bristle": {"name": "Boar Bristle", "worth": 4, "kind": "souvenir", "desc": "Coarse as a doormat."},
	"fox_fur":      {"name": "Fox Fur", "worth": 5, "kind": "souvenir", "desc": "Snagged on a fence post."},
	"birds_nest":   {"name": "Birds Nest", "worth": 5, "kind": "souvenir", "desc": "Fell out of a felled tree."},
	"snake_skin":   {"name": "Snake Skin", "worth": 6, "kind": "souvenir", "desc": "Shed, papery, a bit rude."},
	"rusty_key":    {"name": "Rusty Key", "worth": 6, "kind": "souvenir", "desc": "Opens nothing. Yet."},
	"arrowhead":    {"name": "Arrowhead", "worth": 8, "kind": "souvenir", "desc": "Very, very old."},
	"wisp_jar":     {"name": "Wisp in a Jar", "worth": 12, "kind": "souvenir", "desc": "It glows when he hums."},
	"geode":        {"name": "Geode", "worth": 15, "kind": "souvenir", "desc": "Plain outside. Not inside."},
	"tome_page":    {"name": "Tome Page", "worth": 15, "kind": "souvenir", "desc": "The ink moves when unwatched."},
	"alien_bolt":   {"name": "Alien Bolt", "worth": 20, "kind": "souvenir", "desc": "No thread. Still fits."},
	"star_shard":   {"name": "Star Shard", "worth": 30, "kind": "souvenir", "desc": "Warm. Fell from the sky."},
	"blue_ribbon":  {"name": "Blue Ribbon", "worth": 40, "kind": "souvenir", "desc": "FIRST PRIZE. Nearly framed."},
	"chitin":       {"name": "Chitin Shard", "worth": 8, "kind": "souvenir", "desc": "Off a giant bug. Shiny as a beetle."},
	"silk":         {"name": "Silk Spool", "worth": 12, "kind": "souvenir", "desc": "Spider-ish silk. Stronger than rope."},
	"royal_jelly":  {"name": "Royal Jelly", "worth": 150, "kind": "keepsake", "desc": "A gift from an insect queen."},
	"grandpa_letter": {"name": "Grandpas Letter", "worth": 10, "kind": "keepsake", "desc": "In grandpa's wobbly hand."},
	"egg_shell":    {"name": "Egg Shell", "worth": 200, "kind": "keepsake", "desc": "What the hatchling came from."},
	"bound_tome":   {"name": "Bound Tome", "worth": 250, "kind": "keepsake", "desc": "The pages found each other."},
	"alien_gift":   {"name": "Alien Gift", "worth": 300, "kind": "keepsake", "desc": "A humming cube. A thank-you."},
	"grandpa_medal": {"name": "Grandpas Medal", "worth": 300, "kind": "keepsake", "desc": "Pinned on by a ghost."},
	"star_key":     {"name": "Star Key", "worth": 1000, "kind": "keepsake", "desc": "It opened the sky once."},
}
## Trinkets, largest first: how trade value is paid out.
const TRINKETS := ["gemstone", "pearl", "pocket_watch", "silver_spoon", "tin_soldier", "ribbon", "marble", "button"]
## What a shooed critter sometimes leaves behind.
const CRITTER_SOUVENIRS := {"crow": "crow_feather", "rabbit": "rabbit_fluff", "fox": "fox_fur",
	"boar": "boar_bristle", "snake": "snake_skin", "wasps": "wasp_stinger"}
## What the farmer says about his chest (%d = how many of that he has).
const CHEST_LINES := {
	"button": ["%d buttons. No coat, mind.", "Buttons are money if you believe."],
	"marble": ["%d marbles! Never lost them, see?"],
	"crow_feather": ["%d crow feathers. One day: a hat.", "The crows pay me in feathers now."],
	"rabbit_fluff": ["%d tufts of rabbit fluff. A pillow, soon."],
	"sunflower_seeds": ["%d sunflower seeds. Snack or savings? Both."],
	"tome_page": ["The pages rustle in the chest at night.", "%d tome pages. They want to be a book."],
	"star_shard": ["%d star shards! The chest glows a bit."],
	"wisp_jar": ["The wisp jar hums when I count my treasure."],
	"pocket_watch": ["Pocket watch says it's treasure o'clock."],
	"gemstone": ["A real gemstone. In MY chest!"],
	"blue_ribbon": ["First prize! I polish that ribbon daily."],
	"grandpa_letter": ["Grandpa's letters. I read them most nights."],
	"grandpa_medal": ["Grandpa's medal. Not for trade. Ever."],
	"egg_shell": ["Kept the egg shell. Sentimental, me."],
	"alien_gift": ["The alien cube hummed again. Friendly hum."],
	"bound_tome": ["Don't open the bound tome. Don't."],
	"star_key": ["The star key. Richest farmer alive, me."],
}
const RICH_LINES := [
	[0, ["My chest is mostly lint and hope.", "Poor as a field mouse. Happy though."]],
	[40, ["%d worth of treasure. Comfortable!", "A modest chest for a modest farmer."]],
	[200, ["%d worth in my chest! I'm gentry now.", "A chest worth %d. Fancy that."]],
	[800, ["Rich! RICH! %d worth of treasure!", "Should I get a second chest?"]],
	[3000, ["I could buy the village. Twice.", "%d worth! Grandpa would faint."]],
]

const TOTEMS_MAX := 6

## Edicts: lasting rules a card lays down over the farm (edicts.gd). They keep steering the
## simulation every day, and whenever one kicks in the log and the farmer name it.
## rival = the edict it replaces (the other side of the same card). lines = what the farmer says.
const EDICTS := {
	"rain_covenant": {"name": "Rain Covenant", "rival": "sun_covenant", "desc": "Rain every dawn. No heatwaves, more storms.",
		"lines": ["Rain at dawn again. The covenant holds.", "Never a dry morning since the covenant."]},
	"sun_covenant": {"name": "Sun Covenant", "rival": "rain_covenant", "desc": "Blazing sun every morning. No rain, ever.",
		"lines": ["Not a cloud. Not one, since the covenant.", "Sun again! I'll fetch the watering can."]},
	"wild_reserve": {"name": "Wild Reserve", "rival": "tame_all", "desc": "The south of the farm belongs to the wild.",
		"lines": ["I leave the south alone. That was the deal.", "The reserve is thick as a jungle now."]},
	"tame_all": {"name": "Tame It All", "rival": "wild_reserve", "desc": "No weed ever grows back. Every tree came down.",
		"lines": ["Not a weed since we tamed it all.", "Miss the apple trees, a bit."]},
	"side_aliens": {"name": "Pact with the Stars", "rival": "side_brood", "desc": "The aliens are friends. The brood are not.",
		"lines": ["The aliens wave at me now. The bugs glare.", "Our friends from the stars, eh?"]},
	"side_brood": {"name": "Pact with the Brood", "rival": "side_aliens", "desc": "The brood are friends. The aliens are not.",
		"lines": ["The ants bring honey since the pact.", "We stand with the bugs. Weird, but we do."]},
	"crow_pact": {"name": "Crow Pact", "rival": "hen_republic", "desc": "Crows guard the crops. They take a trinket a day.",
		"lines": ["The crows guard my rows now.", "Another button for the crows. Fair's fair."]},
	"hen_republic": {"name": "Hen Republic", "rival": "crow_pact", "desc": "A new hen every dawn. No foxes. Hens peck seedlings.",
		"lines": ["Long live the hens!", "So many hens. So few seedlings."]},
}
## How long the background holds its breath after a card is played (no random events, no turns of fate).
const HUSH_SECONDS := 45.0

const WEATHER_NAMES := {"sunny": "Sunny", "cloudy": "Cloudy", "rain": "Rain", "storm": "Storm", "heat": "Heatwave"}

var running := false     # false while the welcome screen is up
var puppet := false      # a guest in a shared world: shows the host's state, simulates nothing
var slot := 1
var chest := {}          # treasure id -> count (see TREASURES)
var total_found := 0     # worth of every treasure ever found: sets the farm level
var day := 1
var time_of_day := 0.27
var weather := "sunny"
var hands := {}          # pid -> {box, stash, card_timer[, name]}: each player's own pool of cards
var owner_pid := ""      # whose world this is (the host / the solo player)
var world_id := ""       # this world's id; a copy that goes its own way gets a new one
var forked_from := ""    # the world_id this one was copied from ("" = an original)
var present := {}        # pids playing right now: only their cards drip in (not saved)
var acting_pid := ""     # whose action is being applied: cards it causes go to them ("" = the owner)
## The local player's card box (new cards push in from the left, the right one is trashed),
## stash (cards kept safe, "" = empty slot) and seconds since the last arrival.
var box: Array:
	get: return hand()["box"]
	set(v): hand()["box"] = v
var stash: Array:
	get: return hand()["stash"]
	set(v): hand()["stash"] = v
var card_timer: float:
	get: return float(hand()["card_timer"])
	set(v): hand()["card_timer"] = v
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
var sagas := {}          # mystery id -> {stage, t, data, done} (see sagas.gd)
var colony := {}         # the alien faction's state (colony.gd)
var mutations := {}      # id -> true (see MUTATIONS)
var tides := {}          # faction balance history + timers (tides.gd)
var brood := {}          # the mutant insects' state (swarm.gd)
var chores := {}         # grandpa's letter of starter chores (chores.gd)
var edicts := {}         # id -> {day}: lasting rules laid down by cards (see EDICTS, edicts.gd)
var hush_t := 0.0        # seconds the background stays quiet after a card was played (not saved)
var settings := {"dock": "right", "card_minutes": DEFAULT_CARD_MINUTES, "speed": 1}
var time_scale := 1.0    # game speed (fast forward), from settings["speed"]
var profile := ""        # "" or "_p2".. (`-- profile=N`): separate settings + slots, for two copies on one PC
var my_pid := ""         # this player's id (settings["pid"]), see MULTIPLAYER.md
var play_seconds := 0.0
var _defaults := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("profile=") and int(a.substr(8)) > 1:
			profile = "_p%d" % int(a.substr(8))
	_load_settings()
	if String(settings.get("pid", "")) == "":
		settings["pid"] = new_id()
		save_settings()
	my_pid = String(settings["pid"])
	_defaults = to_dict().duplicate(true)


## A random 16-hex id (player ids, world ids).
func new_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%08x%08x" % [rng.randi(), rng.randi()]


## Back to a brand-new game.
func reset() -> void:
	var keep := settings.duplicate()
	from_dict(_defaults.duplicate(true))
	settings = keep
	stats = {"harvested": 0, "shooed": 0, "cards": 0, "faints": 0, "built": 0}
	relics = {}
	unlocked = {}
	pending = []
	seen = {}
	log_lines = []
	perks = {}
	friends = {}
	totems = 0
	played = {}
	chest = {}
	sagas = {}
	colony = {}
	mutations = {}
	tides = {}
	brood = {}
	chores = {}
	edicts = {}
	hush_t = 0.0


func _process(delta: float) -> void:
	if running and puppet:
		# a guest's clock keeps ticking between the host's snapshots (cosmetic only)
		time_of_day = fmod(time_of_day + delta * time_scale / DAY_LENGTH, 1.0)
		return
	if not simulating():
		return
	var d := delta * time_scale
	play_seconds += delta
	hush_t = maxf(0.0, hush_t - d)
	var prev := time_of_day
	time_of_day += d / DAY_LENGTH
	if time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
		add_log("Day %d begins." % day)
		new_day.emit(day)
	if prev < 0.25 and time_of_day >= 0.25:
		add_log("The sun rises.")
	for p in present:
		var h := hand(p)
		h["card_timer"] = float(h["card_timer"]) + d
		if h["card_timer"] >= card_interval():
			h["card_timer"] = 0.0
			draw_requested.emit(p)
	for k in buffs.keys():
		buffs[k] -= d
		if buffs[k] <= 0.0:
			buffs.erase(k)


## Should this machine run the simulation? (not on the welcome screen, not as a guest)
func simulating() -> bool:
	return running and not puppet


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


# ---------------------------------------------------------------- level & chest
func level() -> int:
	var lv := 1
	for i in LEVEL_THRESHOLDS.size():
		if total_found >= LEVEL_THRESHOLDS[i]:
			lv = i + 1
	return lv


func level_progress() -> float:
	var lv := level()
	if lv >= LEVEL_THRESHOLDS.size():
		return 1.0
	var a: int = LEVEL_THRESHOLDS[lv - 1]
	var b: int = LEVEL_THRESHOLDS[lv]
	return clampf(float(total_found - a) / float(b - a), 0.0, 1.0)


## Puts treasure in the chest. found = counts towards the farm level.
func add_treasure(id: String, n: int = 1, found: bool = true) -> void:
	if n <= 0 or not TREASURES.has(id):
		return
	var before := level()
	chest[id] = int(chest.get(id, 0)) + n
	if found:
		total_found += int(TREASURES[id]["worth"]) * n
	chest_changed.emit()
	if level() > before:
		add_log("Farm level %d! New things unlocked." % level())


func remove_treasure(id: String, n: int = 1) -> int:
	var have := int(chest.get(id, 0))
	var k := mini(have, n)
	if k <= 0:
		return 0
	chest[id] = have - k
	if chest[id] == 0:
		chest.erase(id)
	chest_changed.emit()
	return k


func treasure_count(id: String) -> int:
	return int(chest.get(id, 0))


## Total worth of everything in the chest right now.
func wealth() -> int:
	var w := 0
	for id in chest:
		w += int(TREASURES.get(id, {}).get("worth", 0)) * int(chest[id])
	return w


## Pays out `worth` as trinkets (largest first, with a few smaller pieces mixed in).
## Returns {id: count} of what was given.
func gain_trinkets(worth: int, found: bool = true) -> Dictionary:
	var got := {}
	var left := worth
	for id in TRINKETS:
		var w: int = TREASURES[id]["worth"]
		var k := left / w
		if k == 1 and id != "button" and randf() < 0.3:
			k = 0
		if k > 0:
			got[id] = k
			left -= k * w
	for id in got:
		add_treasure(id, got[id], found)
	return got


## "a pocket watch, 3 marbles and a button"
func describe(items: Dictionary) -> String:
	var ids: Array = items.keys()
	ids.sort_custom(func(a, b): return int(TREASURES[a]["worth"]) > int(TREASURES[b]["worth"]))
	var parts: Array = []
	for id in ids:
		var n := int(items[id])
		var nm: String = String(TREASURES[id]["name"]).to_lower()
		parts.append(("a " + nm) if n == 1 else "%d %ss" % [n, nm])
	if parts.is_empty():
		return "nothing"
	if parts.size() == 1:
		return parts[0]
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + String(parts[parts.size() - 1])


## The most valuable thing in the chest that isn't a keepsake ("" if none).
func best_tradeable() -> String:
	var best := ""
	var bw := -1
	for id in chest:
		var def: Dictionary = TREASURES.get(id, {})
		if def.get("kind", "") != "keepsake" and int(def.get("worth", 0)) > bw:
			bw = int(def["worth"])
			best = id
	return best


## Something for the farmer to say about his chest and how rich he is.
func chest_comment() -> String:
	var w := wealth()
	var opts: Array = []
	for tier in RICH_LINES:
		if w >= int(tier[0]):
			opts = tier[1]
	var owned: Array = []
	for id in chest:
		if CHEST_LINES.has(id):
			owned.append(id)
	if owned.size() > 0 and randf() < 0.55:
		var id: String = owned.pick_random()
		return String(CHEST_LINES[id].pick_random()).replace("%d", str(treasure_count(id)))
	return String(opts.pick_random()).replace("%d", str(w))


## Card treasure rewards scale up with farm level.
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


## Trades all produce (not materials) for trinkets. Returns {worth, got: {id: n}}.
func trade_goods(mult: float = 1.0) -> Dictionary:
	var v := inventory_value(mult)
	for k in inventory.keys():
		if not k in MATERIALS:
			inventory.erase(k)
	var got: Dictionary = gain_trinkets(v) if v > 0 else {}
	return {"worth": v, "got": got}


## Buildings cost materials only (the Carpenter puts fences up for free).
func can_afford(def: Dictionary) -> bool:
	if has_perk("carpenter") and def.get("name", "") == "fence":
		return true
	var m: Dictionary = def.get("mats", {})
	for k in m:
		if item_count(k) < int(m[k]):
			return false
	return true


func pay_for(def: Dictionary) -> void:
	if has_perk("carpenter") and def.get("name", "") == "fence":
		return
	var m: Dictionary = def.get("mats", {})
	for k in m:
		add_item(k, -int(m[k]))


# ---------------------------------------------------------------- cards / weird / relics
func card_interval() -> float:
	return float(settings.get("card_minutes", DEFAULT_CARD_MINUTES)) * 60.0


func next_card_left() -> float:
	return maxf(0.0, card_interval() - card_timer)


## This copy of the world goes its own way, owned by the local player (a guest keeping the
## shared world after the host left, or opening a slot that was saved as someone's guest).
func fork() -> void:
	forked_from = world_id
	world_id = new_id()
	owner_pid = my_pid
	hand()


## A player's cards ("" = the local player), created empty on first use.
func hand(pid: String = "") -> Dictionary:
	if pid == "":
		pid = my_pid
	if not hands.has(pid):
		hands[pid] = {"box": _slots([], BOX_SIZE), "stash": _slots([], STASH_SIZE), "card_timer": 0.0}
	return hands[pid]


## Who gets a card nobody asked for: the given player, else whoever's action caused it, else the owner.
func card_target(pid: String = "") -> String:
	if pid != "":
		return pid
	if acting_pid != "" and hands.has(acting_pid):
		return acting_pid
	return owner_pid if owner_pid != "" else my_pid


func player_name(pid: String) -> String:
	var n := String(hand(pid).get("name", ""))
	if n != "":
		return n
	return "PLAYER 1" if pid == owner_pid else "PLAYER 2"


## A new card enters the box on the left and pushes the others right (into the first gap);
## with no gap, the far-right card falls out and is trashed.
func add_card(id: String, pid: String = "") -> bool:
	if id == "":
		return false
	pid = card_target(pid)
	var b: Array = hand(pid)["box"]
	var gap := b.find("")
	if gap < 0:
		var gone: String = b[BOX_SIZE - 1]
		gap = BOX_SIZE - 1
		if pid == my_pid:
			add_log("A card fell out of the box: %s." % gone_title(gone))
			card_trashed.emit(gone)
		else:
			add_log("A card fell out of %s's box: %s." % [player_name(pid), gone_title(gone)])
	for i in range(gap, 0, -1):
		b[i] = b[i - 1]
	b[0] = id
	seen[id] = int(seen.get(id, 0)) + 1
	cards_changed.emit()
	if pid == my_pid:
		card_arrived.emit(id)
	return true


## Set by cards.gd so Game can name a card without knowing the deck.
var title_of: Callable


func gone_title(id: String) -> String:
	return String(title_of.call(id)) if title_of.is_valid() else id


## Anyone holding this card? (so the same card is never in two places)
func has_card(id: String) -> bool:
	if id == "":
		return false
	for p in hands:
		if id in hands[p]["box"] or id in hands[p]["stash"]:
			return true
	return false


func _slots_of(where: String, pid: String) -> Array:
	return hand(pid)["box" if where == "box" else "stash"]


func card_at(where: String, i: int, pid: String = "") -> String:
	var arr := _slots_of(where, pid)
	return String(arr[i]) if i >= 0 and i < arr.size() else ""


## Empties a slot after a card was played.
func take_card(where: String, i: int, pid: String = "") -> void:
	var arr := _slots_of(where, pid)
	if i >= 0 and i < arr.size() and arr[i] != "":
		arr[i] = ""
		stats["cards"] = int(stats["cards"]) + 1
		cards_changed.emit()


## Moves (or swaps) a card between any two slots of the box/stash.
func move_card(from_where: String, fi: int, to_where: String, ti: int, pid: String = "") -> void:
	if from_where == to_where and fi == ti:
		return
	var a := _slots_of(from_where, pid)
	var b := _slots_of(to_where, pid)
	if fi < 0 or ti < 0 or fi >= a.size() or ti >= b.size():
		return
	var tmp: String = b[ti]
	b[ti] = a[fi]
	a[fi] = tmp
	cards_changed.emit()


func card_count(pid: String = "") -> int:
	var n := 0
	var h := hand(pid)
	for id in h["box"] + h["stash"]:
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


func has_mutation(id: String) -> bool:
	return mutations.has(id)


func has_edict(id: String) -> bool:
	return edicts.has(id)


## True while the farm holds its breath after a card (random events, turns of fate and faction
## outreach wait until it's over, so the card's change is the only thing happening).
func hushed() -> bool:
	return hush_t > 0.0


## When a timer that came due during the hush should go off instead: after it, staggered, so
## everything held back doesn't land in the same second.
func hush_after() -> float:
	return hush_t + randf_range(8.0, 40.0)


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


func set_speed(n: int) -> void:
	settings["speed"] = n
	time_scale = float(n)
	save_settings()


func save_settings() -> void:
	var fa := FileAccess.open(settings_path(), FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(settings))


func _load_settings() -> void:
	if not FileAccess.file_exists(settings_path()):
		return
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(settings_path()))
	if typeof(p) == TYPE_DICTIONARY:
		for k in p:
			settings[k] = p[k]
	time_scale = float(settings.get("speed", 1))


func settings_path() -> String:
	return "user://settings%s.json" % profile


func slot_path(n: int) -> String:
	return "user://slot%s_%d.json" % [profile, n]


func to_dict() -> Dictionary:
	return {
		"chest": chest, "total_found": total_found, "sagas": sagas, "day": day, "time_of_day": time_of_day,
		"weather": weather, "hands": hands, "owner_pid": owner_pid,
		"perks": perks, "friends": friends, "totems": totems, "played": played, "quirk": quirk,
		"farm_name": farm_name,
		"inventory": inventory, "buffs": buffs, "charms": charms, "health": health, "energy": energy,
		"mood": mood, "poison": poison, "stats": stats, "log": log_lines, "weird": weird,
		"relics": relics, "unlocked": unlocked, "favor_crop": favor_crop, "pending": pending,
		"seen": seen, "play_seconds": play_seconds,
		"colony": colony, "mutations": mutations, "tides": tides, "brood": brood, "chores": chores, "edicts": edicts,
		"world_id": world_id, "forked_from": forked_from,
	}


func from_dict(d: Dictionary) -> void:
	chest = {}
	var ch: Dictionary = d.get("chest", {})
	for k in ch:
		if TREASURES.has(k):
			chest[k] = int(ch[k])
	total_found = int(d.get("total_found", d.get("total_earned", 0)))
	# saves from before the chest: grandpa's old coins become trinkets
	if d.has("coins") and not d.has("chest"):
		gain_trinkets(int(d["coins"]), false)
	world_id = String(d.get("world_id", ""))
	if world_id == "":
		world_id = new_id()   # a brand-new game, or a save from before world ids
	forked_from = String(d.get("forked_from", ""))
	sagas = d.get("sagas", {})
	colony = d.get("colony", {})
	mutations = d.get("mutations", {})
	tides = d.get("tides", {})
	brood = d.get("brood", {})
	chores = d.get("chores", {})
	edicts = {}
	var ed: Dictionary = d.get("edicts", {})
	for k in ed:
		if EDICTS.has(k):
			edicts[k] = ed[k]
	day =int(d.get("day", day))
	time_of_day = float(d.get("time_of_day", time_of_day))
	weather = String(d.get("weather", weather))
	owner_pid = String(d.get("owner_pid", ""))
	if owner_pid == "":
		owner_pid = my_pid
	hands = {}
	if d.has("hands"):
		var hs: Dictionary = d["hands"]
		for p in hs:
			var h: Dictionary = hs[p]
			hands[p] = {"box": _slots(h.get("box", []), BOX_SIZE), "stash": _slots(h.get("stash", []), STASH_SIZE),
				"card_timer": float(h.get("card_timer", 0.0))}
			if h.has("name"):
				hands[p]["name"] = String(h["name"])
	else:
		# saves from before multiplayer: one box + stash, the owner's
		hands[owner_pid] = {"box": _slots(d.get("box", d.get("hand", [])), BOX_SIZE),
			"stash": _slots(d.get("stash", []), STASH_SIZE), "card_timer": float(d.get("card_timer", 0.0))}
	present = {my_pid: true}
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
