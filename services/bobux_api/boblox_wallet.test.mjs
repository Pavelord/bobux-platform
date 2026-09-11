import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { BobloxWallet } from "./boblox_wallet.mjs";

const folder = mkdtempSync(join(tmpdir(), "boblox-wallet-test-"));
const filename = join(folder, "wallet.sqlite");
let wallet = new BobloxWallet(filename);
try {
  assert.equal(wallet.read("player1").balance, 0);
  const credit = { userId: "player1", amount: 100, operationId: "test:grant:1", reason: "test_reward" };
  assert.equal(wallet.apply(credit).balance, 100);
  assert.equal(wallet.apply(credit).applied, false);
  assert.throws(() => wallet.apply({ ...credit, amount: 200 }), /conflict/);
  assert.throws(() => wallet.apply({ ...credit, userId: "player2" }), /conflict/);
  assert.throws(() => wallet.apply({ ...credit, amount: 0.5 }), /integer/);
  assert.throws(() => wallet.apply({ ...credit, amount: -101, operationId: "test:spend:1" }), /Insufficient/);
  assert.equal(wallet.read("player1").balance, 100);
  assert.equal(wallet.history("player1").length, 1);
  assert.equal(wallet.apply({ ...credit, amount: -25, operationId: "test:spend:2" }).balance, 75);
  const other = new BobloxWallet(filename);
  assert.equal(other.read("player1").balance, 75);
  assert.equal(other.apply(credit).applied, false);
  assert.equal(other.history("player2").length, 0);
  other.close();
  wallet.close();
  wallet = new BobloxWallet(filename);
  assert.equal(wallet.read("player1").balance, 75);
  assert.equal(wallet.history("player1").reduce((sum, row) => sum + row.amount, 0), 75);
  assert.throws(() => wallet.db.exec("UPDATE boblox_ledger SET amount=1000"), /immutable/);
  console.log("[boblox] persistence, idempotency, isolation, debit rollback and immutable ledger passed");
} finally {
  wallet.close();
  rmSync(folder, { recursive: true }); // mkdtemp-owned isolated test directory.
}
