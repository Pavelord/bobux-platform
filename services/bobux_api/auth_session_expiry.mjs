// Expiration metadata only. PocketBase still authenticates every protected
// request; decoding a claim does not verify a token or authorize its holder.
export function tokenExpiresAt(token) {
  try {
    const parts = String(token || "").split(".");
    if (parts.length !== 3 || !parts[0] || !parts[2] || !parts[1] || parts[1].length > 16384 || parts[1].length % 4 === 1 || !/^[A-Za-z0-9_-]+$/.test(parts[1])) return 0;
    const claims = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    const exp = claims?.exp;
    return Number.isSafeInteger(exp) && exp > 0 && exp <= 253402300799 ? exp : 0;
  } catch { return 0; }
}

export function sessionExpiry(token, now, fallbackTtl) {
  const expiresAt = tokenExpiresAt(token) || now + fallbackTtl;
  return { expires_at: expiresAt, expires_in: Math.max(0, expiresAt - now) };
}
