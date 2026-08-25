extends SceneTree
func _initialize() -> void:
    var wsmp := WebSocketMultiplayerPeer.new()
    for m in wsmp.get_method_list():
        var name = str(m.get('name', ''))
        if name == 'get_peer':
            print(m)
    quit()
