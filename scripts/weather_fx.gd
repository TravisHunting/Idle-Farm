extends Node2D
## Weather overlay over the farm: rain, storm gloom, lightning bolts/flashes, heat shimmer,
## drifting cloud shadows and the meteor streak.

const W := 192
const H := 352

var drops: Array = []
var clouds: Array = []
var flash := 0.0
var bolt: PackedVector2Array = PackedVector2Array()
var bolt_t := 0.0
var meteor_from := Vector2.ZERO
var meteor_to := Vector2.ZERO
var meteor_t := -1.0
var beam_p := Vector2.ZERO
var beam_t := 0.0
var t := 0.0


func _ready() -> void:
	for i in 120:
		drops.append(Vector2(randf() * W, randf() * H))
	for i in 3:
		clouds.append(Vector2(randf() * W, randf() * H))


func strike(p: Vector2) -> void:
	flash = 1.0
	bolt_t = 0.25
	bolt = PackedVector2Array()
	var y := -4.0
	var x := p.x + randf_range(-20, 20)
	while y < p.y:
		bolt.append(Vector2(x, y))
		y += randf_range(8, 18)
		x = lerpf(x, p.x, 0.35) + randf_range(-6, 6)
	bolt.append(p)


func beam(p: Vector2) -> void:
	beam_p = p
	beam_t = 1.5


func meteor(p: Vector2) -> void:
	meteor_to = p
	meteor_from = p + Vector2(-90, -160)
	meteor_t = 0.0


func _process(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta * 3.0)
	bolt_t -= delta
	beam_t -= delta
	if meteor_t >= 0.0:
		meteor_t += delta / 0.6
		if meteor_t > 1.0:
			meteor_t = -1.0
			flash = 0.6
	var w := Game.weather
	var n := 0
	if w == "rain":
		n = 60
	elif w == "storm":
		n = 120
	for i in n:
		var d: Vector2 = drops[i]
		d += Vector2(-30, 160) * delta * (1.3 if w == "storm" else 1.0)
		if d.y > H:
			d = Vector2(randf() * (W + 40), -4)
		if d.x < -4:
			d.x += W + 8
		drops[i] = d
	for i in clouds.size():
		var c: Vector2 = clouds[i]
		c.x += delta * 4.0
		if c.x > W + 50:
			c = Vector2(-50, randf() * H)
		clouds[i] = c
	queue_redraw()


func _draw() -> void:
	var w := Game.weather
	if w in ["cloudy", "rain", "storm"]:
		for c in clouds:
			draw_circle(c, 40.0, Color(0, 0, 0.1, 0.07))
			draw_circle(c + Vector2(26, 6), 28.0, Color(0, 0, 0.1, 0.06))
	if w == "storm":
		draw_rect(Rect2(0, 0, W, H), Color(0.05, 0.05, 0.15, 0.22))
	elif w == "rain":
		draw_rect(Rect2(0, 0, W, H), Color(0.1, 0.15, 0.3, 0.1))
	elif w == "heat":
		draw_rect(Rect2(0, 0, W, H), Color(1.0, 0.6, 0.2, 0.08))
		for i in 6:
			var y := fmod(i * 47.0 + t * 6.0, H)
			for x in range(0, W, 3):
				if int(x / 3.0 + t * 4.0 + i) % 5 == 0:
					draw_rect(Rect2(x, y + sin(x * 0.2 + t * 3.0), 2, 1), Color(1, 1, 0.9, 0.12))
	var n := 60 if w == "rain" else (120 if w == "storm" else 0)
	for i in n:
		var d: Vector2 = drops[i]
		draw_line(d.floor(), d.floor() + Vector2(-1, 3), Color(0.7, 0.85, 1.0, 0.55), 1.0)
	if bolt_t > 0.0 and bolt.size() > 1:
		draw_polyline(bolt, Color(1, 1, 0.8, 1), 1.0)
		for p in bolt:
			draw_rect(Rect2(p + Vector2(1, 0), Vector2(1, 1)), Color(1, 0.9, 0.5, 0.8))
	if meteor_t >= 0.0:
		var p2 := meteor_from.lerp(meteor_to, meteor_t)
		for i in 8:
			var q := meteor_from.lerp(meteor_to, maxf(0.0, meteor_t - i * 0.03))
			draw_rect(Rect2(q.floor(), Vector2(2, 2)), Color(1, 0.6 - i * 0.05, 0.2, 1.0 - i * 0.12))
		draw_rect(Rect2(p2.floor() - Vector2(1, 1), Vector2(4, 4)), Color("ffcd75"))
	if beam_t > 0.0:
		var a := minf(1.0, beam_t)
		draw_rect(Rect2(beam_p.x - 6, 0, 12, beam_p.y + 4), Color(0.6, 1.0, 0.9, 0.25 * a))
		draw_rect(Rect2(beam_p.x - 3, 0, 6, beam_p.y + 4), Color(0.8, 1.0, 1.0, 0.35 * a))
		for i in 6:
			var y := fmod(t * 60.0 + i * 37.0, beam_p.y + 4)
			draw_rect(Rect2(beam_p.x - 4 + (i % 3) * 3, y, 1, 1), Color(1, 1, 1, a))
	if flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, flash * 0.6))
