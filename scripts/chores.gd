class_name Chores
extends Node
## Grandpa's letter: a few starter chores waiting in the mailbox, so a new farm has something to
## do (and cards coming in) from the first minute instead of waiting for the card timer. Each chore
## done mails a card to every player here, plus a few trinkets. Click a mailbox to read the letter.
## State in Game.chores: {done: {id: true}, read: {pid: chores done when they last read it}}.

const LIST := [
	{"id": "pull", "text": "Pull 5 weeds (click them)", "stat": "pulled", "n": 5},
	{"id": "card", "text": "Play a card", "stat": "cards", "n": 1},
	{"id": "rocks", "text": "Smash 2 rocks (click them)", "stat": "smashed", "n": 2},
	{"id": "plant", "text": "Plant 4 crops", "stat": "planted", "n": 4},
	{"id": "harvest", "text": "Harvest 5 crops", "stat": "harvested", "n": 5},
	{"id": "build", "text": "Build something", "stat": "built", "n": 1},
	{"id": "clear", "text": "Clear 40% of the farm", "cleared": 0.4},
	{"id": "picture", "text": "Grow a crop picture", "stat": "patterns", "n": 1},
]
const LETTER := "Dear grandchild, the farm is yours now. Sorry about the weeds! Give the farmer a hand with these chores and I'll mail you a card for each one. - Grandpa"

var world: World
var cards: Node
var _t := 1.0


func _process(delta: float) -> void:
	if not Game.simulating() or world == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	check()


## A new farm starts with the letter unread and nothing done.
static func start() -> void:
	Game.chores = {"done": {}, "read": {}}


func check() -> void:
	if not Game.chores.has("done"):
		# a farm from before the letter: whatever is already done counts, quietly
		start()
		for ch in LIST:
			var pr := progress(ch, world)
			if pr[0] >= pr[1]:
				Game.chores["done"][ch["id"]] = true
		for p in Game.hands:
			Game.chores["read"][p] = done_count()
		return
	for ch in LIST:
		if Game.chores["done"].has(ch["id"]):
			continue
		var pr := progress(ch, world)
		if pr[0] < pr[1]:
			continue
		Game.chores["done"][ch["id"]] = true
		for p in Game.present:
			cards.draw_card(p)
		for c in world.cells_with_obj(["mailbox"]):
			if Game.present.has(String(world.objs[c].get("pid", ""))):
				world.float_text("MAIL!", world.center(c) + Vector2(-10, -18), Color("ffcd75"))
		world.loot_trinkets(Game.scaled_reward(8), world.feet(world.DOOR))
		Game.add_log("Chore done: %s. Grandpa mailed a card!" % String(ch["text"]).get_slice(" (", 0))
		if done_count() == LIST.size():
			world.loot_trinkets(Game.scaled_reward(30), world.feet(world.DOOR))
			Game.add_log("Every chore on grandpa's list is done. He'd be proud.")
		return   # one at a time, so they trickle in


## [have, need] for a chore.
static func progress(ch: Dictionary, w: World) -> Array:
	if ch.has("cleared"):
		var have := int(w.cleared_ratio() * 100.0) if w else 0
		return [have, int(float(ch["cleared"]) * 100.0)]
	var n := int(ch["n"])
	return [mini(int(Game.stats.get(ch["stat"], 0)), n), n]


static func done_count() -> int:
	return (Game.chores.get("done", {}) as Dictionary).size()


## Has something happened on the list since this player last read the letter?
static func unread(pid: String) -> bool:
	if not Game.chores.has("done"):
		return false
	return int(Game.chores.get("read", {}).get(pid, -1)) < done_count()


static func mark_read(pid: String) -> void:
	if Game.chores.has("done"):
		Game.chores["read"][pid] = done_count()
