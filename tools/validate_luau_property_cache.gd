extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var engine := root.get_node("LuaScriptEngine")
	var label := Label.new()
	root.add_child(label)
	var wrapper = engine.BobuxInstance.wrap(label)
	var ok := wrapper._get("TextTransparency") == null
	label.modulate = Color.RED
	ok = ok and wrapper._get("MODULATE") == Color.RED
	label.modulate = Color.BLUE
	ok = ok and wrapper._get("Modulate") == Color.BLUE
	label.add_theme_color_override("font_color", Color.GREEN)
	ok = ok and wrapper._get("theme_override_colors/font_color") == Color.GREEN
	label.set_meta("fresh", 42)
	ok = ok and wrapper._get("metadata/fresh") == 42
	var custom := GDScript.new()
	custom.source_code = """extends Label
var TextTransparency := 0.375
var dynamic_name := 'FirstDynamic'
func _get_property_list() -> Array[Dictionary]:
    return [{'name': dynamic_name, 'type': TYPE_INT}]
func _get(property: StringName) -> Variant:
    return 17 if property == dynamic_name else null
"""
	ok = ok and custom.reload() == OK
	label.set_script(custom)
	ok = ok and wrapper._get("TextTransparency") == 0.375 and wrapper._get("firstdynamic") == 17
	label.set("dynamic_name", "SecondDynamic")
	label.notify_property_list_changed()
	ok = ok and wrapper._get("FirstDynamic") == null and wrapper._get("SecondDynamic") == 17
	label.set_script(null)
	ok = ok and wrapper._get("TextTransparency") == null
	var part := MeshInstance3D.new()
	root.add_child(part)
	part.mesh = BoxMesh.new()
	var instance = engine.BobuxInstance.wrap(part)
	var changes: Array = []
	instance.Changed.Connect(func(property): changes.append(property))
	for index in 64:
		instance.CFrame = engine.BobuxCFrame.new(Transform3D(Basis.IDENTITY, Vector3(index, 2, 3)))
	ok = ok and changes.size() == 64 and instance.CFrame.Position == Vector3(63, 2, 3)
	part.free()
	label.free()
	print("[property-cache] PASS=", ok, " live values, missing values, dynamic schemas, theme/metadata, CFrame events")
	quit(0 if ok else 1)
