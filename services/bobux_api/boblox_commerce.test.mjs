import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdtempSync, rmSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import express from "express";
import { BobloxWallet } from "./boblox_wallet.mjs";
import { BobloxCommerce, YooKassa, catalog } from "./boblox_commerce.mjs";
import { mountBoblox, createBobloxFromEnv } from "./boblox_routes.mjs";

const folder = mkdtempSync(join(tmpdir(), "boblox-commerce-"));
let clock = Date.UTC(2026, 8, 10, 12);
const DAY = 86400000;
const now = () => clock;
const payments = new Map();
const calls = [];
let loseResponse = false;
const provider = new YooKassa({ shopId: "12345", secret: "test-secret", returnUrl: "https://bobux.example/api/boblox/return",
  fetchImpl: async (url, options) => {
    calls.push({ url, options });
    assert.equal(options.headers.Authorization, "Basic " + Buffer.from("12345:test-secret").toString("base64"));
    if (options.method === "POST") {
      const request = JSON.parse(options.body);
      const key = options.headers["Idempotence-Key"];
      if (!payments.has(key)) payments.set(key, { id: randomUUID(), amount: request.amount, metadata: request.metadata,
        recipient: { account_id: "12345" }, test: true, status: "pending", paid: false,
        confirmation: { confirmation_url: "https://yoomoney.ru/checkout/payments/test" } });
      if (loseResponse) { loseResponse = false; throw new Error("Simulated lost provider response"); }
      return { ok: true, json: async () => structuredClone(payments.get(key)) };
    }
    const value = [...payments.values()].find(p => p.id === url.split("/").at(-1));
    assert.ok(value);
    return { ok: true, json: async () => structuredClone(value) };
  } });
let wallet = new BobloxWallet(join(folder, "commerce.sqlite"));
let commerce = new BobloxCommerce(wallet, { provider, now });
let server;
const request = product => ({ product_id: product, request_key: randomUUID(), email: "buyer@example.com" });
const succeed = async (user, order) => {
  const payment = payments.get(order.id);
  payment.status = "succeeded"; payment.paid = true;
  return commerce.refresh(user, order.id);
};
try {
  assert.deepEqual(catalog, JSON.parse(readFileSync(new URL("../../assets/currency/commerce_catalog.json", import.meta.url))));
  assert.equal(commerce.account("player1").membership.tier, "BC");
  assert.equal(await createBobloxFromEnv({ BOBLOX_ENABLED: "false" }), null);
  await assert.rejects(createBobloxFromEnv({ BOBLOX_ENABLED: "true", BOBLOX_PAYMENT_MODE: "live" }), /credentials/);
  const input = request("boblox_100");
  const [order, retry] = await Promise.all([commerce.checkout("player1", input), commerce.checkout("player1", input)]);
  assert.equal(order.id, retry.id);
  assert.equal(calls.filter(c => c.options.method === "POST").length, 1);
  assert.equal(wallet.read("player1").balance, 0);
  const body = JSON.parse(calls[0].options.body);
  assert.equal(body.amount.value, "50.00");
  assert.equal(body.capture, true);
  assert.equal(body.save_payment_method, undefined);
  await assert.rejects(commerce.checkout("player1", { ...input, product_id: "TBC" }), /ключ/);
  await assert.rejects(commerce.refresh("player2", order.id), /найден/);
  const original = structuredClone(payments.get(order.id));
  for (const change of [{ amount: { value: "0.01", currency: "RUB" } }, { test: false },
    { recipient: { account_id: "wrong" } }, { metadata: { bobux_order_id: "wrong" } }, { id: randomUUID() }]) {
    assert.throws(() => commerce.accept(order.id, { ...original, ...change, status: "succeeded", paid: true }), /соответствует/);
  }
  assert.equal(wallet.read("player1").balance, 0);
  await commerce.notification({ event: "payment.succeeded", object: { id: original.id, paid: true } });
  assert.equal(wallet.read("player1").balance, 0); // provider still says pending
  await succeed("player1", order);
  await Promise.all(Array.from({ length: 8 }, () => commerce.notification({ event: "payment.succeeded", object: { id: original.id } })));
  assert.equal(wallet.read("player1").balance, 100);
  assert.equal(wallet.history("player1").length, 1);
  wallet.close();
  wallet = new BobloxWallet(join(folder, "commerce.sqlite"));
  commerce = new BobloxCommerce(wallet, { provider, now });
  await commerce.refresh("player1", order.id);
  assert.equal(wallet.read("player1").balance, 100);
  loseResponse = true;
  const lostInput = request("boblox_500");
  await assert.rejects(commerce.checkout("player1", lostInput), /Simulated/);
  const recovered = await commerce.checkout("player1", lostInput);
  assert.equal([...payments.values()].filter(p => p.metadata.bobux_order_id === recovered.id).length, 1);
  payments.get(recovered.id).status = "canceled";
  await commerce.refresh("player1", recovered.id);
  assert.equal(wallet.read("player1").balance, 100);
  const club = await commerce.checkout("member", request("BBC"));
  await succeed("member", club);
  assert.equal(commerce.account("member").membership.tier, "BBC");
  assert.equal(wallet.read("member").balance, 10);
  await assert.rejects(commerce.checkout("member", request("PBC")), /окончания/);
  clock += 3 * DAY;
  assert.equal(commerce.account("member").balance, 40);
  assert.equal(commerce.account("member").balance, 40);
  const renewal = await commerce.checkout("member", request("BBC"));
  await succeed("member", renewal);
  assert.equal(wallet.read("member").balance, 40);
  clock += 27 * DAY;
  assert.equal(commerce.account("member").balance, 310);
  clock += 30 * DAY;
  assert.equal(commerce.account("member").balance, 600);
  assert.equal(commerce.account("member").membership.tier, "BC");
  clock += 100 * DAY;
  assert.equal(commerce.account("member").balance, 600);
  const pbc = await commerce.checkout("member", request("PBC"));
  await succeed("member", pbc);
  assert.equal(commerce.account("member").membership.tier, "PBC");
  payments.get(pbc.id).refunded_amount = { value: "299.00", currency: "RUB" };
  await commerce.notification({ event: "refund.succeeded", object: { payment_id: payments.get(pbc.id).id } });
  assert.equal(commerce.account("member").membership.tier, "BC");
  assert.equal(commerce.account("member").orders.find(o => o.id === pbc.id).review, 1);
  clock += 20 * DAY;
  assert.equal(commerce.account("member").balance, 622);
  const rollback = await commerce.checkout("rollbackUser", request("boblox_100"));
  wallet.db.exec("CREATE TRIGGER fail_credit BEFORE INSERT ON boblox_ledger WHEN NEW.user_id='rollbackUser' BEGIN SELECT RAISE(ABORT,'disk test'); END;");
  await assert.rejects(succeed("rollbackUser", rollback), /disk test/);
  assert.equal(wallet.read("rollbackUser").balance, 0);
  assert.equal(commerce.order("rollbackUser", rollback.id).fulfilled_ms, null);
  wallet.db.exec("DROP TRIGGER fail_credit");
  await commerce.refresh("rollbackUser", rollback.id);
  assert.equal(wallet.read("rollbackUser").balance, 100);
  const unattended = await commerce.checkout("offlineUser", request("boblox_100"));
  payments.get(unattended.id).status = "succeeded";
  payments.get(unattended.id).paid = true;
  await commerce.reconcile();
  assert.equal(wallet.read("offlineUser").balance, 100);
  await commerce.reconcile();
  assert.equal(wallet.read("offlineUser").balance, 100);
  const app = express();
  mountBoblox(app, commerce, async req => {
    if (!req.headers.authorization) throw Object.assign(new Error("Sign in"), { status: 401 });
    return { record: { id: req.headers.authorization, email: "buyer@example.com" } };
  });
  server = app.listen(0, "127.0.0.1");
  await new Promise(resolve => server.once("listening", resolve));
  const base = "http://127.0.0.1:" + server.address().port + "/api/boblox";
  assert.equal((await fetch(base + "/wallet")).status, 401);
  const catalogResponse = await (await fetch(base + "/catalog")).json();
  assert.equal(catalogResponse.sales_enabled, true);
  assert.equal(catalogResponse.test, true);
  assert.equal(JSON.stringify(catalogResponse).includes("test-secret"), false);
  assert.equal((await fetch(base + "/orders/" + order.id + "/refresh", { method: "POST", headers: { Authorization: "player2" } })).status, 404);
  assert.equal((await fetch(base + "/return")).status, 200);
  assert.equal(wallet.read("player1").balance, 100);
  console.log("[boblox-commerce] PASS: HTTP routes, provider request, tampering, duplicate callbacks, restart, lost response, cancellation, atomic rollback, daily catch-up, renewal, expiry, refund review");
} finally {
  if (server) await new Promise(resolve => server.close(resolve));
  wallet.close();
  rmSync(folder, { recursive: true }); // Only the directory created by this test.
}
