extends Node2D
class_name World
## The farm: a COLS x ROWS tile grid plus everything that lives on it.
## Owns ground/wetness arrays, crops, objects, planned fields, the farmer + animals (RefCounted
## actors), particles and floating texts. Draws ground + crops; EntityLayer draws objects/actors.
##
## A new farm (new_farm) is randomised: a biome flavours the overgrowth (woods, rocks, brambles,
## meadow, marsh), the house lands somewhere along the top, there may be a pond and some junk
## grandpa left behind, and everything except a little yard is heavily overgrown.
## The farmer plans fields in (sometimes silly) shapes, clears them, lays paths and fences them.

const COLS := 12
const ROWS := 22
const T := 16
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]

const G_GRASS := 0
const G_TILLED := 1
const G_PATH := 2
const G_WATER := 3

## Overgrowth the farmer can clear: work seconds, tool, materials dropped, thorn chance.
const CLEARABLE := {
	"weed":      {"dur": 1.0, "tool": "tool_sickle", "drops": {}},
	"tallgrass": {"dur": 1.2, "tool": "tool_sickle", "drops": {}},
	"ash":       {"dur": 1.0, "tool": "tool_hoe", "drops": {}},
	"bush":      {"dur": 2.2, "tool": "tool_axe", "drops": {"wood": 1}},
	"bramble":   {"dur": 2.8, "tool": "tool_sickle", "drops": {"wood": 1}, "thorns": 0.25},
	"rock":      {"dur": 2.5, "tool": "tool_hammer", "drops": {"stone": 2}},
	"boulder":   {"dur": 6.0, "tool": "tool_hammer", "drops": {"stone": 5}},
	"stump":     {"dur": 3.5, "tool": "tool_axe", "drops": {"wood": 2}},
	"log":       {"dur": 3.0, "tool": "tool_axe", "drops": {"wood": 3}},
	"a_ruin":    {"dur": 4.0, "tool": "tool_hammer", "drops": {"stone": 2, "ore": 1}},
	"a_husk":    {"dur": 1.5, "tool": "tool_hammer", "drops": {"stone": 1}},
}
const TREES := ["tree", "pine"]
## Object types that block movement (structures use Game.STRUCTS[...].solid).
const SOLID_DEBRIS := ["rock", "boulder", "stump", "log", "bush", "bramble", "tree", "pine", "ore", "bin", "a_ruin"]
## Alien village buildings (colony.gd); the solid ones block walking.
const ALIEN_SOLID := ["a_pod", "a_hatchery", "a_spire", "a_dish", "a_pylon"]
## Objects left by the mysteries (sagas.gd): never cleared, burned or built over. Solid ones block.
const MYSTERY := ["strange_egg", "strange_egg_glow", "strange_egg_cracked", "ufo", "glyph", "candle", "bootprints"]
const MYSTERY_SOLID := ["strange_egg", "strange_egg_glow", "strange_egg_cracked", "ufo"]
## Crops that glow faintly at night.
const GLOWING := ["glowshroom", "moonflower", "starfruit"]
## Things that count as "overgrowth" for regrowth caps and the cleared % stat.
const DEBRIS := ["weed", "tallgrass", "rock", "boulder", "stump", "log", "bush", "bramble", "ash", "ore"]

## Biomes: name pool + weights per group. Groups are picked by a second noise layer so
## trees cluster into copses, rocks into stony patches, and ground cover fills the rest.
const BIOMES := {
	"woodland": {"names": ["Whispering Pines", "Old Oak Hollow", "Mossy Glen"], "density": 0.80, "pond": 0.4,
		"wood": {"pine": 6, "tree": 4, "stump": 3, "log": 2, "bush": 3}, "stone": {"rock": 4, "bramble": 2, "boulder": 1},
		"cover": {"tallgrass": 4, "weed": 3, "bush": 3, "bramble": 1}, "bias": 0.25},
	"rocky": {"names": ["Stony Acre", "Pebble Ridge", "Gravelbottom"], "density": 0.74, "pond": 0.3,
		"wood": {"pine": 3, "stump": 2, "bush": 2}, "stone": {"rock": 6, "boulder": 3, "bramble": 1},
		"cover": {"weed": 4, "tallgrass": 3, "rock": 2}, "bias": -0.25},
	"brambles": {"names": ["Thornbury", "Bramble End", "Prickle Patch"], "density": 0.80, "pond": 0.3,
		"wood": {"bush": 4, "tree": 2, "stump": 2}, "stone": {"bramble": 5, "rock": 3},
		"cover": {"bramble": 3, "weed": 4, "tallgrass": 3, "bush": 2}, "bias": 0.0},
	"meadow": {"names": ["Clover Field", "Long Grass Farm", "Buttercup Rise"], "density": 0.72, "pond": 0.5,
		"wood": {"tree": 3, "bush": 3, "log": 1}, "stone": {"rock": 3, "boulder": 1},
		"cover": {"tallgrass": 7, "weed": 4, "bush": 1}, "bias": 0.0},
	"marsh": {"names": ["Froggy Bottom", "Mudwater Farm", "Soggy Acres"], "density": 0.76, "pond": 1.1,
		"wood": {"log": 3, "tree": 2, "bush": 3, "stump": 2}, "stone": {"rock": 3, "bramble": 2},
		"cover": {"tallgrass": 6, "weed": 4, "bramble": 1}, "bias": 0.1},
}

## Field shapes (# = tilled). The farmer is a bit silly: some fields are hearts or smileys,
## and he nudges the odd tile out of line.
const SHAPES := {
	"patch":    ["###", "###"],
	"block":    ["###", "###", "###"],
	"rows":     ["####", "....", "####"],
	"stripes":  ["#.#.#", "#.#.#", "#.#.#"],
	"checker":  ["#.#.", ".#.#", "#.#."],
	"heart":    [".#.#.", "#####", ".###.", "..#.."],
	"smiley":   ["#...#", ".....", "#...#", ".###."],
	"ring":     ["###", "#.#", "###"],
	"plus":     [".#.", "###", ".#."],
	"diagonal": ["#...", ".#..", "..#.", "...#"],
	"zigzag":   ["#.#.#", ".#.#."],
	"ell":      ["#..", "#..", "###"],
	"letter_f": ["###", "#..", "##.", "#.."],
	"line":     ["#####"],
	"pair":     ["##"],
}
const SILLY := ["heart", "smiley", "ring", "plus", "diagonal", "zigzag", "ell", "letter_f", "checker"]
const SENSIBLE := ["patch", "block", "rows", "stripes", "line"]

var ground := PackedInt32Array()       # G_* per cell
var wet := PackedFloat32Array()        # 0..1
var gvar := PackedInt32Array()         # grass variant
var crops := {}                        # Vector2i -> {type, growth, health, dead}
var objs := {}                         # Vector2i -> {type, hp, ...}
var fields: Array = []                 # [{cells: [Vector2i], shape, crop}]
var alien_land := {}                   # Vector2i -> true: the alien creep (colony.gd)
var biome := "meadow"
var house := Vector2i(0, 0)            # top-left cell of the 2x2 house
var DOOR := Vector2i(1, 2)
var BIN := Vector2i(3, 1)
var BIN_FRONT := Vector2i(3, 2)
var farmer: Farmer
var animals: Array = []
var particles: Array = []              # {p, v, life, c}
var floats: Array = []                 # {text, p, t, c}
var entity_layer: Node2D
var fx_layer: Node2D
var director: Node
var colony: Colony

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


# ---------------------------------------------------------------- new farm
func new_farm() -> void:
	ground.fill(G_GRASS)
	wet.fill(0.0)
	crops.clear()
	objs.clear()
	animals.clear()
	fields.clear()
	alien_land.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	biome = BIOMES.keys()[rng.randi() % BIOMES.size()]
	var b: Dictionary = BIOMES[biome]
	# the house sits somewhere along the top, the shipping bin beside it
	_set_house(Vector2i(rng.randi_range(0, COLS - 4), rng.randi_range(0, 2)), rng.randf() < 0.5)
	objs[BIN] = {"type": "bin", "hp": 999}
	ground[idx(DOOR)] = G_PATH
	ground[idx(BIN_FRONT)] = G_PATH
	# a pond, sometimes
	var ponds := 1 if rng.randf() < float(b["pond"]) else 0
	if biome == "marsh":
		ponds = 2
	for i in ponds:
		_dig_pond(rng, rng.randi_range(3, 7 if biome == "marsh" else 5))
	# the overgrowth: two noise layers (how dense, what kind)
	var dense := FastNoiseLite.new()
	dense.seed = rng.randi()
	dense.frequency = 0.18
	var kind := FastNoiseLite.new()
	kind.seed = rng.randi()
	kind.frequency = 0.14
	for y in ROWS:
		for x in COLS:
			var c := Vector2i(x, y)
			if not is_free_grass(c) or _in_yard(c):
				continue
			var p: float = float(b["density"]) + dense.get_noise_2d(x, y) * 0.35
			if rng.randf() > p:
				continue
			var k := kind.get_noise_2d(x, y) + float(b["bias"])
			var group := "cover"
			if k > 0.28:
				group = "wood"
			elif k < -0.28:
				group = "stone"
			var t := _weighted(rng, b[group])
			if t == "boulder" and (x == 0 or y == ROWS - 1):
				t = "rock"
			place_obj(c, t)
	_leftovers(rng)
	# reachability: never wall the farmer into his yard with solid stuff
	_open_up()
	Game.farm_name = (b["names"] as Array)[rng.randi() % (b["names"] as Array).size()]
	Game.quirk = Game.QUIRKS.keys()[rng.randi() % Game.QUIRKS.size()]
	# grandpa left a few trinkets in the chest
	Game.gain_trinkets(rng.randi_range(18, 40), false)
	farmer = Farmer.new(self)
	farmer.pos = feet(DOOR)


func _set_house(top_left: Vector2i, bin_left: bool) -> void:
	house = top_left
	DOOR = house + Vector2i(1, 2)
	if bin_left and house.x >= 1:
		BIN = house + Vector2i(-1, 1)
	else:
		BIN = house + Vector2i(3, 1)
	BIN_FRONT = BIN + Vector2i(0, 1)


## The little clearing in front of the house that starts out free.
func _in_yard(c: Vector2i) -> bool:
	if c.y < house.y + 2 or c.y > house.y + 3:
		return false
	return c.x >= mini(house.x, BIN.x) - 1 and c.x <= maxi(house.x + 1, BIN.x) + 1


func _weighted(rng: RandomNumberGenerator, table: Dictionary) -> String:
	var total := 0
	for k in table:
		total += int(table[k])
	var r := rng.randi() % maxi(1, total)
	for k in table:
		r -= int(table[k])
		if r < 0:
			return k
	return table.keys()[0]


func _dig_pond(rng: RandomNumberGenerator, size: int) -> void:
	for attempt in 30:
		var c := Vector2i(rng.randi_range(0, COLS - 1), rng.randi_range(house.y + 5, ROWS - 1))
		if not is_free_grass(c) or c.distance_to(DOOR) < 4.0:
			continue
		var cells := [c]
		for i in size * 3:
			if cells.size() >= size:
				break
			var n: Vector2i = cells.pick_random() + DIRS[rng.randi() % 4]
			if in_bounds(n) and is_free_grass(n) and not n in cells and n.distance_to(DOOR) >= 4.0:
				cells.append(n)
		for p in cells:
			ground[idx(p)] = G_WATER
		return


## Grandpa left some things lying around. Different every farm.
func _leftovers(rng: RandomNumberGenerator) -> void:
	var junk := ["old_bench", "old_scarecrow", "ore", "old_patch", "old_sign", "apple_tree", "boulders", "logs"]
	junk.shuffle()
	for j in junk.slice(0, rng.randi_range(2, 3)):
		var cells := free_or_overgrown_cells()
		cells.shuffle()
		if cells.is_empty():
			return
		var c: Vector2i = cells[0]
		match j:
			"old_bench":
				remove_obj(c)
				place_obj(c, "bench", {"hp": 18})
			"old_scarecrow":
				remove_obj(c)
				place_obj(c, "scarecrow", {"hp": 24})
			"old_sign":
				remove_obj(c)
				place_obj(c, "sign", {"hp": 15})
			"ore":
				remove_obj(c)
				place_obj(c, "ore")
			"apple_tree":
				remove_obj(c)
				place_obj(c, "tree", {"apple": true})
			"boulders":
				for i in 3:
					if i < cells.size():
						remove_obj(cells[i])
						place_obj(cells[i], "boulder")
			"logs":
				for i in 3:
					if i < cells.size():
						remove_obj(cells[i])
						place_obj(cells[i], "log")
			"old_patch":
				# a few weedy tilled tiles from grandpa's last season, near the house
				var near: Array = []
				for cc in cells:
					if cc.distance_to(DOOR) <= 4.5 and not _in_yard(cc):
						near.append(cc)
				for i in mini(3, near.size()):
					remove_obj(near[i])
					ground[idx(near[i])] = G_TILLED


## Makes sure the yard isn't sealed in: knocks out solid debris until the farmer can reach
## a good chunk of the farm (walking over weeds/tall grass is fine).
func _open_up() -> void:
	for i in 40:
		var reach := reachable_from(DOOR)
		if reach.size() >= 40:
			return
		var best: Variant = null
		var bd := 1e9
		for c in reach:
			for d in DIRS:
				var n: Vector2i = c + d
				if in_bounds(n) and not reach.has(n) and objs.has(n) and obj_type(n) in SOLID_DEBRIS and obj_type(n) != "bin":
					var dd := n.distance_to(DOOR)
					if dd < bd:
						bd = dd
						best = n
		if best == null:
			return
		var t := obj_type(best)
		remove_obj(best)
		place_obj(best, "tallgrass" if t in ["rock", "boulder", "bramble"] else "weed")


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


func house_px() -> Vector2:
	return Vector2(house * T)


func is_house(c: Vector2i) -> bool:
	return c.x >= house.x and c.x <= house.x + 1 and c.y >= house.y and c.y <= house.y + 1


func is_tilled(c: Vector2i) -> bool:
	return in_bounds(c) and ground[idx(c)] == G_TILLED


func is_path(c: Vector2i) -> bool:
	return in_bounds(c) and ground[idx(c)] == G_PATH


func is_water(c: Vector2i) -> bool:
	return in_bounds(c) and ground[idx(c)] == G_WATER


func set_tilled(c: Vector2i, v: bool) -> void:
	ground[idx(c)] = G_TILLED if v else G_GRASS
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
	if is_house(c) or is_water(c):
		return true
	if not objs.has(c):
		return false
	var t := obj_type(c)
	if t in SOLID_DEBRIS or t in MYSTERY_SOLID or t in ALIEN_SOLID:
		return true
	if Game.STRUCTS.has(t):
		return Game.STRUCTS[t]["solid"]
	return false


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not is_solid(c)


func is_free_grass(c: Vector2i) -> bool:
	return in_bounds(c) and not is_house(c) and ground[idx(c)] == G_GRASS and not objs.has(c) \
		and c != DOOR and c != BIN_FRONT and not crops.has(c) and not alien_land.has(c)


func is_clearable(c: Vector2i) -> bool:
	var t := obj_type(c)
	return CLEARABLE.has(t) or t in TREES


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
			if ground[y * COLS + x] == G_TILLED:
				out.append(Vector2i(x, y))
	return out


func path_count() -> int:
	return ground.count(G_PATH)


func free_grass_cells() -> Array:
	var out: Array = []
	for y in ROWS:
		for x in COLS:
			var c := Vector2i(x, y)
			if is_free_grass(c):
				out.append(c)
	return out


## Grass cells that are empty or only have clearable overgrowth on them.
func free_or_overgrown_cells() -> Array:
	var out: Array = []
	for y in ROWS:
		for x in COLS:
			var c := Vector2i(x, y)
			if in_bounds(c) and not is_house(c) and ground[idx(c)] == G_GRASS and c != DOOR \
					and c != BIN_FRONT and not crops.has(c) and (not objs.has(c) or is_clearable(c)):
				out.append(c)
	return out


## Share of the farm that is no longer overgrown (0..1).
func cleared_ratio() -> float:
	var land := 0
	var over := 0
	for y in ROWS:
		for x in COLS:
			var c := Vector2i(x, y)
			if is_house(c) or is_water(c):
				continue
			land += 1
			if objs.has(c) and (obj_type(c) in DEBRIS or obj_type(c) in TREES):
				over += 1
	return 1.0 - float(over) / maxf(1.0, land)


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


## Every cell the farmer can walk to from `from` (as a set).
func reachable_from(from: Vector2i, block: Vector2i = Vector2i(-99, -99)) -> Dictionary:
	var seen := {from: true}
	var q: Array = [from]
	while q.size() > 0:
		var c: Vector2i = q.pop_front()
		for d in DIRS:
			var n: Vector2i = c + d
			if seen.has(n) or n == block or not is_walkable(n):
				continue
			seen[n] = true
			q.append(n)
	return seen


## Cells holding something clearable that the farmer can actually get at.
func reachable_debris(reach: Dictionary) -> Array:
	var out: Array = []
	for c in objs:
		if not is_clearable(c):
			continue
		if reach.has(c):
			out.append(c)
			continue
		for d in DIRS:
			if reach.has(c + d):
				out.append(c)
				break
	return out


## True if putting something solid on c does not cut the farm in two.
func keeps_connected(c: Vector2i) -> bool:
	var before := reachable_from(DOOR).size()
	var after := reachable_from(DOOR, c).size()
	return after >= before - 1


# ---------------------------------------------------------------- fields
func field_index(c: Vector2i) -> int:
	for i in fields.size():
		if c in fields[i]["cells"]:
			return i
	return -1


func is_planned(c: Vector2i) -> bool:
	return field_index(c) >= 0


## A cell that can (eventually) be tilled for a field.
func _field_ok(c: Vector2i) -> bool:
	if not in_bounds(c) or is_house(c) or c == DOOR or c == BIN or c == BIN_FRONT:
		return false
	if ground[idx(c)] != G_GRASS or crops.has(c) or alien_land.has(c):
		return false
	return not objs.has(c) or is_clearable(c)


## Planned field cells that still need work: [cells to till now, cells still overgrown].
func field_todo() -> Array:
	var till: Array = []
	var blocked: Array = []
	for f in fields:
		for c in f["cells"]:
			if is_tilled(c) or not _field_ok(c):
				continue
			if objs.has(c):
				blocked.append(c)
			else:
				till.append(c)
	return [till, blocked]


func planned_open() -> int:
	var t: Array = field_todo()
	return t[0].size() + t[1].size()


## Plans a new field somewhere sensible-ish. Returns the field dict ({} if nothing fits).
func plan_field(shape: String = "", crop: String = "", capacity: int = -1) -> Dictionary:
	var cap := capacity
	if cap < 0:
		cap = Game.max_tilled() - tilled_cells().size() - planned_open()
	if cap < 2:
		return {}
	var options: Array = []
	if shape != "" and SHAPES.has(shape):
		options = [shape]
	else:
		var silly_chance := 0.65 if Game.quirk == "artsy" else 0.35
		var pool: Array = SILLY if randf() < silly_chance else SENSIBLE
		for s in pool:
			if _mask_cells(SHAPES[s]).size() <= cap:
				options.append(s)
		if options.is_empty():
			for s in SHAPES:
				if _mask_cells(SHAPES[s]).size() <= cap:
					options.append(s)
	if options.is_empty():
		return {}
	var pick: String = options.pick_random()
	var rel := _mask_cells(SHAPES[pick])
	# random rotation / mirror
	if randf() < 0.5:
		rel = rel.map(func(v: Vector2i) -> Vector2i: return Vector2i(v.y, v.x))
	if randf() < 0.5:
		var w := 0
		for v in rel:
			w = maxi(w, v.x)
		rel = rel.map(func(v: Vector2i) -> Vector2i: return Vector2i(w - v.x, v.y))
	var size := Vector2i.ZERO
	for v in rel:
		size = Vector2i(maxi(size.x, v.x + 1), maxi(size.y, v.y + 1))
	var best: Array = []
	var best_s := 1e9
	for attempt in 80:
		var a := Vector2i(randi_range(0, COLS - size.x), randi_range(0, ROWS - size.y))
		var cells: Array = []
		var ok := true
		var score := 0.0
		for v in rel:
			var c: Vector2i = a + v
			if not _field_ok(c) or _touches_field(c):
				ok = false
				break
			cells.append(c)
			if objs.has(c):
				score += 1.2 if obj_type(c) in ["boulder", "tree", "pine", "stump", "log"] else 0.15
		if not ok:
			continue
		score += Vector2(a + size / 2).distance_to(Vector2(DOOR)) * 0.9 + randf() * 3.0
		if score < best_s:
			best_s = score
			best = cells
	if best.is_empty():
		return {}
	# he's a bit sloppy: the odd tile ends up one step out of line
	var cells2: Array = []
	for c in best:
		var cc: Vector2i = c
		if randf() < 0.12:
			var n: Vector2i = c + DIRS.pick_random()
			if _field_ok(n) and not n in best and not n in cells2 and not _touches_field(n):
				cc = n
		cells2.append(cc)
	var crop_plan := crop
	if crop_plan == "":
		var r := randf()
		if r < 0.3:
			crop_plan = "mixed"
		elif r < 0.65:
			crop_plan = "any"
		else:
			crop_plan = _fancy_crop()
	var f := {"cells": cells2, "shape": pick, "crop": crop_plan}
	fields.append(f)
	return f


func _fancy_crop() -> String:
	var opts: Array = []
	for id in Game.CROPS:
		if id != "melon" and Game.crop_unlocked(id):
			opts.append(id)
	return opts.pick_random() if opts.size() > 0 else "turnip"


func _touches_field(c: Vector2i) -> bool:
	for f in fields:
		for o in f["cells"]:
			if absi(o.x - c.x) + absi(o.y - c.y) <= 1:
				return true
	return false


func _mask_cells(mask: Array) -> Array:
	var out: Array = []
	for y in mask.size():
		var row: String = mask[y]
		for x in row.length():
			if row[x] == "#":
				out.append(Vector2i(x, y))
	return out


## Drops fields with nothing left in them (e.g. after a fire or a card ripped them up).
func prune_fields() -> void:
	for f in fields.duplicate():
		var alive := false
		for c in f["cells"]:
			if is_tilled(c) or _field_ok(c):
				alive = true
				break
		if not alive:
			fields.erase(f)


# ---------------------------------------------------------------- paths & fences
func max_paths() -> int:
	return 10 + Game.level() * 6


## The next tile of footpath worth laying (door -> bin, fields, well, coop...), or null.
## allow_debris: tiles under weeds/tall grass count too (a card clears them first).
func next_path_cell(allow_debris: bool = false) -> Variant:
	if path_count() >= max_paths():
		return null
	var targets: Array = [BIN_FRONT]
	for f in fields:
		var tl: Array = []
		for c in f["cells"]:
			if is_tilled(c):
				tl.append(c)
		if tl.size() >= 2:
			targets.append(nearest(tl, DOOR))
	for t in ["well", "coop", "bench", "compost", "altar"]:
		for c in cells_with_obj([t]):
			targets.append(c)
	for t in targets:
		var route: Variant = _route(DOOR, t)
		if route == null:
			continue
		for c in route:
			if is_planned(c):
				continue
			if is_free_grass(c):
				return c
			if allow_debris and ground[idx(c)] == G_GRASS and is_clearable(c) and not is_solid(c) and not crops.has(c):
				return c
	return null


## 0-1 BFS from a to (next to) b over walkable, untilled cells; existing paths are free to use.
func _route(a: Vector2i, b: Vector2i) -> Variant:
	var dist := {a: 0}
	var prev := {}
	var dq: Array = [a]
	var goal: Variant = null
	while dq.size() > 0:
		var c: Vector2i = dq.pop_front()
		if _adjacent(c, b) or c == b:
			goal = c
			break
		for d in DIRS:
			var n: Vector2i = c + d
			if not in_bounds(n) or not is_walkable(n) or is_tilled(n) or (is_planned(n) and n != b):
				continue
			var w := 0 if is_path(n) else 1
			var nd: int = dist[c] + w
			if dist.has(n) and dist[n] <= nd:
				continue
			dist[n] = nd
			prev[n] = c
			if w == 0:
				dq.push_front(n)
			else:
				dq.push_back(n)
	if goal == null:
		return null
	var out: Array = []
	var cur: Vector2i = goal
	while cur != a:
		out.push_front(cur)
		cur = prev[cur]
	return out


## A tile on the edge of a field that still wants a fence (leaving a gate), or null.
func next_fence_cell() -> Variant:
	if count_obj("fence") >= int(Game.STRUCTS["fence"]["max"]):
		return null
	for f in fields:
		var tl: Array = []
		for c in f["cells"]:
			if is_tilled(c):
				tl.append(c)
		if tl.size() < 4:
			continue
		var ring := {}
		for c in tl:
			for d in DIRS8:
				var n: Vector2i = c + d
				if in_bounds(n) and not (n in f["cells"]) and not is_tilled(n):
					ring[n] = true
		# the gate: the ring tile closest to the house stays open
		var gate: Variant = nearest(ring.keys(), DOOR)
		var cands: Array = []
		for n in ring:
			if n != gate and is_free_grass(n) and not is_planned(n):
				cands.append(n)
		cands.shuffle()
		for n in cands.slice(0, 6):
			if keeps_connected(n):
				return n
	return null


## Where a structure of this type would go (used by the farmer and by card effects).
func pick_build_cell(id: String) -> Variant:
	if id == "fence":
		var fc: Variant = next_fence_cell()
		if fc != null:
			return fc
	var free: Array = free_grass_cells()
	var cands: Array = []
	var tilled: Array = tilled_cells()
	for c in free:
		if is_planned(c):
			continue
		var ok := true
		match id:
			"fence":
				ok = c.x == 0 or c.x == COLS - 1 or c.y == ROWS - 1
			"scarecrow", "beehive", "compost":
				ok = false
				for t in tilled:
					if Vector2(t).distance_to(Vector2(c)) <= 2.0:
						ok = true
						break
			"flowerbed":
				ok = false
				for d in DIRS:
					if is_path(c + d):
						ok = true
						break
			"sign", "bench", "lamp":
				ok = c.distance_to(DOOR) <= 5.0
			_:
				ok = not (c.y <= house.y + 2 and absi(c.x - house.x - 1) <= 2)
		if ok:
			cands.append(c)
	if cands.is_empty() and id in ["flowerbed", "lamp", "bench"]:
		for c in free:
			if not is_planned(c):
				cands.append(c)
	cands.shuffle()
	for c in cands.slice(0, 8):
		if not Game.STRUCTS.get(id, {}).get("solid", true) or keeps_connected(c):
			return c
	return null


## Places a structure for free (card rewards). Returns the cell or null.
func place_struct_auto(id: String) -> Variant:
	var c: Variant = pick_build_cell(id)
	if c == null:
		return null
	place_obj(c, id)
	puff(center(c), Color("c28a5a"), 10, 18.0)
	if id == "coop":
		for i in 2:
			add_animal(Animal.new(self, "chicken", feet(c) + Vector2(randf_range(-10, 10), 10)))
	return c


## Clears n pieces of overgrowth (nearest the house first, -1 = all). Drops materials.
func clear_overgrowth(n: int, near: Vector2i = Vector2i(-1, -1)) -> int:
	var from := DOOR if near.x < 0 else near
	var cells: Array = []
	for c in objs:
		if is_clearable(c):
			cells.append(c)
	cells.sort_custom(func(a, b): return Vector2(a).distance_squared_to(Vector2(from)) < Vector2(b).distance_squared_to(Vector2(from)))
	var done := 0
	for c in cells:
		if n >= 0 and done >= n:
			break
		var t := obj_type(c)
		var drops: Dictionary = CLEARABLE.get(t, {}).get("drops", {"wood": 3} if t in TREES else {})
		for k in drops:
			Game.add_item(k, int(drops[k]))
		remove_obj(c)
		puff(center(c), Color("38b764"), 5, 14.0)
		done += 1
	return done


## Spreads n pieces of overgrowth onto free grass (bad luck, neglect, magic).
func overgrow(n: int, types: Array = ["weed", "tallgrass", "bush", "bramble"]) -> void:
	var cells := free_grass_cells()
	cells.shuffle()
	for i in mini(n, cells.size()):
		if is_planned(cells[i]) and randf() < 0.5:
			continue
		place_obj(cells[i], types.pick_random())
		puff(center(cells[i]), Color("38b764"), 3, 8.0)


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
			if a is Alien and colony:
				colony.on_gone(a)
	_update_fx(d)
	_weed_t += d
	if _weed_t > 25.0:
		_weed_t = 0.0
		# ash washes away on its own
		var ash := cells_with_obj(["ash"])
		if ash.size() > 0 and randf() < 0.5:
			remove_obj(ash.pick_random())
		if randf() < 0.3 and cells_with_obj(DEBRIS).size() < 60:
			var cells := free_grass_cells()
			if cells.size() > 0:
				place_obj(cells.pick_random(), "weed" if randf() < 0.7 else "tallgrass")
	queue_redraw()
	if entity_layer:
		entity_layer.queue_redraw()
	if fx_layer:
		fx_layer.queue_redraw()


func growth_mult(c: Vector2i) -> float:
	var mult := 1.0
	if Game.buff("sun"):
		mult *= 2.0
	if Game.buff("growth"):
		mult *= 1.5
	if Game.has_perk("green_thumb"):
		mult *= 1.3
	if near_obj(c, "beehive", 2.5):
		mult *= 1.3
	if near_obj(c, "compost", 3.0):
		mult *= 1.2
	if near_obj(c, "idol", 3.0):
		mult *= 1.5
	return mult


func _update_ground(d: float) -> void:
	var raining := Game.weather == "rain" or Game.weather == "storm"
	var decay := 1.0 / (70.0 if Game.weather == "heat" else 160.0)
	for y in ROWS:
		for x in COLS:
			var i := y * COLS + x
			if ground[i] != G_TILLED:
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
				cr["growth"] = minf(1.0, cr["growth"] + d / float(Game.CROPS[cr["type"]]["grow"]) * growth_mult(c))
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


## Treasure for the chest, with a little floating label above p (default: the farmer).
func loot(id: String, n: int = 1, p: Vector2 = Vector2(-1, -1)) -> void:
	if n <= 0 or not Game.TREASURES.has(id):
		return
	Game.add_treasure(id, n)
	if p.x < 0.0:
		p = farmer.pos if farmer != null else feet(DOOR)
	var nm: String = String(Game.TREASURES[id]["name"]).to_upper()
	var s: String = ("+" + nm) if n == 1 else "+%d %s" % [n, nm]
	float_text(s, p + Vector2(-Art.text_width(s) / 2.0, -30), Color("e8b04b"))
	puff(p + Vector2(0, -12), Color("ffcd75"), 6, 14.0)


## Trinkets worth n for the chest (scaled by the caller), with a floating label.
func loot_trinkets(n: int, p: Vector2 = Vector2(-1, -1)) -> Dictionary:
	if n <= 0:
		return {}
	var got: Dictionary = Game.gain_trinkets(n)
	if p.x < 0.0:
		p = farmer.pos if farmer != null else feet(DOOR)
	var s := "+%d WORTH" % n
	float_text(s, p + Vector2(-Art.text_width(s) / 2.0, -30), Color("e8b04b"))
	puff(p + Vector2(0, -12), Color("ffcd75"), 10, 20.0)
	return got


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
			match ground[i]:
				G_TILLED:
					draw_texture(Art.tex("tilled_wet" if wet[i] > 0.05 else "tilled"), p)
				G_PATH:
					draw_texture(Art.tex("path%d" % ((x * 7 + y * 3) % 2)), p)
				G_WATER:
					_draw_water(Vector2i(x, y), p)
				_:
					draw_texture(Art.tex("grass%d" % gvar[i]), p)
	_draw_creep()
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


## The alien creep: a violet film with glowing veins that pulse, edged where it meets grass.
func _draw_creep() -> void:
	var pulse := 0.5 + 0.5 * sin(_anim_t * 1.6)
	var glow := 0.25 + 0.4 * Game.darkness()
	for c: Vector2i in alien_land:
		var p := Vector2(c * T)
		draw_rect(Rect2(p, Vector2(T, T)), Color(0.52, 0.2, 0.66, 0.5))
		var h := (c.x * 73 + c.y * 37) % 7
		var vein := Color(0.55, 1.0, 0.7, glow * (0.5 + 0.5 * pulse))
		draw_rect(Rect2(p + Vector2(2 + h, 3), Vector2(1, 6)), vein)
		draw_rect(Rect2(p + Vector2(3 + h, 8), Vector2(5, 1)), vein)
		draw_rect(Rect2(p + Vector2(11 - h / 2, 11), Vector2(3, 1)), vein)
		var edge := Color(0.42, 0.12, 0.45, 0.8)
		if not alien_land.has(c + Vector2i(0, -1)):
			draw_rect(Rect2(p, Vector2(T, 1)), edge)
		if not alien_land.has(c + Vector2i(0, 1)):
			draw_rect(Rect2(p + Vector2(0, T - 1), Vector2(T, 1)), edge)
		if not alien_land.has(c + Vector2i(-1, 0)):
			draw_rect(Rect2(p, Vector2(1, T)), edge)
		if not alien_land.has(c + Vector2i(1, 0)):
			draw_rect(Rect2(p + Vector2(T - 1, 0), Vector2(1, T)), edge)


func _draw_water(c: Vector2i, p: Vector2) -> void:
	draw_rect(Rect2(p, Vector2(T, T)), Color("3b5dc9"))
	draw_rect(Rect2(p + Vector2(1, 1), Vector2(T - 2, T - 2)), Color("41a6f6"))
	# muddy banks where the pond meets grass
	var bank := Color("6a4630")
	if not is_water(c + Vector2i(0, -1)):
		draw_rect(Rect2(p, Vector2(T, 2)), bank)
	if not is_water(c + Vector2i(0, 1)):
		draw_rect(Rect2(p + Vector2(0, T - 2), Vector2(T, 2)), bank)
	if not is_water(c + Vector2i(-1, 0)):
		draw_rect(Rect2(p, Vector2(2, T)), bank)
	if not is_water(c + Vector2i(1, 0)):
		draw_rect(Rect2(p + Vector2(T - 2, 0), Vector2(2, T)), bank)
	var s := _anim_t * 0.8 + c.x * 1.7 + c.y * 2.3
	var rp := p + Vector2(4 + fmod(s * 3.0, 7.0), 5 + int(s) % 6)
	draw_rect(Rect2(rp.floor(), Vector2(3, 1)), Color("73eff7"))
	if (c.x + c.y) % 3 == 0:
		draw_rect(Rect2(p + Vector2(10, 10), Vector2(2, 1)), Color(1, 1, 1, 0.5))


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
	var fl: Array = []
	for f in fields:
		var cells: Array = []
		for c in f["cells"]:
			cells.append("%d,%d" % [c.x, c.y])
		fl.append({"cells": cells, "shape": f["shape"], "crop": f["crop"]})
	var land: Array = []
	for c: Vector2i in alien_land:
		land.append("%d,%d" % [c.x, c.y])
	return {"alien_land": land, "rows": ROWS, "ground": Array(ground), "wet": Array(wet), "crops": cr, "objs": ob, "animals": an,
		"farmer": farmer.to_dict() if farmer else {}, "fields": fl, "biome": biome,
		"house": "%d,%d" % [house.x, house.y], "bin": "%d,%d" % [BIN.x, BIN.y]}


func from_dict(d: Dictionary) -> void:
	var rows_saved := int(d.get("rows", 16))   # v0.2 farms were 16 rows tall
	ground.fill(G_GRASS)
	wet.fill(0.0)
	var g: Array = d.get("ground", [])
	for i in mini(g.size(), COLS * mini(rows_saved, ROWS)):
		ground[i] = int(g[i])
	var w: Array = d.get("wet", [])
	for i in mini(w.size(), COLS * mini(rows_saved, ROWS)):
		wet[i] = float(w[i])
	house = _key_cell(String(d.get("house", "0,0")))
	_set_house(house, false)
	BIN = _key_cell(String(d.get("bin", "%d,%d" % [house.x + 3, house.y + 1])))
	BIN_FRONT = BIN + Vector2i(0, 1)
	biome = String(d.get("biome", "meadow"))
	crops.clear()
	var cr: Dictionary = d.get("crops", {})
	for k in cr:
		var c := _key_cell(k)
		var v: Dictionary = cr[k]
		if in_bounds(c) and Game.CROPS.has(v.get("type", "")):
			crops[c] = {"type": v["type"], "growth": float(v.get("growth", 0)), "health": float(v.get("health", 100)),
				"dead": bool(v.get("dead", false))}
	objs.clear()
	var ob: Dictionary = d.get("objs", {})
	for k in ob:
		var c2 := _key_cell(k)
		if in_bounds(c2):
			objs[c2] = ob[k]
	if not objs.has(BIN):
		objs[BIN] = {"type": "bin", "hp": 999}
	fields.clear()
	for f in d.get("fields", []):
		var cells: Array = []
		for k in f.get("cells", []):
			cells.append(_key_cell(String(k)))
		fields.append({"cells": cells, "shape": String(f.get("shape", "patch")), "crop": String(f.get("crop", "any"))})
	if rows_saved < ROWS:
		_grow_old_farm(rows_saved)
	alien_land.clear()
	for k in d.get("alien_land", []):
		var c3 := _key_cell(String(k))
		if in_bounds(c3):
			alien_land[c3] = true
	animals.clear()
	farmer = Farmer.new(self)
	farmer.pos = feet(DOOR)
	farmer.from_dict(d.get("farmer", {}))
	for ad in d.get("animals", []):
		var kind := String(ad.get("kind", "chicken"))
		var ap := Vector2(float(ad.get("x", 80)), float(ad.get("y", 80)))
		var a: Animal = Alien.new(self, String(ad.get("caste", "worker")), ap) if kind == "alien" else Animal.new(self, kind, ap)
		a.from_dict(ad)
		animals.append(a)


## Old saves were shorter: the new rows at the bottom start out wild.
func _grow_old_farm(from_row: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var b: Dictionary = BIOMES[biome] if BIOMES.has(biome) else BIOMES["meadow"]
	for y in range(from_row, ROWS):
		for x in COLS:
			if rng.randf() < 0.8:
				place_obj(Vector2i(x, y), _weighted(rng, b["cover"] if rng.randf() < 0.6 else b["wood"]))


func _key_cell(k: String) -> Vector2i:
	var parts := k.split(",")
	if parts.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))
