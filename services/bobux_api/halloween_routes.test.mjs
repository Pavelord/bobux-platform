import assert from "node:assert/strict";
import express from "express";
import { HalloweenEvent, GIFT_ID, PUMPKIN_ID, REWARD_AT } from "./halloween_event.mjs";
import { catalogItemHandler, mountHalloweenRoutes } from "./halloween_routes.mjs";

let now = "2026-10-10T09:00:00.000Z";
// This store outlives the HTTP server/event object, just like persisted rows.
const rows = [];
const writes = [];
const adoptedUsers = [];
const ordinaryGrants = [];
const grant = async (user_id, item_id, item_type, created_at) => {
  await new Promise(resolve => setTimeout(resolve, 2));
  const row = { user_id, item_id, item_type, created_at };
  rows.push(row); writes.push(row); return row;
};
const authenticate = async req => {
  const token = req.headers.authorization;
  if (!token) throw new Error("Missing bearer token");
  const id = { "Bearer test-alice": "alice", "Bearer test-bob": "bob" }[token];
  if (!id) throw Object.assign(new Error("Invalid session"), { status: 401 });
  return { record: { id } };
};
async function openServer() {
  const event = new HalloweenEvent({ clock: () => new Date(now), readInventory: async () => rows, grant });
  const app = express();
  const dependencies = { event, authenticate, adoptProfile: async user => adoptedUsers.push(user.id) };
  mountHalloweenRoutes(app, dependencies);
  app.post("/api/rest/v1/rpc/get_catalog_item", express.json({ limit: "5mb" }), catalogItemHandler({ ...dependencies,
    grantOrdinary: async (user, item, type) => { ordinaryGrants.push({ user, item, type }); return { user_id: user }; }
  }));
  const server = app.listen(0, "127.0.0.1");
  await new Promise(resolve => server.once("listening", resolve));
  return { server, base: `http://127.0.0.1:${server.address().port}/api/rest/v1/rpc/` };
}
let running = await openServer();
async function post(route, body = {}, token = "Bearer test-alice") {
  const response = await fetch(running.base + route, { method: "POST",
    headers: { "content-type": "application/json", ...(token ? { authorization: token } : {}) }, body: JSON.stringify(body) });
  return { status: response.status, cache: response.headers.get("cache-control"), body: await response.json() };
}
async function closeServer() { await new Promise(resolve => running.server.close(resolve)); }
try {
  assert.equal((await post("halloween_event", { claim: GIFT_ID, user_id: "alice" }, "")).status, 401);
  assert.equal((await post("halloween_event", { claim: GIFT_ID }, "Bearer forged")).status, 401);
  assert.equal((await post("get_catalog_item", { item_id: GIFT_ID }, "Bearer forged")).status, 401);
  assert.equal(writes.length, 0);
  assert.equal((await post("halloween_event", { claim: PUMPKIN_ID, server_time: REWARD_AT })).status, 409);
  assert.equal((await post("get_catalog_item", { item_id: PUMPKIN_ID, user_id: "bob", created_at: "2026-10-01", server_time: REWARD_AT })).status, 409);
  assert.equal((await post("get_catalog_item", { target_id: " " + PUMPKIN_ID + " ", item_type: "model" })).status, 400);
  assert.equal((await post("halloween_event", { claim: "ordinary_hat" })).status, 400);
  assert.equal(ordinaryGrants.length, 0, "reserved event IDs never reach the ordinary catalog grant");
  const concurrent = await Promise.all(Array.from({ length: 12 }, (_, index) => index % 2
    ? post("get_catalog_item", { target_id: " " + GIFT_ID + " ", item_type: "avatar_item", user_id: "bob", created_at: "2026-01-01" })
    : post("halloween_event", { claim: GIFT_ID, user_id: "bob", server_time: "2026-01-01", created_at: "2026-01-01" })));
  assert(concurrent.every(result => [200, 201].includes(result.status) && result.body.gift_owned));
  assert(concurrent.every(result => result.cache.includes("no-store")));
  assert.equal(writes.length, 1);
  assert.deepEqual(rows[0], { user_id: "alice", item_id: GIFT_ID, item_type: "avatar_item", created_at: now });
  assert.equal((await post("halloween_event", { user_id: "alice" }, "Bearer test-bob")).body.gift_owned, false);
  assert.equal((await post("get_catalog_item", { item_id: "ordinary_hat", user_id: "bob", claim: PUMPKIN_ID })).status, 201);
  assert.deepEqual(ordinaryGrants, [{ user: "alice", item: "ordinary_hat", type: "avatar_item" }]);
  assert(adoptedUsers.every(id => ["alice", "bob"].includes(id)));
  const originalClaimTime = rows[0].created_at;
  now = REWARD_AT;
  // A new process/event object uses the same persistent store; claims remain
  // eligible and never overwrite the date that proved eligibility.
  await closeServer(); running = await openServer();
  const rewards = await Promise.all(Array.from({ length: 12 }, (_, index) => index % 2
    ? post("get_catalog_item", { item_id: PUMPKIN_ID, user_id: "bob" })
    : post("halloween_event", { claim: PUMPKIN_ID, user_id: "bob" })));
  assert(rewards.every(result => result.body.pumpkin_owned && [200, 201].includes(result.status)));
  assert.equal(writes.length, 2); assert.equal(rows[0].created_at, originalClaimTime);
  assert.equal(rows[1].user_id, "alice"); assert.equal(rows[1].item_id, PUMPKIN_ID);
  assert.equal((await post("halloween_event", { claim: GIFT_ID, server_time: "2026-10-01" }, "Bearer test-bob")).status, 409);
  assert.equal((await post("get_catalog_item", { item_id: GIFT_ID, created_at: "2026-10-01" }, "Bearer test-bob")).status, 409);
  rows.push({ user_id: "bob", item_id: GIFT_ID, item_type: "avatar_item", created_at: REWARD_AT });
  assert.equal((await post("get_catalog_item", { item_id: PUMPKIN_ID }, "Bearer test-bob")).status, 409);
  now = "2026-11-15T00:00:00Z";
  const retained = await post("halloween_event", { claim: PUMPKIN_ID });
  assert.equal(retained.status, 200); assert.equal(retained.body.pumpkin_owned, true); assert.equal(writes.length, 2);
  console.log("Halloween HTTP PASS: auth, forged user/time/date, early pumpkin, ordinary catalog bypass, concurrent mixed routes, restart persistence, Moscow boundary and permanent ownership.");
} finally { await closeServer(); }
