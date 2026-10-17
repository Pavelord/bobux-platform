extends SceneTree

const SOUND := preload("res://addons/roblox_runtime/roblox_sound_runtime.gd")
const MODEL := preload("res://addons/roblox_studio/roblox_data_model.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error(message)

func run() -> void:
	var workspace := Node3D.new()
	workspace.name = "Workspace"
	workspace.set_meta("roblox_class", "Workspace")
	root.add_child(workspace)
	var sound := MODEL.create_instance("Sound", "DelayedSound")
	workspace.add_child(sound)
	var media := root.get_node("MapMediaStream")
	var path := "user://delayed_sound_contract.wav"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	media.expect_file(path)
	sound.set_meta("SoundId", path)
	sound.set_meta("Looped", true)
	SOUND.play(sound)
	check(bool(sound.get_meta("Playing", false)), "Play request must survive unavailable audio")
	await create_timer(1 if OS.get_cmdline_user_args().has("--quick") else 16).timeout
	# Real file arrives after the previous 15-second polling cutoff.
	var tone := AudioStreamWAV.new()
	tone.format = AudioStreamWAV.FORMAT_16_BITS
	tone.mix_rate = 22050
	var pcm := PackedByteArray()
	pcm.resize(22050 * 2)
	for i in range(22050): pcm.encode_s16(i * 2, int(sin(float(i) * TAU * 440.0 / 22050.0) * 5000.0))
	tone.data = pcm
	check(tone.save_to_wav(path) == OK, "Fixture WAV must be saved")
	media.file_available(path)
	await create_timer(0.3).timeout
	var player := SOUND.player_for(sound)
	print("[sound-debug] source=", path, " exists=",FileAccess.file_exists(path)," request=",sound.get_meta("bobux_sound_request"), " stream=",player.stream, " playing=",player.playing," loaded=",preload("res://addons/roblox_runtime/audio_file_loader.gd").load_stream(path)," sound children=",sound.get_children())
	check(player.stream != null and player.playing, "Delayed audio must start after more than 15 seconds")
	var generation := int(sound.get_meta("BobuxSoundPlayGeneration", 0))
	check(generation == 1, "Asset completion must not issue a second Play")
	var bridge := root.get_node("ImportedPlaceNetwork")
	var state := {"roots":{"root":workspace}, "nodes":{"root":workspace,"sound":sound}, "workspace":workspace}
	var props := {"SoundId":path, "Looped":true, "Playing":true, "BobuxSoundPlayGeneration":generation, "Volume":0.5}
	sound.set_meta("roblox_properties", props.duplicate())
	props.Volume = 0.25
	bridge._apply_entry({"ref":"sound", "class":"Sound", "name":"DelayedSound", "parent_ref":"root", "properties":props}, state, {})
	check(int(sound.get_meta("bobux_sound_request", 0)) == 1, "Volume replication must not restart playback")
	props.BobuxSoundPlayGeneration += 1
	bridge._apply_entry({"ref":"sound", "class":"Sound", "name":"DelayedSound", "parent_ref":"root", "properties":props}, state, {})
	check(int(sound.get_meta("bobux_sound_request", 0)) == 2, "Repeated authored Play must restart playback")
	SOUND.stop(sound)
	check(not player.playing and not bool(sound.get_meta("Playing", true)), "Stop must cancel the native player and authored playback")
	var failed_path := "user://failed_sound_contract.wav"
	media.expect_file(failed_path)
	media.file_failed(failed_path)
	check(not media.can_stream(failed_path), "Failed download must stop pending audio polling")
	workspace.queue_free()
	await process_frame
	print("[halloween-sound-contract] PASS=", failures.is_empty(), " failures=", failures)
	quit(0 if failures.is_empty() else 1)
