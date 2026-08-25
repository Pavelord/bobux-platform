extends SceneTree
func _initialize() -> void:
    var wsmp := WebSocketMultiplayerPeer.new()
    for m in wsmp.get_method_list():
        var name = str(m.get('name', ''))
        if 'peer' in name.to_lower() or 'socket' in name.to_lower() or 'channel' in name.to_lower() or 'get_' in name.to_lower():
            print(name)
    quit()
