class_name Commands
extends Node
## Every player action goes through here (see MULTIPLAYER.md): the HUD and the debug keys
## `submit()` a command; `execute()` checks it and applies it for one player. Solo (and on the
## host) commands run at once; a guest will send them to the host instead (phase 1).
## A command is a Dictionary {"type": ..., args...}:
##   choose      {where: "box"|"stash", i, which: "a"|"b"}   play a card from your box/stash
##   move_card   {from, fi, to, ti}                           move/swap a card between your slots
##   card_minutes {n}                                          card cadence (a world rule: owner only)
##   speed       {n}                                           game speed (owner only)
##   debug       {key}                                         debug actions (owner only, debug builds)
##   poke        {x, y}                                        clear overgrowth on a tile by hand (a click)
##   read_letter {}                                            this player read grandpa's letter (chores.gd)

## Debug commands -> what they do (the keys live in main._unhandled_input).
const DEBUG := ["draw", "fill", "event", "next_card", "weird", "alien", "tides", "brood", "locusts", "cataclysm"]

var cards: Node
var director: Node
var colony: Colony
var swarm: Swarm
var tides: Tides
var world: World
var _poke_ms := {}   # pid -> last poke (ms): a click can't be faster than a person clicks


## Run a command from the local player (a guest sends it to the host instead). True if it was
## applied (for a guest: sent; the host may still refuse it).
func submit(cmd: Dictionary) -> bool:
	if Net.is_guest():
		Net.send_command(cmd)
		return true
	return execute(Game.my_pid, cmd)


## Checks and applies a command for player `pid`. Never trust the arguments: they may come
## from the other player's machine.
func execute(pid: String, cmd: Dictionary) -> bool:
	if not Game.running or not Game.hands.has(pid):
		return false
	var owner := pid == Game.owner_pid
	match String(cmd.get("type", "")):
		"choose":
			var where := _where(cmd.get("where"))
			var which := String(cmd.get("which", ""))
			if where == "" or which not in ["a", "b"]:
				return false
			return cards.choose(where, _int(cmd.get("i")), which, pid)
		"move_card":
			var fw := _where(cmd.get("from"))
			var tw := _where(cmd.get("to"))
			if fw == "" or tw == "":
				return false
			Game.move_card(fw, _int(cmd.get("fi")), tw, _int(cmd.get("ti")), pid)
			return true
		"card_minutes":
			var n := _int(cmd.get("n"))
			if not owner or n not in Game.CARD_MINUTES:
				return false
			Game.settings["card_minutes"] = n
			Game.save_settings()
			return true
		"speed":
			var sp := _int(cmd.get("n"))
			if not owner or sp not in Game.SPEEDS:
				return false
			Game.set_speed(sp)
			Game.add_log("Game speed x%d" % sp)
			return true
		"poke":
			var c := Vector2i(_int(cmd.get("x")), _int(cmd.get("y")))
			var now := Time.get_ticks_msec()
			if world == null or not world.in_bounds(c) or now - int(_poke_ms.get(pid, -1000)) < 80:
				return false
			_poke_ms[pid] = now
			return world.poke(c)
		"read_letter":
			Chores.mark_read(pid)
			return true
		"debug":
			if not owner or not OS.is_debug_build():
				return false
			return _debug(String(cmd.get("key", "")), pid)
	return false


func _debug(key: String, pid: String) -> bool:
	match key:
		"draw":
			cards.draw_card(pid)
		"fill":
			for i in Game.BOX_SIZE:
				cards.draw_card(pid)
		"event":
			director.random_event()
		"next_card":
			Game.hand(pid)["card_timer"] = Game.card_interval()
		"weird":
			Game.add_weird(10.0)
		"alien":
			colony.arrive("")
		"tides":
			tides.turn()
		"brood":
			swarm.arrive("")
		"locusts":
			swarm.launch_swarm("")
		"cataclysm":
			tides.roll_cataclysm(["aliens", "insects", "wild", "farm"].pick_random())
		_:
			return false
	return true


func _where(v: Variant) -> String:
	var w := String(v) if v is String else ""
	return w if w in ["box", "stash"] else ""


## Ints may arrive as floats (JSON) or junk: anything else becomes -1 (out of range everywhere).
func _int(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return int(v)
	return -1
