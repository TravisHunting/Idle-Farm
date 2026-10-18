extends Control
## All in-game UI, custom-drawn with the pixel font. Sits on a CanvasLayer so the night tint skips it.
## Layout (192x432): 0-16 top bar · 16-272 farm · 272-302 status · 302-432 card tray.
## The choice-card modal is drawn over the farm area while a card is open.
## Input is handled in _input() with manual hit-testing (mouse_filter = IGNORE).

const FARM_Y := 16
const STATUS_Y := 272
const TRAY_Y := 302
const SLOT_W := 29
const SLOT_H := 28
const COLS := 6
const ROWS := 3

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

const MODAL := Rect2(6, 19, 180, 250)
const BOX_A := Rect2(10, 104, 172, 64)
const BOX_B := Rect2(10, 172, 172, 64)
const LATER := Rect2(70, 242, 52, 13)

var world: World
var director: Node
var cards: Node
var main: Node

var hover_card := ""
var hover_btn := ""
var hover_choice := ""
var hover_relic := ""
var open_card := ""
var chain := false          # "open all" mode: next card opens after choosing
var dragging := false
var drag_off := Vector2i.ZERO
var pulse := {}
var log_flash := 0.0
var t := 0.0
var btns := {
	"menu": Rect2(147, 3, 9, 9),
	"dock": Rect2(158, 3, 9, 9),
	"min": Rect2(169, 3, 9, 9),
	"close": Rect2(180, 3, 9, 9),
	"openall": Rect2(144, 416, 45, 13),
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(192, 432)
	Game.card_arrived.connect(_on_card_arrived)
	Game.log_added.connect(_on_log)


func _on_card_arrived(id: String) -> void:
	pulse[id] = 1.5


func _on_log(_text: String) -> void:
	log_flash = 1.0


func _process(delta: float) -> void:
	t += delta
	for k in pulse.keys():
		pulse[k] -= delta
		if pulse[k] <= 0.0:
			pulse.erase(k)
	log_flash = maxf(0.0, log_flash - delta)
	if open_card != "" and not (open_card in Game.hand):
		open_card = ""
	queue_redraw()


# ---------------------------------------------------------------- input
func _slot_rect(i: int) -> Rect2:
	var col := i % COLS
	var row := i / COLS
	return Rect2(4 + col * (SLOT_W + 2), TRAY_Y + 12 + row * (SLOT_H + 2), SLOT_W, SLOT_H)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if dragging:
			DisplayServer.window_set_position(DisplayServer.mouse_get_position() - drag_off)
			return
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			dragging = false
			return
		var p: Vector2 = event.position
		_update_hover(p)
		if hover_btn != "":
			match hover_btn:
				"menu": main.back_to_menu()
				"dock": main.toggle_dock()
				"min": main.minimize()
				"close": main.save_and_quit()
				"openall":
					if Game.hand.size() > 0:
						chain = true
						open_card = Game.hand[0]
				"later":
					open_card = ""
					chain = false
			return
		if open_card != "":
			if hover_choice != "":
				var c: Dictionary = cards.card(open_card)
				if cards.can_choose(c, hover_choice):
					cards.choose(open_card, hover_choice)
					open_card = Game.hand[0] if chain and Game.hand.size() > 0 else ""
					if open_card == "":
						chain = false
			elif not MODAL.has_point(p) and p.y >= FARM_Y and p.y < STATUS_Y:
				open_card = ""
				chain = false
			if p.y < TRAY_Y:
				return
		if hover_card != "":
			open_card = hover_card
			chain = false
			return
		if p.y < FARM_Y and not main.embedded:
			dragging = true
			drag_off = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
			return
		if open_card == "" and p.y >= FARM_Y and p.y < STATUS_Y:
			var wp := p - Vector2(0, FARM_Y)
			var f := world.farmer
			if f and f.pos.distance_to(wp + Vector2(0, 6)) < 12.0:
				f.on_click()


func _update_hover(p: Vector2) -> void:
	hover_btn = ""
	hover_card = ""
	hover_choice = ""
	hover_relic = ""
	if open_card == "" and hover_card == "" and p.y >= 415 and p.y <= 425:
		var i := int((p.x - 4) / 9.0)
		var ids := Game.relics.keys()
		if p.x >= 4 and i < ids.size() and i < 15:
			hover_relic = ids[i]
	for k in btns:
		if btns[k].has_point(p):
			if k == "openall" and Game.hand.is_empty():
				continue
			hover_btn = k
			return
	if open_card != "":
		if LATER.has_point(p):
			hover_btn = "later"
			return
		if BOX_A.has_point(p):
			hover_choice = "a"
			return
		if BOX_B.has_point(p):
			hover_choice = "b"
			return
	for i in Game.hand.size():
		if i < COLS * ROWS and _slot_rect(i).has_point(p):
			hover_card = Game.hand[i]
			return


# ---------------------------------------------------------------- drawing helpers
func _txt(s: String, p: Vector2, c: Color = C_TEXT) -> void:
	Art.draw_text(self, s, p, c, C_SHADOW)


func _bar(r: Rect2, v: float, c: Color) -> void:
	draw_rect(r, C_BG)
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2((r.size.x - 2) * clampf(v, 0.0, 1.0), r.size.y - 2)), c)


func _frame(r: Rect2, edge: Color, fill: Color) -> void:
	draw_rect(r, edge)
	draw_rect(r.grow(-1), fill)


## Draws a texture scaled by an integer factor to fit inside box (centred).
func _icon(name_: String, box: Rect2, max_scale: int = 1) -> void:
	var tx := Art.tex(name_)
	var w := tx.get_width()
	var h := tx.get_height()
	var s := maxi(1, mini(max_scale, mini(int(box.size.x) / maxi(w, 1), int(box.size.y) / maxi(h, 1))))
	if w * s > box.size.x or h * s > box.size.y:
		var f := minf(box.size.x / w, box.size.y / h)
		draw_texture_rect(tx, Rect2(box.get_center() - Vector2(w, h) * f * 0.5, Vector2(w, h) * f).abs(), false)
		return
	var sz := Vector2(w * s, h * s)
	draw_texture_rect(tx, Rect2((box.get_center() - sz * 0.5).floor(), sz), false)


func _draw() -> void:
	_draw_world_overlays()
	if open_card != "":
		_draw_modal()
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
	var tx := clampf(bottom_center.x, r.position.x + 3, r.end.x - 4)
	draw_rect(Rect2(floorf(tx), r.end.y, 3, 1), C_TEXT)
	draw_rect(Rect2(floorf(tx) + 1, r.end.y + 1, 1, 1), C_TEXT)
	draw_rect(Rect2(floorf(tx) - 1, r.end.y, 1, 1), C_BG)
	draw_rect(Rect2(floorf(tx) + 3, r.end.y, 1, 1), C_BG)
	for i in lines.size():
		Art.draw_text(self, lines[i], Vector2(r.position.x + 3, r.position.y + 2 + i * 6), C_BG)


# ---------------------------------------------------------------- modal
func _draw_modal() -> void:
	var c: Dictionary = cards.card(open_card)
	if c.is_empty():
		open_card = ""
		return
	var rar := int(c.get("rarity", 1))
	var rc: Color = cards.RARITY_COLORS.get(rar, C_EDGE)
	draw_rect(Rect2(0, FARM_Y, 192, STATUS_Y - FARM_Y), Color(0.05, 0.05, 0.1, 0.55))
	_frame(MODAL.grow(1), C_BG, C_BG)
	_frame(MODAL, rc, C_PANEL)
	# rarity + count
	_txt(cards.RARITY_NAMES.get(rar, "").to_upper(), MODAL.position + Vector2(4, 3), rc)
	var idx := Game.hand.find(open_card) + 1
	var cnt := "%d/%d" % [idx, Game.hand.size()]
	_txt(cnt, Vector2(MODAL.end.x - Art.text_width(cnt) - 4, MODAL.position.y + 3), C_DIM)
	# title
	var title: String = c["title"]
	_txt(title, Vector2(96 - Art.text_width(title) / 2, MODAL.position.y + 11), C_GOLD)
	# portrait
	var pr := Rect2(80, MODAL.position.y + 19, 32, 32)
	_frame(pr.grow(1), rc.darkened(0.3), C_BG)
	var bob := sin(t * 2.0) * 0.6 if c.get("visitor", false) else 0.0
	_icon(c["art"], Rect2(pr.position + Vector2(0, bob), pr.size), 2)
	# flavour text
	var lines := Art.wrap(c["text"], 43)
	for i in mini(5, lines.size()):
		_txt(lines[i], Vector2(10, MODAL.position.y + 55 + i * 6), C_TEXT)
	_draw_choice(c, "a", BOX_A)
	_draw_choice(c, "b", BOX_B)
	# later button
	var hl := hover_btn == "later"
	_frame(LATER, C_GOLD if hl else C_EDGE, C_SLOT)
	_txt("LATER", LATER.position + Vector2(16, 4), C_TEXT)


func _draw_choice(c: Dictionary, which: String, box: Rect2) -> void:
	var ch: Dictionary = c[which]
	var ok: bool = cards.can_choose(c, which)
	var hov := hover_choice == which
	var edge := C_EDGE
	if ok and hov:
		edge = C_GOLD
	elif not ok:
		edge = Color("4a3040")
	_frame(box, edge, Color("303859") if ok else Color("221f30"))
	_txt(ch["label"], box.position + Vector2(4, 3), C_GOLD if ok else C_DIM)
	if ok and hov:
		_txt("CHOOSE", Vector2(box.end.x - 28, box.position.y + 3), C_GREEN)
	var y := box.position.y + 11
	for l in Art.wrap(ch["desc"], 41).slice(0, 3):
		_txt(l, Vector2(box.position.x + 4, y), C_TEXT if ok else C_DIM)
		y += 6
	y += 2
	for r in cards.choice_lines(c, which).slice(0, 4):
		if r[1] == "":
			continue
		var s := ("+ " if r[0] else "x ") + "NEED " + String(r[1])
		_txt(s.substr(0, 42), Vector2(box.position.x + 4, y), C_GREEN if r[0] else C_RED)
		y += 6


# ---------------------------------------------------------------- bars
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
	_txt("DAY %d" % Game.day, Vector2(76, 3))
	_txt(Game.clock_text(), Vector2(76, 9), C_DIM)
	var wicon: String = "ic_moon" if Game.is_night() and Game.weather in ["sunny", "heat"] else {
		"sunny": "ic_sun", "cloudy": "ic_cloud", "rain": "ic_rain", "storm": "ic_storm", "heat": "ic_heat"}[Game.weather]
	draw_texture(Art.tex(wicon), Vector2(116, 0))
	for k in ["menu", "dock", "min", "close"]:
		var r: Rect2 = btns[k]
		draw_rect(r, C_EDGE if hover_btn == k else C_SLOT)
		var glyph: String = {"menu": "=", "dock": "<" if Game.settings.get("dock", "right") == "right" else ">", "min": "_", "close": "X"}[k]
		Art.draw_text(self, glyph, r.position + Vector2(3, 2), C_RED if k == "close" and hover_btn == k else C_TEXT)


func _draw_status() -> void:
	draw_rect(Rect2(0, STATUS_Y, 192, TRAY_Y - STATUS_Y), C_PANEL)
	draw_rect(Rect2(0, STATUS_Y, 192, 1), C_EDGE)
	var y := STATUS_Y + 3
	draw_texture(Art.tex("heart"), Vector2(3, y))
	_bar(Rect2(12, y + 1, 32, 5), Game.health / 100.0, C_RED if Game.poison <= 0.0 else Color("38b764"))
	draw_texture(Art.tex("bolt"), Vector2(48, y))
	_bar(Rect2(56, y + 1, 32, 5), Game.energy / 100.0, C_GOLD)
	var face := "face_happy" if Game.mood > 65.0 else ("face_ok" if Game.mood > 35.0 else "face_sad")
	draw_texture(Art.tex(face), Vector2(92, y))
	draw_texture(Art.tex("eye"), Vector2(102, y), Color.WHITE.lerp(C_PURPLE, clampf(Game.weird / 60.0, 0.0, 1.0)))
	_txt(str(int(Game.weird)), Vector2(110, y + 1), C_PURPLE if Game.weird >= 10.0 else C_DIM)
	var x := 110 + Art.text_width(str(int(Game.weird))) + 3
	var icons: Array = []
	if Game.buff("sun"):
		icons.append(["sunny", ""])
	if Game.buff("growth"):
		icons.append(["sprout", ""])
	if Game.buff("dog"):
		icons.append(["paw", ""])
	if Game.charms > 0:
		icons.append(["charm", str(Game.charms)])
	if Game.poison > 0.0:
		icons.append(["poison", ""])
	if Game.inventory_count() > 0:
		icons.append(["basket", str(Game.inventory_count())])
	for ic in icons:
		if x > 184:
			break
		draw_texture(Art.tex(ic[0]), Vector2(x, y))
		x += 8
		if ic[1] != "":
			_txt(ic[1], Vector2(x, y + 1), C_TEXT)
			x += Art.text_width(ic[1]) + 2
	var act := "> " + (world.farmer.activity if world and world.farmer else "")
	_txt(act.substr(0, 46), Vector2(3, STATUS_Y + 12), C_TEXT)
	var last: String = Game.log_lines[Game.log_lines.size() - 1] if Game.log_lines.size() > 0 else "Welcome to the farm!"
	_txt(last.substr(0, 46), Vector2(3, STATUS_Y + 20), C_DIM.lerp(C_GOLD, log_flash))


func _draw_tray() -> void:
	var bottom := 432
	draw_rect(Rect2(0, TRAY_Y, 192, bottom - TRAY_Y - 2), C_BG)
	draw_rect(Rect2(1, bottom - 2, 190, 1), C_BG)
	draw_rect(Rect2(2, bottom - 1, 188, 1), C_BG)
	draw_rect(Rect2(0, TRAY_Y, 192, 1), C_EDGE)
	var n := Game.hand.size()
	_txt("CARDS %d/%d" % [n, Game.HAND_CAP], Vector2(4, TRAY_Y + 4), C_GOLD)
	if n < Game.HAND_CAP:
		var left := int(maxf(0.0, Game.next_card_in - Game.card_timer))
		var s := "NEXT %d:%02d" % [left / 60, left % 60]
		_txt(s, Vector2(188 - Art.text_width(s), TRAY_Y + 4), C_DIM)
	else:
		_txt("FULL!", Vector2(168, TRAY_Y + 4), C_RED)
	for i in COLS * ROWS:
		var r := _slot_rect(i)
		if i >= n:
			draw_rect(r, Color(1, 1, 1, 0.03))
			continue
		var id: String = Game.hand[i]
		var c: Dictionary = cards.card(id)
		var rc: Color = cards.RARITY_COLORS.get(int(c.get("rarity", 1)), C_EDGE)
		var hov := id == hover_card or id == open_card
		var pl: float = pulse.get(id, 0.0)
		var edge := rc
		if hov:
			edge = C_GOLD
		elif pl > 0.0 and int(pl * 6.0) % 2 == 0:
			edge = C_TEXT
		_frame(r, edge, C_SLOT if not hov else Color("4a5480"))
		# little "playable" pip: green if at least one choice is available
		var any_ok: bool = cards.can_choose(c, "a") or cards.can_choose(c, "b")
		draw_rect(Rect2(r.end.x - 4, r.position.y + 2, 2, 2), C_GREEN if any_ok else C_RED)
		_icon(c.get("art", ""), Rect2(r.position + Vector2(2, 2 + (-1 if hov else 0)), Vector2(SLOT_W - 4, SLOT_H - 4)), 1)
	# bottom: hovered card name, or the relic shelf
	if hover_relic != "" and Game.relics.has(hover_relic):
		var rl: Dictionary = Game.RELICS[hover_relic]
		_txt(rl["name"], Vector2(4, 416), C_PURPLE)
		_txt(String(rl["desc"]).substr(0, 46), Vector2(4, 423), C_TEXT)
		return
	if hover_card != "":
		var c2: Dictionary = cards.card(hover_card)
		_txt(c2["title"], Vector2(4, 416), C_GOLD)
		_txt(cards.RARITY_NAMES.get(int(c2.get("rarity", 1)), "").to_upper(), Vector2(4, 423), cards.RARITY_COLORS.get(int(c2.get("rarity", 1)), C_DIM))
	elif Game.relics.size() > 0:
		var x := 4
		for id in Game.relics:
			if x > 135:
				break
			draw_texture(Art.tex(Game.RELICS[id]["icon"]), Vector2(x, 417))
			x += 9
		_txt("RELICS", Vector2(4, 425), C_PURPLE)
	elif n == 0:
		_txt("CARDS TRICKLE IN OVER TIME.", Vector2(4, 417), C_DIM)
		_txt("SAVE THEM UP!", Vector2(4, 424), C_DIM)
	else:
		_txt("CLICK A CARD TO DECIDE,", Vector2(4, 417), C_DIM)
		_txt("OR GO THROUGH THEM ALL ->", Vector2(4, 424), C_DIM)
	if n > 0:
		var r2: Rect2 = btns["openall"]
		var hov2 := hover_btn == "openall"
		_frame(r2, C_GOLD if hov2 else Color("ef7d57"), Color("b13e53") if not hov2 else Color("ef7d57"))
		_txt("OPEN ALL", r2.position + Vector2(7, 4), C_TEXT)
