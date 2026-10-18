extends Control
## All UI, custom-drawn with the pixel font. Sits on a CanvasLayer so the night tint skips it.
## Layout (192x432): 0-16 top bar · 16-272 farm · 272-302 status · 302-432 activity tray.
## Input is handled in _input() with manual hit-testing (mouse_filter = IGNORE).

const FARM_Y := 16
const STATUS_Y := 272
const TRAY_Y := 302
const SLOT_W := 29
const SLOT_H := 23
const COLS := 6
const ROWS := 4

const C_BG := Color("1a1c2c")
const C_PANEL := Color("262b44")
const C_SLOT := Color("3a4466")
const C_EDGE := Color("5a6988")
const C_TEXT := Color("f4f4f4")
const C_DIM := Color("94b0c2")
const C_GOLD := Color("ffcd75")
const C_RED := Color("b13e53")
const C_GREEN := Color("a7f070")
const C_SHADOW := Color(0, 0, 0, 0.6)

var world: World
var director: Node
var main: Node

var hover_card := ""
var hover_btn := ""
var dragging := false
var drag_off := Vector2i.ZERO
var pulse := {}
var log_flash := 0.0
var btns := {
	"dock": Rect2(158, 3, 9, 9),
	"min": Rect2(169, 3, 9, 9),
	"close": Rect2(180, 3, 9, 9),
	"useall": Rect2(150, 416, 39, 13),
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(192, 432)
	Game.card_arrived.connect(func(id: String) -> void: pulse[id] = 1.0)
	Game.log_added.connect(func(_t: String) -> void: log_flash = 1.0)


func _process(delta: float) -> void:
	for k in pulse.keys():
		pulse[k] -= delta
		if pulse[k] <= 0.0:
			pulse.erase(k)
	log_flash = maxf(0.0, log_flash - delta)
	queue_redraw()


# ---------------------------------------------------------------- input
func _owned_ids() -> Array:
	var out: Array = []
	for id in Game.CARDS:
		if int(Game.cards.get(id, 0)) > 0:
			out.append(id)
	return out


func _slot_rect(i: int) -> Rect2:
	var col := i % COLS
	var row := i / COLS
	return Rect2(4 + col * (SLOT_W + 2), TRAY_Y + 12 + row * (SLOT_H + 2), SLOT_W, SLOT_H)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if dragging:
			DisplayServer.window_set_position(DisplayServer.mouse_get_position() - drag_off)
			return
		_update_hover(get_viewport().get_mouse_position())
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			dragging = false
			return
		var p := get_viewport().get_mouse_position()
		_update_hover(p)
		if hover_btn != "":
			match hover_btn:
				"dock": main.toggle_dock()
				"min": main.minimize()
				"close": main.save_and_quit()
				"useall": director.play_all()
			return
		if hover_card != "":
			director.play_card(hover_card)
			return
		if p.y < FARM_Y and not main.embedded:
			dragging = true
			drag_off = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
			return
		if p.y >= FARM_Y and p.y < STATUS_Y:
			var wp := p - Vector2(0, FARM_Y)
			var f := world.farmer
			if f and f.pos.distance_to(wp + Vector2(0, 6)) < 12.0:
				f.on_click()


func _update_hover(p: Vector2) -> void:
	hover_btn = ""
	hover_card = ""
	for k in btns:
		if btns[k].has_point(p):
			if k == "useall" and Game.card_count() == 0:
				continue
			hover_btn = k
			return
	var ids := _owned_ids()
	for i in ids.size():
		if _slot_rect(i).has_point(p):
			hover_card = ids[i]
			return


# ---------------------------------------------------------------- drawing
func _txt(s: String, p: Vector2, c: Color = C_TEXT) -> void:
	Art.draw_text(self, s, p, c, C_SHADOW)


func _bar(r: Rect2, v: float, c: Color) -> void:
	draw_rect(r, C_BG)
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2((r.size.x - 2) * clampf(v, 0.0, 1.0), r.size.y - 2)), c)


func _draw() -> void:
	_draw_world_overlays()
	_draw_top()
	_draw_status()
	_draw_tray()


func _draw_world_overlays() -> void:
	if world == null:
		return
	var f := world.farmer
	if f and f.bubble_t > 0.0 and f.bubble != "":
		var anchor := f.pos
		if f.hidden:
			anchor = Vector2(16, 6)
		_bubble(f.bubble, anchor + Vector2(0, FARM_Y - 18))
	for a in world.animals:
		if a.bubble_t > 0.0 and not a.dead:
			_bubble(a.bubble, a.pos + Vector2(0, FARM_Y - 18))
	for fl in world.floats:
		var c: Color = fl["c"]
		c.a = clampf(1.6 - fl["t"], 0.0, 1.0)
		var p: Vector2 = fl["p"] + Vector2(0, FARM_Y)
		if p.y > FARM_Y and p.y < STATUS_Y - 5:
			Art.draw_text(self, fl["text"], p, c, Color(0, 0, 0, c.a * 0.7))


func _bubble(text: String, bottom_center: Vector2) -> void:
	var lines := Art.wrap(text, 20)
	var w := 0
	for l in lines:
		w = maxi(w, Art.text_width(l))
	w += 6
	var h := lines.size() * 6 + 4
	var x := clampf(bottom_center.x - w / 2.0, 1.0, 191.0 - w)
	var y := clampf(bottom_center.y - h, FARM_Y + 1.0, STATUS_Y - h - 4.0)
	var r := Rect2(floorf(x), floorf(y), w, h)
	draw_rect(r.grow(1), C_BG)
	draw_rect(r, C_TEXT)
	# tail
	var tx := clampf(bottom_center.x, r.position.x + 3, r.end.x - 4)
	draw_rect(Rect2(floorf(tx), r.end.y, 3, 1), C_TEXT)
	draw_rect(Rect2(floorf(tx) + 1, r.end.y + 1, 1, 1), C_TEXT)
	draw_rect(Rect2(floorf(tx) - 1, r.end.y, 1, 1), C_BG)
	draw_rect(Rect2(floorf(tx) + 3, r.end.y, 1, 1), C_BG)
	for i in lines.size():
		Art.draw_text(self, lines[i], Vector2(r.position.x + 3, r.position.y + 2 + i * 6), C_BG)


func _draw_top() -> void:
	draw_rect(Rect2(2, 0, 188, 1), C_BG)
	draw_rect(Rect2(1, 1, 190, 1), C_BG)
	draw_rect(Rect2(0, 2, 192, 14), C_BG)
	draw_rect(Rect2(0, 15, 192, 1), C_EDGE)
	draw_texture(Art.tex("coin"), Vector2(3, 4))
	_txt(str(Game.coins), Vector2(12, 5), C_GOLD)
	var lv_x := 12 + Art.text_width(str(Game.coins)) + 5
	_txt("LV%d" % Game.level(), Vector2(lv_x, 3), C_GREEN)
	_bar(Rect2(lv_x, 9, 15, 3), Game.level_progress(), C_GREEN)
	_txt("DAY %d" % Game.day, Vector2(78, 3))
	_txt(Game.clock_text(), Vector2(78, 9), C_DIM)
	var wicon: String = "ic_moon" if Game.is_night() and Game.weather in ["sunny", "heat"] else {
		"sunny": "ic_sun", "cloudy": "ic_cloud", "rain": "ic_rain", "storm": "ic_storm", "heat": "ic_heat"}[Game.weather]
	draw_texture(Art.tex(wicon), Vector2(112, 0))
	_txt(Game.WEATHER_NAMES[Game.weather] if not (Game.is_night() and Game.weather == "sunny") else "Night", Vector2(129, 5), C_DIM)
	for k in ["dock", "min", "close"]:
		var r: Rect2 = btns[k]
		draw_rect(r, C_EDGE if hover_btn == k else C_SLOT)
		var glyph: String = {"dock": "<" if Game.settings.get("dock", "right") == "right" else ">", "min": "_", "close": "X"}[k]
		Art.draw_text(self, glyph, r.position + Vector2(3, 2), C_RED if k == "close" and hover_btn == k else C_TEXT)


func _draw_status() -> void:
	draw_rect(Rect2(0, STATUS_Y, 192, TRAY_Y - STATUS_Y), C_PANEL)
	draw_rect(Rect2(0, STATUS_Y, 192, 1), C_EDGE)
	var y := STATUS_Y + 3
	draw_texture(Art.tex("heart"), Vector2(3, y))
	_bar(Rect2(12, y + 1, 36, 5), Game.health / 100.0, Color("e43b44") if Game.poison <= 0.0 else Color("38b764"))
	draw_texture(Art.tex("bolt"), Vector2(52, y))
	_bar(Rect2(60, y + 1, 36, 5), Game.energy / 100.0, C_GOLD)
	var face := "face_happy" if Game.mood > 65.0 else ("face_ok" if Game.mood > 35.0 else "face_sad")
	draw_texture(Art.tex(face), Vector2(100, y))
	var x := 112
	var icons: Array = []
	if Game.buff("sun"):
		icons.append(["sunny", ""])
	if Game.buff("dog"):
		icons.append(["paw", ""])
	if Game.charms > 0:
		icons.append(["charm", str(Game.charms)])
	if Game.poison > 0.0:
		icons.append(["poison", ""])
	if Game.inventory_count() > 0:
		icons.append(["basket", str(Game.inventory_count())])
	for ic in icons:
		draw_texture(Art.tex(ic[0]), Vector2(x, y))
		x += 8
		if ic[1] != "":
			_txt(ic[1], Vector2(x, y + 1), C_TEXT)
			x += Art.text_width(ic[1]) + 2
	var act := "> " + (world.farmer.activity if world and world.farmer else "")
	_txt(act.substr(0, 46), Vector2(3, STATUS_Y + 12), C_TEXT)
	var last: String = Game.log_lines[Game.log_lines.size() - 1] if Game.log_lines.size() > 0 else "Welcome to the farm!"
	var lc := C_DIM.lerp(C_GOLD, log_flash)
	_txt(last.substr(0, 46), Vector2(3, STATUS_Y + 20), lc)


func _draw_tray() -> void:
	var bottom := 432
	draw_rect(Rect2(0, TRAY_Y, 192, bottom - TRAY_Y - 2), C_BG)
	draw_rect(Rect2(1, bottom - 2, 190, 1), C_BG)
	draw_rect(Rect2(2, bottom - 1, 188, 1), C_BG)
	draw_rect(Rect2(0, TRAY_Y, 192, 1), C_EDGE)
	var n := Game.card_count()
	_txt("ACTIVITIES %d/%d" % [n, Game.CARD_CAP], Vector2(4, TRAY_Y + 4), C_GOLD)
	if n < Game.CARD_CAP:
		var left := int(maxf(0.0, Game.next_card_in - Game.card_timer))
		var s := "NEXT %d:%02d" % [left / 60, left % 60]
		_txt(s, Vector2(188 - Art.text_width(s), TRAY_Y + 4), C_DIM)
	else:
		_txt("FULL!", Vector2(168, TRAY_Y + 4), C_RED)
	var ids := _owned_ids()
	for i in COLS * ROWS:
		var r := _slot_rect(i)
		if i >= ids.size():
			draw_rect(r, Color(1, 1, 1, 0.03))
			continue
		var id: String = ids[i]
		var hov := id == hover_card
		var pl: float = pulse.get(id, 0.0)
		draw_rect(r, C_GOLD if hov else (C_GOLD.lerp(C_EDGE, 1.0 - pl) if pl > 0.0 else C_EDGE))
		draw_rect(r.grow(-1), C_SLOT if not hov else Color("4a5480"))
		var tx := Art.tex(Game.CARDS[id]["icon"])
		var iw := mini(tx.get_width(), 16)
		var ih := mini(tx.get_height(), 16)
		var bob := -1.0 if hov else 0.0
		draw_texture_rect(tx, Rect2(r.position.x + (SLOT_W - iw) / 2, r.position.y + 2 + bob + (16 - ih) / 2, iw, ih), false)
		var cnt := int(Game.cards[id])
		if cnt > 1:
			var cs := "x%d" % cnt
			_txt(cs, Vector2(r.end.x - Art.text_width(cs) - 2, r.end.y - 7), C_TEXT)
	# description / hint + use all
	var desc_w := 36
	if hover_card != "":
		var c: Dictionary = Game.CARDS[hover_card]
		_txt(c["name"], Vector2(4, 415), C_GOLD)
		var lines := Art.wrap(c["desc"], desc_w)
		for i in mini(2, lines.size()):
			_txt(lines[i], Vector2(4, 421 + i * 6), C_TEXT)
	elif n == 0:
		_txt("ACTIVITIES TRICKLE IN", Vector2(4, 418), C_DIM)
		_txt("OVER TIME. SAVE THEM UP!", Vector2(4, 424), C_DIM)
	else:
		_txt("CLICK A CARD TO USE IT,", Vector2(4, 418), C_DIM)
		_txt("OR UNLEASH THEM ALL ->", Vector2(4, 424), C_DIM)
	if n > 0:
		var r2: Rect2 = btns["useall"]
		var hov2 := hover_btn == "useall"
		draw_rect(r2, C_GOLD if hov2 else Color("ef7d57"))
		draw_rect(r2.grow(-1), Color("b13e53") if not hov2 else Color("ef7d57"))
		_txt("USE ALL", r2.position + Vector2(6, 4), C_TEXT)
