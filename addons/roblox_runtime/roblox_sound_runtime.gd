extends RefCounted

const LOADER = preload("res://addons/roblox_runtime/audio_file_loader.gd")
static var streams: Dictionary = {}

static func player_for(sound: Node) -> Node:
	if not is_instance_valid(sound): return null
	var parent := sound.get_parent()
	var spatial := parent is MeshInstance3D or (parent != null and str(parent.get_meta("roblox_class", "")) == "Attachment")
	if spatial:
		var global_player := sound.get_node_or_null("GlobalAudio")
		if global_player != null: global_player.stop()
		if sound is AudioStreamPlayer3D: return sound
		var spatial_player := sound.get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
		if spatial_player == null:
			spatial_player = AudioStreamPlayer3D.new()
			spatial_player.name = "AudioStreamPlayer3D"
			spatial_player.set_meta("bobux_runtime_generated", true)
			sound.add_child(spatial_player)
		return spatial_player
	if sound is AudioStreamPlayer3D:
		sound.stop()
	else:
		var old_spatial_player := sound.get_node_or_null("AudioStreamPlayer3D")
		if old_spatial_player != null: old_spatial_player.stop()
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
			if stream is AudioStreamWAV:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
				# WAV files without a sampler chunk have loop_end=0. Enabling
				# that empty loop ends playback immediately instead of looping.
				if looped and stream.loop_end <= stream.loop_begin:
					stream.loop_begin = 0
					stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
			elif stream is AudioStreamOggVorbis or stream is AudioStreamMP3: stream.loop = looped
			streams[key] = stream
	var stream: AudioStream = streams.get(key, null)
	if player.stream != stream: player.stream = stream
	var finished_callback := _finished.bind(sound.get_instance_id())
	if not player.finished.is_connected(finished_callback): player.finished.connect(finished_callback)
	player.volume_db = linear_to_db(maxf(float(sound.get_meta("Volume", props.get("Volume", 0.5))), 0.0001))
	player.pitch_scale = clampf(float(sound.get_meta("PlaybackSpeed", sound.get_meta("Pitch", props.get("PlaybackSpeed", props.get("Pitch", 1.0))))), 0.01, 8.0)
	if player is AudioStreamPlayer3D:
		player.unit_size = float(sound.get_meta("RollOffMinDistance", props.get("RollOffMinDistance", 10.0))) * 0.5
		player.max_distance = float(sound.get_meta("RollOffMaxDistance", props.get("RollOffMaxDistance", 10000.0))) * 0.5
	return player

static func _finished(sound_id: int) -> void:
	var sound: Variant = instance_from_id(sound_id)
	if not is_instance_valid(sound): return
	sound.set_meta("Playing", false)
	_mark_playback_changed(sound)
	if sound.is_inside_tree():
		var engine: Node = sound.get_tree().root.get_node_or_null("LuaScriptEngine")
		if engine != null: engine.fire_roblox_instance_event(sound, "Ended")

static func play(sound: Node) -> void:
	if not is_instance_valid(sound): return
	var request := int(sound.get_meta("bobux_sound_request", 0)) + 1
	sound.set_meta("bobux_sound_request", request)
	# Playing describes the authored request even while the asset is loading.
	# Clients need that request; a native audio player on a headless server is
	# not the source of truth for whether the mode started a sound.
	sound.set_meta("Playing", true)
	sound.set_meta("BobuxSoundPlayGeneration", int(sound.get_meta("BobuxSoundPlayGeneration", 0)) + 1)
	_mark_playback_changed(sound)
	var player := configure(sound)
	if player != null and player.stream != null and sound.is_inside_tree():
		player.play(float(sound.get_meta("TimePosition", 0.0)))
		sound.set_meta("Playing", true)
	elif sound.is_inside_tree():
		var source := str(sound.get_meta("SoundId", sound.get_meta("roblox_properties", {}).get("SoundId", "")))
		var media := sound.get_tree().root.get_node_or_null("MapMediaStream")
		if media != null and media.can_stream(source) and not FileAccess.file_exists(source):
			_play_when_ready(sound.get_instance_id(), source, request)
		elif not sound.has_meta("bobux_missing_sound_reported"):
			sound.set_meta("bobux_missing_sound_reported", true)
			push_warning("[Roblox Sound] Audio asset is unavailable: " + source)

static func _play_when_ready(sound_id: int, source: String, request: int) -> void:
	while true:
		var sound: Node = instance_from_id(sound_id) as Node
		if not is_instance_valid(sound) or not sound.is_inside_tree() or sound.get_meta("bobux_sound_request", 0) != request: return
		if FileAccess.file_exists(source):
			var player := configure(sound)
			if player != null and player.stream != null: player.play(float(sound.get_meta("TimePosition", 0.0)))
			return
		var media := sound.get_tree().root.get_node_or_null("MapMediaStream")
		if media == null or not media.can_stream(source): return
		await sound.get_tree().create_timer(0.1).timeout

static func stop(sound: Node) -> void:
	if not is_instance_valid(sound): return
	sound.set_meta("bobux_sound_request", int(sound.get_meta("bobux_sound_request", 0)) + 1)
	var player := player_for(sound)
	if player != null: player.stop()
	sound.set_meta("Playing", false)
	_mark_playback_changed(sound)

static func _mark_playback_changed(sound: Node) -> void:
	if not sound.is_inside_tree(): return
	var replication := sound.get_tree().root.get_node_or_null("ImportedPlaceNetwork")
	if replication != null: replication.mark_changed(sound, "Playing")
