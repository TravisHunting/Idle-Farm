extends Node
## Two copies of the game on localhost (MULTIPLAYER.md): A hosts a farm, B joins it, then the roles
## swap. Runs in real time (the network needs real frames). The script, in order:
##   1. A hosts (port P), B joins: B lands in puppet mode with A's world, actors stream in and move,
##      a card A gives B arrives, B plays it by command and sees the result; bandwidth report.
##      B signals "done" by moving a card to its stash.
##   2. A stops hosting (says bye): B keeps the farm as its own fork (owner B, new world id, saved,
##      simulating) and hosts it on port P+1.
##   3. A joins B's fork (A's own farm is saved first): A gets its old hand back; B sees A's hand
##      was kept, not recreated.
##   4. A goes back to the menu (bye): B notices at once; A's copy of B's farm is in A's slot.
## role=solo (one copy): addresses, the router step (faked; upnp=1 tries the real router), join errors.
## Each copy checks its own side; exit code 0 = all its checks passed.

const SLOT := 8          # each copy's own farm (A's original, B's copy of it)
const SLOT_VISIT := 7    # A's copy of B's farm (step 3)
const BANDWIDTH_WINDOW := 10.0
const QUICK := 3.0       # a bye must be noticed well before the 5s timeout

var role := "host"
var port := 24690
var main: Node
var failures: Array = []
var shot := ""      # guest, windowed runs only: save a screenshot here (shot=<path.png>)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("role="):
			role = a.substr(5)
		elif a.begins_with("port="):
			port = int(a.substr(5))
		elif a.begins_with("shot=") and DisplayServer.get_name() != "headless":
			shot = a.substr(5)
	Net.verbose = true
	# never touch the real router from a test unless asked to (upnp=1 opens a real port mapping)
	Net.use_upnp = "upnp=1" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	_wipe()
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	if role == "host":
		await _a()
	elif role == "solo":
		await _solo()
	else:
		await _b()
	Net.stop()
	_wipe()
	print("[%s] stats: %s" % [role, Net.stats])
	if failures.is_empty():
		print("== [%s] ALL CHECKS PASSED" % role)
		get_tree().quit(0)
	else:
		for f in failures:
			print("FAIL [%s]: %s" % [role, f])
		get_tree().quit(1)


func check(ok: bool, what: String) -> bool:
	if not ok:
		failures.append(what)
	else:
		print("  ok [%s]: %s" % [role, what])
	return ok


## Waits (real time) until cond() is true or the timeout runs out.
func until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wipe() -> void:
	for n in [SLOT, SLOT_VISIT]:
		var p := ProjectSettings.globalize_path(Game.slot_path(n))
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## The "game" part of a save slot ({} if missing).
func _slot_game(n: int) -> Dictionary:
	var p := Game.slot_path(n)
	if not FileAccess.file_exists(p):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d.get("game", {}) if d is Dictionary else {}


## Join (retrying while the other side opens its port); true once in the game as a guest.
func _join(p: int, slot: int) -> bool:
	for tries in 8:
		if Net.join("127.0.0.1", p, slot) == OK:
			await until(func() -> bool: return Net.is_guest() or Net.mode == "offline", 6.0)
		if Net.is_guest():
			return true
		await wait(1.0)
	return false


# ---------------------------------------------------------------- A: host first, then guest
func _a() -> void:
	main.start_slot(SLOT)
	Game.running = true
	# a busy farm, so the bandwidth check means something
	main.colony.arrive("saucer")
	main.swarm.arrive("hive")
	for i in 12:
		main.world.add_animal(Animal.new(main.world, "chicken", main.world.feet(main.world.DOOR) + Vector2(i * 6 - 36, 30)))
	var my_world := Game.world_id
	# 1.
	check(Net.host(port) == OK, "hosting on port %d" % port)
	if not check(await until(func() -> bool: return Net.guest_pid != "", 30.0), "the guest joined"):
		return
	var g := Net.guest_pid
	check(Game.hands.has(g) and Game.present.has(g), "the guest has a hand and is present")
	check(Game.owner_pid == Game.my_pid, "the host still owns the world")
	await wait(2.0)
	for i in 3:
		main.cards.draw_card(g)
	main.cards.draw_card()   # and one for us, to recognise our hand later
	var played := await until(func() -> bool:
		for l in Game.log_lines:
			if String(l).begins_with(Game.player_name(g) + " chose"):
				return true
		return false, 30.0)
	check(played, "the guest's card play arrived and was applied")
	check(Game.card_count(g) < 3, "the card left the guest's hand on the host")
	check(await until(func() -> bool: return Game.hand(g)["stash"].count("") < Game.STASH_SIZE, 60.0),
		"the guest's 'done' signal (a card moved to its stash) arrived")
	# 2.
	await wait(1.5)   # let the latest snapshot (with our hand) reach the guest
	var mine := [Game.box.duplicate(), Game.stash.duplicate()]
	Net.stop()
	check(Net.mode == "offline" and Game.running and not Game.puppet and Game.world_id == my_world,
		"stopped hosting; still on our own farm")
	check(not Game.present.has(g) and Game.hands.has(g), "the guest's hand stays, but no longer drips")
	await wait(2.0)
	# 3.
	if not check(await _join(port + 1, SLOT_VISIT), "joined the guest's fork on port %d" % (port + 1)):
		return
	await until(func() -> bool: return Game.box.size() > 0, 2.0)
	check(Game.puppet and Game.owner_pid == g, "visiting the old guest's farm in puppet mode")
	check(Game.forked_from == my_world, "it is a fork of our farm")
	check(Game.box == mine[0] and Game.stash == mine[1], "our old hand is back (%s %s)" % [Game.box, Game.stash])
	var own := _slot_game(SLOT)
	check(own.get("owner_pid", "") == Game.my_pid and own.get("world_id", "") == my_world,
		"our own farm was saved before joining")
	await wait(2.0)
	# 4.
	main.back_to_menu()
	check(Net.mode == "offline" and not Game.puppet, "left the visit")
	var copy := _slot_game(SLOT_VISIT)
	check(copy.get("owner_pid", "") == g and copy.get("forked_from", "") == my_world, "kept a copy of the visited farm")
	await wait(1.0)


# ---------------------------------------------------------------- B: guest first, then host
func _b() -> void:
	await wait(1.5)   # let the host open its port
	if not check(await _join(port, SLOT), "joined the host's farm"):
		return
	check(Game.running and Game.puppet, "in puppet mode")
	var host_pid := Game.owner_pid
	var host_world := Game.world_id
	var t_join := Time.get_ticks_msec() / 1000.0
	check(host_pid != Game.my_pid, "the world belongs to the host")
	check(main.world.farmer != null and main.world.objs.size() > 10, "the farm arrived (%d objects)" % main.world.objs.size())
	var p0: Vector2 = main.world.farmer.pos
	var aliens := await until(func() -> bool:
		for a in main.world.animals:
			if a is Alien:
				return true
		return false, 15.0)
	check(aliens, "aliens streamed in (%d actors)" % main.world.animals.size())
	await until(func() -> bool: return main.world.farmer.pos.distance_to(p0) > 2.0, 15.0)
	check(main.world.farmer.pos.distance_to(p0) > 2.0, "the farmer moves on the guest's screen")
	var tod := Game.time_of_day
	await wait(1.0)
	check(Game.time_of_day != tod, "the guest's clock keeps going")
	if not check(await until(func() -> bool: return Game.card_count() >= 3, 20.0), "the cards the host gave us arrived"):
		return
	var i := -1
	var which := ""
	for k in Game.BOX_SIZE:
		var c: Dictionary = main.cards.card(Game.card_at("box", k))
		for w in ["a", "b"]:
			if which == "" and not c.is_empty() and main.cards.can_choose(c, w):
				i = k
				which = w
	if not check(which != "", "one of our cards is playable"):
		return
	var id := Game.card_at("box", i)
	main.commands.submit({"type": "choose", "where": "box", "i": i, "which": which})
	var back := await until(func() -> bool: return not id in Game.box and Game.played.get(id, "") == which, 10.0)
	check(back, "our card play came back in the host's snapshot")
	if shot != "":
		await wait(3.0)
		get_viewport().get_texture().get_image().save_png(shot)
		main.hud.settings_open = true
		await wait(0.3)
		get_viewport().get_texture().get_image().save_png(shot.get_basename() + "_settings.png")
		main.hud.settings_open = false
		print("[guest] screenshots: ", shot, " + _settings")
	print("[guest] join + play took %.1fs" % (Time.get_ticks_msec() / 1000.0 - t_join))
	# steady-state bandwidth (the welcome packet with the whole farm is excluded)
	var b0 := int(Net.stats["received"])
	var w0: int = Net.wire()["received"]
	var n0: int = main.world.animals.size()
	await wait(BANDWIDTH_WINDOW)
	var payload := (int(Net.stats["received"]) - b0) / BANDWIDTH_WINDOW
	var wire_rate := (int(Net.wire()["received"]) - w0) / BANDWIDTH_WINDOW
	print("[guest] steady %.0fs: payload %.1f KB/s, wire %.1f KB/s, %d -> %d actors" % [
		BANDWIDTH_WINDOW, payload / 1024.0, wire_rate / 1024.0, n0, main.world.animals.size()])
	check(wire_rate < 20.0 * 1024.0, "bandwidth on the wire under 20 KB/s (%.1f KB/s)" % (wire_rate / 1024.0))
	var k2 := Game.box.find(Game.box.filter(func(x: String) -> bool: return x != "")[0])
	main.commands.submit({"type": "move_card", "from": "box", "fi": k2, "to": "stash", "ti": 0})   # "done"
	# 2. the host leaves: the farm is ours now
	var host_hand: Array = Game.hand(host_pid)["box"].duplicate()
	var gone := await until(func() -> bool: return not Game.puppet, 60.0)
	if not check(gone, "noticed the host leaving"):
		return
	check(Net.last_exit == "bye", "the host said goodbye (no timeout wait)")
	check(Net.mode == "offline" and Game.running, "back offline, still on the farm")
	check(Game.owner_pid == Game.my_pid and Game.forked_from == host_world and Game.world_id != host_world,
		"the farm is now our own fork")
	check(Game.present.size() == 1 and Game.present.has(Game.my_pid), "only our cards drip now")
	check(Game.hands.has(host_pid), "the host's hand is kept in our copy")
	var saved := _slot_game(SLOT)
	check(saved.get("owner_pid", "") == Game.my_pid and saved.get("world_id", "") == Game.world_id, "our fork was saved")
	var uids := {main.world.farmer.uid: true}
	for a in main.world.animals:
		uids[a.uid] = true
	check(uids.size() == main.world.animals.size() + 1 and main.world.next_uid > uids.keys().max(), "actor ids still unique, counter ahead")
	var p1: Vector2 = main.world.farmer.pos
	var pop: int = main.world.animals.size()
	await until(func() -> bool: return main.world.farmer.pos.distance_to(p1) > 2.0, 15.0)
	check(main.world.farmer.pos.distance_to(p1) > 2.0, "the farm simulates on our side now (%d actors kept)" % pop)
	# 3. host our fork; the old host comes to visit
	check(Net.host(port + 1) == OK, "hosting our fork on port %d" % (port + 1))
	if not check(await until(func() -> bool: return Net.guest_pid != "", 30.0), "the old host joined our fork"):
		return
	check(Net.guest_pid == host_pid and Game.hand(host_pid)["box"] == host_hand, "the old host's hand was kept, not recreated")
	# 4. the visitor leaves
	var left := await until(func() -> bool: return Net.guest_pid == "", 60.0)
	check(left, "noticed the visitor leaving")
	check(Net.last_exit == "bye", "the visitor said goodbye (no timeout wait)")
	check(not Game.present.has(host_pid) and Game.hands.has(host_pid), "the visitor's hand stays for next time")


# ---------------------------------------------------------------- solo: addresses, UPnP, join errors
func _solo() -> void:
	# typed addresses
	var cases := {"1.2.3.4": ["1.2.3.4", Net.PORT], " 1.2.3.4:5000 ": ["1.2.3.4", 5000], "farm.example.com:99": ["farm.example.com", 99],
		"[::1]:7000": ["::1", 7000], "::1": ["::1", Net.PORT], "localhost": ["localhost", Net.PORT],
		"": [], "1.2.3.4:": [], "1.2.3.4:abc": [], "1.2.3.4:70000": [], "999.1.1.1": [], "two words": [], "a_b": [], "[::1": []}
	for t in cases:
		var got: Array = Net.parse_address(t)
		check(got == cases[t], "parse_address(%s) -> %s" % [JSON.stringify(t), got])
	# the router step, faked
	main.start_slot(SLOT)
	Game.running = true
	var real := Net.use_upnp
	Net.use_upnp = true
	if not real:
		Net.upnp_fake = {"ok": true, "ip": "203.0.113.7"}
	check(Net.host(port) == OK, "hosting (UPnP %s)" % ("REAL" if real else "faked: router says yes"))
	check(await until(func() -> bool: return Net.upnp_state != "working", 10.0), "the router step finished")
	print("  [solo] status: ", Net.status)
	for l in Net.help_lines():
		print("  [solo] help: ", l)
	if not real:
		check(Net.upnp_state == "open" and Net.share_address() == "203.0.113.7:%d" % port, "share the internet address when the port is open")
		Net.stop()
		Net.upnp_fake = {"ok": false, "why": "the router said no (718)"}
		Net.host(port)
		await until(func() -> bool: return Net.upnp_state != "working", 10.0)
		var lan := Net.lan_addresses()
		check(Net.upnp_state == "failed" and Net.share_address().ends_with(":%d" % port)
			and (lan.is_empty() or Net.share_address().begins_with(lan[0])), "fall back to the LAN address (%s)" % Net.share_address())
		var help := "
".join(Net.help_lines())
		check("forward UDP port %d" % port in help and "718" in help and "firewall" in help, "the help text explains port forwarding")
		print("  [solo] fallback status: ", Net.status)
		Net.upnp_fake = {}
	var mapped := real and Net.upnp_state == "open"
	if real:
		print("  [solo] router lease: %ds (0 = permanent), mapped: %s" % [Net.upnp_lease, mapped])
	Net.stop()
	check(Net.upnp_state == "" and Net.mode == "offline", "stopping clears the router state")
	if mapped:
		# ask the router to delete it again: it must say there's no such mapping any more
		var u := UPNP.new()
		var found := u.discover(Net.UPNP_WAIT_MS, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS
		var again := u.delete_port_mapping(port, "UDP") if found else -1
		print("  [solo] router after stop: delete again -> %d" % again)
		check(found and again != UPNP.UPNP_RESULT_SUCCESS, "the port mapping is gone from the router (%d)" % again)
	Net.use_upnp = real
	# joining nobody: a clear message, not a hang
	var t := Time.get_ticks_msec()
	check(Net.join("127.0.0.1", port + 7, SLOT_VISIT) == OK, "trying to join a port nobody listens on")
	await until(func() -> bool: return Net.mode == "offline", 15.0)
	var secs := (Time.get_ticks_msec() - t) / 1000.0
	check(Net.mode == "offline" and secs < Net.JOIN_TIMEOUT + 1.5, "gave up after %.1fs" % secs)
	check("hosting" in Net.status, "said why: %s" % Net.status)
	check(Game.running and not Game.puppet, "still on our own farm")
