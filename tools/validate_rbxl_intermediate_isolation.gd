extends SceneTree


const RuntimeImporter := preload("res://addons/rbxl_importer/rbxl_runtime_importer.gd")


func _initialize() -> void:
	var cache_dir := ProjectSettings.globalize_path("user://rbxl_import_cache")
	var source := "C:\\Maps\\Concurrent Place.rbxl"
	var first := RuntimeImporter.new()
	var second := RuntimeImporter.new()
	var first_path: String = first._unique_intermediate_json_path(cache_dir, source)
	var second_path: String = second._unique_intermediate_json_path(cache_dir, source)
	var ok := (
		first_path != second_path
		and first_path.get_base_dir() == cache_dir
		and second_path.get_base_dir() == cache_dir
		and first_path.ends_with(".intermediate.json")
		and second_path.ends_with(".intermediate.json")
	)
	print("[validate_rbxl_intermediate_isolation] ok=%s first=%s second=%s" % [
		str(ok), first_path.get_file(), second_path.get_file(),
	])
	quit(0 if ok else 1)
