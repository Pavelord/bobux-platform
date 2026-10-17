import assert from "node:assert/strict";
import { normalizeReadQuery, pageReadRows } from "./map_list_query.mjs";

const rows = Array.from({ length: 450 }, (_, id) => ({ id }));
const first = normalizeReadQuery("maps", {});
assert.equal(pageReadRows(rows, first).length, 100);
assert.ok(first.select.includes("thumbnail") && !first.select.split(",").includes("data"));
const second = pageReadRows(rows, normalizeReadQuery("maps", { offset: "100" }));
assert.equal(second[0].id, 100);
assert.equal(second.at(-1).id, 199);
assert.equal(pageReadRows(rows, normalizeReadQuery("maps", { limit: "900000" })).length, 200);
assert.deepEqual(pageReadRows(rows, { limit: "0", offset: "100" }), []);
assert.equal(pageReadRows(rows, { limit: 1, offset: -10 })[0].id, 0);
assert.equal(pageReadRows(rows, { limit: 1, offset: "bad" })[0].id, 0);
assert.deepEqual(normalizeReadQuery("maps", { id: "eq.mode", select: "data", limit: "1" }), { id: "eq.mode", select: "data", limit: "1" });
assert.equal(normalizeReadQuery("maps", { select: "id,name" }).select, "id,name");
assert.deepEqual(normalizeReadQuery("profiles", { select: "id" }), { select: "id" });
console.log("[map-list] PASS bounded metadata, adjacent pages, offsets, detail queries");
