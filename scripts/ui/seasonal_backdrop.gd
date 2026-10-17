extends Control
## Eight inexpensive embers; no particles, blur passes or animated shaders.
var _phase := 0.0
var _elapsed := 0.0
var paint_background := true

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	visibility_changed.connect(update_animation_setting)
	var prefs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("ClientPreferences")
	if prefs != null and prefs.has_signal("changed"):
		prefs.connect("changed", func(key: String, _value: Variant):
			if key in ["interface_animations", "app_theme"]: update_animation_setting.call_deferred()
		)
	update_animation_setting()

func update_animation_setting() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var prefs: Node = tree.root.get_node_or_null("ClientPreferences") if tree != null else null
	set_process(is_visible_in_tree() and (prefs == null or bool(prefs.get("values").get("interface_animations", true))))
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.05: return
	_phase += _elapsed
	_elapsed = 0
	queue_redraw()

func _draw() -> void:
	if paint_background: draw_rect(Rect2(Vector2.ZERO, size), Color("121216"))
	for index in range(8):
		var x := size.x * (float(index) + 0.5) / 8.0 + sin(_phase * 0.15 + index) * 22
		var y := fposmod(size.y * float(index) * 0.137 - _phase * (6.0 + index), maxf(size.y, 1.0))
		draw_circle(Vector2(x, y), 2.0 + float(index % 2), Color(1.0, 0.40, 0.08, 0.13))
	draw_line(Vector2(0, 0), Vector2(size.x, 0), Color(1.0, 0.45, 0.12, 0.45), 1)
