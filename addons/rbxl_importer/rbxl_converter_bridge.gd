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

const _PythonCandidates := [
	"python",
	"python3",
	"py",
]

## Populated with the stderr / OS error message of the last failed call.
var last_error: String = ""


## Convert `source_path` (.rbxl or .rbxlx) into an intermediate JSON at
## `output_path`. Returns OK on success, an Error constant otherwise, and fills
## `last_error` with details on failure.
func convert_file(source_path: String, output_path: String) -> Error:
	last_error = ""
	var py_script := ProjectSettings.globalize_path(_CONVERTER_PATH)
	if not FileAccess.file_exists(py_script):
		last_error = "converter not found: %s" % py_script
		return ERR_FILE_NOT_FOUND
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
