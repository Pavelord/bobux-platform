extends RefCounted

const LOADER = preload("res://addons/roblox_runtime/audio_file_loader.gd")
static var streams: Dictionary = {}

static func player_for(sound: Node) -> Node:
	if not is_instance_valid(sound): return null
	var parent := sound.get_parent()
	var spatial := parent is MeshInstance3D or (parent != null and str(parent.get_meta("roblox_class", "")) == "Attachment")
	if spatial and sound is AudioStreamPlayer3D:
		var global_player := sound.get_node_or_null("GlobalAudio")
		if global_player != null: global_player.stop()
		return sound
	var player := sound.get_node_or_null("GlobalAudio")
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "GlobalAudio"
		player.set_meta("bobux_runtime_generated", true)
		sound.add_child(player)
	if sound is AudioStreamPlayer3D: sound.stop()
	return player

static func configure(sound: Node) -> Node:
	var player := player_for(sound)
	if player == null: return null
	var props: Dictionary = sound.get_meta("roblox_properties", {})
	var source := str(sound.get_meta("SoundId", props.get("SoundId", "")))
	var looped := bool(sound.get_meta("Looped", props.get("Looped", false)))
	var key := source + "|" + str(looped)
	if not streams.has(key):
		var resolver = load("res://addons/rbxl_importer/rbxl_runtime_importer.gd").new()
		var path: String = resolver._resolve_sound_content_to_local_path(source)
		var stream := LOADER.load_stream(path, not looped)
		if stream != null:
			if stream is AudioStreamWAV: stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
			elif stream is AudioStreamOggVorbis or stream is AudioStreamMP3: stream.loop = looped
			streams[key] = stream
	player.stream = streams.get(key, null)
	player.volume_db = linear_to_db(maxf(float(sound.get_meta("Volume", props.get("Volume", 0.5))), 0.0001))
	player.pitch_scale = clampf(float(sound.get_meta("PlaybackSpeed", sound.get_meta("Pitch", props.get("PlaybackSpeed", props.get("Pitch", 1.0))))), 0.01, 8.0)
	if player is AudioStreamPlayer3D:
		player.unit_size = float(sound.get_meta("RollOffMinDistance", props.get("RollOffMinDistance", 10.0))) * 0.5
		player.max_distance = float(sound.get_meta("RollOffMaxDistance", props.get("RollOffMaxDistance", 10000.0))) * 0.5
	return player

static func play(sound: Node) -> void:
	var player := configure(sound)
	if player != null and player.stream != null and sound.is_inside_tree():
		player.play(float(sound.get_meta("TimePosition", 0.0)))
		sound.set_meta("Playing", true)
	elif not sound.has_meta("bobux_missing_sound_reported"):
		sound.set_meta("bobux_missing_sound_reported", true)
		push_warning("[Roblox Sound] Audio asset is unavailable: " + str(sound.get_meta("roblox_properties", {}).get("SoundId", sound.name)))

static func stop(sound: Node) -> void:
	var player := player_for(sound)
	if player != null: player.stop()
	sound.set_meta("Playing", false)
