import express from "express";
import { BobloxCommerce, YooKassa, catalog } from "./boblox_commerce.mjs";

// Exported separately so real HTTP routes can be tested without PocketBase or live credentials.
export function mountBoblox(app, commerce, authenticate) {
  const route = handler => async (req, res) => {
    res.set("Cache-Control", "private, no-store");
    try { await handler(req, res); }
    catch (error) { res.status(Number(error.status) || 400).json({ ok: false, error: error.message }); }
  };
  const user = async req => {
    const auth = await authenticate(req);
    const record = auth?.record;
    if (!record?.id || record.email?.endsWith("@anon.bobux.local")) throw Object.assign(new Error("Войдите в постоянный аккаунт Bobux."), { status: 401 });
    return record.id;
  };
  const requireCommerce = () => {
    if (!commerce) throw Object.assign(new Error("Кошелёк ещё не подключён на сервере."), { status: 503 });
    return commerce;
  };
  app.get("/api/boblox/catalog", route(async (_req, res) => res.json({ ok: true,
    ...(commerce?.publicCatalog() || { ...catalog, sales_enabled: false, test: false }) })));
  app.get("/api/boblox/wallet", route(async (req, res) => res.json({ ok: true, ...requireCommerce().account(await user(req)) })));
  app.post("/api/boblox/founder-reward/claim", route(async (req, res) => {
    res.json({ ok: true, ...requireCommerce().claimFounder(await user(req)) });
  }));
  app.post("/api/boblox/checkout", express.json({ limit: "4kb" }), route(async (req, res) => {
    res.json({ ok: true, order: await requireCommerce().checkout(await user(req), req.body || {}) });
  }));
  app.post("/api/boblox/orders/:id/refresh", route(async (req, res) => {
    const userId = await user(req);
    res.json({ ok: true, order: await requireCommerce().refresh(userId, req.params.id), account: commerce.account(userId) });
  }));
  app.post("/api/boblox/yookassa/webhook", express.json({ limit: "16kb" }), route(async (req, res) => {
    await requireCommerce().notification(req.body);
    res.json({ ok: true });
  }));
  // The return page is informational. Visiting it never grants a purchase.
  app.get("/api/boblox/return", (_req, res) => res.type("html").send(`<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Bobux — оплата</title><body style="font-family:Arial;background:#f2f2f2;color:#333;margin:0"><header style="background:#0074bd;color:white;padding:20px;font-size:24px">BOBUX</header><main style="max-width:520px;background:white;margin:50px auto;padding:32px;border:1px solid #ddd"><h1>Вернитесь в Bobux</h1><p>В разделе Boblox нажмите «Проверить оплату». Баланс обновится после подтверждения платёжного сервиса.</p><p>Эту вкладку можно закрыть.</p></main></body></html>`));
}

export async function createBobloxFromEnv(env = process.env) {
  if (env.BOBLOX_ENABLED !== "true") return null;
  const mode = env.BOBLOX_PAYMENT_MODE || "off";
  if (!["off", "test", "live"].includes(mode)) throw new Error("Invalid BOBLOX_PAYMENT_MODE");
  let provider = null;
  if (mode !== "off") {
    if (!env.YOOKASSA_SHOP_ID || !env.YOOKASSA_SECRET_KEY) throw new Error("YooKassa server credentials are required");
    if (!/^https:\/\//.test(env.BOBLOX_RETURN_URL || "")) throw new Error("BOBLOX_RETURN_URL must be HTTPS");
    if (mode === "live" && (env.BOBLOX_SALES_APPROVED !== "true" || !/^https:\/\//.test(env.BOBLOX_TERMS_URL || "") || !/^https:\/\//.test(env.BOBLOX_SUPPORT_URL || "")))
      throw new Error("Live sales need merchant approval, published terms and support URL");
    if (!["external", "yookassa"].includes(env.BOBLOX_RECEIPT_MODE || "")) throw new Error("Set the merchant's confirmed receipt mode");
    provider = new YooKassa({ shopId: env.YOOKASSA_SHOP_ID, secret: env.YOOKASSA_SECRET_KEY, returnUrl: env.BOBLOX_RETURN_URL,
      test: mode === "test", receiptMode: env.BOBLOX_RECEIPT_MODE, vatCode: Number(env.BOBLOX_VAT_CODE || 1) });
  }
  const { BobloxWallet } = await import("./boblox_wallet.mjs");
  const filename = env.BOBLOX_DATABASE_PATH || "/var/lib/bobux/boblox.sqlite";
  // Test purchases cannot become real currency when switching the merchant to live mode.
  const wallet = new BobloxWallet(mode === "test" ? `${filename}.test` : filename);
  return new BobloxCommerce(wallet, { provider, termsUrl: env.BOBLOX_TERMS_URL, supportUrl: env.BOBLOX_SUPPORT_URL });
}
