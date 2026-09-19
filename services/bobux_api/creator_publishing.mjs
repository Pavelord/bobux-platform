import { randomUUID } from "node:crypto";
import { catalog } from "./boblox_commerce.mjs";
const fail = (message, status = 400) => Object.assign(new Error(message), { status });
export const publicationKind = category => ["shirt", "tshirt", "t-shirt", "t_shirt", "pants", "clothing", "classic_shirt", "classic_pants"].includes(String(category).toLowerCase()) ? "clothing" : "items";
const isPublic = row => row && row.visibility !== "private" && row.is_public !== false;
export class CreatorPublishing {
  constructor(commerce) {
    this.commerce = commerce; this.db = commerce.db; this.tails = new Map();
    this.db.exec(`CREATE TABLE IF NOT EXISTS creator_publications (
      item_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, month TEXT NOT NULL,
      fee INTEGER NOT NULL, operation TEXT NOT NULL, state TEXT NOT NULL
    ) STRICT;
    CREATE INDEX IF NOT EXISTS creator_publications_usage ON creator_publications(user_id,month,kind);
    CREATE TABLE IF NOT EXISTS creator_free_listings (
      item_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, month TEXT NOT NULL, state TEXT NOT NULL
    ) STRICT;
    CREATE INDEX IF NOT EXISTS creator_free_usage ON creator_free_listings(user_id,month);`);
  }
  benefits(userId) {
    const tier = this.commerce.publicBadges(userId).club_tier;
    const month = new Date(this.commerce.now()).toISOString().slice(0, 7);
    const rules = catalog.tiers.find(t => t.id === tier).creator;
    const usage = { clothing: 0, items: 0 };
    for (const row of this.db.prepare("SELECT kind,COUNT(*) n FROM creator_publications WHERE user_id=? AND month=? AND state!='refunded' GROUP BY kind").all(userId, month)) usage[row.kind] = row.n;
    const freeUsage = this.db.prepare("SELECT COUNT(*) n FROM creator_free_listings WHERE user_id=? AND month=? AND state!='refunded'").get(userId, month).n;
    return { tier, month, rules, usage, free_items_remaining: Math.max(0, rules.free_items_limit - freeUsage) };
  }
  quote(userId, itemId, category, existing, visibility = "public", price = existing?.price_robux ?? 0) {
    if (!itemId || itemId.length > 128) throw fail("Некорректный ID предмета.");
    if (!Number.isSafeInteger(price) || price < 0 || price > 1000000) throw fail("Цена должна быть целым числом от 0 до 1 000 000 Boblox.");
    if (existing && existing.owner_id !== userId) throw fail("Редактировать предмет может только его автор.", 403);
    if (existing && publicationKind(existing.category) !== publicationKind(category)) throw fail("Для другого типа предмета создайте новую публикацию.", 409);
    const prior = this.db.prepare("SELECT * FROM creator_publications WHERE item_id=?").get(itemId);
    const freePrior = this.db.prepare("SELECT * FROM creator_free_listings WHERE item_id=?").get(itemId);
    if ((prior && prior.user_id !== userId) || (freePrior && freePrior.user_id !== userId)) throw fail("Предмет принадлежит другому автору.", 403);
    const benefits = this.benefits(userId), kind = publicationKind(category);
    if (prior && prior.kind !== kind) throw fail("Нельзя менять тип уже опубликованного предмета.", 409);
    const publicTarget = visibility === "public";
    const freeEdit = !publicTarget || prior?.state === "committed" || (!prior && isPublic(existing));
    const resume = prior?.state === "pending";
    const freeRemaining = Math.max(0, benefits.rules[kind + "_limit"] - benefits.usage[kind]);
    const remaining = Math.max(0, benefits.rules[kind + "_max"] - benefits.usage[kind]);
    const fee = freeEdit || resume || freeRemaining > 0 ? 0 : benefits.rules[kind + "_fee"];
    const legacyFree = !freePrior && isPublic(existing) && Number(existing.price_robux || 0) === 0;
    const needsFreeSlot = publicTarget && price === 0 && !legacyFree && (!freePrior || freePrior.state === "refunded");
    let error = "";
    if (publicTarget && !freeEdit && !resume && remaining === 0) error = "Достигнут месячный предел публикаций. Он обновится 1-го числа, 00:00 UTC.";
    if (needsFreeSlot && benefits.free_items_remaining === 0) error = "Лимит бесплатных товаров на этот месяц исчерпан. Укажите цену или дождитесь следующего месяца.";
    if (publicTarget && price > 0 && price < benefits.rules[kind + "_min_price"] && !(isPublic(existing) && price === Number(existing.price_robux))) error = `Минимальная цена этого типа предметов — ${benefits.rules[kind + "_min_price"]} Boblox.`;
    return { ...benefits, item_id: itemId, kind, fee, free_edit: !!freeEdit, resume, remaining, free_remaining: freeRemaining,
      needs_free_slot: needsFreeSlot, legacy_free: !!legacyFree, allowed: !error, error, price };
  }
  async publish({ userId, itemId, category, visibility, price, acceptedFee, lookup, save }) {
    // Lock both the account quota and the item identity across awaited database writes.
    const keys = [`user:${userId}`, `item:${itemId}`];
    const task = Promise.all(keys.map(key => (this.tails.get(key) || Promise.resolve()).catch(() => {}))).then(async () => {
      const existing = await lookup();
      const quote = this.quote(userId, itemId, category, existing, visibility, price ?? existing?.price_robux ?? 0);
      if (!quote.allowed) throw fail(quote.error, 409);
      let reservation = this.db.prepare("SELECT * FROM creator_publications WHERE item_id=?").get(itemId);
      if (reservation?.state === "pending" && isPublic(existing)) {
        this.db.prepare("UPDATE creator_publications SET state='committed' WHERE item_id=?").run(itemId);
        reservation.state = "committed";
      }
      if (visibility !== "public") {
        if (reservation?.state === "pending") throw fail("Сначала повторите предыдущую публикацию этого предмета.", 409);
        return save();
      }
      let reservedFree = false;
      this.commerce.wallet.transaction(() => {
        if (!reservation || reservation.state === "refunded") {
          if (quote.fee > 0 && Number(acceptedFee) !== quote.fee) throw fail(`Подтвердите стоимость публикации: ${quote.fee} Boblox.`, 409);
          reservation = { operation: randomUUID(), fee: quote.fee, state: quote.free_edit ? "committed" : "pending" };
          this.commerce.settleInTransaction(userId);
          if (quote.fee) this.commerce.wallet.applyInTransaction({ userId, amount: -quote.fee, operationId: `publish:${reservation.operation}`, reason: "catalog_publication" });
          this.db.prepare("INSERT INTO creator_publications VALUES (?,?,?,?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET month=excluded.month,fee=excluded.fee,operation=excluded.operation,state=excluded.state")
            .run(itemId, userId, quote.kind, quote.free_edit ? "" : quote.month, quote.fee, reservation.operation, reservation.state);
        }
        if (quote.needs_free_slot || quote.legacy_free) {
          this.db.prepare("INSERT INTO creator_free_listings VALUES (?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET month=excluded.month,state=excluded.state")
            .run(itemId, userId, quote.legacy_free ? "" : quote.month, quote.legacy_free ? "committed" : "pending");
          reservedFree = quote.needs_free_slot;
        } else {
          reservedFree = this.db.prepare("SELECT state FROM creator_free_listings WHERE item_id=?").get(itemId)?.state === "pending";
        }
      });
      const finish = () => this.commerce.wallet.transaction(() => {
        this.db.prepare("UPDATE creator_publications SET state='committed' WHERE item_id=?").run(itemId);
        if (reservedFree) this.db.prepare("UPDATE creator_free_listings SET state='committed' WHERE item_id=?").run(itemId);
      });
      try {
        const result = await save(); finish(); return result;
      } catch (error) {
        let actual;
        try { actual = await lookup(); } catch { throw fail("Проверяем результат публикации. Повторите отправку этого же предмета: повторного списания не будет.", 503); }
        if (isPublic(actual) && Number(actual.price_robux || 0) === quote.price) { finish(); return actual; }
        this.commerce.wallet.transaction(() => {
          if (reservation.state === "pending") {
            if (reservation.fee) this.commerce.wallet.applyInTransaction({ userId, amount: reservation.fee, operationId: `refund:${reservation.operation}`, reason: "publication_refund" });
            this.db.prepare("UPDATE creator_publications SET state='refunded' WHERE item_id=?").run(itemId);
          }
          if (reservedFree) this.db.prepare("UPDATE creator_free_listings SET state='refunded' WHERE item_id=?").run(itemId);
        });
        throw error;
      }
    });
    for (const key of keys) this.tails.set(key, task);
    try { return await task; } finally { for (const key of keys) if (this.tails.get(key) === task) this.tails.delete(key); }
  }
}
