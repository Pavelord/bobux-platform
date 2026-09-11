import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

export const catalog = JSON.parse(readFileSync(new URL("./commerce_catalog.json", import.meta.url), "utf8"));
const DAY = 86_400_000;
const fail = (message, status = 400) => Object.assign(new Error(message), { status });
const money = kopecks => (kopecks / 100).toFixed(2);

export class YooKassa {
  constructor({ shopId, secret, returnUrl, test = true, receiptMode = "external", vatCode = 1, fetchImpl = fetch }) {
    Object.assign(this, { shopId, secret, returnUrl, test, receiptMode, vatCode, fetchImpl });
  }
  async request(route, body, key) {
    const response = await this.fetchImpl(`https://api.yookassa.ru/v3/${route}`, {
      method: body ? "POST" : "GET", signal: AbortSignal.timeout(15000),
      headers: { Authorization: `Basic ${Buffer.from(`${this.shopId}:${this.secret}`).toString("base64")}`,
        "Content-Type": "application/json", ...(key ? { "Idempotence-Key": key } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {})
    });
    if (!response.ok) throw fail("Платёжный сервис временно недоступен. Повторите проверку заказа.", 502);
    return response.json();
  }
  create(order) {
    const item = JSON.parse(order.product);
    const amount = { value: money(order.price_kopecks), currency: "RUB" };
    const body = { amount, capture: true, confirmation: { type: "redirect", return_url: this.returnUrl },
      description: item.name, metadata: { bobux_order_id: order.id } };
    if (this.receiptMode === "yookassa") body.receipt = {
      customer: { email: order.email }, items: [{ description: item.name, quantity: "1.00", amount,
        vat_code: this.vatCode, payment_mode: "full_payment", payment_subject: "service" }]
    };
    return this.request("payments", body, order.id);
  }
  get(id) {
    if (!/^[a-zA-Z0-9-]{10,80}$/.test(id)) throw fail("Некорректный платёж.");
    return this.request(`payments/${id}`);
  }
}

export class BobloxCommerce {
  constructor(wallet, { provider = null, now = Date.now, termsUrl = "", supportUrl = "" } = {}) {
    Object.assign(this, { wallet, provider, now, termsUrl, supportUrl });
    this.db = wallet.db;
    this.inFlight = new Map();
    this.refreshInFlight = new Map();
    this.reconciling = false;
    this.db.exec(`CREATE TABLE IF NOT EXISTS boblox_orders (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL, request_key TEXT NOT NULL,
      product TEXT NOT NULL, price_kopecks INTEGER NOT NULL CHECK(price_kopecks>0), email TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'creating', payment_id TEXT UNIQUE, confirmation_url TEXT NOT NULL DEFAULT '',
      created_ms INTEGER NOT NULL, fulfilled_ms INTEGER, review INTEGER NOT NULL DEFAULT 0,
      UNIQUE(user_id,request_key)
    ) STRICT;
    CREATE INDEX IF NOT EXISTS boblox_orders_user ON boblox_orders(user_id,created_ms);
    CREATE TABLE IF NOT EXISTS boblox_memberships (
      order_id TEXT PRIMARY KEY REFERENCES boblox_orders(id), user_id TEXT NOT NULL, tier TEXT NOT NULL,
      start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, daily INTEGER NOT NULL CHECK(daily>0),
      days INTEGER NOT NULL CHECK(days>0), credited_days INTEGER NOT NULL DEFAULT 0,
      suspended INTEGER NOT NULL DEFAULT 0
    ) STRICT;
    CREATE INDEX IF NOT EXISTS boblox_memberships_user ON boblox_memberships(user_id,start_ms);`);
    if (!this.db.prepare("PRAGMA table_info(boblox_orders)").all().some(column => column.name === "checked_ms"))
      this.db.exec("ALTER TABLE boblox_orders ADD COLUMN checked_ms INTEGER NOT NULL DEFAULT 0");
  }
  publicCatalog() {
    return { ...catalog, sales_enabled: !!this.provider, test: this.provider?.test ?? false,
      terms_url: this.termsUrl, support_url: this.supportUrl };
  }
  product(id) {
    const pack = catalog.packs.find(p => p.id === id);
    if (pack) return { ...pack, kind: "pack", name: `${pack.amount} Boblox` };
    const tier = catalog.tiers.find(t => t.id === id && t.price_kopecks > 0);
    if (tier) return { ...tier, kind: "membership", name: `${tier.name} — ${tier.days} дней` };
    throw fail("Товар не найден.");
  }
  settleInTransaction(userId) {
    for (const period of this.db.prepare("SELECT * FROM boblox_memberships WHERE user_id=? AND suspended=0").all(userId)) {
      const due = Math.min(period.days, Math.max(0, Math.floor((this.now() - period.start_ms) / DAY) + 1));
      if (due <= period.credited_days) continue;
      this.wallet.applyInTransaction({ userId, amount: (due - period.credited_days) * period.daily,
        operationId: `club:${period.order_id}:${due}`, reason: `${period.tier}:daily` });
      this.db.prepare("UPDATE boblox_memberships SET credited_days=? WHERE order_id=?").run(due, period.order_id);
    }
  }
  account(userId) {
    this.wallet.transaction(() => this.settleInTransaction(userId));
    const active = this.db.prepare("SELECT tier,start_ms,end_ms,daily FROM boblox_memberships WHERE user_id=? AND suspended=0 AND start_ms<=? AND end_ms>? ORDER BY start_ms LIMIT 1")
      .get(userId, this.now(), this.now());
    const lastEnd = this.db.prepare("SELECT MAX(end_ms) AS end_ms FROM boblox_memberships WHERE user_id=? AND suspended=0 AND end_ms>?").get(userId, this.now()).end_ms;
    return { ...this.wallet.read(userId), test: this.provider?.test ?? false,
      membership: active ? { ...active, paid_until_ms: lastEnd } : { tier: "BC", daily: 0 },
      operations: this.wallet.history(userId), orders: this.db.prepare("SELECT id,product,status,created_ms,review FROM boblox_orders WHERE user_id=? ORDER BY created_ms DESC LIMIT 10")
        .all(userId).map(o => ({ ...o, product: JSON.parse(o.product).name })) };
  }
  order(userId, id) {
    const row = this.db.prepare("SELECT * FROM boblox_orders WHERE id=? AND user_id=?").get(id, userId);
    if (!row) throw fail("Заказ не найден.", 404);
    return row;
  }
  view(order) {
    return { id: order.id, status: order.status, price_kopecks: order.price_kopecks,
      product_id: JSON.parse(order.product).id,
      confirmation_url: order.confirmation_url, review: !!order.review, test: this.provider?.test ?? false };
  }
  async checkout(userId, { product_id: productId, request_key: key, email = "" }) {
    if (!this.provider) throw fail("Продажи ещё не открыты.", 503);
    this.wallet.read(userId); // Validate identity before persisting anything.
    if (typeof key !== "string" || !/^[a-f0-9-]{32,40}$/.test(key)) throw fail("Некорректный ключ заказа.");
    if (typeof email !== "string" || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw fail("Укажите email для чека.");
    let order = this.wallet.transaction(() => {
      const previous = this.db.prepare("SELECT * FROM boblox_orders WHERE user_id=? AND request_key=?").get(userId, key);
      if (previous) {
        if (JSON.parse(previous.product).id !== productId) throw fail("Этот ключ уже связан с другим заказом.", 409);
        return previous;
      }
      const product = this.product(productId);
      if (product.kind === "membership") {
        const other = this.db.prepare("SELECT tier FROM boblox_memberships WHERE user_id=? AND end_ms>? AND suspended=0 AND tier!=?").get(userId, this.now(), product.id);
        if (other) throw fail("Другой уровень клуба можно выбрать после окончания текущего срока.", 409);
        const pending = this.db.prepare("SELECT product FROM boblox_orders WHERE user_id=? AND status IN ('creating','pending','waiting_for_capture')").all(userId);
        if (pending.some(p => JSON.parse(p.product).kind === "membership")) throw fail("Сначала завершите или отмените предыдущую оплату клуба на странице оплаты.", 409);
      }
      const recent = this.db.prepare("SELECT COUNT(*) AS n FROM boblox_orders WHERE user_id=? AND created_ms>?").get(userId, this.now() - 3600000).n;
      if (recent >= 12) throw fail("Слишком много заказов. Попробуйте позже.", 429);
      const id = randomUUID();
      this.db.prepare("INSERT INTO boblox_orders(id,user_id,request_key,product,price_kopecks,email,created_ms) VALUES (?,?,?,?,?,?,?)")
        .run(id, userId, key, JSON.stringify(product), product.price_kopecks, email, this.now());
      return this.order(userId, id);
    });
    await this.ensurePayment(order);
    return this.view(this.order(userId, order.id));
  }
  async ensurePayment(order) {
    if (order.payment_id) return;
    // YooKassa remembers idempotence keys for 24h. Never re-create an ambiguous older charge.
    if (this.now() - order.created_ms > 23 * 3600000) throw fail("Заказ требует проверки поддержкой. Не оплачивайте его повторно.", 409);
    if (this.inFlight.has(order.id)) return this.inFlight.get(order.id);
    const promise = (async () => {
      const payment = await this.provider.create(order);
      this.verify(order, payment);
      const url = payment.confirmation?.confirmation_url || "";
      if (url && !/^https:\/\/(?:[a-z0-9-]+\.)*(?:yookassa\.ru|yoomoney\.ru)(?:\/|$)/i.test(url)) throw fail("Неизвестная страница оплаты.", 502);
      this.db.prepare("UPDATE boblox_orders SET payment_id=?,confirmation_url=? WHERE id=? AND payment_id IS NULL").run(payment.id, url, order.id);
      this.accept(order.id, payment);
    })();
    this.inFlight.set(order.id, promise);
    try { await promise; } finally { this.inFlight.delete(order.id); }
  }
  verify(order, payment) {
    if (typeof payment.id !== "string" || !/^[a-zA-Z0-9-]{10,80}$/.test(payment.id) ||
        (order.payment_id && payment.id !== order.payment_id) ||
        payment.metadata?.bobux_order_id !== order.id || payment.amount?.currency !== "RUB" ||
        payment.amount?.value !== money(order.price_kopecks) || payment.test !== this.provider.test ||
        String(payment.recipient?.account_id) !== String(this.provider.shopId)) throw fail("Платёж не соответствует заказу.", 502);
  }
  accept(id, payment) {
    return this.wallet.transaction(() => {
      const order = this.db.prepare("SELECT * FROM boblox_orders WHERE id=?").get(id);
      this.verify(order, payment);
      if (Number(payment.refunded_amount?.value || 0) > 0) {
        // Keep the immutable original credit. Stop future rewards until the merchant reconciles the refund.
        this.db.prepare("UPDATE boblox_orders SET review=1 WHERE id=?").run(id);
        this.db.prepare("UPDATE boblox_memberships SET suspended=1 WHERE order_id=?").run(id);
        return;
      }
      if (order.fulfilled_ms !== null) return;
      if (!["pending", "waiting_for_capture", "succeeded", "canceled"].includes(payment.status)) throw fail("Неизвестный статус оплаты.", 502);
      if (order.status === "canceled" && payment.status !== "canceled") throw fail("Статус отменённого платежа изменился.", 502);
      this.db.prepare("UPDATE boblox_orders SET status=? WHERE id=?").run(payment.status, id);
      if (payment.status !== "succeeded") return;
      if (payment.paid !== true) throw fail("Оплата не подтверждена.", 502);
      const item = JSON.parse(order.product);
      if (item.kind === "pack") {
        this.wallet.applyInTransaction({ userId: order.user_id, amount: item.amount, operationId: `payment:${id}`, reason: "boblox_purchase" });
      } else {
        const previousEnd = this.db.prepare("SELECT MAX(end_ms) AS value FROM boblox_memberships WHERE user_id=? AND suspended=0").get(order.user_id).value || 0;
        const start = Math.max(this.now(), previousEnd);
        this.db.prepare("INSERT INTO boblox_memberships(order_id,user_id,tier,start_ms,end_ms,daily,days) VALUES (?,?,?,?,?,?,?)")
          .run(id, order.user_id, item.id, start, start + item.days * DAY, item.daily, item.days);
        this.settleInTransaction(order.user_id);
      }
      this.db.prepare("UPDATE boblox_orders SET fulfilled_ms=? WHERE id=?").run(this.now(), id);
    });
  }
  async refresh(userId, id) {
    if (!this.provider) throw fail("Проверка платежей временно недоступна.", 503);
    const order = this.order(userId, id);
    if (!order.payment_id) await this.ensurePayment(order);
    else await this.refreshPayment(order);
    return this.view(this.order(userId, id));
  }
  async refreshPayment(order) {
    if (this.refreshInFlight.has(order.id)) return this.refreshInFlight.get(order.id);
    const work = (async () => this.accept(order.id, await this.provider.get(order.payment_id)))();
    this.refreshInFlight.set(order.id, work);
    try { await work; } finally { this.refreshInFlight.delete(order.id); }
  }
  async reconcile() {
    if (!this.provider || this.reconciling) return;
    this.reconciling = true;
    try {
      const pending = this.db.prepare("SELECT * FROM boblox_orders WHERE status IN ('creating','pending','waiting_for_capture') AND review=0 ORDER BY checked_ms,created_ms LIMIT 25").all();
      for (const order of pending) {
        this.db.prepare("UPDATE boblox_orders SET checked_ms=? WHERE id=?").run(this.now(), order.id);
        if (!order.payment_id && this.now() - order.created_ms > 23 * 3600000) {
          this.db.prepare("UPDATE boblox_orders SET review=1 WHERE id=?").run(order.id);
          continue;
        }
        try {
          if (order.payment_id) await this.refreshPayment(order);
          else await this.ensurePayment(order);
        } catch { /* Keep pending; the next sweep retries without minting or charging again. */ }
      }
    } finally { this.reconciling = false; }
  }
  async notification(body) {
    if (!this.provider) throw fail("Payments disabled", 503);
    const id = body?.event === "refund.succeeded" ? body?.object?.payment_id : body?.object?.id;
    if (typeof id !== "string") throw fail("Invalid notification");
    const order = this.db.prepare("SELECT * FROM boblox_orders WHERE payment_id=?").get(id);
    if (!order) return; // No provider request for arbitrary untrusted IDs.
    // Never trust webhook fields, query the authenticated provider API.
    await this.refreshPayment(order);
  }
}
