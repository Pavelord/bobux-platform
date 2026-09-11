extends SceneTree

const Library = preload("res://addons/roblox_studio/toolbox_asset_library.gd")
const CANDIDATES := "res://toolbox_assets/metadata/candidates.json"
var valid: Array = []
var failures: Array = []

func _initialize() -> void:
	await process_frame
	var database: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATES))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#E5EBF2")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.5
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.make_current()
	DirAccess.make_dir_recursive_absolute("res://toolbox_assets/thumbnails")
	var processed := 0
	for raw in database.assets:
		var entry: Dictionary = raw.duplicate(true)
		var path: String = entry.file
		if entry.type == "sound":
			var stream := AudioStreamOggVorbis.load_from_file(path)
			if stream == null or stream.get_length() <= 0:
				failures.append({"id": entry.id, "reason": "Invalid AudioStream or duration"})
				continue
			entry.duration = stream.get_length()
		else:
			var model := Library.load_model(path)
			if model == null:
				failures.append({"id": entry.id, "reason": "GLB loading failed"})
				continue
			var box := Library.bounds(model)
			if not box.size.is_finite() or not box.position.is_finite() or box.size.length() < 0.001 or box.size.length() > 10000:
				failures.append({"id": entry.id, "reason": "Invalid/empty geometry bounds"})
				model.free()
				continue
			entry.bounds = {"position": [box.position.x, box.position.y, box.position.z], "size": [box.size.x, box.size.y, box.size.z]}
			entry.units_to_studs = 3.0
			stage.add_child(model)
			if not FileAccess.file_exists(entry.thumbnail):
				var center := box.get_center()
				var extent := box.size.length()
				camera.position = center + Vector3(1.2, 0.85, 1.4).normalized() * extent * 2
				camera.look_at(center)
				camera.size = extent * 1.2
				camera.far = maxf(extent * 5, 100)
				await process_frame
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				if image == null or image.is_empty() or image.save_png(entry.thumbnail) != OK:
					failures.append({"id": entry.id, "reason": "Thumbnail render failed; use a graphics driver, not --headless"})
					model.free()
					continue
			model.free()
		entry.validated = true
		valid.append(entry)
		processed += 1
		if processed % 50 == 0:
			print("[asset_library] validated=%d / %d failed=%d" % [processed, database.assets.size(), failures.size()])
			await process_frame
	FileAccess.open("res://toolbox_assets/metadata/index.json", FileAccess.WRITE).store_string(JSON.stringify({"version": 1, "assets": valid}, "\t"))
	FileAccess.open("res://toolbox_assets/metadata/failed_assets.json", FileAccess.WRITE).store_string(JSON.stringify(failures, "\t"))
	var report_path := "res://toolbox_assets/metadata/asset_import_report.json"
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	report.imported = valid.size()
	report.validation_failures = failures.size()
	report.models_validated = valid.filter(func(x): return x.type == "model").size()
	report.sounds_validated = valid.filter(func(x): return x.type == "sound").size()
	FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[asset_library] complete=" + JSON.stringify(report))
	viewport.free()
	quit(0 if failures.is_empty() else 1)
