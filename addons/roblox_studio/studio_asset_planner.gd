extends RefCounted

const Library = preload("res://addons/roblox_studio/toolbox_asset_library.gd")

# Resolve simple placement requests from the same index as Toolbox. Compound
# tasks and behavioral/edit requests keep their full context for the provider.
static func plan_for_request(prompt: String, context: Dictionary) -> Dictionary:
	var command := RegEx.new()
	command.compile("(?i)^\\s*(?:create|add|place|spawn|создай|добавь|поставь)\\s+(?:(?:a|an|the|модель)\\s+)?([a-zа-яё -]+)[.!]?\\s*$")
	var found := command.search(prompt)
	if found == null: return {}
	var query := found.get_string(1).strip_edges().to_lower()
	var compound := RegEx.new()
	compound.compile("(?i)(forest|village|room|office|street|лес|деревн|комнат|офис|улиц|работа|скрипт|script|shoot|стрел|npc|нпс|зомби|пистолет|pistol|rocket|рпг|двигател|engine|\\band\\b|\\bwith\\b|\\bи\\b|\\bс\\b|возле|внутри)")
	var sound_request := "sound" in query or "звук" in query
	if not sound_request and compound.search(query) != null: return {}
	var bundle := Library.get_asset_bundle_for_concept(query)
	if sound_request:
		# Attaching audio is an edit: retain the exact selected instance reference.
		var selected := str(context.get("selected_ref", ""))
		if selected.is_empty() or bundle.sounds.is_empty(): return {}
		return {"ok": true, "message": "Звук добавлен к выбранному объекту. В свойствах можно настроить воспроизведение.", "actions": [{"type": "attach_sound", "asset_id": bundle.sounds[0].id, "parent": selected}]}
	var entry: Dictionary = bundle.primary_model
	if entry.is_empty(): return {}
	# Unmatched adjectives, locations and requested features must not be silently
	# discarded by a local shortcut. The remote planner can assemble those.
	var vocabulary := " ".join([str(entry.name), " ".join(entry.tags), " ".join(entry.synonyms)]).to_lower()
	for token in bundle.search_terms:
		if token not in vocabulary: return {}
	return {"ok": true, "message": "Добавлена модель «%s» из библиотеки CC0. Её части доступны в Explorer." % entry.name, "actions": [{"type": "spawn_asset", "asset_id": entry.id}]}
