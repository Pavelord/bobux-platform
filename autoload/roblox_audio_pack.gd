extends Node

const AudioFileLoader = preload("res://addons/roblox_runtime/audio_file_loader.gd")
const SFX_DIR := "res://RobloxAudioPack_2018/SFX"

var _streams: Dictionary = {}
var _ui_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "RobloxAudioUI"
	add_child(_ui_player)


func play_ui(file_name: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if _ui_player == null:
		return
	var stream := _load_stream(file_name)
	if stream == null:
		return
	_ui_player.stop()
	_ui_player.stream = stream
	_ui_player.volume_db = volume_db
	_ui_player.pitch_scale = pitch
	_ui_player.play()


func play_at(file_name: String, world_position: Vector3, volume_db: float = -4.0, pitch: float = 1.0, max_distance: float = 36.0) -> void:
	var stream := _load_stream(file_name)
	if stream == null or get_tree() == null or get_tree().current_scene == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = max_distance
	player.unit_size = 8.0
	player.finished.connect(player.queue_free)
	get_tree().current_scene.add_child(player)
	player.global_position = world_position
	player.play()


func play_character(file_name: String, character: Node3D, volume_db: float = -4.0, pitch: float = 1.0) -> void:
	if is_instance_valid(character):
		play_at(file_name, character.global_position, volume_db, pitch)


func play_random(options: Array[String], character: Node3D, volume_db: float = -4.0) -> void:
	if options.is_empty() or not is_instance_valid(character):
		return
	play_character(options[_rng.randi_range(0, options.size() - 1)], character, volume_db, _rng.randf_range(0.94, 1.06))


func play_footstep(material_name: String, character: Node3D, volume_db: float = -10.0) -> void:
	if not is_instance_valid(character):
		return
	var material := _normalize_material(material_name)
	var options: Array[String] = []
	match material:
		"Grass", "LeafyGrass", "Ground", "Mud", "Sand", "Snow":
			options = ["grass.mp3", "grass2.mp3", "grass3.mp3"]
		"Ice":
			options = ["ice.mp3", "ice2.mp3", "ice3.mp3"]
		"Metal", "CorrodedMetal", "DiamondPlate":
			options = ["metal.mp3", "metal2.mp3", "metal3.mp3"]
		"Wood", "WoodPlanks":
			options = ["woodwood.mp3", "woodwood2.mp3", "woodwood3.mp3"]
		"Brick", "Cobblestone", "Concrete", "Rock", "Slate", "Stone", "Asphalt", "Basalt", "Pavement":
			options = ["stone.mp3", "stone2.mp3", "stone3.mp3"]
		"Water":
			options = ["action_swim.mp3"]
		_:
			pass
	if material == "Water":
		_play_footstep_layer("RobloxFootstepMainAudio", "action_swim.mp3", character, volume_db)
		_stop_footstep_layer(character, "RobloxFootstepSurfaceAudio")
		return
	# Roblox's plastic step remains the recognizable, dominant part of every step.
	_play_footstep_layer("RobloxFootstepMainAudio", "action_footsteps_plastic.mp3", character, volume_db + 2.0)
	if options.is_empty():
		_stop_footstep_layer(character, "RobloxFootstepSurfaceAudio")
		return
	var surface_sound := options[_rng.randi_range(0, options.size() - 1)]
	_play_footstep_layer("RobloxFootstepSurfaceAudio", surface_sound, character, volume_db - 27.0)


func _play_footstep_layer(player_name: String, file_name: String, character: Node3D, volume_db: float) -> void:
	var stream := _load_stream(file_name)
	if stream == null:
		return
	var player := character.get_node_or_null(player_name) as AudioStreamPlayer3D
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.name = player_name
		player.max_distance = 36.0
		player.unit_size = 8.0
		character.add_child(player)
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = _rng.randf_range(0.94, 1.06)
	player.play()


func stop_footstep(character: Node3D) -> void:
	if not is_instance_valid(character):
		return
	_stop_footstep_layer(character, "RobloxFootstepMainAudio")
	_stop_footstep_layer(character, "RobloxFootstepSurfaceAudio")


func _stop_footstep_layer(character: Node3D, player_name: String) -> void:
	var player := character.get_node_or_null(player_name) as AudioStreamPlayer3D
	if player != null:
		player.stop()


func play_collision(material_a: String, material_b: String, world_position: Vector3, strength: float = 1.0) -> void:
	var pair := _material_pair_key(material_a, material_b)
	var suffix := str(_rng.randi_range(1, 3))
	var path := SFX_DIR.path_join(pair + suffix + ".mp3")
	if not FileAccess.file_exists(path):
		path = SFX_DIR.path_join(pair + ".mp3")
	if not FileAccess.file_exists(path):
		path = SFX_DIR.path_join("collide.mp3")
	play_at(path.get_file(), world_position, lerpf(-18.0, -5.0, clampf(strength, 0.0, 1.0)), _rng.randf_range(0.94, 1.06))


func _material_pair_key(material_a: String, material_b: String) -> String:
	var a := _material_key(material_a)
	var b := _material_key(material_b)
	if a.is_empty() or b.is_empty():
		return "collide"
	var direct := a + b
	var reverse := b + a
	for pair in [direct, reverse]:
		for suffix in ["1", "2", "3", ""]:
			if FileAccess.file_exists(SFX_DIR.path_join(pair + suffix + ".mp3")):
				return pair
	return "collide"


func _normalize_material(raw: String) -> String:
	var key := raw.strip_edges().to_lower().replace("enum.material.", "").replace(" ", "").replace("_", "").replace("-", "")
	var names := {"leafygrass":"LeafyGrass", "woodplanks":"WoodPlanks", "corrodedmetal":"CorrodedMetal", "diamondplate":"DiamondPlate", "cobblestone":"Cobblestone", "concrete":"Concrete", "asphalt":"Asphalt", "basalt":"Basalt", "pavement":"Pavement", "water":"Water", "grass":"Grass", "ground":"Ground", "mud":"Mud", "sand":"Sand", "snow":"Snow", "ice":"Ice", "metal":"Metal", "wood":"Wood", "brick":"Brick", "rock":"Rock", "slate":"Slate", "stone":"Stone", "plastic":"Plastic"}
	return str(names.get(key, "Plastic"))


func _material_key(raw: String) -> String:
	var key := _normalize_material(raw).to_lower()
	match key:
		"grass", "leafygrass", "ground", "mud", "sand", "snow": return "grass"
		"ice": return "ice"
		"metal", "corrodedmetal", "diamondplate": return "metal"
		"wood", "woodplanks": return "wood"
		"brick", "cobblestone", "concrete", "rock", "slate", "stone", "asphalt", "basalt", "pavement": return "stone"
		_: return "plastic"


func _load_stream(file_name: String) -> AudioStream:
	if not _streams.has(file_name):
		_streams[file_name] = AudioFileLoader.load_stream(SFX_DIR.path_join(file_name), true)
	return _streams[file_name] as AudioStream
