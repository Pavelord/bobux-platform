extends SceneTree

const CONVERTER_RESOURCE := "res://addons/rbxl_importer/rbxl_converter.py"
const BRIDGE_SCRIPT := "res://addons/rbxl_importer/rbxl_converter_bridge.gd"
const MIN_CONVERTER_BYTES := 32 * 1024


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := FileAccess.open(CONVERTER_RESOURCE, FileAccess.READ)
	if source == null or source.get_length() < MIN_CONVERTER_BYTES:
		push_error("[validate_rbxl_converter_runtime] Converter resource is missing or incomplete")
		quit(1)
		return
	var source_bytes := source.get_buffer(source.get_length())
	source.close()

	var bridge_script := load(BRIDGE_SCRIPT) as GDScript
	if bridge_script == null:
		push_error("[validate_rbxl_converter_runtime] Bridge failed to load")
		quit(1)
		return
	var bridge: RefCounted = bridge_script.new()
	var prepare_error := int(bridge.call("prepare_converter"))
	var runtime_path := str(bridge.call("get_prepared_converter_path"))
	var extracted_path := str(bridge.call("_materialize_packaged_converter"))
	var extracted_bytes := FileAccess.get_file_as_bytes(extracted_path)

	var ok := (
		prepare_error == OK
		and not runtime_path.is_empty()
		and source_bytes == extracted_bytes
	)
	print(
		"[validate_rbxl_converter_runtime] ok=%s error=%d bytes=%d path=%s"
		% [ok, prepare_error, extracted_bytes.size(), extracted_path]
	)
	quit(0 if ok else 1)
