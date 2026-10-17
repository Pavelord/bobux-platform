extends RefCounted
## Display metadata is bundled with the client; only the event API grants ownership.
const GIFT_ID := "event_halloween_2026_gift"
const PUMPKIN_ID := "event_halloween_2026_pumpkin"
const REWARD_AT := "2026-10-30T21:00:00.000Z"

static func display_name(item: Dictionary) -> String:
	# Old offline outfit payloads may still contain the former display names.
	# Naming is cosmetic; IDs and server ownership remain unchanged.
	match str(item.get("id", item.get("item_id", ""))):
		GIFT_ID: return "Coffin Gift Box - Halloween"
		PUMPKIN_ID: return "Pumpkin"
	return str(item.get("name", item.get("title", item.get("id", "Item"))))

static func catalog() -> Array:
	var result: Array = []
	for kind in ["gift", "pumpkin"]:
		var gift: bool = kind == "gift"
		result.append({
			"id": GIFT_ID if gift else PUMPKIN_ID, "name": "Coffin Gift Box - Halloween" if gift else "Pumpkin",
			"description": "Лимитированный гроб-подарок для головы." if gift else "Светящаяся тыква для головы.",
			"owner_id": "bobux", "owner_name": "Bobux", "category": "accessory", "asset_type": "avatar_item", "price_robux": 0,
			"source_url": "res://assets/events/halloween2026/%s.glb" % kind,
			"attachment_slot": "Head" if gift else "HeadCenter",
			"attachment_transform": {"position": [0, 0, 0], "rotation_degrees": [0, 0 if gift else -90, 0], "scale": [0.65, 0.65, 0.65] if gift else [0.9, 0.9, 0.9]},
			"data": {"event_id": "halloween_2026", "art_version": 4, "limited": true, "covers_head": not gift, "attachment_anchor": "head_top" if gift else "center"}
		})
	return result

static func unavailable_state() -> Dictionary:
	return {"event_id": "halloween_2026", "timezone": "Europe/Moscow", "gift_owned": false, "pumpkin_owned": false,
		"can_claim_gift": false, "gift_deadline": REWARD_AT, "reward_at": REWARD_AT, "items": catalog(), "service_available": false}
