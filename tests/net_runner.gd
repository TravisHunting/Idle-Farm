extends Node
## Two copies of the game on localhost (MULTIPLAYER.md): one hosts a farm, the other joins it.
## Runs in real time (the network needs real frames). What it checks:
##   host:  the guest joins and gets a hand; the guest's card play arrives as a command and is
##          applied to the guest's hand; the guest leaving is noticed
##   guest: it lands in puppet mode with the host's world; actors stream in and move; a card the
##          host gives it shows up; playing it comes back in the next snapshot; bandwidth report
## Exit code 0 = all checks passed (each copy reports its own checks).

const SLOT := 8
const BANDWIDTH_WINDOW := 15.0

var role := "host"
var port := 24690
var main: Node
var failures: Array = []
var t0 := 0.0
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
	_run.call_deferred()


func _run() -> void:
	_wipe()
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	t0 = Time.get_ticks_msec() / 1000.0
	if role == "host":
		await _host()
	else:
		await _guest()
	_wipe()
	print("[%s] stats: %s" % [role, Net.stats])
	if failures.is_empty():
		print("== [%s] ALL CHECKS PASSED" % role)
		get_tree().quit(0)
	else:
		for f in failures:
			print("FAIL [%s]: %s" % [role, f])
		get_tree().quit(1)


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
	else:
		print("  ok [%s]: %s" % [role, what])


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
	var p := ProjectSettings.globalize_path(Game.slot_path(SLOT))
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


# ---------------------------------------------------------------- host
func _host() -> void:
	main.start_slot(SLOT)
	Game.running = true
	# a busy farm, so the bandwidth check means something
	main.colony.arrive("saucer")
	main.swarm.arrive("hive")
	for i in 12:
		main.world.add_animal(Animal.new(main.world, "chicken", main.world.feet(main.world.DOOR) + Vector2(i * 6 - 36, 30)))
	check(Net.host(port) == OK, "hosting on port %d" % port)
	var joined := await until(func() -> bool: return Net.guest_pid != "", 30.0)
	check(joined, "the guest joined")
	if not joined:
		return
	var g := Net.guest_pid
	check(Game.hands.has(g) and Game.present.has(g), "the guest has a hand and is present")
	check(Game.owner_pid == Game.my_pid, "the host still owns the world")
	await wait(2.0)
	# give the guest something to play
	for i in 3:
		main.cards.draw_card(g)
	var played := await until(func() -> bool:
		for l in Game.log_lines:
			if String(l).begins_with(Game.player_name(g) + " chose"):
				return true
		return false, 30.0)
	check(played, "the guest's card play arrived and was applied")
	check(Game.card_count(g) < 3, "the card left the guest's hand on the host")
	check(Game.card_count() == Game.card_count(Game.my_pid), "the host's own hand is untouched")
	var left := await until(func() -> bool: return Net.guest_pid == "", 60.0)
	check(left, "the host noticed the guest leaving")
	check(not Game.present.has(g) and Game.hands.has(g), "the guest's hand stays, but no longer drips")
	await wait(0.5)
	Net.stop()


# ---------------------------------------------------------------- guest
func _guest() -> void:
	await wait(1.5)   # let the host open its port
	var tries := 0
	while tries < 5 and not Game.running:
		tries += 1
		check(Net.join("127.0.0.1", port, SLOT) == OK, "joining (try %d)" % tries)
		await until(func() -> bool: return Game.running or Net.mode == "offline", 6.0)
		if not Game.running:
			await wait(1.0)
	check(Game.running and Net.is_guest() and Game.puppet, "joined the host's farm in puppet mode")
	if not Game.running:
		return
	var t_join := Time.get_ticks_msec() / 1000.0
	check(Game.owner_pid != Game.my_pid, "the world belongs to the host")
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
	var got := await until(func() -> bool: return Game.card_count() > 0, 20.0)
	check(got, "the cards the host gave us arrived")
	if not got:
		return
	var where := "box"
	var i := -1
	var which := ""
	for k in Game.BOX_SIZE:
		var c: Dictionary = main.cards.card(Game.card_at("box", k))
		for w in ["a", "b"]:
			if which == "" and not c.is_empty() and main.cards.can_choose(c, w):
				i = k
				which = w
	check(which != "", "one of our cards is playable")
	if which == "":
		return
	var id := Game.card_at(where, i)
	main.commands.submit({"type": "choose", "where": where, "i": i, "which": which})
	var back := await until(func() -> bool: return not id in Game.box and Game.played.get(id, "") == which, 10.0)
	check(back, "our card play came back in the host's snapshot")
	if shot != "":
		await wait(3.0)
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		print("[guest] screenshot: ", shot)
	print("[guest] join + play took %.1fs" % (Time.get_ticks_msec() / 1000.0 - t_join))
	# steady-state bandwidth (the welcome packet with the whole farm is excluded)
	var b0 := int(Net.stats["received"])
	var w0: int = Net.wire()["received"]
	var s0 := int(Net.stats["states"])
	var a0 := int(Net.stats["actors"])
	var n0: int = main.world.animals.size()
	await wait(BANDWIDTH_WINDOW)
	var payload := (int(Net.stats["received"]) - b0) / BANDWIDTH_WINDOW
	var wire_rate := (int(Net.wire()["received"]) - w0) / BANDWIDTH_WINDOW
	print("[guest] steady %.0fs: payload %.1f KB/s, wire %.1f KB/s, %d states, %d actor packets, %d -> %d actors" % [
		BANDWIDTH_WINDOW, payload / 1024.0, wire_rate / 1024.0, int(Net.stats["states"]) - s0,
		int(Net.stats["actors"]) - a0, n0, main.world.animals.size()])
	check(wire_rate < 20.0 * 1024.0, "bandwidth on the wire under 20 KB/s (%.1f KB/s)" % (wire_rate / 1024.0))
	Net.stop()
	await wait(0.5)
