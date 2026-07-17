extends SceneTree
func _initialize() -> void:
    var wsmp := WebSocketMultiplayerPeer.new()
    print('WSMP methods:')
    for m in wsmp.get_method_list():
        var name = str(m.get('name', ''))
        if 'ping' in name.to_lower() or 'heart' in name.to_lower() or 'timeout' in name.to_lower() or 'handshake' in name.to_lower() or 'interval' in name.to_lower() or 'alive' in name.to_lower():
            print('  method:', name)
    print('WSMP properties:')
    for p in wsmp.get_property_list():
        var name = str(p.get('name', ''))
        if 'ping' in name.to_lower() or 'heart' in name.to_lower() or 'timeout' in name.to_lower() or 'handshake' in name.to_lower() or 'interval' in name.to_lower() or 'alive' in name.to_lower():
            print('  prop:', name, ' type=', p.get('type', ''))
    var wsp := WebSocketPeer.new()
    print('WSP methods:')
    for m in wsp.get_method_list():
        var name = str(m.get('name', ''))
        if 'ping' in name.to_lower() or 'heart' in name.to_lower() or 'timeout' in name.to_lower() or 'handshake' in name.to_lower() or 'interval' in name.to_lower() or 'alive' in name.to_lower():
            print('  method:', name)
    print('WSP properties:')
    for p in wsp.get_property_list():
        var name = str(p.get('name', ''))
        if 'ping' in name.to_lower() or 'heart' in name.to_lower() or 'timeout' in name.to_lower() or 'handshake' in name.to_lower() or 'interval' in name.to_lower() or 'alive' in name.to_lower():
            print('  prop:', name, ' type=', p.get('type', ''))
    quit()
