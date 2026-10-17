extends "res://autoload/imported_place_network.gd"
## Inspect serialization work and recipient contents on a real transport.
var encoded_count := 0
var received := {}

func _encode_transaction(data: Dictionary) -> Dictionary:
	encoded_count += 1
	return super._encode_transaction(data)

func _queue_encoded_transaction(peer: int, _token: int, encoded: Dictionary) -> void:
	if encoded.is_empty(): return
	var raw: PackedByteArray = encoded.compressed.decompress(encoded.raw_size, FileAccess.COMPRESSION_ZSTD)
	received[peer] = bytes_to_var(raw)
