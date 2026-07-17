@tool
class_name RbxlConverterBridge
extends RefCounted

## Bridge between GDScript and `rbxl_converter.py`.
##
## Locates a usable Python interpreter (with lz4/zstandard installed) and runs
## the converter on a `.rbxl` / `.rbxlx` file. Works both inside the editor
## (EditorImportPlugin path) and at runtime (Place Editor path) since it only
## relies on `OS.execute`.

const _CONVERTER_PATH := "res://addons/rbxl_importer/rbxl_converter.py"
const _RUNTIME_CONVERTER_PATH := "user://rbxl_runtime/rbxl_converter.py"
const _MIN_CONVERTER_BYTES := 32 * 1024

static var _materialize_mutex := Mutex.new()

const _PythonCandidates := [
	"python",
	"python3",
	"py",
]

## Populated with the stderr / OS error message of the last failed call.
var last_error: String = ""
var _prepared_converter_path: String = ""


## Convert `source_path` (.rbxl or .rbxlx) into an intermediate JSON at
## `output_path`. Returns OK on success, an Error constant otherwise, and fills
## `last_error` with details on failure.
func convert_file(source_path: String, output_path: String) -> Error:
	last_error = ""
	var prepare_error := prepare_converter()
	if prepare_error != OK:
		return prepare_error
	var py_script := _prepared_converter_path
	var input_path := _globalize_if_needed(source_path)
	var target_path := _globalize_if_needed(output_path)
	if not FileAccess.file_exists(input_path):
		last_error = "input not found: %s" % input_path
		return ERR_FILE_NOT_FOUND

	var py_exec := _find_python()
	if py_exec.is_empty():
		last_error = "no Python interpreter found on PATH (tried: %s). Install Python 3. The optional zstandard package is only needed for zstd-compressed RBXL chunks." % ", ".join(_PythonCandidates)
		return ERR_CANT_OPEN

	var asset_cache_dir := ProjectSettings.globalize_path("user://rbxl_assets")
	DirAccess.make_dir_recursive_absolute(asset_cache_dir)
	var args := PackedStringArray([
		py_script,
		input_path,
		target_path,
		"--asset-cache-dir",
		asset_cache_dir,
		"--fetch-gui-assets"
	])
	var output: Array = []
	var exit_code: int = OS.execute(py_exec, args, output, true)
	if exit_code != 0:
		last_error = "\n".join(output).strip_edges()
		if last_error.is_empty():
			last_error = "python exited with code %d" % exit_code
		return ERR_PARSE_ERROR

	if not FileAccess.file_exists(target_path):
		last_error = "converter reported success but produced no output at %s" % target_path
		return ERR_BUG
	return OK


## Makes the Python converter available as a physical file. In exported builds
## res:// lives inside the PCK, so Python cannot execute it directly. A sidecar
## copy is preferred when present; otherwise the packaged resource is extracted
## into user:// and refreshed whenever its contents change.
func prepare_converter() -> Error:
	last_error = ""
	_prepared_converter_path = ""

	var sidecar_path := ProjectSettings.globalize_path(_CONVERTER_PATH)
	if FileAccess.file_exists(sidecar_path):
		var sidecar := FileAccess.open(sidecar_path, FileAccess.READ)
		if sidecar != null and sidecar.get_length() >= _MIN_CONVERTER_BYTES:
			sidecar.close()
			_prepared_converter_path = sidecar_path
			return OK

	_materialize_mutex.lock()
	var materialized_path := _materialize_packaged_converter()
	_materialize_mutex.unlock()
	if materialized_path.is_empty():
		return ERR_FILE_NOT_FOUND
	_prepared_converter_path = materialized_path
	return OK


func get_prepared_converter_path() -> String:
	return _prepared_converter_path


func _materialize_packaged_converter() -> String:
	var source := FileAccess.open(_CONVERTER_PATH, FileAccess.READ)
	if source == null:
		last_error = (
			"RBXL converter resource is missing from this build: %s. "
			+ "Reinstall or update Bobux."
		) % _CONVERTER_PATH
		return ""
	var converter_bytes := source.get_buffer(source.get_length())
	source.close()
	if converter_bytes.size() < _MIN_CONVERTER_BYTES:
		last_error = "RBXL converter resource is incomplete (%d bytes)." % converter_bytes.size()
		return ""

	var runtime_dir := ProjectSettings.globalize_path(_RUNTIME_CONVERTER_PATH.get_base_dir())
	var mkdir_error := DirAccess.make_dir_recursive_absolute(runtime_dir)
	if mkdir_error != OK:
		last_error = "cannot create RBXL runtime directory: %s" % runtime_dir
		return ""
	var target_path := ProjectSettings.globalize_path(_RUNTIME_CONVERTER_PATH)
	if FileAccess.file_exists(target_path):
		var existing_bytes := FileAccess.get_file_as_bytes(target_path)
		if existing_bytes == converter_bytes:
			return target_path

	var temporary_path := "%s.tmp.%d.%d" % [
		target_path,
		OS.get_process_id(),
		Time.get_ticks_usec(),
	]
	var target := FileAccess.open(temporary_path, FileAccess.WRITE)
	if target == null:
		last_error = "cannot extract RBXL converter to %s" % temporary_path
		return ""
	target.store_buffer(converter_bytes)
	target.flush()
	target.close()
	if FileAccess.file_exists(target_path):
		DirAccess.remove_absolute(target_path)
	var rename_error := DirAccess.rename_absolute(temporary_path, target_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary_path)
		last_error = "cannot activate extracted RBXL converter (error %d)" % rename_error
		return ""
	return target_path


func _globalize_if_needed(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _find_python() -> String:
	# 1. Honor an explicit override via project settings (optional convenience).
	var override: String = ProjectSettings.get_setting("bobux/rbxl/python_path", "")
	if not override.is_empty() and _python_works(override):
		return override

	# 2. Try common names on PATH.
	for candidate in _PythonCandidates:
		if _python_works(candidate):
			return candidate
	return ""


func _python_works(name: String) -> bool:
	# `OS.execute` returns -1 if the binary cannot be launched at all.
	var out: Array = []
	var code: int = OS.execute(name, ["--version"], out, true)
	return code == 0
