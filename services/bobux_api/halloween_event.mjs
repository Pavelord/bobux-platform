// Event dates are absolute instants in Moscow (UTC+3), never the client's clock.
export const GIFT_ID = "event_halloween_2026_gift";
export const PUMPKIN_ID = "event_halloween_2026_pumpkin";
export const START_AT = "2026-09-30T21:00:00.000Z";
export const REWARD_AT = "2026-10-30T21:00:00.000Z";
export const isHalloweenItem = id => [GIFT_ID, PUMPKIN_ID].includes(String(id || "").trim());

export function assertEventInventoryWrite(collection, payloads = [], existing = []) {
  if (collection === "user_inventory" && [...payloads, ...existing].some(row => isHalloweenItem(row?.item_id))) {
    throw Object.assign(new Error("Event ownership and claim dates are managed by Bobux."), { status: 403 });
  }
}

export function eventCatalog() {
  return [
    { id: GIFT_ID, name: "Coffin Gift Box - Halloween", description: "Гроб-подарок Halloween 2026 для головы. Бесплатно до конца 30 октября по московскому времени. После получения останется в вашем инвентаре.", model: "gift", scale: [0.65, 0.65, 0.65], position: [0, 0, 0] },
    { id: PUMPKIN_ID, name: "Pumpkin", description: "Светящаяся тыква Halloween 2026 для головы.", model: "pumpkin", scale: [0.90, 0.90, 0.90], position: [0, 0, 0] }
  ].map(item => ({
    id: item.id, name: item.name, description: item.description,
    owner_id: "bobux", owner_name: "Bobux", visibility: "public", is_public: true,
    category: "accessory", asset_type: "avatar_item", price_robux: 0, likes_count: 0,
    thumbnail: "", source_url: `res://assets/events/halloween2026/${item.model}.glb`,
    attachment_slot: item.model === "pumpkin" ? "HeadCenter" : "Head", attachment_transform: { position: item.position, rotation_degrees: [0, item.model === "pumpkin" ? -90 : 0, 0], scale: item.scale },
    data: { event_id: "halloween_2026", art_version: 4, limited: true, covers_head: item.model === "pumpkin", attachment_anchor: item.model === "gift" ? "head_top" : "center", item_kind: "accessory", source_url: `res://assets/events/halloween2026/${item.model}.glb` },
    created_at: START_AT, updated_at: "2026-10-10T00:00:00.000Z"
  }));
}

export class HalloweenEvent {
  constructor({ readInventory, grant, clock = () => new Date() }) {
    this.readInventory = readInventory;
    this.grant = grant;
    this.clock = clock;
    this.tails = new Map();
  }
  async lock(userId, task) {
    const previous = this.tails.get(userId) || Promise.resolve();
    const current = previous.catch(() => undefined).then(task);
    this.tails.set(userId, current);
    try { return await current; }
    finally { if (this.tails.get(userId) === current) this.tails.delete(userId); }
  }
  async state(userId, claim = "") {
    if (!userId) throw Object.assign(new Error("Войдите в аккаунт."), { status: 401 });
    return this.lock(userId, async () => {
      const now = new Date(this.clock());
      const started = now >= new Date(START_AT);
      const rewardTime = now >= new Date(REWARD_AT);
      const rows = (await this.readInventory(userId)).filter(row => row.user_id === userId && row.item_type === "avatar_item");
      let gift = rows.find(row => row.item_id === GIFT_ID);
      let pumpkin = rows.find(row => row.item_id === PUMPKIN_ID);
      if (claim === GIFT_ID && !gift) {
        if (!started || rewardTime) throw Object.assign(new Error("Получение подарка завершено или ещё не началось."), { status: 409 });
        gift = await this.grant(userId, GIFT_ID, "avatar_item", now.toISOString());
      }
      // Ownership alone is insufficient: a forged/backfilled late gift cannot earn a pumpkin.
      const claimedAt = Date.parse(gift?.created_at || "");
      const eligible = Number.isFinite(claimedAt) && claimedAt >= Date.parse(START_AT) && claimedAt < Date.parse(REWARD_AT);
      if (rewardTime && eligible && !pumpkin) pumpkin = await this.grant(userId, PUMPKIN_ID, "avatar_item", now.toISOString());
      if (claim === PUMPKIN_ID && !pumpkin) throw Object.assign(new Error("Тыква доступна с 31 октября владельцам подарка, полученного до Хеллоуина."), { status: 409 });
      return {
        event_id: "halloween_2026", timezone: "Europe/Moscow", server_time: now.toISOString(),
        gift_deadline: REWARD_AT, reward_at: REWARD_AT, gift_owned: Boolean(gift), pumpkin_owned: Boolean(pumpkin),
        can_claim_gift: started && !rewardTime && !gift, eligible_for_pumpkin: eligible,
        items: eventCatalog().map(item => ({ ...item, owned: item.id === GIFT_ID ? Boolean(gift) : Boolean(pumpkin) }))
      };
    });
  }
  async reconcileAll() {
    if (new Date(this.clock()) < new Date(REWARD_AT)) return false;
    const users = new Set((await this.readInventory()).filter(row => row.item_id === GIFT_ID && row.item_type === "avatar_item").map(row => row.user_id));
    for (const userId of users) await this.state(userId);
    return true;
  }
}
