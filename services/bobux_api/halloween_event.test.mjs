import assert from "node:assert/strict";
import { HalloweenEvent, eventCatalog, GIFT_ID, PUMPKIN_ID, isHalloweenItem, assertEventInventoryWrite, REWARD_AT } from "./halloween_event.mjs";
let now = "2026-10-30T20:59:59.999Z";
const rows = [];
let writes = 0;
const event = new HalloweenEvent({ clock: () => new Date(now), readInventory: async () => rows,
  grant: async (user_id, item_id, item_type, created_at) => {
    await new Promise(resolve => setTimeout(resolve, 2));
    const row = { user_id, item_id, item_type, created_at }; rows.push(row); writes++; return row;
  } });
await assert.rejects(event.state(""), { status: 401 });
await assert.rejects(event.state("early", PUMPKIN_ID), { status: 409 });
const states = await Promise.all(Array.from({ length: 16 }, () => event.state("player", GIFT_ID)));
assert(states.every(state => state.gift_owned && state.eligible_for_pumpkin));
assert.equal(writes, 1); assert.equal(rows[0].created_at, now);
now = REWARD_AT;
await assert.rejects(event.state("late", GIFT_ID), { status: 409 });
const rewards = await Promise.all(Array.from({ length: 16 }, () => event.state("player", PUMPKIN_ID)));
assert(rewards.every(state => state.pumpkin_owned)); assert.equal(writes, 2);
assert.equal(rows[0].created_at, "2026-10-30T20:59:59.999Z");
rows.push({ user_id: "forged", item_id: GIFT_ID, item_type: "avatar_item", created_at: REWARD_AT });
rows.push({ user_id: "wrong_type", item_id: GIFT_ID, item_type: "model", created_at: "2026-10-10T00:00:00Z" });
assert.equal((await event.state("forged")).eligible_for_pumpkin, false);
assert.equal((await event.state("wrong_type")).gift_owned, false);
now = "2026-11-15T00:00:00Z";
await event.reconcileAll(); assert.equal(writes, 2);
assert.equal((await event.state("player")).pumpkin_owned, true);
assert(isHalloweenItem(GIFT_ID) && isHalloweenItem(PUMPKIN_ID) && !isHalloweenItem("ordinary"));
for (const id of [GIFT_ID, PUMPKIN_ID]) {
  assert.throws(() => assertEventInventoryWrite("user_inventory", [{ item_id: id }]), { status: 403 });
  assert.throws(() => assertEventInventoryWrite("user_inventory", [{ created_at: "2026-10-01" }], [{ item_id: id }]), { status: 403 });
  assert.throws(() => assertEventInventoryWrite("user_inventory", [], [{ item_id: id }]), { status: 403 });
}
assertEventInventoryWrite("user_inventory", [{ item_id: "ordinary" }]);
assert(eventCatalog().every(item => ["Head", "HeadCenter"].includes(item.attachment_slot) && item.source_url.endsWith(".glb") && item.data.limited));
assert.equal(eventCatalog().find(item => item.id === PUMPKIN_ID).attachment_slot, "HeadCenter");
assert.equal(eventCatalog().find(item => item.id === PUMPKIN_ID).data.covers_head, true);
assert.equal(eventCatalog().find(item => item.id === GIFT_ID).name, "Coffin Gift Box - Halloween");
assert.equal(eventCatalog().find(item => item.id === PUMPKIN_ID).name, "Pumpkin");
assert(!/тыкв|pumpkin|31 окт/iu.test(eventCatalog().find(item => item.id === GIFT_ID).description));
now = "2026-09-30T20:59:59Z";
await assert.rejects(event.state("before", GIFT_ID), { status: 409 });
console.log("Halloween event PASS: Moscow midnight, eligibility, authentication, 16-way concurrency, persistent idempotent rewards.");
