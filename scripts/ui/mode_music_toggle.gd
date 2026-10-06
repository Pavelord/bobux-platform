extends CanvasLayer

var music: AudioStreamPlayer
var button: Button

static func attach(parent: Node, player: AudioStreamPlayer) -> CanvasLayer:
	var toggle: CanvasLayer = load("res://scripts/ui/mode_music_toggle.gd").new()
	toggle.music = player
	parent.add_child(toggle)
	return toggle

func _ready() -> void:
	layer = 40
	button = Button.new()
	button.name = "MusicToggle"
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.icon = load("res://assets/ui/music_note.svg")
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.tooltip_text = "Выключить фоновую музыку только для себя"
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = -62
	button.offset_right = -18
	button.offset_top = -62
	button.offset_bottom = -18
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#0074bd") if state == "normal" else Color("#005e99")
		style.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_font_size_override("font_size", 15)
	add_child(button)
	button.toggled.connect(func(muted: bool):
		if is_instance_valid(music): music.stream_paused = muted
		button.modulate = Color(0.65,0.65,0.65) if muted else Color.WHITE
		button.tooltip_text = "Включить музыку" if muted else "Выключить музыку"
	)

func _process(_delta: float) -> void:
	# A downloaded next track must preserve the listener's mute choice.
	if is_instance_valid(music): music.stream_paused = button.button_pressed
