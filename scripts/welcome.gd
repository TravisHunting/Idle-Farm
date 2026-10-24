extends Control
## Welcome screen: page 0 = how to play, page 1 = pick one of Game.SLOT_COUNT save slots,
## page 2 = join a friend's farm (name, address, which slot keeps the copy; see MULTIPLAYER.md).
## Drawn with the pixel font over a little animated night-time farm. Calls main.start_slot(n),
## or Net.join() (Net then calls main.start_guest).

const C_BG := Color("1a1c2c")
const C_PANEL := Color("262b44")
const C_SLOT := Color("3a4466")
const C_EDGE := Color("5a6988")
const C_TEXT := Color("f4f4f4")
const C_DIM := Color("94b0c2")
const C_GOLD := Color("ffcd75")
const C_RED := Color("e43b44")
const C_GREEN := Color("a7f070")
const C_PURPLE := Color("b45cff")
const C_SHADOW := Color(0, 0, 0, 0.6)

const HOW_TO := [
	["GRANDPA LEFT YOU HIS FARM. IT IS VERY", C_GOLD],
	["OVERGROWN. THE FARMER CLEARS IT, PLANS", C_TEXT],
	["(SILLY) FIELDS, LAYS PATHS AND FENCES,", C_TEXT],
	["PLANTS AND BUILDS - ALL BY HIMSELF.", C_TEXT],
	["", C_TEXT],
	["EVERY FEW MINUTES A CARD SLIDES INTO", C_GOLD],
	["THE BOX. THE BOX HOLDS 3 - THE OLDEST", C_TEXT],
	["FALLS OUT. DRAG CARDS TO YOUR STASH", C_TEXT],
	["TO KEEP THEM. EACH CARD HAS TWO", C_TEXT],
	["CHOICES THAT CHANGE THE FARM.", C_TEXT],
	["", C_TEXT],
	["SOME CHOICES NEED THINGS FIRST, AND", C_GOLD],
	["SOME CARDS ONLY EVER SHOW UP ONCE", C_TEXT],
	["THEIR TIME HAS COME.", C_TEXT],
	["", C_TEXT],
	["ODD VISITORS COME CALLING. THE STRANGER", C_PURPLE],
	["YOUR CHOICES, THE STRANGER THE FARM", C_PURPLE],
	["GETS. KEEP AN EYE ON THE EYE.", C_PURPLE],
	["", C_TEXT],
	["CLICK THE FARMER FOR HIS STATS.", C_DIM],
	["THE GEAR SETS HOW OFTEN CARDS COME.", C_DIM],
	["PROGRESS SAVES ITSELF AS YOU PLAY.", C_DIM],
]

var main: Node
var page := 0
var hover := ""
var confirm_delete := -1
var metas: Array = []
var t := 0.0
var dragging := false
var drag_off := Vector2i.ZERO
var stars: Array = []
var name_entry := TextEntry.new(12, TextEntry.NAME)
var addr_entry := TextEntry.new(40, TextEntry.ADDRESS)
var focus := ""              # "name" / "addr" / "" (which field gets the keys)
var join_slot := 1
var join_sure := false       # the chosen slot has a farm in it: JOIN asks once more
var join_error := ""         # a problem found before connecting (a bad address)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(192, 432)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		stars.append(Vector3(rng.randi_range(2, 189), rng.randi_range(18, 300), rng.randf() * TAU))
	name_entry.set_text(String(Game.settings.get("name", "")))
	addr_entry.set_text(String(Game.settings.get("last_join", "")))
	_refresh()


func _refresh() -> void:
	metas.clear()
	for i in Game.SLOT_COUNT:
		metas.append(main.slot_meta(i + 1))


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


# ---------------------------------------------------------------- layout
func _rects() -> Dictionary:
	var r := {"close": Rect2(180, 3, 9, 9), "min": Rect2(169, 3, 9, 9)}
	if page == 0:
		r["continue"] = Rect2(56, 404, 80, 15)
	elif page == 2:
		r["name"] = Rect2(8, 132, 176, 11)
		r["addr"] = Rect2(8, 160, 176, 11)
		for i in Game.SLOT_COUNT:
			r["keep%d" % (i + 1)] = Rect2(8 + i * 60, 188, 56, 24)
		r["back"] = Rect2(8, 404, 40, 15)
		r["join"] = Rect2(100, 404, 84, 15)
	else:
		r["friend"] = Rect2(100, 404, 84, 15)
		for i in Game.SLOT_COUNT:
			var box := Rect2(8, 150 + i * 62, 176, 54)
			r["slot%d" % (i + 1)] = box
			if not metas[i].is_empty():
				r["del%d" % (i + 1)] = Rect2(box.end.x - 30, box.end.y - 13, 26, 10)
		r["back"] = Rect2(8, 404, 40, 15)
	return r


func _input(event: InputEvent) -> void:
	if event is InputEventKey and page == 2 and focus != "":
		_key(event)
		return
	if event is InputEventMouseMotion:
		if dragging:
			DisplayServer.window_set_position(DisplayServer.mouse_get_position() - drag_off)
			return
		hover = _hit(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			dragging = false
			return
		var p: Vector2 = event.position
		var h := _hit(p)
		if h == "":
			focus = ""
			if p.y < 16 and not main.embedded:
				dragging = true
				drag_off = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
			elif page == 0 and p.y > 16:
				page = 1
			confirm_delete = -1
			return
		get_viewport().set_input_as_handled()
		if h == "close":
			get_tree().quit()
		elif h == "min":
			main.minimize()
		elif h == "continue":
			page = 1
			_refresh()
		elif h == "back":
			if page == 2:
				Net.stop()
			page = 1 if page == 2 else 0
			confirm_delete = -1
			focus = ""
		elif h == "friend":
			page = 2
			join_error = ""
			join_sure = false
			_refresh()
			focus = "name" if name_entry.text == "" else "addr"
		elif h == "name" or h == "addr":
			focus = h
		elif h.begins_with("keep"):
			join_slot = int(h.substr(4))
			join_sure = false
		elif h == "join":
			_join()
		elif h.begins_with("del"):
			var n := int(h.substr(3))
			if confirm_delete == n:
				main.delete_slot(n)
				confirm_delete = -1
				_refresh()
			else:
				confirm_delete = n
		elif h.begins_with("slot"):
			main.start_slot(int(h.substr(4)))


func _key(e: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if e is InputEventKey and e.pressed and e.keycode == KEY_TAB:
		focus = "addr" if focus == "name" else "name"
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		focus = ""
		return
	var res := (name_entry if focus == "name" else addr_entry).key(e)
	if res == "edit":
		join_error = ""
		join_sure = false
	elif res == "submit":
		if focus == "name":
			focus = "addr"
		else:
			_join()


## JOIN pressed: check the address, confirm overwriting a farm, then connect (or cancel).
func _join() -> void:
	if Net.mode == "joining":
		Net.stop()
		return
	var a := Net.parse_address(addr_entry.text)
	if a.is_empty():
		join_error = "THAT ISN'T AN ADDRESS. IT LOOKS LIKE 1.2.3.4:24680"
		focus = "addr"
		return
	if not metas[join_slot - 1].is_empty() and not join_sure:
		join_sure = true
		return
	focus = ""
	join_sure = false
	join_error = ""
	Game.settings["name"] = name_entry.text.strip_edges()
	Game.settings["last_join"] = addr_entry.text
	Game.save_settings()
	Net.join(a[0], a[1], join_slot)


func _hit(p: Vector2) -> String:
	var r := _rects()
	# delete buttons sit inside slot boxes: test them first
	for k in r:
		if String(k).begins_with("del") and r[k].has_point(p):
			return k
	for k in r:
		if r[k].has_point(p):
			return k
	return ""


# ---------------------------------------------------------------- drawing
func _txt(s: String, p: Vector2, c: Color = C_TEXT) -> void:
	Art.draw_text(self, s, p, c, C_SHADOW)


func _ctxt(s: String, y: float, c: Color = C_TEXT) -> void:
	_txt(s, Vector2(96 - Art.text_width(s) / 2, y), c)


func _frame(r: Rect2, edge: Color, fill: Color) -> void:
	draw_rect(r, edge)
	draw_rect(r.grow(-1), fill)


func _draw() -> void:
	# backdrop: night sky, stars, hills, a tiny farm
	draw_rect(Rect2(2, 0, 188, 1), C_BG)
	draw_rect(Rect2(1, 1, 190, 1), C_BG)
	draw_rect(Rect2(0, 2, 192, 428), C_BG)
	draw_rect(Rect2(1, 430, 190, 1), C_BG)
	draw_rect(Rect2(2, 431, 188, 1), C_BG)
	for s in stars:
		var a := 0.35 + 0.35 * sin(t * 1.5 + s.z)
		draw_rect(Rect2(s.x, s.y, 1, 1), Color(1, 1, 1, a))
	_draw_title()
	if page == 0:
		_draw_howto()
	elif page == 2:
		_draw_join()
	else:
		_draw_slots()
	# top strip buttons
	draw_rect(Rect2(0, 15, 192, 1), C_EDGE)
	for k in ["min", "close"]:
		var r: Rect2 = _rects()[k]
		draw_rect(r, C_EDGE if hover == k else C_SLOT)
		Art.draw_text(self, "_" if k == "min" else "X", r.position + Vector2(3, 2), C_TEXT)
	_txt("WELCOME", Vector2(4, 5), C_DIM)


func _draw_title() -> void:
	# big title: the pixel font drawn at 3x
	var title := "IDLE FARM"
	draw_set_transform(Vector2(96 - Art.text_width(title) * 1.5, 26 + sin(t * 1.2) * 1.0), 0.0, Vector2(3, 3))
	Art.draw_text(self, title, Vector2.ZERO, C_GOLD, Color("8b5a3c"))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_ctxt("A FARMER. A FIELD. SOME VISITORS.", 48, C_DIM)
	# vignette: hill + house + farmer + a pale visitor
	var gy := 82.0
	for x in 192:
		var h := 4.0 + sin(x * 0.05) * 3.0
		draw_rect(Rect2(x, gy - h, 1, h + 12), Color("2a5a3a"))
	draw_texture(Art.tex("house"), Vector2(18, gy - 30))
	var fx := 70.0 + sin(t * 0.5) * 20.0
	draw_set_transform(Vector2(fx, gy - 2), 0.0, Vector2(-1.0 if cos(t * 0.5) < 0.0 else 1.0, 1.0))
	draw_texture(Art.tex("farmer_walk1" if int(t * 5.0) % 2 == 0 else "farmer_walk2"), Vector2(-8, -15))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_texture(Art.tex("crop_sunflower"), Vector2(110, gy - 16))
	draw_texture(Art.tex("crop_sunflower"), Vector2(124, gy - 15))
	draw_texture(Art.tex("v_peddler"), Vector2(150, gy - 17 + (1.0 if int(t * 2.0) % 2 == 0 else 0.0)), Color(1, 1, 1, 0.55 + 0.25 * sin(t)))
	draw_texture(Art.tex("ic_moon"), Vector2(160, 54))
	draw_rect(Rect2(0, gy + 8, 192, 2), C_EDGE)


func _draw_howto() -> void:
	_ctxt("HOW TO PLAY", 98, C_GOLD)
	for i in HOW_TO.size():
		_txt(HOW_TO[i][0], Vector2(6, 110 + i * 12), HOW_TO[i][1])
	var r: Rect2 = _rects()["continue"]
	var hov := hover == "continue"
	var blink := int(t * 2.0) % 2 == 0
	_frame(r, C_GOLD if hov or blink else Color("ef7d57"), Color("b13e53") if not hov else Color("ef7d57"))
	_ctxt("CONTINUE", r.position.y + 5, C_TEXT)


func _draw_slots() -> void:
	_ctxt("CHOOSE A FARM", 106, C_GOLD)
	_ctxt("EACH FARM SAVES ITSELF AS YOU PLAY.", 118, C_DIM)
	_ctxt("CLICK ONE TO PLAY.", 128, C_DIM)
	var r := _rects()
	for i in Game.SLOT_COUNT:
		var n := i + 1
		var box: Rect2 = r["slot%d" % n]
		var m: Dictionary = metas[i]
		var hov := hover == "slot%d" % n
		_frame(box, C_GOLD if hov else C_EDGE, C_PANEL if not hov else Color("303859"))
		var nm := String(m.get("farm", "")).to_upper()
		_txt("FARM %d" % n if nm == "" else nm, box.position + Vector2(5, 5), C_GOLD)
		if m.is_empty():
			_txt("EMPTY FIELD", box.position + Vector2(5, 16), C_DIM)
			_txt("> START A NEW FARM", box.position + Vector2(5, 28), C_GREEN if hov else C_TEXT)
			draw_texture(Art.tex("sprout"), box.position + Vector2(160, 6))
		elif m.has("broken"):
			_txt("SAVE DAMAGED - DELETE TO REUSE", box.position + Vector2(5, 16), C_RED)
		else:
			_txt("DAY %d   LV %d   %d WORTH" % [m.get("day", 1), m.get("level", 1), m.get("wealth", m.get("coins", 0))], box.position + Vector2(5, 16), C_TEXT)
			var w := int(m.get("weird", 0))
			var line2 := "WEIRD %d   RELICS %d" % [w, m.get("relics", 0)]
			_txt(line2, box.position + Vector2(5, 25), C_PURPLE if w >= 10 else C_DIM)
			if m.get("shared", false) or m.get("forked", false):
				var tag := "SHARED" if m.get("shared", false) else "SPLIT OFF"
				_txt(tag, Vector2(box.end.x - 36 - Art.text_width(tag), box.position.y + 43), C_GREEN)   # left of DEL
			_txt("SAVED " + _ago(float(m.get("time", 0.0))), box.position + Vector2(5, 34), C_DIM)
			_txt("PLAYED " + _dur(float(m.get("play_seconds", 0.0))), box.position + Vector2(5, 43), C_DIM)
			draw_texture(Art.tex("house"), box.position + Vector2(140, 4))
			var dr: Rect2 = r["del%d" % n]
			var sure := confirm_delete == n
			_frame(dr, C_RED if hover == "del%d" % n or sure else C_EDGE, Color("4a2030") if sure else C_SLOT)
			_txt("SURE?" if sure else "DEL", dr.position + Vector2(3 if sure else 7, 3), C_RED if sure else C_TEXT)
	var b: Rect2 = r["back"]
	_frame(b, C_GOLD if hover == "back" else C_EDGE, C_SLOT)
	_txt("< BACK", b.position + Vector2(8, 5), C_TEXT)
	var fr: Rect2 = r["friend"]
	_frame(fr, C_GOLD if hover == "friend" else C_EDGE, C_SLOT)
	_txt("JOIN A FRIEND >", fr.position + Vector2(13, 5), C_GREEN)


func _draw_join() -> void:
	var r := _rects()
	_ctxt("JOIN A FRIEND", 106, C_GOLD)
	_ctxt("PLAY ON THEIR FARM, TOGETHER.", 116, C_DIM)
	_txt("YOUR NAME", Vector2(8, 125), C_TEXT)
	name_entry.draw(self, r["name"], focus == "name", t, "FRIEND")
	_txt("THEIR ADDRESS (IP:PORT)", Vector2(8, 153), C_TEXT)
	addr_entry.draw(self, r["addr"], focus == "addr", t, "1.2.3.4:%d" % Net.PORT)
	_txt("KEEP A COPY OF THEIR FARM IN", Vector2(8, 181), C_TEXT)
	for i in Game.SLOT_COUNT:
		var n := i + 1
		var box: Rect2 = r["keep%d" % n]
		var sel := join_slot == n
		_frame(box, C_GOLD if sel else (C_DIM if hover == "keep%d" % n else C_EDGE), Color("303859") if sel else C_PANEL)
		_txt("FARM %d" % n, box.position + Vector2(5, 4), C_GOLD if sel else C_TEXT)
		var m: Dictionary = metas[i]
		var what := "EMPTY" if m.is_empty() else ("DAY %d" % int(m.get("day", 1)))
		_txt(what, box.position + Vector2(5, 14), C_DIM if m.is_empty() else C_RED)
	var y := 218.0
	var m2: Dictionary = metas[join_slot - 1]
	if not m2.is_empty():
		var nm := String(m2.get("farm", "")).to_upper()
		var warn := "THIS REPLACES %s (DAY %d) IN FARM %d." % [nm, int(m2.get("day", 1)), join_slot] if nm != "" \
			else "THIS REPLACES THE DAY %d FARM IN FARM %d." % [int(m2.get("day", 1)), join_slot]
		for l in Art.wrap(warn, 44):
			_txt(l, Vector2(8, y), C_RED)
			y += 8
	y += 6
	var msg := join_error if join_error != "" else Net.status.to_upper()
	var col := C_RED if join_error != "" or Net.mode == "offline" else C_GREEN
	for l in Art.wrap(msg, 44):
		_txt(l, Vector2(8, y), col)
		y += 8
	var notes := [
		"ASK YOUR FRIEND FOR THE ADDRESS IN",
		"THEIR GEAR MENU > HOST THIS FARM.",
		"",
		"YOU BOTH KEEP A COPY OF THE FARM:",
		"IF EITHER OF YOU LEAVES, THE OTHER",
		"CARRIES ON WITH IT.",
	]
	for i in notes.size():
		_txt(notes[i], Vector2(8, 330 + i * 9), C_DIM)
	var b: Rect2 = r["back"]
	_frame(b, C_GOLD if hover == "back" else C_EDGE, C_SLOT)
	_txt("< BACK", b.position + Vector2(8, 5), C_TEXT)
	var j: Rect2 = r["join"]
	var label := "CANCEL" if Net.mode == "joining" else ("SURE? REPLACE" if join_sure else "JOIN")
	var hov := hover == "join"
	_frame(j, C_GOLD if hov else (C_RED if join_sure else C_EDGE), Color("b13e53") if join_sure else C_SLOT)
	_txt(label, j.position + Vector2(42 - Art.text_width(label) / 2.0, 5), C_TEXT)


func _ago(ts: float) -> String:
	var s := Time.get_unix_time_from_system() - ts
	if s < 90.0:
		return "JUST NOW"
	if s < 3600.0:
		return "%d MIN AGO" % int(s / 60.0)
	if s < 86400.0:
		return "%d HR AGO" % int(s / 3600.0)
	return "%d DAYS AGO" % int(s / 86400.0)


func _dur(s: float) -> String:
	if s < 3600.0:
		return "%d MIN" % int(s / 60.0)
	return "%dH %02dM" % [int(s / 3600.0), int(fmod(s, 3600.0) / 60.0)]
