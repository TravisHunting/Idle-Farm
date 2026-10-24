extends Control
## All in-game UI, custom-drawn with the pixel font. Sits on a CanvasLayer so the night tint skips it.
## Layout (192x432): 0-16 top bar · 16-368 farm · 368-394 status · 394-432 card strip.
## Card strip: STASH (3 slots, kept safe) on the left, the card BOX (3 slots) on the right.
## New cards push into the box from the left; the far-right card falls off the edge.
## Click a card to open it (the choice modal is drawn over the farm); drag cards between slots.
## Also: the settings panel (gear) and the farmer panel (click the farmer).
## Input is handled in _input() with manual hit-testing (mouse_filter = IGNORE).

const FARM_Y := 16
const STATUS_Y := 368
const TRAY_Y := 394
const SLOT_W := 28
const SLOT_H := 27
const SLOT_Y := 403
const STASH_X := [4, 34, 64]
const BOX_X := [100, 130, 160]

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
const C_WOOD := Color("c28a5a")
const C_SHADOW := Color(0, 0, 0, 0.6)

const MODAL := Rect2(6, 106, 180, 258)
const PANEL := Rect2(6, 20, 180, 262)

var world: World
var director: Node
var cards: Node
var main: Node
var commands: Commands

var hover_slot := []          # ["box"|"stash", i] or []
var hover_btn := ""
var hover_choice := ""
var open_id := ""             # card id open in the modal
var open_where := ""
var open_i := -1
var settings_open := false
var panel_open := false
var letter_open := false      # grandpa's letter (click a mailbox), see chores.gd
var dragging := false         # window drag
var drag_off := Vector2i.ZERO
var press_slot := []          # slot pressed (click or card drag)
var press_pos := Vector2.ZERO
var card_drag := false
var mouse := Vector2.ZERO
var pulse := {}
var trash_anim := {}          # {id, t}
var log_flash := 0.0
var name_entry := TextEntry.new(12, TextEntry.NAME)
var name_focus := false
var toast := {}               # {text, t}: a multiplayer message shown over the farm for a few seconds
var t := 0.0
var btns := {
	"menu": Rect2(136, 3, 9, 9),
	"gear": Rect2(147, 3, 9, 9),
	"dock": Rect2(158, 3, 9, 9),
	"min": Rect2(169, 3, 9, 9),
	"close": Rect2(180, 3, 9, 9),
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(192, 432)
	Game.card_arrived.connect(_on_card_arrived)
	Game.card_trashed.connect(_on_card_trashed)
	Game.log_added.connect(_on_log)
	Game.cards_changed.connect(_on_cards_changed)
	Net.status_changed.connect(_on_net_status)
	name_entry.set_text(String(Game.settings.get("name", "")))


func _on_net_status(text: String) -> void:
	toast = {"text": text, "t": 5.0}


func _on_card_arrived(id: String) -> void:
	pulse[id] = 2.0


func _on_card_trashed(id: String) -> void:
	trash_anim = {"id": id, "t": 0.0}


func _on_log(_text: String) -> void:
	log_flash = 1.0


## Cards shift around in the box: keep the open modal pointed at the same card.
func _on_cards_changed() -> void:
	if open_id == "":
		return
	if Game.card_at(open_where, open_i) == open_id:
		return
	for w in ["box", "stash"]:
		var arr: Array = Game.box if w == "box" else Game.stash
		var i := arr.find(open_id)
		if i >= 0:
			open_where = w
			open_i = i
			return
	_close_modal()


func _process(delta: float) -> void:
	t += delta
	for k in pulse.keys():
		pulse[k] -= delta
		if pulse[k] <= 0.0:
			pulse.erase(k)
	if not trash_anim.is_empty():
		trash_anim["t"] += delta
		if trash_anim["t"] > 1.2:
			trash_anim = {}
	log_flash = maxf(0.0, log_flash - delta)
	if not toast.is_empty():
		toast["t"] -= delta
		if toast["t"] <= 0.0:
			toast = {}
	queue_redraw()


# ---------------------------------------------------------------- input
func _slot_rect(where: String, i: int) -> Rect2:
	var xs: Array = BOX_X if where == "box" else STASH_X
	return Rect2(xs[i], SLOT_Y, SLOT_W, SLOT_H)


func _slot_at(p: Vector2) -> Array:
	for w in ["stash", "box"]:
		for i in 3:
			if _slot_rect(w, i).grow(1).has_point(p):
				return [w, i]
	return []


func _modal_rects() -> Dictionary:
	var y := MODAL.position.y
	return {
		"a": Rect2(10, y + 87, 172, 64),
		"b": Rect2(10, y + 155, 172, 64),
		"later": Rect2(14, y + 226, 74, 13),
		"move": Rect2(104, y + 226, 74, 13),
	}


func _settings_rects() -> Dictionary:
	var y := PANEL.position.y
	var r := {
		"min_down": Rect2(100, y + 30, 11, 11), "min_up": Rect2(170, y + 30, 11, 11),
		"dock_side": Rect2(100, y + 52, 81, 11),
		"next_now": Rect2(100, y + 74, 81, 11),
		"name": Rect2(100, y + 108, 81, 11),
		"done": Rect2(66, y + 244, 60, 14),
	}
	match Net.mode:
		"hosting":
			r["copy"] = Rect2(12, y + 224, 80, 13)
			r["stop_host"] = Rect2(100, y + 224, 81, 13)
		"guest":
			r["leave"] = Rect2(12, y + 224, 169, 13)
		_:
			r["host"] = Rect2(12, y + 126, 169, 13)
	return r


func _input(event: InputEvent) -> void:
	if event is InputEventKey and settings_open and name_focus:
		get_viewport().set_input_as_handled()
		var res := name_entry.key(event)
		if res == "edit" or res == "submit":
			_save_name()
		if res == "submit" or (event.pressed and event.keycode in [KEY_ESCAPE, KEY_TAB]):
			name_focus = false
		return
	if event is InputEventMouseMotion:
		mouse = event.position
		if dragging:
			DisplayServer.window_set_position(DisplayServer.mouse_get_position() - drag_off)
			return
		if not press_slot.is_empty() and not card_drag and mouse.distance_to(press_pos) > 3.0:
			card_drag = true
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position
		mouse = p
		if not event.pressed:
			dragging = false
			_release(p)
			return
		_update_hover(p)
		_press(p)


func _press(p: Vector2) -> void:
	if hover_btn in btns:
		match hover_btn:
			"menu": main.back_to_menu()
			"gear":
				settings_open = not settings_open
				_close_modal()
				panel_open = false
				letter_open = false
			"dock": main.toggle_dock()
			"min": main.minimize()
			"close": main.save_and_quit()
		return
	if settings_open:
		_settings_click(p)
		return
	if open_id != "":
		if hover_choice != "":
			var c: Dictionary = cards.card(open_id)
			if cards.can_choose(c, hover_choice):
				commands.submit({"type": "choose", "where": open_where, "i": open_i, "which": hover_choice})
				_close_modal()
			return
		if hover_btn == "later":
			_close_modal()
			return
		if hover_btn == "move":
			_move_open_card()
			return
		if MODAL.has_point(p):
			return
		if p.y >= FARM_Y and p.y < STATUS_Y:
			_close_modal()
			return
	var s := _slot_at(p)
	if not s.is_empty() and Game.card_at(s[0], s[1]) != "":
		press_slot = s
		press_pos = p
		card_drag = false
		return
	if p.y < FARM_Y and not main.embedded:
		dragging = true
		drag_off = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
		return
	if p.y >= FARM_Y and p.y < STATUS_Y:
		var wp := p - Vector2(0, FARM_Y)
		if letter_open:
			letter_open = false
			return
		var f := world.farmer
		var fr := world.friend
		if f and f.visible_outside() and f.pos.distance_to(wp + Vector2(0, 6)) < 12.0:
			f.on_click()
			panel_open = not panel_open
		elif fr and fr.visible_outside() and fr.pos.distance_to(wp + Vector2(0, 6)) < 12.0:
			fr.on_click()
			panel_open = false
		elif panel_open:
			panel_open = false
		elif world.obj_type(world.cell_of(wp)) == "mailbox":
			letter_open = true
			commands.submit({"type": "read_letter"})
		else:
			var c := _poke_cell(wp)
			if c.x >= 0:
				commands.submit({"type": "poke", "x": c.x, "y": c.y})


## The overgrowth a click at wp (farm pixels) would pull: the tile under it, or a tall thing
## (tree, boulder...) standing on the tile below. (-1, -1) if none.
func _poke_cell(wp: Vector2) -> Vector2i:
	var c := world.cell_of(wp)
	if World.TAPS.has(world.obj_type(c)):
		return c
	var below := c + Vector2i(0, 1)
	if world.in_bounds(below) and world.obj_type(below) in ["tree", "pine", "boulder", "bush", "bramble"]:
		return below
	return Vector2i(-1, -1)


func _release(p: Vector2) -> void:
	if press_slot.is_empty():
		return
	var from: Array = press_slot
	press_slot = []
	if card_drag:
		card_drag = false
		var to := _slot_at(p)
		if not to.is_empty():
			commands.submit({"type": "move_card", "from": from[0], "fi": from[1], "to": to[0], "ti": to[1]})
		return
	_open(from[0], from[1])


func _open(where: String, i: int) -> void:
	var id := Game.card_at(where, i)
	if id == "":
		return
	open_id = id
	open_where = where
	open_i = i
	panel_open = false


func _close_modal() -> void:
	open_id = ""
	open_where = ""
	open_i = -1


## Box -> first free stash slot, stash -> first free box slot.
func _move_open_card() -> void:
	var other := "stash" if open_where == "box" else "box"
	var arr: Array = Game.stash if other == "stash" else Game.box
	var free := arr.find("")
	if free < 0:
		return
	commands.submit({"type": "move_card", "from": open_where, "fi": open_i, "to": other, "ti": free})


## The player's name: kept in settings, shown in the log ("TRAVIS chose ...") and to the friend.
func _save_name() -> void:
	var nm := name_entry.text.strip_edges()
	Game.settings["name"] = nm
	Game.save_settings()
	if not Game.puppet and nm != "":
		Game.hand()["name"] = nm


func _settings_click(p: Vector2) -> void:
	var r := _settings_rects()
	name_focus = r["name"].has_point(p)
	if name_focus:
		return
	if r.has("host") and r["host"].has_point(p):
		Net.host(int(Game.settings.get("port", Net.PORT)))   # "port" in the settings file, if 24680 is taken
		return
	if r.has("stop_host") and r["stop_host"].has_point(p):
		Net.stop()
		return
	if r.has("copy") and r["copy"].has_point(p):
		Net.copy_address()
		toast = {"text": "Copied %s. Send it to your friend." % Net.share_address(), "t": 4.0}
		return
	if r.has("leave") and r["leave"].has_point(p):
		settings_open = false
		main.back_to_menu()
		return
	if Game.puppet and (r["min_down"].has_point(p) or r["min_up"].has_point(p) or r["next_now"].has_point(p)):
		return   # the host's world, the host's rules
	var opts: Array = Game.CARD_MINUTES
	var cur := opts.find(int(Game.settings.get("card_minutes", Game.DEFAULT_CARD_MINUTES)))
	if cur < 0:
		cur = opts.find(Game.DEFAULT_CARD_MINUTES)
	if r["min_down"].has_point(p):
		commands.submit({"type": "card_minutes", "n": opts[maxi(0, cur - 1)]})
	elif r["min_up"].has_point(p):
		commands.submit({"type": "card_minutes", "n": opts[mini(opts.size() - 1, cur + 1)]})
	elif r["dock_side"].has_point(p):
		main.toggle_dock()
	elif r["next_now"].has_point(p) and OS.is_debug_build():
		commands.submit({"type": "debug", "key": "next_card"})
	elif r["done"].has_point(p) or not PANEL.has_point(p):
		settings_open = false


func _update_hover(p: Vector2) -> void:
	hover_btn = ""
	hover_slot = []
	hover_choice = ""
	for k in btns:
		if btns[k].has_point(p):
			hover_btn = k
			return
	if settings_open:
		var sr := _settings_rects()
		for k in sr:
			if sr[k].has_point(p):
				hover_btn = k
				return
		return
	if open_id != "":
		var mr := _modal_rects()
		if mr["later"].has_point(p):
			hover_btn = "later"
			return
		if mr["move"].has_point(p):
			hover_btn = "move"
			return
		if mr["a"].has_point(p):
			hover_choice = "a"
			return
		if mr["b"].has_point(p):
			hover_choice = "b"
			return
	hover_slot = _slot_at(p)


# ---------------------------------------------------------------- drawing helpers
func _txt(s: String, p: Vector2, c: Color = C_TEXT) -> void:
	Art.draw_text(self, s, p, c, C_SHADOW)


func _ctxt(s: String, y: float, c: Color = C_TEXT) -> void:
	_txt(s, Vector2(96 - Art.text_width(s) / 2, y), c)


func _bar(r: Rect2, v: float, c: Color) -> void:
	draw_rect(r, C_BG)
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2((r.size.x - 2) * clampf(v, 0.0, 1.0), r.size.y - 2)), c)


func _frame(r: Rect2, edge: Color, fill: Color) -> void:
	draw_rect(r, edge)
	draw_rect(r.grow(-1), fill)


func _button(r: Rect2, label: String, hot: bool, enabled: bool = true) -> void:
	_frame(r, C_GOLD if hot and enabled else C_EDGE, C_SLOT if enabled else Color("221f30"))
	_txt(label, Vector2(r.get_center().x - Art.text_width(label) / 2.0, r.position.y + (r.size.y - 5) / 2.0), C_TEXT if enabled else C_DIM)


## Draws a texture scaled by an integer factor to fit inside box (centred).
func _icon(name_: String, box: Rect2, max_scale: int = 1, mod: Color = Color.WHITE) -> void:
	var tx := Art.tex(name_)
	var w := tx.get_width()
	var h := tx.get_height()
	var s := maxi(1, mini(max_scale, mini(int(box.size.x) / maxi(w, 1), int(box.size.y) / maxi(h, 1))))
	if w * s > box.size.x or h * s > box.size.y:
		var f := minf(box.size.x / w, box.size.y / h)
		draw_texture_rect(tx, Rect2(box.get_center() - Vector2(w, h) * f * 0.5, Vector2(w, h) * f).abs(), false, mod)
		return
	var sz := Vector2(w * s, h * s)
	draw_texture_rect(tx, Rect2((box.get_center() - sz * 0.5).floor(), sz), false, mod)


func _draw() -> void:
	_draw_world_overlays()
	if panel_open:
		_draw_farmer_panel()
	if letter_open:
		_draw_letter()
	if open_id != "":
		_draw_modal()
	if settings_open:
		_draw_settings()
	_draw_top()
	_draw_status()
	_draw_tray()
	_draw_toast()


func _draw_toast() -> void:
	if toast.is_empty() or settings_open:   # the settings panel shows the same news
		return
	var lines := Art.wrap(String(toast["text"]).to_upper(), 44)
	var h := lines.size() * 8 + 6
	var a := clampf(float(toast["t"]) * 2.0, 0.0, 1.0)
	draw_rect(Rect2(4, FARM_Y + 3, 184, h), Color(C_BG, 0.85 * a))
	draw_rect(Rect2(4, FARM_Y + 3, 184, 1), Color(C_GREEN, a))
	for i in lines.size():
		Art.draw_text(self, lines[i], Vector2(8, FARM_Y + 7 + i * 8), Color(C_TEXT, a), Color(0, 0, 0, 0.6 * a))


func _draw_world_overlays() -> void:
	if world == null:
		return
	_draw_hover_cell()
	for f: Farmer in [world.farmer, world.friend]:
		if f and f.bubble_t > 0.0 and f.bubble != "":
			var anchor := f.pos
			if f.hidden:
				anchor = f.home_px() + Vector2(-6, 2)
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


## Outlines what a click on the farm would do: pull this weed / smash this rock, or read the mail.
func _draw_hover_cell() -> void:
	if panel_open or letter_open or settings_open or open_id != "" or mouse.y < FARM_Y or mouse.y >= STATUS_Y:
		return
	var wp := mouse - Vector2(0, FARM_Y)
	var c := world.cell_of(wp)
	var col := Color(1, 0.8, 0.46, 0.8)
	if world.obj_type(c) != "mailbox":
		c = _poke_cell(wp)
		col = Color(1, 1, 1, 0.45)
	if c.x < 0:
		return
	var r := Rect2(Vector2(c * 16) + Vector2(0, FARM_Y), Vector2(16, 16))
	draw_rect(r, col, false, 1.0)


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
	var c: Dictionary = cards.card(open_id)
	if c.is_empty():
		_close_modal()
		return
	var y := MODAL.position.y
	var rar := int(c.get("rarity", 1))
	var rc: Color = cards.RARITY_COLORS.get(rar, C_EDGE)
	draw_rect(Rect2(0, FARM_Y, 192, STATUS_Y - FARM_Y), Color(0.05, 0.05, 0.1, 0.45))
	_frame(MODAL.grow(1), C_BG, C_BG)
	_frame(MODAL, rc, C_PANEL)
	_txt(cards.RARITY_NAMES.get(rar, "").to_upper(), MODAL.position + Vector2(4, 3), rc)
	var where := "IN THE BOX" if open_where == "box" else "STASHED"
	_txt(where, Vector2(MODAL.end.x - Art.text_width(where) - 4, y + 3), C_DIM)
	var title: String = c["title"]
	_ctxt(title, y + 11, C_GOLD)
	var pr := Rect2(80, y + 19, 32, 32)
	_frame(pr.grow(1), rc.darkened(0.3), C_BG)
	var bob := sin(t * 2.0) * 0.6 if c.get("visitor", false) else 0.0
	_icon(c["art"], Rect2(pr.position + Vector2(0, bob), pr.size), 2)
	var lines := Art.wrap(c["text"], 43)
	for i in mini(5, lines.size()):
		_txt(lines[i], Vector2(10, y + 55 + i * 6), C_TEXT)
	var mr := _modal_rects()
	_draw_choice(c, "a", mr["a"])
	_draw_choice(c, "b", mr["b"])
	_button(mr["later"], "LATER", hover_btn == "later")
	var other: Array = Game.stash if open_where == "box" else Game.box
	_button(mr["move"], "STASH IT" if open_where == "box" else "TO BOX", hover_btn == "move", other.has(""))
	var hint := ""
	if open_where == "box":
		var left := Game.BOX_SIZE - open_i
		hint = "FALLS OUT OF THE BOX IN %d CARD%s" % [left, "" if left == 1 else "S"]
	else:
		hint = "SAFE IN THE STASH"
	_ctxt(hint, y + 245, C_RED if open_where == "box" and open_i == Game.BOX_SIZE - 1 else C_DIM)


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


# ---------------------------------------------------------------- panels
func _draw_settings() -> void:
	draw_rect(Rect2(0, FARM_Y, 192, STATUS_Y - FARM_Y), Color(0.05, 0.05, 0.1, 0.55))
	_frame(PANEL.grow(1), C_BG, C_BG)
	_frame(PANEL, C_EDGE, C_PANEL)
	var y := PANEL.position.y
	var r := _settings_rects()
	_ctxt("SETTINGS", y + 6, C_GOLD)
	_txt("NEW CARD EVERY", Vector2(12, y + 33), C_TEXT)
	var mins := int(Game.settings.get("card_minutes", Game.DEFAULT_CARD_MINUTES))
	var own := not Game.puppet
	_button(r["min_down"], "<", hover_btn == "min_down", own)
	_button(r["min_up"], ">", hover_btn == "min_up", own)
	var ms := "%d MIN" % mins if own else "HOST'S"
	_txt(ms, Vector2(141 - Art.text_width(ms) / 2.0, y + 33), C_GOLD if own else C_DIM)
	_txt("WINDOW SIDE", Vector2(12, y + 55), C_TEXT)
	_button(r["dock_side"], Game.settings.get("dock", "right").to_upper(), hover_btn == "dock_side")
	_txt("NEXT CARD", Vector2(12, y + 77), C_TEXT)
	_button(r["next_now"], "NOW (DEBUG)" if OS.is_debug_build() else "SKIP WAIT", hover_btn == "next_now", OS.is_debug_build() and own)
	_draw_together(r, y + 94)
	_button(r["done"], "DONE", hover_btn == "done")


## The settings panel's multiplayer part: name, host / stop / copy address, or leave a visit.
func _draw_together(r: Dictionary, y: float) -> void:
	draw_rect(Rect2(12, y, 169, 1), C_EDGE)
	_txt("PLAY TOGETHER", Vector2(12, y + 4), C_GOLD)
	_txt("YOUR NAME", Vector2(12, y + 16), C_TEXT)
	name_entry.draw(self, r["name"], name_focus, t, "FRIEND")
	var ly := y + 48.0
	var lines: Array = []
	match Net.mode:
		"hosting":
			var who := "%s IS HERE!" % Game.player_name(Net.guest_pid) if Net.guest_pid != "" else "WAITING FOR YOUR FRIEND..."
			lines.append([who, C_GREEN])
			lines.append(["", C_DIM])
			for h in Net.help_lines():
				for l in Art.wrap(String(h).to_upper(), 42):
					lines.append([l, C_TEXT if l.begins_with("FRIEND TYPES") else C_DIM])
			_button(r["copy"], "COPY ADDRESS", hover_btn == "copy")
			_button(r["stop_host"], "STOP HOSTING", hover_btn == "stop_host")
		"guest":
			lines.append(["VISITING %s'S FARM." % Game.player_name(Game.owner_pid), C_GREEN])
			lines.append(["", C_DIM])
			for l in ["YOUR CARDS ARE YOUR OWN. THE", "HOST'S FARM RUNS ON THEIR PC.",
					"", "LEAVING KEEPS A COPY OF THIS FARM", "IN YOUR FARM %d SLOT." % Game.slot]:
				lines.append([l, C_DIM])
			_button(r["leave"], "LEAVE (KEEP A COPY)", hover_btn == "leave")
		_:
			ly = y + 50.0
			_button(r["host"], "HOST THIS FARM", hover_btn == "host")
			for l in ["LET A FRIEND JOIN THIS FARM. THEY", "PICK JOIN A FRIEND ON THEIR", "WELCOME SCREEN AND TYPE THE", "ADDRESS SHOWN HERE. EACH OF YOU",
					"GETS YOUR OWN CARDS, AND BOTH", "KEEP A COPY OF THE FARM."]:
				lines.append([l, C_DIM])
	for i in lines.size():
		_txt(lines[i][0], Vector2(12, ly + i * 8), lines[i][1])


func _draw_farmer_panel() -> void:
	_frame(PANEL.grow(1), C_BG, C_BG)
	_frame(PANEL, C_GOLD.darkened(0.3), C_PANEL)
	var x := PANEL.position.x + 6
	var y := PANEL.position.y + 5
	_txt(Game.farm_name.to_upper() if Game.farm_name != "" else "THE FARM", Vector2(x, y), C_GOLD)
	y += 8
	if Game.QUIRKS.has(Game.quirk):
		_txt("FARMER: " + String(Game.QUIRKS[Game.quirk]["name"]).to_upper(), Vector2(x, y), C_TEXT)
		y += 7
		_txt(String(Game.QUIRKS[Game.quirk]["desc"]), Vector2(x, y), C_DIM)
		y += 9
	var cleared := int(world.cleared_ratio() * 100.0)
	_txt("CLEARED %d%%  FIELDS %d  PATHS %d" % [cleared, world.fields.size(), world.path_count()], Vector2(x, y), C_TEXT)
	y += 7
	_txt("WOOD %d  STONE %d  ORE %d" % [Game.item_count("wood"), Game.item_count("stone"), Game.item_count("ore")], Vector2(x, y), C_WOOD)
	y += 10
	_txt("ABILITIES", Vector2(x, y), C_GREEN)
	y += 7
	if Game.perks.is_empty():
		_txt("NONE YET - CARDS CAN TEACH HIM", Vector2(x, y), C_DIM)
		y += 7
	for id in Game.perks:
		if y > PANEL.end.y - 40:
			break
		_txt(String(Game.PERKS[id]["name"]).to_upper() + ": " + String(Game.PERKS[id]["desc"]), Vector2(x, y), C_TEXT)
		y += 7
	y += 3
	_txt("FRIENDS", Vector2(x, y), C_GOLD)
	y += 7
	if Game.friends.is_empty():
		_txt("NOBODY VISITS... YET", Vector2(x, y), C_DIM)
		y += 7
	else:
		var fx := x
		for id in Game.friends:
			draw_texture(Art.tex(Game.FRIENDS[id]["icon"]), Vector2(fx, y))
			fx += 9
		y += 9
	y += 3
	_txt("RELICS", Vector2(x, y), C_PURPLE)
	if Game.totems > 0:
		_txt("TOTEMS %d/%d" % [Game.totems, Game.TOTEMS_MAX], Vector2(PANEL.end.x - 50, y), C_PURPLE)
	y += 7
	if Game.relics.is_empty():
		_txt("NONE", Vector2(x, y), C_DIM)
	else:
		var rx := x
		for id in Game.relics:
			if rx > PANEL.end.x - 10:
				break
			draw_texture(Art.tex(Game.RELICS[id]["icon"]), Vector2(rx, y))
			rx += 9
	y += 11
	_draw_faction_lines(x, y)
	_txt("CLICK THE FARM TO CLOSE", Vector2(x, PANEL.end.y - 9), C_DIM)


## Grandpa's letter: the starter chores (chores.gd), ticked off as they get done.
func _draw_letter() -> void:
	var paper := Color("e8dcc0")
	var ink := Color("3b2a20")
	_frame(PANEL.grow(1), C_BG, C_BG)
	_frame(PANEL, C_WOOD, paper)
	var x := PANEL.position.x + 6
	var y := PANEL.position.y + 5
	Art.draw_text(self, "A LETTER FROM GRANDPA", Vector2(x, y), Color("8b3a3a"))
	y += 9
	for l in Art.wrap(Chores.LETTER.to_upper(), 42):
		Art.draw_text(self, l, Vector2(x, y), ink)
		y += 7
	y += 4
	for ch in Chores.LIST:
		var pr := Chores.progress(ch, world)
		var done: bool = Game.chores.get("done", {}).has(ch["id"])
		draw_rect(Rect2(x, y, 5, 5), ink, false, 1.0)
		if done:
			draw_rect(Rect2(x + 1, y + 1, 3, 3), Color("38b764"))
		var c := Color("6a6050") if done else ink
		Art.draw_text(self, String(ch["text"]).to_upper(), Vector2(x + 8, y), c)
		var prog := "%d/%d" % [pr[0], pr[1]] if not ch.has("cleared") else "%d%%" % pr[0]
		Art.draw_text(self, "DONE" if done else prog, Vector2(PANEL.end.x - 6 - Art.text_width("DONE" if done else prog), y),
			Color("38b764") if done else Color("8b5a3c"))
		y += 9
	y += 3
	Art.draw_text(self, "EACH CHORE DONE: A CARD IN THE MAIL", Vector2(x, y), Color("8b5a3c"))
	y += 7
	Art.draw_text(self, "TIP: CLICK WEEDS AND ROCKS TO HELP", Vector2(x, y), Color("8b5a3c"))
	Art.draw_text(self, "CLICK THE FARM TO CLOSE", Vector2(x, PANEL.end.y - 9), Color("6a6050"))


## The aliens next door, what they did to the farmer, and who the tides favour.
func _draw_faction_lines(x: float, y: float) -> void:
	var col: Colony = world.colony
	if col == null:
		return
	_txt("ALIENS", Vector2(x, y), C_GREEN)
	if col.active():
		var r := int(col.rel())
		var rc := C_GREEN if r >= 20 else (C_RED if r < -30 else C_GOLD)
		var rs := "RELATIONS %+d" % r
		_txt(rs, Vector2(PANEL.end.x - 6 - Art.text_width(rs), y), rc)
	y += 7
	for line in Art.wrap(col.status_line(), 42):
		_txt(line, Vector2(x, y), C_TEXT)
		y += 7
	if col.active():
		_txt("FOOD %d  MATTER %d  BORN %d  DIED %d" % [int(Game.colony["food"]), int(Game.colony["matter"]),
			int(Game.colony["born"]), int(Game.colony["died"])], Vector2(x, y), C_DIM)
		y += 7
	var sw: Swarm = world.swarm
	if sw != null:
		y += 2
		_txt("BROOD", Vector2(x, y), Color("ef7d57"))
		if sw.active():
			var rf := int(sw.rel_farm())
			var ra := int(sw.rel_aliens())
			var rs2 := "FARM %+d  ALIENS %+d" % [rf, ra]
			_txt(rs2, Vector2(PANEL.end.x - 6 - Art.text_width(rs2), y), C_RED if sw.at_war() or rf < -30 else C_GOLD)
		y += 7
		for line in Art.wrap(sw.status_line(), 42):
			_txt(line, Vector2(x, y), C_TEXT)
			y += 7
		if sw.active():
			_txt("FOOD %d  WEBS %d  SINKHOLES %d  BARE %d" % [int(Game.brood["food"]), world.count_obj("i_web"),
				int(Game.brood.get("sinkholes", 0)), world.bare.size()], Vector2(x, y), C_DIM)
			y += 7
	if not Game.mutations.is_empty():
		var names: Array = []
		for id in Game.mutations:
			names.append(String(Game.MUTATIONS[id]["name"]).to_upper())
		for line in Art.wrap("MUTATIONS: " + ", ".join(names), 42):
			_txt(line, Vector2(x, y), C_PURPLE)
			y += 7
	var tides = main.tides if main else null
	if tides:
		y += 2
		for line in Art.wrap("TIDES: " + tides.status_line(), 42):
			_txt(line, Vector2(x, y), Color("73eff7"))
			y += 7
		_txt(tides.extinction_line(), Vector2(x, y), C_DIM)
		y += 7


# ---------------------------------------------------------------- bars
func _draw_top() -> void:
	draw_rect(Rect2(2, 0, 188, 1), C_BG)
	draw_rect(Rect2(1, 1, 190, 1), C_BG)
	draw_rect(Rect2(0, 2, 192, 14), C_BG)
	draw_rect(Rect2(0, 15, 192, 1), C_EDGE)
	draw_texture(Art.tex("chest"), Vector2(3, 4))
	_txt(str(Game.wealth()), Vector2(12, 5), C_GOLD)
	var lv_x := 12 + Art.text_width(str(Game.wealth())) + 5
	_txt("LV%d" % Game.level(), Vector2(lv_x, 3), C_GREEN)
	_bar(Rect2(lv_x, 9, 15, 3), Game.level_progress(), C_GREEN)
	_txt("DAY %d" % Game.day, Vector2(70, 3))
	_txt(Game.clock_text(), Vector2(70, 9), C_DIM)
	var wicon: String = "ic_moon" if Game.is_night() and Game.weather in ["sunny", "heat"] else {
		"sunny": "ic_sun", "cloudy": "ic_cloud", "rain": "ic_rain", "storm": "ic_storm", "heat": "ic_heat"}[Game.weather]
	draw_texture(Art.tex(wicon), Vector2(106, 0))
	# multiplayer: who's here
	# "2P": green with two players on the farm, blinking while hosting and waiting for the friend
	var together := Net.is_guest() or (Net.mode == "hosting" and Net.guest_pid != "")
	if together or (Net.mode == "hosting" and int(t * 1.5) % 2 == 0):
		_txt("2P", Vector2(125, 5), C_GREEN if together else C_DIM)
	for k in btns:
		var r: Rect2 = btns[k]
		draw_rect(r, C_EDGE if hover_btn == k or (k == "gear" and settings_open) else C_SLOT)
		if k == "gear":
			draw_texture(Art.tex("gear"), r.position + Vector2(1, 1))
			continue
		var glyph: String = {"menu": "=", "dock": "<" if Game.settings.get("dock", "right") == "right" else ">", "min": "_", "close": "X"}[k]
		Art.draw_text(self, glyph, r.position + Vector2(3, 2), C_RED if k == "close" and hover_btn == k else C_TEXT)


func _draw_status() -> void:
	draw_rect(Rect2(0, STATUS_Y, 192, TRAY_Y - STATUS_Y), C_PANEL)
	draw_rect(Rect2(0, STATUS_Y, 192, 1), C_EDGE)
	var y := STATUS_Y + 3
	draw_texture(Art.tex("heart"), Vector2(3, y))
	_bar(Rect2(12, y + 1, 26, 5), Game.health / 100.0, C_RED if Game.poison <= 0.0 else Color("38b764"))
	draw_texture(Art.tex("bolt"), Vector2(41, y))
	_bar(Rect2(49, y + 1, 26, 5), Game.energy / 100.0, C_GOLD)
	var face := "face_happy" if Game.mood > 65.0 else ("face_ok" if Game.mood > 35.0 else "face_sad")
	draw_texture(Art.tex(face), Vector2(79, y))
	draw_texture(Art.tex("eye"), Vector2(89, y), Color.WHITE.lerp(C_PURPLE, clampf(Game.weird / 60.0, 0.0, 1.0)))
	_txt(str(int(Game.weird)), Vector2(97, y + 1), C_PURPLE if Game.weird >= 10.0 else C_DIM)
	var x := 97 + Art.text_width(str(int(Game.weird))) + 3
	var icons: Array = []
	if Game.totems > 0:
		icons.append(["r_totem", "%d" % Game.totems])
	if world and world.colony and world.colony.active():
		icons.append(["r_alien", str(world.colony.population())])
	if world and world.swarm and world.swarm.active():
		icons.append(["r_brood", str(world.swarm.population())])
	if not Game.mutations.is_empty():
		icons.append(["r_mutation", ""])
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
		if x > 150:
			break
		draw_texture(Art.tex(ic[0]), Vector2(x, y))
		x += 8
		if ic[1] != "":
			_txt(ic[1], Vector2(x, y + 1), C_TEXT)
			x += Art.text_width(ic[1]) + 2
	# building materials, right-aligned: a little plank and a little stone
	var mats := "%d" % Game.item_count("stone")
	var mx := 189 - Art.text_width(mats)
	_txt(mats, Vector2(mx, y + 1), C_DIM)
	draw_rect(Rect2(mx - 6, y + 2, 4, 3), Color("94b0c2"))
	draw_rect(Rect2(mx - 6, y + 4, 4, 1), Color("566c86"))
	var wd := "%d" % Game.item_count("wood")
	var wx := mx - 9 - Art.text_width(wd)
	_txt(wd, Vector2(wx, y + 1), C_WOOD)
	draw_rect(Rect2(wx - 7, y + 2, 5, 2), C_WOOD)
	draw_rect(Rect2(wx - 7, y + 4, 5, 1), Color("8b5a3c"))
	var act := "> " + (world.farmer.activity if world and world.farmer else "")
	_txt(act.substr(0, 46), Vector2(3, STATUS_Y + 11), C_TEXT)
	# bottom line: hovered card, else the latest log line
	var hs: Array = hover_slot
	if not hs.is_empty() and Game.card_at(hs[0], hs[1]) != "" and open_id == "":
		var c2: Dictionary = cards.card(Game.card_at(hs[0], hs[1]))
		var rar := int(c2.get("rarity", 1))
		_txt(String(c2.get("title", "")).substr(0, 30), Vector2(3, STATUS_Y + 18), C_GOLD)
		var rn: String = String(cards.RARITY_NAMES.get(rar, "")).to_upper()
		_txt(rn, Vector2(189 - Art.text_width(rn), STATUS_Y + 18), cards.RARITY_COLORS.get(rar, C_DIM))
		return
	var last: String = Game.log_lines[Game.log_lines.size() - 1] if Game.log_lines.size() > 0 else "Welcome to the farm!"
	_txt(last.substr(0, 46), Vector2(3, STATUS_Y + 18), C_DIM.lerp(C_GOLD, log_flash))


func _draw_tray() -> void:
	var bottom := 432
	draw_rect(Rect2(0, TRAY_Y, 192, bottom - TRAY_Y - 2), C_BG)
	draw_rect(Rect2(1, bottom - 2, 190, 1), C_BG)
	draw_rect(Rect2(2, bottom - 1, 188, 1), C_BG)
	draw_rect(Rect2(0, TRAY_Y, 192, 1), C_EDGE)
	_txt("STASH", Vector2(4, TRAY_Y + 3), C_GREEN)
	_txt("BOX", Vector2(100, TRAY_Y + 3), C_GOLD)
	var left := int(Game.next_card_left())
	var s := "%d:%02d" % [left / 60, left % 60]
	_txt(s, Vector2(188 - Art.text_width(s), TRAY_Y + 3), C_DIM if left > 10 else C_GOLD)
	# divider + "new cards come in here" arrow
	draw_rect(Rect2(95, TRAY_Y + 3, 1, 33), C_EDGE)
	var ax := 96.0 + fmod(t * 4.0, 3.0)
	_txt(">", Vector2(ax, SLOT_Y + 11), C_GOLD.darkened(0.3))
	for w in ["stash", "box"]:
		for i in 3:
			_draw_slot(w, i)
	# a trashed card sliding off the right edge
	if not trash_anim.is_empty():
		var k: float = trash_anim["t"]
		var r := _slot_rect("box", 2)
		r.position += Vector2(k * 40.0, k * k * 30.0)
		var c: Dictionary = cards.card(trash_anim["id"])
		var a := clampf(1.0 - k, 0.0, 1.0)
		_frame(r, Color(C_RED, a), Color(C_SLOT, a))
		_icon(c.get("art", ""), Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4)), 1, Color(1, 1, 1, a))
	# the card being dragged
	if card_drag and not press_slot.is_empty():
		var id := Game.card_at(press_slot[0], press_slot[1])
		if id != "":
			var r2 := Rect2(mouse - Vector2(SLOT_W, SLOT_H) * 0.5, Vector2(SLOT_W, SLOT_H))
			_frame(r2, C_GOLD, Color("4a5480"))
			_icon(cards.card(id).get("art", ""), Rect2(r2.position + Vector2(2, 2), r2.size - Vector2(4, 4)), 1)


func _draw_slot(where: String, i: int) -> void:
	var r := _slot_rect(where, i)
	var id := Game.card_at(where, i)
	var hov: bool = hover_slot == [where, i]
	var dragged: bool = card_drag and press_slot == [where, i]
	if id == "" or dragged:
		_frame(r, Color(1, 1, 1, 0.12) if not (card_drag and hov) else C_GOLD, Color(1, 1, 1, 0.03))
		if where == "box" and i == Game.BOX_SIZE - 1 and id == "":
			_txt("X", r.get_center() - Vector2(1, 2), Color(1, 1, 1, 0.08))
		return
	var c: Dictionary = cards.card(id)
	var rc: Color = cards.RARITY_COLORS.get(int(c.get("rarity", 1)), C_EDGE)
	var is_open := id == open_id
	var pl: float = pulse.get(id, 0.0)
	var edge := rc
	if hov or is_open:
		edge = C_GOLD
	elif pl > 0.0 and int(pl * 6.0) % 2 == 0:
		edge = C_TEXT
	var off := Vector2.ZERO
	if pl > 1.5 and where == "box":
		off.x = -(pl - 1.5) * 40.0   # slides in from the left
	var rr := Rect2(r.position + off, r.size)
	_frame(rr, edge, C_SLOT if not (hov or is_open) else Color("4a5480"))
	# the far-right box card is about to fall out: a red warning edge
	if where == "box" and i == Game.BOX_SIZE - 1 and int(t * 2.0) % 2 == 0:
		draw_rect(Rect2(rr.position.x, rr.end.y - 1, rr.size.x, 1), C_RED)
	var any_ok: bool = cards.can_choose(c, "a") or cards.can_choose(c, "b")
	draw_rect(Rect2(rr.end.x - 4, rr.position.y + 2, 2, 2), C_GREEN if any_ok else C_RED)
	_icon(c.get("art", ""), Rect2(rr.position + Vector2(2, 2 + (-1 if hov else 0)), Vector2(SLOT_W - 4, SLOT_H - 4)), 1)
