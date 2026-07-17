extends SceneTree

const AvatarTemplateProcessorClass = preload("res://scripts/avatar/avatar_template_processor.gd")

func _initialize() -> void:
	var source_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	source_image.fill(Color(0.12, 0.58, 0.92, 1.0))
	var extensionless_path := "user://mobile_gallery_selection"
	var source_file := FileAccess.open(extensionless_path, FileAccess.WRITE)
	if source_file == null:
		_finish(false, "could not create source fixture")
		return
	source_file.store_buffer(source_image.save_png_to_buffer())
	source_file.close()

	var result: Dictionary = AvatarTemplateProcessorClass.import_template_to_user_storage(
		extensionless_path,
		"shirt",
		"mobile_validation"
	)
	var imported_path := str(result.get("path", ""))
	var preview_path := str(result.get("preview_path", ""))
	var imported := Image.new()
	var imported_ok := not imported_path.is_empty() \
		and FileAccess.file_exists(imported_path) \
		and imported.load(imported_path) == OK \
		and imported.get_width() == AvatarTemplateProcessorClass.OUTPUT_SIZE \
		and imported.get_height() == AvatarTemplateProcessorClass.OUTPUT_SIZE
	var preview_ok := not preview_path.is_empty() and FileAccess.file_exists(preview_path)
	var ok := bool(result.get("ok", false)) and imported_ok and preview_ok

	_remove_if_present(extensionless_path)
	_remove_if_present(imported_path)
	if preview_path != imported_path:
		_remove_if_present(preview_path)
	_finish(ok, "decoded=%s preview=%s" % [str(imported_ok), str(preview_ok)])

func _remove_if_present(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _finish(ok: bool, details: String) -> void:
	print("[validate_mobile_avatar_file_import] ok=%s %s" % [str(ok), details])
	quit(0 if ok else 1)
