extends Control

var _elapsed: float = 0.0
var _redraw_budget: float = 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	_redraw_budget += delta
	# Ambient movement is decorative and never runs at the game render rate.
	if _redraw_budget >= 1.0 / 20.0:
		_redraw_budget = 0.0
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101116"))
	var glow_center := Vector2(size.x * 0.18, size.y * 0.72)
	for ring in range(14, 0, -1):
		draw_circle(glow_center, float(ring) * 28.0, Color(0.65, 0.23, 0.065, 0.008))
	var moon_center := Vector2(size.x * 0.95, size.y * 0.17)
	for ring in range(10, 0, -1):
		draw_circle(moon_center, float(ring) * 13.0, Color(1.0, 0.47, 0.15, 0.008))
	draw_circle(moon_center, 37.0, Color("b7652b"))
	draw_circle(moon_center + Vector2(16, -9), 34.0, Color("101116"))
	for index in range(16):
		var x: float = fmod(float(index * 97 + 31), maxf(size.x, 1.0))
		var y: float = size.y - fmod(float(index * 61) + _elapsed * (7.0 + float(index % 3)), size.y + 20.0)
		var shimmer: float = 0.12 + 0.08 * sin(_elapsed * 0.7 + float(index))
		draw_circle(Vector2(x, y), 1.0 if index % 3 else 2.0, Color(1.0, 0.46, 0.1, shimmer))
	_draw_bat(Vector2(size.x * 0.045, size.y * 0.2 + sin(_elapsed * 0.55) * 5.0), 17.0, _elapsed * 0.85)
	_draw_bat(Vector2(size.x * 0.957, size.y * 0.84 + sin(_elapsed * 0.5 + 1.0) * 4.0), 11.0, _elapsed * 0.85 + 0.7)

func _draw_bat(center: Vector2, span: float, phase: float) -> void:
	var lift: float = sin(phase) * span * 0.13
	var points := PackedVector2Array([
		Vector2(-span, -span * 0.28 - lift), Vector2(-span * 0.55, -span * 0.5 - lift),
		Vector2(-span * 0.15, -span * 0.05), Vector2(-span * 0.08, -span * 0.27),
		Vector2(0, -span * 0.16), Vector2(span * 0.08, -span * 0.27),
		Vector2(span * 0.15, -span * 0.05), Vector2(span * 0.55, -span * 0.5 - lift),
		Vector2(span, -span * 0.28 - lift), Vector2(span * 0.65, span * 0.25),
		Vector2(span * 0.32, span * 0.07), Vector2(0, span * 0.35),
		Vector2(-span * 0.32, span * 0.07), Vector2(-span * 0.65, span * 0.25)
	])
	for index in range(points.size()):
		points[index] += center
	draw_colored_polygon(points, Color("7b452744"))
