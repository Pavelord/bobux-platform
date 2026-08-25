@tool
extends EditorPlugin

## Bobux RBXL Importer
##
## Registers an EditorImportPlugin so that dropping a `.rbxl` / `.rbxlx` file
## into the Godot FileSystem dock produces a `.tscn` PackedScene. The runtime
## bridge (`rbxl_runtime_importer.gd`) is used by the in-game Place Editor
## (studio.gd / legacy_studio.gd) to import directly into the live scene tree.

var _import_plugin: EditorImportPlugin = null


func _enable_plugin() -> void:
	print("[Bobux RBXL Importer] Enabled. Drop a .rbxl / .rbxlx file into the FileSystem dock to import it as a .tscn scene.")


func _disable_plugin() -> void:
	if _import_plugin:
		remove_import_plugin(_import_plugin)
		_import_plugin = null


func _enter_tree() -> void:
	_import_plugin = RbxlEditorImportPlugin.new()
	add_import_plugin(_import_plugin)


func _exit_tree() -> void:
	if _import_plugin:
		remove_import_plugin(_import_plugin)
		_import_plugin = null
