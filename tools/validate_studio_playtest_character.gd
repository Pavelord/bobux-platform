extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/place_editor/studio.tscn")
	if packed == null:
		push_error("Could not load Studio scene")
		quit(1)
		return
	var studio := packed.instantiate()
	get_root().add_child(studio)
	await process_frame
	await process_frame
	var parts: Array = studio._get_editor_parts()
	if parts.is_empty():
		push_error("Studio did not create a baseplate")
		quit(1)
		return
	var touch_script := Node.new()
	touch_script.name = "TouchDamageTest"
	touch_script.set_meta("roblox_class", "Script")
	touch_script.set_meta("script_type", "Script")
	touch_script.set_meta("code", """
script.Parent.Touched:connect(function(hit)
	script.Parent.Name = "TouchCallbackRan"
	local character = hit.Parent
	local humanoid = character:FindFirstChild("Humanoid")
	local player = game.Players:GetPlayerFromCharacter(character)
	if humanoid and player then
		humanoid:TakeDamage(25)
	end
end)
""")
	parts[0].add_child(touch_script)
	print("[validate_studio_playtest_character] starting_playtest")
	await studio._start_studio_playtest()
	print("[validate_studio_playtest_character] playtest_started")
	var player: CharacterBody3D = studio.get("studio_playtest_player") as CharacterBody3D
	var spawned := player != null and is_instance_valid(player)
	var contract_ok := false
	if spawned:
		var required_parts := ["HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg"]
		var parts_ok := true
		for part_name in required_parts:
			var part := player.get_node_or_null(part_name)
			parts_ok = parts_ok and part is Node3D and str(part.get_meta("roblox_class", "")) == "Part"
		var humanoid := player.get_node_or_null("Humanoid")
		var animator := humanoid.get_node_or_null("Animator") if humanoid != null else null
		var body_colors := player.get_node_or_null("Body Colors")
		var motor_count := _count_class_recursive(player, "Motor6D")
		contract_ok = parts_ok and humanoid != null and animator != null and body_colors != null and motor_count == 6
	var player_instance_id := player.get_instance_id() if spawned else 0
	var local_player: Node = null
	var player_children: Array[String] = []
	var data_model: Node = studio.get("data_model")
	if data_model != null:
		var players_service := data_model.get_node_or_null("Players")
		if players_service != null:
			for child in players_service.get_children():
				player_children.append(str(child.name))
				if str(child.name) == "LocalPlayer":
					local_player = child
	var bound := spawned and local_player != null and int(local_player.get_meta("bobux_character_instance_id", 0)) == player_instance_id
	for frame_index in range(150):
		await physics_frame
		await process_frame
		if frame_index % 30 == 0:
			print("[validate_studio_playtest_character] frame=%d" % frame_index)
	var health := int(player.call("get_health")) if spawned and player.has_method("get_health") else 100
	var callback_ran := str(parts[0].get_meta("block_name", parts[0].name)) == "TouchCallbackRan"
	var player_camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D if spawned else null
	var camera_active := player_camera != null and player_camera.current
	var lua_engine := get_root().get_node_or_null("LuaScriptEngine")
	var diagnostics: Dictionary = lua_engine.get_runtime_diagnostics() if lua_engine != null else {}
	var floor_body := parts[0].get_node_or_null("CollisionBody") as StaticBody3D
	var floor_shape := floor_body.get_node_or_null("CollisionShape3D") as CollisionShape3D if floor_body != null else null
	var event_registry: Dictionary = parts[0].get_meta("_bobux_event_registry", {}) if parts[0].get_meta("_bobux_event_registry", {}) is Dictionary else {}
	var collider_debug := "none"
	if spawned and player.get_slide_collision_count() > 0:
		var slide_collision := player.get_slide_collision(0)
		var collider_variant: Variant = slide_collision.get_collider() if slide_collision != null else null
		if collider_variant is Node:
			var collider_node := collider_variant as Node
			var owner_node := collider_node.get_parent() if collider_node.name in ["CollisionBody", "SelectionBody"] else collider_node
			collider_debug = "%s class=%s owner=%s owner_group=%s" % [
				str(collider_node.get_path()), collider_node.get_class(),
				str(owner_node.get_path()) if owner_node != null else "null",
				str(owner_node != null and owner_node.is_in_group("studio_parts")),
			]
	var touched_connections := 0
	if event_registry.get("Touched", null) != null:
		touched_connections = int(event_registry["Touched"].get("connections").size())
	print("[validate_studio_playtest_character] pre_stop pos=%s floor=%s mask=%d floor_layer=%d floor_disabled=%s started=%d failed=%d active=%d touched_connections=%d collisions=%d notifications=%d errors=%s" % [
		str(player.global_position), str(player.is_on_floor()), player.collision_mask,
		floor_body.collision_layer if floor_body != null else -1,
		str(floor_shape.disabled if floor_shape != null else true),
		int(diagnostics.get("started", 0)), int(diagnostics.get("failed", 0)), int(diagnostics.get("active", 0)),
		touched_connections, int(player.get_meta("bobux_touch_collision_count", -1)), int(player.get_meta("bobux_touch_notifications", 0)),
		str(diagnostics.get("last_errors", [])),
	])
	print("[validate_studio_playtest_character] collider=%s" % collider_debug)
	await studio._stop_studio_playtest()
	await process_frame
	var stopped := studio.get("studio_playtest_player") == null and bool(studio.get("studio_playtest_active")) == false
	var editor_camera: Camera3D = studio.get("camera") as Camera3D
	var restored_camera := editor_camera != null and editor_camera.current
	var ok := spawned and contract_ok and bound and camera_active and callback_ran and health <= 75 and stopped and restored_camera
	print("[validate_studio_playtest_character] ok=%s spawned=%s contract=%s bound=%s camera=%s callback=%s health=%d stopped=%s restored_camera=%s players=%s local_character_id=%d actual_id=%d" % [
		str(ok), str(spawned), str(contract_ok), str(bound), str(camera_active), str(callback_ran), health, str(stopped), str(restored_camera),
		str(player_children), int(local_player.get_meta("bobux_character_instance_id", 0)) if local_player != null else 0,
		player_instance_id,
	])
	studio.queue_free()
	await process_frame
	quit(0 if ok else 1)


func _count_class_recursive(root: Node, target_class: String) -> int:
	if root == null:
		return 0
	var count := 1 if str(root.get_meta("roblox_class", "")) == target_class else 0
	for child in root.get_children():
		count += _count_class_recursive(child, target_class)
	return count
