extends RefCounted
## Only schedules refresh. A JWT claim never authenticates a Bobux account.
const MAX_EXPIRY := 253402300799
const BASE64URL := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

static func token_expires_at(token: String) -> int:
	var parts := token.split(".")
	if parts.size() != 3 or parts[0].is_empty() or parts[2].is_empty(): return 0
	var encoded := parts[1]
	if encoded.is_empty() or encoded.length() > 16384 or encoded.length() % 4 == 1: return 0
	for character in encoded:
		if not BASE64URL.contains(character): return 0
	var normalized := encoded.replace("-", "+").replace("_", "/")
	normalized += "=".repeat((4 - normalized.length() % 4) % 4)
	var bytes := Marshalls.base64_to_raw(normalized)
	# exp and JSON structure are ASCII; other identity strings are not used.
	# ASCII conversion also avoids Unicode decoder errors for a corrupt cache.
	var json := JSON.new()
	if json.parse(bytes.get_string_from_ascii()) != OK: return 0
	var claims: Variant = json.data
	if not claims is Dictionary: return 0
	var expiry: Variant = claims.get("exp")
	if not expiry is int and not expiry is float: return 0
	var numeric := float(expiry)
	if not is_finite(numeric) or numeric <= 0 or numeric > MAX_EXPIRY or numeric != floor(numeric): return 0
	return int(numeric)

static func clamp_expiry(metadata_expiry: int, token: String) -> int:
	var claim_expiry := token_expires_at(token)
	if claim_expiry <= 0: return metadata_expiry
	return mini(metadata_expiry, claim_expiry) if metadata_expiry > 0 else claim_expiry
