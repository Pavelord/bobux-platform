extends SceneTree

var errors: Array[String] = []
func check(ok: bool, label_: String) -> void:
	print("[studio_items] %s=%s" % [label_, ok])
	if not ok: errors.append(label_)

func _initialize() -> void:
	await process_frame
	var studio: Node = load("res://scenes/place_editor/studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	var recipes := load("res://addons/roblox_studio/studio_script_recipes.gd")
	check(studio._apply_studio_ai_actions(recipes.points_button_plan().actions) == 3, "editable GUI and script authored")
	check(studio._apply_studio_ai_actions(recipes.buff_coin_plan().actions) == 4, "Tool and pickup script authored")
	var dynamic := [{"type": "create_script", "name": "DynamicGui", "script_type": "LocalScript", "parent": "StarterPlayerScripts", "source": """
local gui = Instance.new('ScreenGui')
gui.Name = 'DynamicScore'
gui.Parent = game:GetService('Players').LocalPlayer.PlayerGui
local button = Instance.new('TextButton')
button.Name = 'DynamicButton'
button.Size = UDim2.new(0, 180, 0, 50)
button.Position = UDim2.new(0.5, -90, 0, 80)
button.Text = 'dynamic'
button.BackgroundColor3 = Color3.new(0.1, 0.8, 0.2)
button.Parent = gui
button.Activated:Connect(function()
    button.Text = 'clicked'
    button.Size = UDim2.new(0, 260, 0, 60)
end)
"""}]
	check(studio._apply_studio_ai_actions(dynamic) == 1, "dynamic GUI script authored")
	var engine := root.get_node("LuaScriptEngine")
	await studio._start_studio_playtest()
	await create_timer(0.4).timeout
	var character: CharacterBody3D = studio.studio_playtest_player
	var inventory: Dictionary = engine.get_local_inventory_state(studio.placement_parent, character)
	var player: Node = inventory.local_player
	var dynamic_view: Button = null
	for candidate in studio.viewport_container_node.find_children("DynamicButton", "Button", true, false):
		if candidate.has_meta("bobux_bound_target_path"): dynamic_view = candidate
	check(dynamic_view != null and dynamic_view.size.x == 180, "Instance.new GUI appears with UDim2 layout")
	if dynamic_view != null:
		check(absf(dynamic_view.position.x - (dynamic_view.get_parent().size.x * 0.5 - 90)) < 1, "dynamic GUI preserves scaled Position")
		dynamic_view.pressed.emit()
		await create_timer(0.15).timeout
		check(dynamic_view.text == "clicked" and dynamic_view.size.x == 260, "dynamic GUI click and resize reach visible control")
	var points: Node = player.get_node_or_null("leaderstats/Points")
	check(points != null, "GUI LocalScript created player points")
	var button: Button = player.get_node_or_null("PlayerGui/ScoreGui/AddPoint") as Button
	check(button != null, "GUI cloned into PlayerGui")
	check(button != null and button.visibility_layer == 0, "DataModel GUI does not draw a duplicate over the game")
	var rendered: Button = null
	for candidate in studio.viewport_container_node.find_children("*", "Button", true, false):
		if button != null and str(candidate.get_meta("roblox_ref", "")) == str(button.get_meta("roblox_ref", "")):
			print("[studio_items] candidate=%s bound=%s" % [candidate.get_path(), candidate.get_meta("bobux_bound_target_path", "")])
			if candidate.has_meta("bobux_bound_target_path"):
				rendered = candidate
	check(rendered != null, "visible GUI bound to live script")
	check(rendered != null and rendered.visibility_layer != 0, "runtime GUI is rendered in the game viewport")
	if rendered != null:
		print("[studio_items] bound=%s expected=%s" % [rendered.get_meta("bobux_bound_target_path", ""), button.get_path()])
		rendered.pressed.emit()
		rendered.pressed.emit()
		await process_frame
		await process_frame
		check(points != null and int(points.get_meta("Value", -1)) == 2, "two GUI clicks add two points")
		print("[studio_items] value=%s text=%s" % [points.get_meta("Value", -1), rendered.text])
		check(rendered.text.contains("2"), "rendered label updates")
	var coin: Node3D = studio.placement_parent.get_node_or_null("BuffCoin")
	var handle: Node3D = coin.get_node("Handle") if coin != null else null
	check(coin != null and handle != null, "coin exists in world")
	if handle != null:
		var camera: Camera3D = studio._get_studio_subviewport().get_camera_3d()
		var screen := camera.unproject_position(handle.global_position)
		var picked: bool = load("res://addons/roblox_runtime/roblox_interaction_runtime.gd").activate_click(camera, screen, studio.placement_parent, character, engine)
		check(picked and coin.get_parent() == inventory.backpack, "ray click picks Tool into Backpack")
		var old_speed: float = character.get_humanoid_walk_speed()
		var old_jump: float = character.get_humanoid_jump_power()
		check(engine.equip_local_tool(coin, studio.placement_parent, character), "inventory equips picked coin")
		character._apply_animation_pose()
		check(absf(character.right_arm_pivot.rotation_degrees.x + 90) < 1, "equipped tool holds right arm forward")
		check(handle.global_position.distance_to(character.to_global(character.get_tool_hand_transform().origin)) < 0.05, "Handle stays at palm")
		check(character.get_humanoid_walk_speed() == 30 and character.get_humanoid_jump_power() == 70, "equipping changes real movement stats")
		character.global_position.y += 15
		character.velocity.y = -60
		await create_timer(0.15).timeout
		check(character.velocity.y > -30, "held coin limits physical falling speed")
		check(engine.unequip_local_tool(coin, studio.placement_parent), "inventory unequips coin")
		check(character.get_humanoid_walk_speed() == old_speed and character.get_humanoid_jump_power() == old_jump, "unequipping restores previous stats")
	var diagnostics: Dictionary = engine.get_runtime_diagnostics()
	var controller: Node = studio.studio_inventory_controller
	controller.refresh_now(true)
	var backpack_button: Button = controller.find_child("OpenBackpack", true, false)
	backpack_button.pressed.emit()
	check(controller.is_inventory_visible(), "Play inventory opens even via visible button")
	var focus := root.gui_get_focus_owner()
	if focus != null: focus.release_focus()
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	root.push_input(tab, true)
	await process_frame
	check(controller.find_child("PlayerList", true, false).visible, "Tab opens Play player list through real input")
	check(int(diagnostics.failed) == 0, "no runtime errors")
	print("[studio_items] diagnostics=%s" % diagnostics)
	await studio._stop_studio_playtest()
	studio.queue_free()
	await process_frame
	await process_frame
	# Regression for the exact freed-object crash reported after leaving Studio.
	engine._input(InputEventMouseMotion.new())
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	engine._input(key)
	check(engine._live_service_caches().is_empty(), "stale service cache pruned after exit")
	print("[studio_items] errors=%s" % [errors])
	quit(0 if errors.is_empty() else 1)
