extends SceneTree

const MaterialCache = preload("res://addons/rbxl_importer/material_cache.gd")

const FIXTURES := [
	{"path": "res://.codex-tmp/avatar_probe/00_banana.glb", "expects_appearance": true},
	{"path": "res://.codex-tmp/avatar_probe/01____________________________.glb", "expects_appearance": true},
	# This legacy upload is genuinely white in its GLB. It remains a loadability
	# fixture; future uploads are covered by the model material round-trip test.
	{"path": "res://.codex-tmp/avatar_probe/02_HAIR.glb", "expects_appearance": false},
]


func _init() -> void:
	var failures: Array[String] = []
	for fixture in FIXTURES:
		var path := str(fixture.get("path", ""))
		var result := _inspect_glb(path)
		print("[validate_real_avatar_attachment_materials] ", path, " ", result)
		if not bool(result.get("loadable", false)) or (
			bool(fixture.get("expects_appearance", false))
			and not bool(result.get("has_appearance", false))
		):
			failures.append(path)
	if failures.is_empty():
		quit(0)
	else:
		push_error("Avatar attachment appearance failed for: %s" % ", ".join(failures))
		quit(1)


func _inspect_glb(path: String) -> Dictionary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		return {"loadable": false, "has_appearance": false, "error": error}
	var scene := document.generate_scene(state)
	if scene == null:
		return {"loadable": false, "has_appearance": false, "error": "generate_scene"}
	MaterialCache.enable_embedded_vertex_colors(scene)
	var stats := {
		"loadable": true,
		"has_appearance": false,
		"meshes": 0,
		"surfaces": 0,
		"textured": 0,
		"colored": 0,
		"vertex_colored": 0,
	}
	_collect_material_stats(scene, stats)
	stats["has_appearance"] = int(stats["meshes"]) > 0 and (
		int(stats["textured"]) > 0
		or int(stats["colored"]) > 0
		or int(stats["vertex_colored"]) > 0
	)
	scene.free()
	return stats


func _collect_material_stats(node: Node, stats: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			stats["meshes"] = int(stats["meshes"]) + 1
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				stats["surfaces"] = int(stats["surfaces"]) + 1
				var material := mesh_instance.get_active_material(surface_index)
				if material is BaseMaterial3D:
					var base := material as BaseMaterial3D
					if base.albedo_texture != null:
						stats["textured"] = int(stats["textured"]) + 1
					if base.vertex_color_use_as_albedo:
						stats["vertex_colored"] = int(stats["vertex_colored"]) + 1
					var color := base.albedo_color
					if absf(color.r - 1.0) > 0.08 or absf(color.g - 1.0) > 0.08 or absf(color.b - 1.0) > 0.08:
						stats["colored"] = int(stats["colored"]) + 1
	for child in node.get_children():
		_collect_material_stats(child, stats)
