extends Animal
class_name Alien
## One member of the alien colony (colony.gd runs the faction as a whole). kind is always
## "alien"; `caste` says what it is and does:
##   egg      sits where it was laid (or fell); hatches into a spawnling
##   spawn    a spawnling: bounces after the grown-ups, matures into an adult caste
##   worker   builds the village, tends the glow moss, clears overgrowth on the creep
##   scout    roams the farm; raids the farmer's crops when the colony is hungry or hostile
##   warden   guards the creep: hunts critters, zaps the farmer when relations are bad
##   envoy    carries the colony's outreach to the farmer (gifts, trades, demands)
##   elder    old adults lay the eggs; the oldest is the matriarch (crowned sprite)
## Arrivals: ship (the saucer: drops colonists or abducts), stranger (walks in, founds a
## village), lurker (sneaks in at night and mutates an animal), mutant (a chicken it got to).
## Aliens hover, so they fly in straight lines (no pathfinding). Ageing happens here; the
## colony decides castes, food, eggs, buildings and outreach.

const ADULTS := ["worker", "scout", "warden", "envoy", "elder"]
const TRANSIENT := ["ship", "lurker"]
const LINES := {
	"worker": ["*bzzt*", "Glorp.", "Build. Build.", "*happy humming*"],
	"scout": ["*scans*", "Interesting...", "Specimen!", "*beep boop*"],
	"warden": ["HALT.", "*whirr*", "Perimeter: secure."],
	"envoy": ["Greetings, Farmer.", "We come in peas.", "Your turnips: fascinating."],
	"elder": ["The hive remembers.", "Mmmmh.", "So many stars..."],
	"spawn": ["*squee*", "*blip*", "!!"],
}

var caste := "spawn"
var age := 0.0          # seconds lived
var lifespan := 2400.0
var grow_at := 60.0     # egg: hatch age · spawn: maturity age · mutant: transformation age
var alien_name := ""
var cargo := 0.0        # food a scout is carrying home
var mission := ""       # ship: "drop"/"abduct"/"exodus"/"mothership" · envoy: what it came to do
var cargo_list: Array = []   # ship: castes to drop
var death_cause := ""   # set when it dies here (old age, a fox...) for the colony's log
var spotted := false    # lurker: seen by the dog or the farmer's third eye
var zap_t := 0.0
var colony              # Colony node


func _init(w, c: String = "spawn", p: Vector2 = Vector2.ZERO) -> void:
	super(w, "alien", p)
	colony = w.colony
	set_caste(c)
	lifespan = randf_range(1900.0, 3400.0)
	alien_name = colony.make_name() if colony else "Zib"


## Switches caste and the per-caste settings.
func set_caste(c: String) -> void:
	caste = c
	state = "idle"
	job = null
	target = null
	timer = randf_range(0.5, 2.0)
	match c:
		"egg":
			speed = 0.0
			grow_at = age + randf_range(110.0, 200.0)
		"spawn":
			speed = 22.0
			grow_at = age + randf_range(240.0, 380.0)
		"worker":
			speed = 20.0
		"scout":
			speed = 34.0
		"warden":
			speed = 26.0
		"envoy":
			speed = 24.0
		"elder":
			speed = 12.0
		"ship":
			speed = 46.0
			state = "descend"
		"stranger":
			speed = 18.0
			state = "enter"
		"lurker":
			speed = 14.0
			state = "enter"
			life = 200.0
		"mutant":
			speed = 12.0
			grow_at = age + randf_range(90.0, 150.0)


func is_adult() -> bool:
	return caste in ADULTS


func is_threat() -> bool:
	if dead:
		return false
	return state == "raid" or state == "haul" or (caste == "lurker" and spotted)


func leaving() -> bool:
	return state in ["leave", "flee", "ascend"]


func persistent() -> bool:
	return not caste in TRANSIENT and not dead and state != "carried"


func scare() -> void:
	if dead or leaving():
		return
	match caste:
		"lurker":
			say("*HISS*", 1.5)
			world.puff(pos + Vector2(0, -4), Color("5d275d"), 8)
			_leave()
		"ship", "egg":
			return
		_:
			if state in ["raid", "haul"]:
				cargo = 0.0
				say(["*eep!*", "Retreat!", "*bzzt!*"].pick_random(), 1.5)
				if colony:
					colony.on_scared(self)
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
	zap_t -= d
	if state == "carried":
		if death_cause == "":
			death_cause = "a fox"
		return
	if not caste in TRANSIENT and caste != "stranger":
		age += d
		if _grow():
			return
	if state == "leave":
		_update_leave(d)
		return
	if state == "flee":
		timer -= d
		if _move(_home_pos(), d, speed * 1.5) or timer <= 0.0:
			state = "idle"
		return
	match caste:
		"egg": pass
		"spawn": _update_spawn(d)
		"worker": _update_worker(d)
		"scout": _update_scout(d)
		"warden": _update_warden(d)
		"envoy": _update_envoy(d)
		"elder": _update_elder(d)
		"ship": _update_ship(d)
		"stranger": _update_stranger(d)
		"lurker": _update_lurker(d)
		"mutant": _update_mutant(d)
	pos.x = clampf(pos.x, -40.0, world.COLS * 16 + 40.0)
	pos.y = clampf(pos.y, -60.0, world.ROWS * 16 + 20.0)


## Life stages. Returns true if it died.
func _grow() -> bool:
	if age >= lifespan and caste != "egg":
		die("old age")
		return true
	match caste:
		"egg":
			if age >= grow_at:
				world.puff(pos + Vector2(0, -4), Color("a7f070"), 10, 16.0)
				set_caste("spawn")
				say("*squee!*", 2.0)
				if colony:
					colony.on_hatch(self)
		"spawn":
			if age >= grow_at and colony:
				colony.mature(self)
		"mutant":
			if age >= grow_at and colony:
				colony.mutant_transform(self)
		_:
			if is_adult() and caste != "elder" and age > lifespan * 0.8 and colony:
				colony.on_elder(self)
	return false


func _home_pos() -> Vector2:
	if colony and colony.has_village():
		return colony.center_pos() + Vector2(randf_range(-6, 6), 6)
	return home


func _chatter(chance: float = 0.004) -> void:
	if bubble_t <= 0.0 and randf() < chance and LINES.has(caste):
		say(LINES[caste].pick_random(), 2.0)


## Drifts between cells of the creep (or around home when there is none).
func _wander(d: float, radius: float = 40.0) -> void:
	timer -= d
	if timer <= 0.0 or target == null or not (target is Vector2):
		timer = randf_range(2.0, 5.0)
		var c: Variant = colony.random_land_cell() if colony else null
		if c != null and randf() < 0.8:
			target = world.feet(c) + Vector2(randf_range(-4, 4), randf_range(-3, 1))
		else:
			target = _home_pos() + Vector2(randf_range(-radius, radius), randf_range(-radius * 0.5, radius * 0.5))
		target.x = clampf(target.x, 6, world.COLS * 16 - 6)
		target.y = clampf(target.y, 24, world.ROWS * 16 - 3)
	_move(target, d, speed * 0.6)


func _update_spawn(d: float) -> void:
	_chatter(0.003)
	timer -= d
	if timer <= 0.0 or target == null:
		timer = randf_range(1.0, 3.0)
		var near: Vector2 = _home_pos()
		for a in world.animals:
			if a is Alien and a.is_adult() and not a.dead and a.pos.distance_to(pos) < 60.0 and randf() < 0.5:
				near = a.pos
				break
		target = near + Vector2(randf_range(-14, 14), randf_range(-6, 8))
		target.x = clampf(target.x, 6, world.COLS * 16 - 6)
		target.y = clampf(target.y, 24, world.ROWS * 16 - 3)
	_move(target, d, speed * (0.4 + 0.6 * absf(sin(anim_t * 7.0))))


## Workers (and anyone, while the colony has no workers) take jobs from the colony.
func _update_worker(d: float) -> void:
	_chatter()
	if job == null:
		timer -= d
		if timer <= 0.0:
			timer = randf_range(1.0, 2.5)
			job = colony.worker_job(self) if colony else null
		if job == null:
			_wander(d)
		return
	var c: Vector2i = job["cell"]
	if not colony.job_valid(job):
		job = null
		return
	if _move(world.feet(c) + Vector2(5 if c.x < world.COLS - 1 else -5, 1), d):
		state = "work"
		flip = c.x * 16 + 8 < pos.x
		if job["kind"] == "build":
			colony.build_progress(d)
			if randf() < d * 2.0:
				world.puff(world.center(c) + Vector2(randf_range(-5, 5), 2), Color("a7f070"), 1, 8.0)
			return
		job["t"] = float(job["t"]) - d
		if float(job["t"]) <= 0.0:
			colony.finish_job(self, job)
			job = null
			state = "idle"
	else:
		state = "go"


func _update_scout(d: float) -> void:
	_chatter(0.003)
	match state:
		"raid":
			if target == null or not (target is Vector2i) or not world.crops.has(target):
				target = null
				state = "idle"
				return
			if _move(world.feet(target) + Vector2(0, 1), d):
				timer -= d
				if timer <= 0.0:
					cargo = colony.on_raid(self, target) if colony else 0.0
					state = "haul"
					target = null
		"haul":
			if _move(_home_pos(), d, speed * 0.8):
				if colony:
					colony.add_food(cargo, "raid")
				cargo = 0.0
				state = "idle"
		_:
			timer -= d
			if timer <= 0.0 and colony and colony.wants_raid():
				var c: Variant = colony.raid_target()
				if c != null:
					target = c
					state = "raid"
					timer = 2.5
					return
			# roams the whole farm, not just the creep
			if target == null or not (target is Vector2) or timer <= 0.0:
				timer = randf_range(3.0, 7.0)
				target = Vector2(randf_range(8, world.COLS * 16 - 8), randf_range(30, world.ROWS * 16 - 4))
				if Game.is_night() or randf() < 0.4:
					target = _home_pos() + Vector2(randf_range(-30, 30), randf_range(-16, 16))
			_move(target, d, speed * 0.5)


func _update_warden(d: float) -> void:
	_chatter(0.002)
	# hunt critters that come near the creep
	var prey: Variant = null
	var bd := 70.0
	for a in world.threats():
		if a is Alien:
			continue
		var dd: float = a.pos.distance_to(pos)
		if dd < bd and (colony == null or colony.near_land(a.pos, 2)):
			bd = dd
			prey = a
	if prey != null:
		state = "hunt"
		if _move(prey.pos, d, speed * 1.2) or bd < 9.0:
			world.puff(prey.pos + Vector2(0, -4), Color("73eff7"), 6, 14.0)
			say("*ZAP*", 1.0)
			if prey.kind in ["rabbit", "crow", "snake", "wasps"] and randf() < 0.6:
				prey.dead = true
				if colony:
					colony.add_food(3.0, "hunt")
			else:
				prey.scare()
			Game.bump("shooed")
		return
	# when relations are bad, the farmer is not welcome on the creep
	var f = world.farmer
	if colony and colony.hostile() and f != null and f.visible_outside() and colony.on_land(f.pos):
		state = "guard"
		if _move(f.pos + Vector2(8 if pos.x > f.pos.x else -8, 0), d) and zap_t <= 0.0:
			zap_t = 6.0
			say("TRESPASSER.", 1.5)
			world.puff(f.pos + Vector2(0, -8), Color("73eff7"), 8, 18.0)
			f.hurt(5, "an alien warden's zap")
		return
	state = "patrol"
	_wander(d, 50.0)


func _update_envoy(d: float) -> void:
	_chatter(0.002)
	var f = world.farmer
	match state:
		"visit":
			var goal: Vector2 = f.pos + Vector2(14, 2) if f != null and f.visible_outside() else world.feet(world.DOOR) + Vector2(12, 14)
			goal.x = clampf(goal.x, 8, world.COLS * 16 - 8)
			if _move(goal, d):
				state = "talk"
				timer = 5.0
				flip = true
				if colony:
					colony.envoy_arrived(self)
		"talk":
			timer -= d
			if timer <= 0.0:
				state = "idle"
				mission = ""
		_:
			_wander(d, 24.0)


func _update_elder(d: float) -> void:
	_chatter(0.002)
	if colony and colony.queen() == self and randf() < d * 0.05:
		world.puff(pos + Vector2(0, -16), Color("ffcd75"), 2, 6.0)
	# the matriarch holds court; the other elders still potter about with the chores
	if colony and (colony.needs_builders() or colony.queen() != self):
		_update_worker(d)
		return
	_wander(d, 18.0)


## The saucer. Descends to its hover spot, then drops colonists / beams something up.
func _update_ship(d: float) -> void:
	match state:
		"descend":
			if _move(home, d):
				state = "beam"
				timer = 2.5
		"beam":
			timer -= d
			if timer <= 0.0:
				if colony:
					colony.ship_arrived(self)
				state = "ascend"
				exit_pos = Vector2(pos.x + randf_range(-40, 40), -70)
		"ascend":
			if _move(exit_pos, d, speed * 1.5):
				dead = true


## The strange visitor: walks up to the farmer, says something odd, then settles somewhere.
func _update_stranger(d: float) -> void:
	var f = world.farmer
	match state:
		"enter":
			var goal: Vector2 = f.pos + Vector2(-16, 2) if f != null and f.visible_outside() else world.feet(world.DOOR) + Vector2(-12, 16)
			goal.x = maxf(goal.x, 8.0)
			if _move(goal, d):
				state = "talk"
				timer = 5.0
				say(["Nice... planet you have.", "I am a normal human man.", "Lovely weather. For Earth.",
					"Mind if I stay a while?"].pick_random(), 4.0)
				if f != null and f.visible_outside():
					f.say(["Er. Welcome?", "Odd fellow.", "Your hands are green."].pick_random(), 3.0)
		"talk":
			flip = false
			timer -= d
			if timer <= 0.0:
				state = "settle"
				target = colony.village_spot() if colony else null
				if target == null:
					_leave()
		"settle":
			if not (target is Vector2i):
				_leave()
				return
			if _move(world.feet(target) + Vector2(0, 2), d):
				if colony:
					colony.stranger_settles(self, target)


## The night lurker: creeps towards an animal (or a crop) and changes it.
func _update_lurker(d: float) -> void:
	life -= d
	spotted = Game.has_mutation("third_eye") or _dog_near(40.0)
	if not Game.is_night() or life <= 0.0:
		_leave()
		return
	if target == null or (target is Animal and (target.dead or target.hidden and target.kind != "chicken")):
		target = colony.lurker_target() if colony else null
		if target == null:
			_leave()
			return
	var goal: Vector2 = target.pos if target is Animal else world.feet(target)
	if _move(goal, d, speed * (0.4 + 0.6 * absf(sin(anim_t * 2.0)))):
		if colony:
			colony.lurker_strikes(self, target)
		_leave()


## A chicken the lurker got to: pecks around strangely, then becomes something else.
func _update_mutant(d: float) -> void:
	if randf() < d * 0.05:
		say(["*bwak-zzt*", "*glorp*", "*bawk?*"].pick_random(), 1.5)
	timer -= d
	if timer <= 0.0 or target == null or not (target is Vector2):
		timer = randf_range(2.0, 5.0)
		target = home + Vector2(randf_range(-20, 20), randf_range(-8, 14))
		target.x = clampf(target.x, 4, world.COLS * 16 - 4)
		target.y = clampf(target.y, 30, world.ROWS * 16 - 4)
	_move(target, d)


func _leave() -> void:
	if caste == "ship":
		state = "ascend"
		exit_pos = Vector2(pos.x, -70)
		return
	state = "leave"
	speed = maxf(speed, 20.0) * 1.6
	exit_pos = Vector2(-24 if pos.x < world.COLS * 8 else world.COLS * 16 + 24, pos.y)


# ---------------------------------------------------------------- drawing
func _frame() -> String:
	var two := int(anim_t * 5.0) % 2 == 0
	match caste:
		"egg":
			return "a_egg_hatching" if age > grow_at - 25.0 and int(anim_t * 6.0) % 2 == 0 else "a_egg"
		"spawn": return "a_spawn1" if two else "a_spawn2"
		"worker": return "a_worker1" if two or state == "work" else "a_worker2"
		"scout": return "a_scout1" if two else "a_scout2"
		"warden": return "a_warden1" if two else "a_warden2"
		"envoy": return "a_envoy1" if two else "a_envoy2"
		"elder":
			if colony and colony.queen() == self:
				return "a_queen1"
			return "a_elder1" if two else "a_elder2"
		"stranger": return "a_stranger1" if two or state == "talk" else "a_stranger2"
		"lurker": return "a_lurker1" if int(anim_t * 3.0) % 2 == 0 else "a_lurker2"
		"mutant": return "a_mutant1" if int(anim_t * 3.0) % 2 == 0 else "a_mutant2"
	return "a_spawn1"


func draw(ci: CanvasItem) -> void:
	if hidden or dead:
		return
	if caste == "ship":
		_draw_ship(ci)
		return
	var tx := Art.tex(_frame())
	var w := tx.get_width()
	var h := tx.get_height()
	var hover := 0.0
	if is_adult() or caste == "spawn":
		hover = 1.0 + sin(anim_t * 3.0 + alien_name.length()) * 1.0
	var mod := tint
	if caste == "lurker":
		mod = Color(1, 1, 1, 0.85 if spotted else 0.35)
	if caste == "elder":
		mod = Color(0.92, 0.9, 1.0)
	ci.draw_rect(Rect2(pos.x - w * 0.3, pos.y, w * 0.6, 1), Color(0, 0, 0, 0.2 if caste != "lurker" else 0.08))
	ci.draw_set_transform(pos + Vector2(0, -hover), 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture(tx, Vector2(-w / 2.0, -h), mod)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if state == "haul" and cargo > 0.0:
		ci.draw_rect(Rect2(pos + Vector2(-2, -h - 4 - hover), Vector2(4, 3)), Color("ffcd75"))
	if caste in ["worker", "elder", "warden"] and Game.darkness() > 0.4:
		ci.draw_rect(Rect2(pos + Vector2(-1, -h + 2 - hover), Vector2(2, 1)), Color(0.45, 1.0, 0.6, 0.6))


func _draw_ship(ci: CanvasItem) -> void:
	var tx := Art.tex("saucer")
	var bob := sin(anim_t * 2.0) * 1.5
	var p := pos + Vector2(-tx.get_width() / 2.0, -tx.get_height() - 14 + bob)
	if state == "beam":
		var a := 0.25 + 0.15 * sin(anim_t * 12.0)
		ci.draw_rect(Rect2(pos.x - 7, p.y + tx.get_height() - 2, 14, pos.y - (p.y + tx.get_height() - 2) + 2), Color(0.45, 1.0, 0.95, a))
		ci.draw_rect(Rect2(pos.x - 4, p.y + tx.get_height() - 2, 8, pos.y - (p.y + tx.get_height() - 2) + 2), Color(1, 1, 1, a * 0.6))
	ci.draw_texture(tx, p.floor())
	var blink := int(anim_t * 4.0) % 3
	ci.draw_rect(Rect2(p + Vector2(4 + blink * 7, 8), Vector2(1, 1)), Color("ffcd75"))


# ---------------------------------------------------------------- save
func to_dict() -> Dictionary:
	var d := super()
	d["caste"] = caste
	d["age"] = age
	d["life"] = lifespan
	d["grow"] = grow_at
	d["name"] = alien_name
	return d


func from_dict(d: Dictionary) -> void:
	super(d)
	age = float(d.get("age", 0.0))
	lifespan = float(d.get("life", lifespan))
	grow_at = float(d.get("grow", grow_at))
	alien_name = String(d.get("name", alien_name))
