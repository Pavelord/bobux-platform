extends "res://autoload/cloud_api.gd"
var launched := {}
var finished := {}
var peak := 0
func _ready() -> void: pass
func _download_cached_map_visual_asset_async(entry: Dictionary, state: Dictionary) -> void:
	launched[entry.file] = Time.get_ticks_msec()
	peak = maxi(peak, int(state.pending))
	await get_tree().create_timer(0.4 if entry.file == "0.res" else 0.02).timeout
	finished[entry.file] = Time.get_ticks_msec()
	state.downloaded += 1
	state.pending -= 1
