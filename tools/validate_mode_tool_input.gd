extends SceneTree
func _initialize(): run.call_deferred()
func run():
 var engine=root.get_node('LuaScriptEngine')
 var studio:Node=load('res://scenes/place_editor/studio.tscn').instantiate()
 root.add_child(studio)
 await process_frame
 var library=load('res://addons/roblox_studio/studio_gameplay_library.gd')
 studio._apply_studio_ai_actions(library.weapon_plan(false,true).actions)
 var folder='user://weapon_mode_regression'
 assert(await studio._save_map(folder))
 studio.queue_free()
 await process_frame
 await process_frame
 var host:Node=load('res://scenes/main/main.tscn').instantiate()
 var fixture=GDScript.new()
 fixture.source_code='extends "res://scripts/main/main.gd"\nfunc _ready(): pass\nfunc _process(_dt): pass\nfunc _exit_tree(): pass\nfunc _refresh_runtime_roblox_ui(_a,_b): pass\n'
 assert(fixture.reload()==OK)
 host.set_script(fixture)
 root.add_child(host)
 current_scene=host
 var map=Node3D.new()
 map.name='MapRoot'
 host.add_child(map)
 var loaded=await host._load_map_into_room_runtime('weapon-test',folder,map)
 print('WEAPON_MODE loaded=',loaded)
 var character:CharacterBody3D=load('res://scenes/player/player.tscn').instantiate()
 character.name='1'
 host.get_node('World/Players').add_child(character)
 engine.bind_local_player_character(character)
 host._start_live_player_scripts(character)
 await create_timer(0.5).timeout
 var inventory=engine.get_local_inventory_state(host,character)
 print('WEAPON_MODE inventory=',inventory.get('tools'), ' equipped=',inventory.get('equipped_tools'))
 var pistol=character.get_node_or_null('Pistol')
 assert(pistol!=null,'Pistol not equipped after loading saved map')
 var hud=CanvasLayer.new()
 host.add_child(hud)
 host._ensure_runtime_roblox_gui_host(hud)
 var inventory_ui=load('res://addons/roblox_runtime/roblox_inventory_controller.gd').new()
 host.add_child(inventory_ui)
 inventory_ui.configure(engine,host,func():return character)
 await process_frame
 var click=InputEventMouseButton.new()
 click.button_index=MOUSE_BUTTON_LEFT
 click.pressed=true
 click.position=Vector2(400,250)
 Input.parse_input_event(click)
 await process_frame
 print('WEAPON_MODE bullets=',map.find_children('Bullet','',true,false).size(),' errors=',engine.get_runtime_diagnostics())
 assert(map.find_children('Bullet','',true,false).size()>0,'No bullet created in normal mode')
 quit()
