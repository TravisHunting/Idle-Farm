extends Node
## See click_test.gd. Two copies, each with its own profile (settings + slots 1-3 are wiped first):
##   host:  welcome > CONTINUE > FARM 1 (new farm) > gear > types its name > HOST THIS FARM;
##          when the guest is in, deals it 3 cards (the only step done in code: the drip takes minutes);
##          sees the guest's name and card play in the log, the guest leaving, then STOP HOSTING > menu.
##   guest: welcome > CONTINUE > JOIN A FRIEND > types its name, Enter, types the address, Enter
##          (JOIN again while the host isn't up yet); drags a card to its stash, opens another and
##          clicks a choice; gear > LEAVE (KEEP A COPY): back on the menu, FARM 1 is tagged SHARED.
## Only clicks where the screens draw their buttons (their own layout functions say where).

var role := "host"
var port := 24700
var out := ""
var main: Node
var failures: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("role="):
			role = a.substr(5)
		elif a.begins_with("port="):
			port = int(a.substr(5))
		elif a.begins_with("out=") and DisplayServer.get_name() != "headless":
			out = a.substr(4)
	Net.use_upnp = false   # never the real router
	_wipe()
	Game.settings["name"] = ""
	Game.settings["last_join"] = ""
	Game.settings["port"] = port
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await wait(0.3)
	if role == "host":
		await _host()
	else:
		await _guest()
	Net.stop()
	await wait(0.3)
	_wipe()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.settings_path()))
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


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _wipe() -> void:
	for n in Game.SLOT_COUNT:
		var p := ProjectSettings.globalize_path(Game.slot_path(n + 1))
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _shot(name_: String) -> void:
	if out == "":
		return
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	img.save_png(out.path_join("%s_%s.png" % [role, name_]))


# ---------------------------------------------------------------- input, in screen (192x432) pixels
func _push(e: InputEvent) -> void:
	get_viewport().push_input(e, true)


func _move(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	_push(m)


func _button(p: Vector2, down: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	b.position = p
	b.global_position = p
	_push(b)


## Moves there, presses and lets go, a frame apart.
func click(p: Vector2) -> void:
	_move(p)
	await get_tree().process_frame
	_button(p, true)
	await get_tree().process_frame
	_button(p, false)
	await wait(0.1)


func click_rect(r: Rect2) -> void:
	await click(r.get_center())


func drag(a: Vector2, b: Vector2) -> void:
	_move(a)
	await get_tree().process_frame
	_button(a, true)
	for i in 6:
		await get_tree().process_frame
		_move(a.lerp(b, (i + 1) / 6.0))
	await get_tree().process_frame
	_button(b, false)
	await wait(0.1)


func key(code: Key, unicode := 0) -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.unicode = unicode if down else 0
		k.pressed = down
		_push(k)
		await get_tree().process_frame


func type_text(s: String) -> void:
	for ch in s:
		var code: Key = KEY_PERIOD if ch == "." or ch == ":" else OS.find_keycode_from_string(ch.to_upper())
		await key(code, ch.unicode_at(0))


# ---------------------------------------------------------------- host
func _host() -> void:
	var w: Control = main.welcome
	await click_rect(w._rects()["continue"])
	check(w.page == 1, "CONTINUE shows the farms")
	await click_rect(w._rects()["slot1"])
	if not check(await until(func() -> bool: return Game.running and main.hud != null, 3.0), "FARM 1 starts a new farm"):
		return
	var hud: Control = main.hud
	await click_rect(hud.btns["gear"])
	check(hud.settings_open, "the gear opens the settings")
	await _shot("settings")
	await click_rect(hud._settings_rects()["name"])
	check(hud.name_focus, "clicking the name field focuses it")
	await type_text("Alice")
	await key(KEY_ENTER)
	check(not hud.name_focus and Game.settings.get("name", "") == "ALICE" and Game.hand()["name"] == "ALICE",
		"the typed name is kept (%s)" % Game.settings.get("name", ""))
	await click_rect(hud._settings_rects()["host"])
	if not check(Net.mode == "hosting" and Net.host_port == port, "HOST THIS FARM hosts on the settings port (%d)" % Net.host_port):
		return
	check(hud._settings_rects().has("stop_host") and hud._settings_rects().has("copy"), "the panel now offers COPY / STOP")
	await _shot("hosting")
	await click_rect(hud._settings_rects()["done"])
	check(not hud.settings_open, "DONE closes the settings")
	if not check(await until(func() -> bool: return Net.guest_pid != "", 30.0), "the guest joined"):
		return
	var g := Net.guest_pid
	await until(func() -> bool: return Game.hand(g).get("name", "") == "BOB", 3.0)
	check(Game.player_name(g) == "BOB", "the guest's typed name reached the host (%s)" % Game.player_name(g))
	check(String(hud.toast.get("text", "")).contains("BOB"), "a toast says who came (%s)" % hud.toast.get("text", ""))
	for i in 3:
		main.cards.draw_card(g)
	await _shot("together")
	check(await until(func() -> bool: return Game.hand(g)["stash"][0] != "", 30.0), "the guest dragged a card to its stash")
	var chose := await until(func() -> bool:
		for l in Game.log_lines:
			if String(l).begins_with("BOB chose"):
				return true
		return false, 30.0)
	check(chose, "the guest's card choice shows in the log as BOB's")
	check(await until(func() -> bool: return Net.guest_pid == "", 15.0), "the guest left (noticed at once)")
	check(Net.mode == "hosting" and Game.running and not Game.puppet, "still hosting our own farm")
	await click_rect(hud.btns["gear"])
	await click_rect(hud._settings_rects()["stop_host"])
	check(Net.mode == "offline", "STOP HOSTING stops")
	check(hud._settings_rects().has("host"), "the panel offers HOST THIS FARM again")
	await click_rect(hud._settings_rects()["done"])
	await click_rect(hud.btns["menu"])
	check(is_instance_valid(main.welcome) and main.welcome.page == 1 and not Game.running,
		"the menu button goes back to the farms")


# ---------------------------------------------------------------- guest
func _guest() -> void:
	var w: Control = main.welcome
	await click_rect(w._rects()["continue"])
	await click_rect(w._rects()["friend"])
	if not check(w.page == 2 and w.focus == "name", "JOIN A FRIEND opens the join page, name field first"):
		return
	await type_text("Bob")
	await key(KEY_ENTER)
	check(w.focus == "addr" and w.name_entry.text == "BOB", "Enter moves from the name to the address")
	await type_text("127.0.0.1:%dx" % port)
	await key(KEY_BACKSPACE)
	check(w.addr_entry.text == "127.0.0.1:%d" % port, "the address was typed, Backspace works (%s)" % w.addr_entry.text)
	await key(KEY_ENTER)   # = JOIN
	check(Net.mode == "joining", "Enter in the address joins")
	await _shot("join")
	# the host may still be on its way: press JOIN again until it answers
	for tries in 15:
		await until(func() -> bool: return Net.mode != "joining", 9.0)
		if Net.is_guest():
			break
		await wait(1.0)
		await click_rect(w._rects()["join"])
	if not check(await until(func() -> bool: return Net.is_guest() and Game.running and main.hud != null, 5.0), "joined the host's farm"):
		return
	check(Game.puppet and Game.settings.get("name", "") == "BOB" and Game.settings.get("last_join", "") == "127.0.0.1:%d" % port,
		"in puppet mode; the name and address are remembered")
	var hud: Control = main.hud
	if not check(await until(func() -> bool: return Game.card_count() >= 3, 20.0), "the host's cards for us arrived"):
		return
	await wait(0.5)
	await _shot("cards")
	# drag the first box card into the first stash slot
	var id0 := Game.card_at("box", 0)
	await drag(hud._slot_rect("box", 0).get_center(), hud._slot_rect("stash", 0).get_center())
	check(await until(func() -> bool: return Game.stash[0] == id0, 5.0), "dragging a card to the stash moved it (via the host)")
	# open a box card that can be played, click a choice
	var slot := -1
	var which := ""
	for k in Game.BOX_SIZE:
		var c: Dictionary = main.cards.card(Game.card_at("box", k))
		for ch in ["a", "b"]:
			if slot < 0 and not c.is_empty() and main.cards.can_choose(c, ch):
				slot = k
				which = ch
	if not check(slot >= 0, "a card in the box can be played"):
		return
	var id := Game.card_at("box", slot)
	var n := Game.card_count()
	await click_rect(hud._slot_rect("box", slot))
	check(hud.open_id == id, "clicking the card opens it")
	await _shot("card_open")
	await click_rect(hud._modal_rects()[which])
	check(hud.open_id == "", "choosing closes the card")
	check(await until(func() -> bool: return Game.card_count() < n, 5.0), "the played card left our hand (via the host)")
	# the host's world, the host's rules: the cadence buttons do nothing for us
	await click_rect(hud.btns["gear"])
	var before := int(Game.settings.get("card_minutes", Game.DEFAULT_CARD_MINUTES))
	await click_rect(hud._settings_rects()["min_up"])
	check(int(Game.settings.get("card_minutes", Game.DEFAULT_CARD_MINUTES)) == before, "a guest can't change the card cadence")
	await _shot("settings")
	check(hud._settings_rects().has("leave"), "the panel offers LEAVE")
	await wait(1.0)
	await click_rect(hud._settings_rects()["leave"])
	check(Net.mode == "offline" and not Game.running and not Game.puppet, "LEAVE goes back to the menu")
	w = main.welcome
	check(is_instance_valid(w) and w.page == 1, "on the farms page")
	check(main.slot_meta(1).get("shared", false), "FARM 1 keeps the copy, tagged SHARED")
	await _shot("menu")
