class_name TextEntry
extends RefCounted
## A one-line text field for the pixel-font UI (join address, player name). The owner draws it
## with draw() and feeds it key events with key(); it never takes focus by itself.
##   var addr := TextEntry.new(21, TextEntry.ADDRESS)
##   addr.key(event)  -> "" (ignored) / "edit" / "submit" (Enter)

const ADDRESS := "0123456789.:-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
const NAME := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -"

var text := ""
var max_len := 21
var allowed := ADDRESS
var upper := true          # names and addresses are shown (and kept) in capitals, like the font


func _init(max_chars: int = 21, chars: String = ADDRESS) -> void:
	max_len = max_chars
	allowed = chars


func set_text(s: String) -> void:
	text = ""
	_insert(s)


## Handles one key press: typing, Backspace, Ctrl+V (paste), Ctrl+Backspace (clear), Enter.
func key(e: InputEvent) -> String:
	if not (e is InputEventKey) or not e.pressed:
		return ""
	var k := e as InputEventKey
	if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		return "submit"
	if k.keycode == KEY_BACKSPACE:
		text = "" if k.ctrl_pressed else text.substr(0, maxi(0, text.length() - 1))
		return "edit"
	if k.keycode == KEY_V and (k.ctrl_pressed or k.meta_pressed):
		_insert(DisplayServer.clipboard_get())
		return "edit"
	if k.unicode > 0 and not k.ctrl_pressed:
		var before := text
		_insert(String.chr(k.unicode))
		return "edit" if text != before else ""
	return ""


func _insert(s: String) -> void:
	var src := s.strip_edges() if text == "" else s
	for ch in src:
		if text.length() >= max_len:
			break
		if ch in allowed:
			text += ch.to_upper() if upper else ch


## Draws the field in rect r (11px tall fits the 3x5 font); a blinking cursor while focused.
func draw(ci: CanvasItem, r: Rect2, focused: bool, t: float, placeholder: String = "") -> void:
	ci.draw_rect(r, Color("ffcd75") if focused else Color("5a6988"))
	ci.draw_rect(r.grow(-1), Color("1a1c2c"))
	var p := r.position + Vector2(3, floorf((r.size.y - 5) / 2.0))
	if text == "" and not focused:
		Art.draw_text(ci, placeholder, p, Color("566c86"))
		return
	# long text scrolls so the end (where you type) stays visible
	var fit := int((r.size.x - 6) / 4)
	var shown := text.substr(maxi(0, text.length() - fit + 1))
	Art.draw_text(ci, shown, p, Color("f4f4f4"))
	if focused and int(t * 2.0) % 2 == 0:
		ci.draw_rect(Rect2(p.x + Art.text_width(shown) + 1, p.y, 1, 5), Color("ffcd75"))
