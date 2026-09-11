extends Control
## Six segments matching the classic experience cards. Missing data is neutral.
var positive := 0
var negative := 0
var available := false

func configure(info: Dictionary) -> void:
	positive = maxi(0, int(info.get("rating_positive", info.get("likes", info.get("likes_count", 0)))))
	negative = maxi(0, int(info.get("rating_negative", 0)))
	available = info.has("rating_positive") and int(info.get("rating_positive", -1)) >= 0
	custom_minimum_size = Vector2(90, 15)
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "%d за · %d против" % [positive, negative] if available else "%d отметок нравится · рейтинг пока недоступен" % positive
	if available and positive + negative == 0: tooltip_text = "У этого режима ещё нет оценок"
	queue_redraw()

func _draw() -> void:
	var ink := Color("#858585")
	# A small monochrome thumb avoids OS-dependent emoji rendering.
	draw_rect(Rect2(0, 7, 3, 7), ink)
	draw_colored_polygon(PackedVector2Array([Vector2(4, 7), Vector2(7, 3), Vector2(7, 1), Vector2(9, 1), Vector2(10, 4), Vector2(9, 7), Vector2(14, 7), Vector2(12, 14), Vector2(4, 14)]), ink)
	var total := positive + negative
	var fraction := float(positive) / float(total) if available and total > 0 else 0.0
	var gap := 2.0
	var width := maxf(1, (size.x - 21 - 5 * gap) / 6)
	for index in range(6):
		var rect := Rect2(21 + index * (width + gap), 7, width, 6)
		draw_rect(rect, Color("#d2d2d2"))
		var fill := clampf(fraction * 6 - index, 0, 1)
		if fill > 0:
			rect.size.x *= fill
			draw_rect(rect, ink)
