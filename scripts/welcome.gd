extends Control
## Welcome screen: page 0 = how to play, page 1 = pick one of Game.SLOT_COUNT save slots.
## Drawn with the pixel font over a little animated night-time farm. Calls main.start_slot(n).

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
	["THE FARMER RUNS HIS FARM ALL BY HIMSELF:", C_GOLD],
	["PLANTING, WATERING, BUILDING, CHATTING.", C_TEXT],
	["WEATHER, CRITTERS AND STRANGER THINGS", C_TEXT],
	["CAN HURT HIM IF NOBODY LOOKS OUT FOR HIM.", C_TEXT],
	["", C_TEXT],
	["CHOICE CARDS ARRIVE OVER TIME.", C_GOLD],
	["LET THEM PILE UP, THEN PLAY THEM.", C_TEXT],
	["EVERY CARD OFFERS TWO CHOICES -", C_TEXT],
	["YOU CAN ONLY PICK ONE.", C_TEXT],
	["", C_TEXT],
	["SOME CHOICES NEED THINGS FIRST, LIKE", C_GOLD],
	["3 SUNFLOWERS GROWING AT ONCE.", C_TEXT],
	["THE HARDER THE NEED, THE BIGGER", C_TEXT],
	["THE PAYOFF.", C_TEXT],
	["", C_TEXT],
	["ODD VISITORS COME CALLING. THE STRANGER", C_PURPLE],
	["YOUR CHOICES, THE STRANGER THE FARM", C_PURPLE],
	["GETS. KEEP AN EYE ON THE EYE.", C_PURPLE],
	["", C_TEXT],
	["CLICK THE FARMER TO SAY HELLO.", C_DIM],
	["DRAG THE TOP BAR TO MOVE THE WINDOW.", C_DIM],
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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(192, 432)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		stars.append(Vector3(rng.randi_range(2, 189), rng.randi_range(18, 300), rng.randf() * TAU))
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
	else:
		for i in Game.SLOT_COUNT:
			var box := Rect2(8, 150 + i * 62, 176, 54)
			r["slot%d" % (i + 1)] = box
			if not metas[i].is_empty():
				r["del%d" % (i + 1)] = Rect2(box.end.x - 30, box.end.y - 13, 26, 10)
		r["back"] = Rect2(8, 404, 40, 15)
	return r


func _input(event: InputEvent) -> void:
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
			page = 0
			confirm_delete = -1
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
		_txt("FARM %d" % n, box.position + Vector2(5, 5), C_GOLD)
		if m.is_empty():
			_txt("EMPTY FIELD", box.position + Vector2(5, 16), C_DIM)
			_txt("> START A NEW FARM", box.position + Vector2(5, 28), C_GREEN if hov else C_TEXT)
			draw_texture(Art.tex("sprout"), box.position + Vector2(160, 6))
		elif m.has("broken"):
			_txt("SAVE DAMAGED - DELETE TO REUSE", box.position + Vector2(5, 16), C_RED)
		else:
			_txt("DAY %d   LV %d   %d COINS" % [m.get("day", 1), m.get("level", 1), m.get("coins", 0)], box.position + Vector2(5, 16), C_TEXT)
			var w := int(m.get("weird", 0))
			var line2 := "WEIRD %d   RELICS %d" % [w, m.get("relics", 0)]
			_txt(line2, box.position + Vector2(5, 25), C_PURPLE if w >= 10 else C_DIM)
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
