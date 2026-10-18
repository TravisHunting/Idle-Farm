extends Node2D
class_name World
## The farm: a COLS x ROWS tile grid plus everything that lives on it.
## Owns ground/wetness arrays, crops, objects, the farmer + animals (RefCounted actors),
## particles and floating texts. Draws ground + crops; EntityLayer draws objects/actors.

const COLS := 12
const ROWS := 16
const T := 16
const HOUSE_CELLS := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
const DOOR := Vector2i(1, 2)
const BIN := Vector2i(3, 1)
const BIN_FRONT := Vector2i(3, 2)
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Object types that block movement (structures use Game.STRUCTS[...].solid).
const SOLID_DEBRIS := ["rock", "stump", "tree", "ore", "bin", "house"]
## Crops that glow faintly at night.
const GLOWING := ["glowshroom", "moonflower", "starfruit"]
const DEBRIS := ["rock", "weed", "stump", "ash", "ore"]

var ground := PackedInt32Array()       # 0 grass, 1 tilled
var wet := PackedFloat32Array()        # 0..1
var gvar := PackedInt32Array()         # grass variant
var crops := {}                        # Vector2i -> {type, growth, health, dead}
var objs := {}                         # Vector2i -> {type, hp, ...}
var farmer: Farmer
var animals: Array = []
var particles: Array = []              # {p, v, life, c}
var floats: Array = []                 # {text, p, t, c}
var entity_layer: Node2D
var fx_layer: Node2D
var director: Node

var _weed_t := 0.0
var _anim_t := 0.0


func _ready() -> void:
	ground.resize(COLS * ROWS)
	wet.resize(COLS * ROWS)
	gvar.resize(COLS * ROWS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in COLS * ROWS:
		var r := rng.randf()
		gvar[i] = 3 if r < 0.08 else (rng.randi() % 3)


func new_farm() -> void:
	ground.fill(0)
	wet.fill(0.0)
	crops.clear()
	objs.clear()
	animals.clear()
	objs[BIN] = {"type": "bin", "hp": 999}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var plan := {"rock": 8, "weed": 12, "stump": 3, "tree": 3}
	for t in plan:
		for n in plan[t]:
			for attempt in 30:
				var c := Vector2i(rng.randi_range(0, COLS - 1), rng.randi_range(0, ROWS - 1))
				if t == "tree" and not (c.x == 0 or c.x == COLS - 1 or c.y == ROWS - 1):
					continue
				if is_free_grass(c) and c.distance_to(DOOR) > 1.5:
					place_obj(c, t)
					break
	farmer = Farmer.new(self)
	farmer.pos = feet(DOOR)


# ---------------------------------------------------------------- grid helpers
func idx(c: Vector2i) -> int:
	return c.y * COLS + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


func feet(c: Vector2i) -> Vector2:
	return Vector2(c.x * T + 8, c.y * T + 13)


func center(c: Vector2i) -> Vector2:
	return Vector2(c.x * T + 8, c.y * T + 8)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x) / T, 0, COLS - 1), clampi(int(p.y) / T, 0, ROWS - 1))


func is_house(c: Vector2i) -> bool:
	return c in HOUSE_CELLS


func is_tilled(c: Vector2i) -> bool:
	return in_bounds(c) and ground[idx(c)] == 1


func set_tilled(c: Vector2i, v: bool) -> void:
	ground[idx(c)] = 1 if v else 0
	if not v:
		wet[idx(c)] = 0.0
		crops.erase(c)


func obj_at(c: Vector2i) -> Dictionary:
	return objs.get(c, {})


func obj_type(c: Vector2i) -> String:
	return String(objs[c]["type"]) if objs.has(c) else ""


func place_obj(c: Vector2i, type: String, extra: Dictionary = {}) -> Dictionary:
	var hp := 50
	if Game.STRUCTS.has(type):
		hp = Game.STRUCTS[type]["hp"]
	var o := {"type": type, "hp": hp}
	if type == "tree":
		o["apple"] = randf() < 0.4
	for k in extra:
		o[k] = extra[k]
	objs[c] = o
	return o


func remove_obj(c: Vector2i) -> void:
	objs.erase(c)


func is_solid(c: Vector2i) -> bool:
	if is_house(c):
		return true
	if not objs.has(c):
		return false
	var t := obj_type(c)
	if t in SOLID_DEBRIS:
		return true
	if Game.STRUCTS.has(t):
		return Game.STRUCTS[t]["solid"]
	return false


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not is_solid(c)


func is_free_grass(c: Vector2i) -> bool:
	return in_bounds(c) and not is_house(c) and ground[idx(c)] == 0 and not objs.has(c) \
		and c != DOOR and c != BIN_FRONT and not crops.has(c)


func count_obj(type: String) -> int:
	var n := 0
	for c in objs:
		if objs[c]["type"] == type:
			n += 1
	return n


func cells_with_obj(types: Array) -> Array:
	var out: Array = []
	for c in objs:
		if objs[c]["type"] in types:
			out.append(c)
	return out


func tilled_cells() -> Array:
	var out: Array = []
	for y in ROWS:
		for x in COLS:
			if ground[y * COLS + x] == 1:
				out.append(Vector2i(x, y))
	return out


func free_grass_cells() -> Array:
	var out: Array = []
	for y in ROWS:
		for x in COLS:
			var c := Vector2i(x, y)
			if is_free_grass(c):
				out.append(c)
	return out


func nearest(cells: Array, from: Vector2i) -> Variant:
	var best: Variant = null
	var bd := 1e9
	for c in cells:
		var d: float = Vector2(c).distance_squared_to(Vector2(from)) + randf() * 0.5
		if d < bd:
			bd = d
			best = c
	return best


func near_obj(c: Vector2i, type: String, radius: float) -> bool:
	for o in objs:
		if objs[o]["type"] == type and Vector2(o).distance_to(Vector2(c)) <= radius:
			return true
	return false


func crop_stage(cr: Dictionary) -> int:
	if cr.get("dead", false):
		return -1
	var g: float = cr["growth"]
	if g < 0.2:
		return 0
	if g < 0.5:
		return 1
	if g < 1.0:
		return 2
	return 3


func ripe_cells() -> Array:
	var out: Array = []
	for c in crops:
		if crop_stage(crops[c]) == 3:
			out.append(c)
	return out


## BFS. Returns the list of cells to walk (excluding start), or null if unreachable.
## adjacent = stop next to `to` (for solid targets).
func find_path(from: Vector2i, to: Vector2i, adjacent: bool = false) -> Variant:
	if from == to and not adjacent:
		return []
	var prev := {from: from}
	var q: Array = [from]
	var goal: Variant = null
	while q.size() > 0:
		var c: Vector2i = q.pop_front()
		if (not adjacent and c == to) or (adjacent and _adjacent(c, to)):
			goal = c
			break
		for d in DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not in_bounds(n):
				continue
			if is_solid(n) and n != to:
				continue
			if n == to and adjacent:
				continue
			prev[n] = c
			q.append(n)
	if goal == null:
		return null
	var path: Array = []
	var cur: Vector2i = goal
	while cur != from:
		path.push_front(cur)
		cur = prev[cur]
	return path


func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


# ---------------------------------------------------------------- simulation
func _process(delta: float) -> void:
	var d := delta * Game.time_scale
	_anim_t += d
	_update_ground(d)
	if farmer:
		farmer.update(d)
	for a in animals.duplicate():
		a.update(d)
		if a.dead:
			animals.erase(a)
	_update_fx(d)
	_weed_t += d
	if _weed_t > 25.0:
		_weed_t = 0.0
		# ash washes away on its own
		var ash := cells_with_obj(["ash"])
		if ash.size() > 0 and randf() < 0.5:
			remove_obj(ash.pick_random())
		if randf() < 0.3 and cells_with_obj(DEBRIS).size() < 16:
			var cells := free_grass_cells()
			if cells.size() > 0:
				place_obj(cells.pick_random(), "weed")
	queue_redraw()
	if entity_layer:
		entity_layer.queue_redraw()
	if fx_layer:
		fx_layer.queue_redraw()


func _update_ground(d: float) -> void:
	var raining := Game.weather == "rain" or Game.weather == "storm"
	var decay := 1.0 / (70.0 if Game.weather == "heat" else 160.0)
	for y in ROWS:
		for x in COLS:
			var i := y * COLS + x
			if ground[i] != 1:
				continue
			if raining:
				wet[i] = 1.0
			else:
				wet[i] = maxf(0.0, wet[i] - d * decay)
	for c in crops:
		var cr: Dictionary = crops[c]
		if cr.get("dead", false):
			continue
		var i := idx(c)
		if cr["growth"] < 1.0:
			if wet[i] > 0.0:
				var mult := 1.0
				if Game.buff("sun"):
					mult *= 2.0
				if Game.buff("growth"):
					mult *= 1.5
				if near_obj(c, "beehive", 2.5):
					mult *= 1.3
				if near_obj(c, "idol", 3.0):
					mult *= 1.5
				cr["growth"] = minf(1.0, cr["growth"] + d / float(Game.CROPS[cr["type"]]["grow"]) * mult)
				cr["health"] = minf(100.0, cr["health"] + d * 2.0)
			else:
				cr["health"] -= d * (1.2 if Game.weather == "heat" else 0.7)
				if cr["health"] <= 0.0:
					cr["dead"] = true
					Game.add_log("A %s withered away." % Game.CROPS[cr["type"]]["name"].to_lower())
					Game.mood = maxf(0.0, Game.mood - 4.0)


func plant(c: Vector2i, type: String) -> void:
	crops[c] = {"type": type, "growth": 0.0, "health": 100.0, "dead": false}


func damage_crop(c: Vector2i, growth_loss: float, health_loss: float) -> void:
	if not crops.has(c):
		return
	var cr: Dictionary = crops[c]
	cr["growth"] = maxf(0.0, cr["growth"] - growth_loss)
	cr["health"] -= health_loss
	if cr["health"] <= 0.0:
		destroy_crop(c, true)


func destroy_crop(c: Vector2i, leave_dead: bool) -> void:
	if not crops.has(c):
		return
	if leave_dead:
		crops[c]["dead"] = true
	else:
		crops.erase(c)


func threats() -> Array:
	var out: Array = []
	for a in animals:
		if a.is_threat() and not a.leaving():
			out.append(a)
	return out


func add_animal(a: Animal) -> Animal:
	animals.append(a)
	return a


func count_animals(kind: String) -> int:
	var n := 0
	for a in animals:
		if a.kind == kind and not a.dead:
			n += 1
	return n


# ---------------------------------------------------------------- fx
func puff(p: Vector2, c: Color, n: int = 6, speed: float = 18.0, up: float = 10.0) -> void:
	for i in n:
		var a := randf() * TAU
		particles.append({"p": p, "v": Vector2(cos(a), sin(a)) * randf_range(0.3, 1.0) * speed + Vector2(0, -up),
			"life": randf_range(0.4, 0.9), "c": c})


func float_text(text: String, p: Vector2, c: Color = Color("ffcd75")) -> void:
	floats.append({"text": text, "p": p, "t": 0.0, "c": c})


func _update_fx(d: float) -> void:
	for pt in particles.duplicate():
		pt["life"] -= d
		pt["v"] += Vector2(0, 30) * d
		pt["p"] += pt["v"] * d
		if pt["life"] <= 0.0:
			particles.erase(pt)
	for f in floats.duplicate():
		f["t"] += d
		f["p"] += Vector2(0, -10) * d
		if f["t"] > 1.6:
			floats.erase(f)


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	for y in ROWS:
		for x in COLS:
			var i := y * COLS + x
			var p := Vector2(x * T, y * T)
			if ground[i] == 1:
				draw_texture(Art.tex("tilled_wet" if wet[i] > 0.05 else "tilled"), p)
			else:
				draw_texture(Art.tex("grass%d" % gvar[i]), p)
	# path to the door
	for c in [DOOR, BIN_FRONT]:
		if ground[idx(c)] == 0:
			draw_rect(Rect2(c.x * T + 4, c.y * T + 2, 8, 12), Color(0.78, 0.66, 0.45, 0.55))
	for c in crops:
		var cr: Dictionary = crops[c]
		var st := crop_stage(cr)
		var name := "crop_dead"
		match st:
			0: name = "crop_seed"
			1: name = "crop_sprout"
			2: name = "crop_grow"
			3: name = "crop_" + String(cr["type"])
		var mod := Color.WHITE
		if st >= 0 and cr["health"] < 45.0:
			mod = Color(0.85, 0.75, 0.5)
		var bob := 0.0
		if st == 3:
			bob = sin(_anim_t * 2.0 + c.x) * 0.5
		draw_texture(Art.tex(name), Vector2(c.x * T, c.y * T + bob - 2), mod)
		if st >= 2 and cr["type"] in GLOWING and Game.darkness() > 0.3:
			draw_circle(center(c), 7.0, Color(0.45, 1.0, 0.95, 0.12 * Game.darkness()))


# ---------------------------------------------------------------- save
func to_dict() -> Dictionary:
	var cr := {}
	for c in crops:
		cr["%d,%d" % [c.x, c.y]] = crops[c]
	var ob := {}
	for c in objs:
		ob["%d,%d" % [c.x, c.y]] = objs[c]
	var an: Array = []
	for a in animals:
		if a.persistent():
			an.append(a.to_dict())
	return {"ground": Array(ground), "wet": Array(wet), "crops": cr, "objs": ob, "animals": an,
		"farmer": farmer.to_dict() if farmer else {}}


func from_dict(d: Dictionary) -> void:
	var g: Array = d.get("ground", [])
	if g.size() == COLS * ROWS:
		for i in g.size():
			ground[i] = int(g[i])
	var w: Array = d.get("wet", [])
	if w.size() == COLS * ROWS:
		for i in w.size():
			wet[i] = float(w[i])
	crops.clear()
	var cr: Dictionary = d.get("crops", {})
	for k in cr:
		var c := _key_cell(k)
		var v: Dictionary = cr[k]
		if Game.CROPS.has(v.get("type", "")):
			crops[c] = {"type": v["type"], "growth": float(v.get("growth", 0)), "health": float(v.get("health", 100)),
				"dead": bool(v.get("dead", false))}
	objs.clear()
	var ob: Dictionary = d.get("objs", {})
	for k in ob:
		objs[_key_cell(k)] = ob[k]
	if not objs.has(BIN):
		objs[BIN] = {"type": "bin", "hp": 999}
	animals.clear()
	farmer = Farmer.new(self)
	farmer.pos = feet(DOOR)
	farmer.from_dict(d.get("farmer", {}))
	for ad in d.get("animals", []):
		var a := Animal.new(self, String(ad.get("kind", "chicken")), Vector2(float(ad.get("x", 80)), float(ad.get("y", 80))))
		a.from_dict(ad)
		animals.append(a)


func _key_cell(k: String) -> Vector2i:
	var parts := k.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
