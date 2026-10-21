extends Animal
class_name Insect
## One member of the Brood, the mutant insects (swarm.gd runs the faction). kind is "insect";
## `caste` says what it is and does:
##   egg      laid in a mound; hatches into a grub
##   grub     wriggles in the tunnels, nibbles roots; pupates into a cocoon
##   pupa     a cocoon; the brood decides what comes out (whatever it is short of)
##   worker   a giant ant: digs tunnels, grows mounds, builds wax walls, forages and hauls food
##   soldier  a mantis: guards the tunnels, eats critters, fights the aliens in a war, stings
##            the farmer when the brood hates him, tears down alien buildings on the front
##   locust   grazes near home; in a swarm it flies across the farm stripping everything bare
##   spinner  spins webs that wall off cells and trap critters
##   glowfly  at night pollinates the farmer's crops and the aliens' glow moss (if friendly)
##   queen    lays the eggs; young queens fly off to found new mounds
##   migrant  a locust passing through on the wind (arrival)
## `glow` = raised near the alien creep: tougher, longer-lived, cyan.
## Insects crawl and fly in straight lines (no pathfinding).

const ADULTS := ["worker", "soldier", "locust", "spinner", "glowfly", "queen"]
const FLYERS := ["locust", "glowfly", "migrant"]
const BASE := {"grub": "i_grub", "worker": "i_ant", "soldier": "i_soldier", "locust": "i_locust",
	"spinner": "i_spinner", "glowfly": "i_glowfly", "queen": "i_queen", "migrant": "i_locust"}

var caste := "egg"
var age := 0.0
var lifespan := 1400.0
var grow_at := 60.0
var glow := false
var hive := Vector2i(-1, -1)   # its mound
var cargo := 0.0
var queen_name := ""
var death_cause := ""
var waypoints: Array = []      # swarm / flight route (Vector2)
var sting_t := 0.0
var think_t := 0.0
var swarm                      # Swarm node


func _init(w, c: String = "egg", p: Vector2 = Vector2.ZERO) -> void:
	super(w, "insect", p)
	swarm = w.swarm
	set_caste(c)


func set_caste(c: String) -> void:
	caste = c
	state = "idle"
	job = null
	target = null
	timer = randf_range(0.3, 1.5)
	lifespan = randf_range(900.0, 1700.0) * (1.4 if glow else 1.0)
	match c:
		"egg":
			speed = 0.0
			grow_at = age + randf_range(50.0, 90.0)
		"grub":
			speed = 6.0
			grow_at = age + randf_range(120.0, 200.0)
		"pupa":
			speed = 0.0
			grow_at = age + randf_range(60.0, 100.0)
		"worker":
			speed = 22.0
		"soldier":
			speed = 26.0
		"locust":
			speed = 30.0
		"spinner":
			speed = 16.0
		"glowfly":
			speed = 18.0
		"queen":
			speed = 14.0
			lifespan *= 2.5
		"migrant":
			speed = 40.0
			state = "swarm"


func is_adult() -> bool:
	return caste in ADULTS


func flying() -> bool:
	return caste in FLYERS or state == "flight"


func is_threat() -> bool:
	if dead:
		return false
	return state in ["raid", "haul_crop", "sting"] or (state == "swarm" and caste in ["locust", "migrant"])


func leaving() -> bool:
	return state in ["leave", "flee"]


func persistent() -> bool:
	return caste != "migrant" and not dead and state != "carried"


func scare() -> void:
	if dead or leaving():
		return
	if state == "swarm" or caste in ["egg", "pupa", "queen"]:
		return   # a swarm doesn't care about one farmer waving a hat
	if state in ["raid", "haul_crop", "sting"] and swarm:
		swarm.on_scared(self)
	cargo = 0.0
	state = "flee"
	timer = 4.0


func die(cause: String) -> void:
	if dead:
		return
	death_cause = cause
	dead = true


# ---------------------------------------------------------------- update
func update(d: float) -> void:
	anim_t += d
	bubble_t -= d
	sting_t -= d
	if state == "carried":
		if death_cause == "":
			death_cause = "a fox"
		return
	if caste != "migrant":
		age += d
		if _grow():
			return
	match state:
		"leave":
			_update_leave(d)
			return
		"flee":
			timer -= d
			if _move(_home_pos(), d, speed * 1.4) or timer <= 0.0:
				state = "idle"
			return
		"swarm", "flight":
			_follow_route(d)
			return
	match caste:
		"grub": _update_grub(d)
		"worker": _update_worker(d)
		"soldier": _update_soldier(d)
		"locust": _wander(d, 30.0)
		"spinner": _update_spinner(d)
		"glowfly": _update_glowfly(d)
		"queen": _wander(d, 6.0)
	pos.x = clampf(pos.x, -40.0, world.COLS * 16 + 40.0)
	pos.y = clampf(pos.y, -60.0, world.ROWS * 16 + 20.0)


func _grow() -> bool:
	if is_adult() and age >= lifespan:
		die("old age")
		return true
	match caste:
		"egg":
			if age >= grow_at:
				set_caste("grub")
		"grub":
			if age >= grow_at:
				set_caste("pupa")
		"pupa":
			if age >= grow_at and swarm:
				swarm.emerge(self)
	return false


func _home_pos() -> Vector2:
	if world.in_bounds(hive) and world.obj_type(hive) == "i_mound":
		return world.feet(hive) + Vector2(randf_range(-6, 6), 3)
	return swarm.home_pos(pos) if swarm else home


func _wander(d: float, radius: float) -> void:
	timer -= d
	if timer <= 0.0 or target == null or not (target is Vector2):
		timer = randf_range(1.5, 4.0)
		var c: Variant = swarm.random_land_cell() if swarm and randf() < 0.6 else null
		target = world.feet(c) + Vector2(randf_range(-5, 5), randf_range(-3, 1)) if c != null else \
			_home_pos() + Vector2(randf_range(-radius, radius), randf_range(-radius * 0.5, radius * 0.5))
		target.x = clampf(target.x, 6, world.COLS * 16 - 6)
		target.y = clampf(target.y, 24, world.ROWS * 16 - 3)
	_move(target, d, speed * 0.55)


## Swarms and nuptial flights follow a list of waypoints; the swarm node eats the land below.
func _follow_route(d: float) -> void:
	if waypoints.is_empty():
		if state == "flight" and swarm:
			swarm.flight_landed(self)
		elif caste == "migrant":
			# the last of a passing cloud may stay behind if nobody has settled yet
			if swarm and not swarm.active() and swarm.queens().is_empty() and randf() < 0.6:
				swarm.migrant_settles(self)
				return
			_leave_map()
		else:
			state = "idle"
		return
	var p: Vector2 = waypoints[0]
	var before: Vector2i = world.cell_of(pos)
	if _move(p + Vector2(sin(anim_t * 3.0 + hive.x) * 6.0, cos(anim_t * 2.0) * 4.0), d):
		waypoints.pop_front()
	var now: Vector2i = world.cell_of(pos)
	if now != before and state == "swarm" and swarm and pos.x > 0 and pos.x < world.COLS * 16:
		swarm.strip(now, self)


func _leave_map() -> void:
	state = "leave"
	exit_pos = Vector2(-30 if pos.x < world.COLS * 8 else world.COLS * 16 + 30, pos.y)


func _update_grub(d: float) -> void:
	timer -= d
	if timer <= 0.0 or target == null:
		timer = randf_range(2.0, 5.0)
		target = _home_pos() + Vector2(randf_range(-16, 16), randf_range(-4, 10))
	_move(target, d, speed * (0.3 + 0.7 * absf(sin(anim_t * 4.0))))


## Workers take jobs from the brood: dig, build, forage.
func _update_worker(d: float) -> void:
	if state == "haul":
		if _move(_home_pos(), d):
			if swarm:
				swarm.add_food(cargo)
			cargo = 0.0
			state = "idle"
		return
	if job == null:
		timer -= d
		if timer <= 0.0:
			timer = randf_range(0.8, 2.0)
			job = swarm.worker_job(self) if swarm else null
		if job == null:
			_wander(d, 20.0)
		return
	if not swarm.job_valid(job):
		job = null
		state = "idle"
		return
	var c: Vector2i = job["cell"]
	state = "raid" if job["kind"] == "raid" else "work"
	if _move(world.feet(c) + Vector2(4 if c.x < world.COLS - 1 else -4, 0), d):
		if job["kind"] == "build":
			swarm.build_progress(d)
			if randf() < d * 2.0:
				world.puff(world.feet(c) + Vector2(randf_range(-4, 4), -2), Color("8b5a3c"), 1, 6.0)
			return
		job["t"] = float(job["t"]) - d
		if float(job["t"]) <= 0.0:
			cargo = swarm.finish_job(self, job)
			job = null
			state = "haul" if cargo > 0.0 else "idle"


func _update_soldier(d: float) -> void:
	# enemies: critters on the tunnels, aliens in a war, the farmer when the brood hates him
	think_t -= d
	if think_t <= 0.0:
		think_t = randf_range(0.4, 0.7)
		job = swarm.soldier_target(self) if swarm else null
	var foe: Variant = job
	if foe is Object and (not is_instance_valid(foe) or (foe is Animal and foe.dead)):
		job = null
		foe = null
	elif foe is Vector2i and not world.objs.has(foe):
		job = null
		foe = null
	if foe != null:
		state = "hunt"
		var fp: Vector2 = foe.pos if foe is Object else world.feet(foe)
		if _move(fp + Vector2(-6 if fp.x > pos.x else 6, 0), d, speed * 1.2) and sting_t <= 0.0:
			sting_t = 1.6
			swarm.strike(self, foe)
		return
	state = "patrol"
	_wander(d, 30.0)


func _update_spinner(d: float) -> void:
	if job == null:
		timer -= d
		if timer <= 0.0:
			timer = randf_range(6.0, 14.0)
			job = swarm.web_spot(self) if swarm else null
		if job == null:
			_wander(d, 20.0)
		return
	var c: Vector2i = job
	if _move(world.feet(c) + Vector2(0, -2), d):
		state = "work"
		timer -= d
		if timer <= -3.0:
			swarm.spin(c)
			job = null
			state = "idle"
			timer = randf_range(20.0, 40.0)


func _update_glowfly(d: float) -> void:
	if not Game.is_night():
		_wander(d, 10.0)
		return
	timer -= d
	if timer <= 0.0 or target == null or not (target is Vector2):
		timer = randf_range(2.0, 4.0)
		var c: Variant = swarm.pollinate_target(self) if swarm else null
		target = (world.center(c) + Vector2(randf_range(-4, 4), -6)) if c != null else _home_pos() + Vector2(randf_range(-30, 30), -10)
	if _move(target, d, speed * 0.6) and swarm:
		swarm.pollinate(world.cell_of(target), d)


# ---------------------------------------------------------------- drawing
func _frame() -> String:
	match caste:
		"egg": return "i_egg"
		"pupa": return "i_pupa"
	var two := int(anim_t * (9.0 if flying() else 5.0)) % 2 == 0
	if state == "work" and caste == "worker":
		two = int(anim_t * 8.0) % 2 == 0
	var n: String = BASE.get(caste, "i_ant") + ("1" if two else "2")
	return n + "_glow" if glow else n


func draw(ci: CanvasItem) -> void:
	if hidden or dead:
		return
	var tx := Art.tex(_frame())
	var w := tx.get_width()
	var h := tx.get_height()
	var lift := 0.0
	if flying():
		lift = 8.0 + sin(anim_t * 5.0 + hive.y) * 2.0
		if state == "swarm" or state == "flight":
			lift += 6.0
	ci.draw_rect(Rect2(pos.x - w * 0.3, pos.y, w * 0.6, 1), Color(0, 0, 0, 0.18))
	if caste == "glowfly" and Game.darkness() > 0.2:
		ci.draw_circle(pos + Vector2(2, -lift - 2), 4.0, Color(1.0, 0.9, 0.4, 0.25 * Game.darkness()))
	ci.draw_set_transform(pos + Vector2(0, -lift), 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture(tx, Vector2(-w / 2.0, -h), tint)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if cargo > 0.0:
		ci.draw_rect(Rect2(pos + Vector2(-1, -h - 3 - lift), Vector2(3, 2)), Color("a7f070"))


# ---------------------------------------------------------------- save
func to_dict() -> Dictionary:
	var d := super()
	d["caste"] = caste
	d["age"] = age
	d["life"] = lifespan
	d["grow"] = grow_at
	d["glow"] = glow
	d["hive"] = "%d,%d" % [hive.x, hive.y]
	d["qname"] = queen_name
	return d


func from_dict(d: Dictionary) -> void:
	super(d)
	age = float(d.get("age", 0.0))
	lifespan = float(d.get("life", lifespan))
	grow_at = float(d.get("grow", grow_at))
	glow = bool(d.get("glow", false))
	queen_name = String(d.get("qname", ""))
	var parts := String(d.get("hive", "-1,-1")).split(",")
	if parts.size() == 2:
		hive = Vector2i(int(parts[0]), int(parts[1]))
