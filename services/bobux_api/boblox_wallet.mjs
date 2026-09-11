import { DatabaseSync } from "node:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

// Platform money is never accepted from a place, Lua script, or client balance.
// Only trusted server code can call apply(); client balances are never accepted.
export class BobloxWallet {
  constructor(filename) {
    if (filename !== ":memory:") mkdirSync(dirname(filename), { recursive: true });
    this.db = new DatabaseSync(filename);
    this.db.exec(`PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS boblox_accounts (
        user_id TEXT PRIMARY KEY, balance INTEGER NOT NULL DEFAULT 0 CHECK(balance >= 0 AND balance <= 9007199254740991)
      ) STRICT;
      CREATE TABLE IF NOT EXISTS boblox_ledger (
        sequence INTEGER PRIMARY KEY, operation_id TEXT NOT NULL UNIQUE,
        user_id TEXT NOT NULL REFERENCES boblox_accounts(user_id),
        amount INTEGER NOT NULL, balance_after INTEGER NOT NULL CHECK(balance_after >= 0),
        reason TEXT NOT NULL, created_at TEXT NOT NULL
      ) STRICT;
      CREATE INDEX IF NOT EXISTS boblox_ledger_user ON boblox_ledger(user_id, sequence);
      CREATE TRIGGER IF NOT EXISTS boblox_ledger_no_update BEFORE UPDATE ON boblox_ledger BEGIN SELECT RAISE(ABORT, 'ledger is immutable'); END;
      CREATE TRIGGER IF NOT EXISTS boblox_ledger_no_delete BEFORE DELETE ON boblox_ledger BEGIN SELECT RAISE(ABORT, 'ledger is immutable'); END;
      PRAGMA user_version=1;`);
  }

  read(userId) {
    validateUser(userId);
    const row = this.db.prepare("SELECT balance FROM boblox_accounts WHERE user_id=?").get(userId);
    return { currency: "BOBLOX", balance: row?.balance ?? 0 };
  }

  history(userId, limit = 30) {
    validateUser(userId);
    return this.db.prepare("SELECT operation_id, amount, balance_after, reason, created_at FROM boblox_ledger WHERE user_id=? ORDER BY sequence DESC LIMIT ?")
      .all(userId, Math.max(1, Math.min(100, Math.floor(Number(limit) || 30))));
  }

  apply({ userId, amount, operationId, reason }) {
    return this.transaction(() => this.applyInTransaction({ userId, amount, operationId, reason }));
  }

  transaction(callback) {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const result = callback();
      this.db.exec("COMMIT");
      return result;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  // Internal to server transactions: payment, entitlement and credit commit together.
  applyInTransaction({ userId, amount, operationId, reason }) {
    validateUser(userId);
    if (!Number.isSafeInteger(amount) || amount === 0 || Math.abs(amount) > 1_000_000_000) throw new Error("Invalid integer amount");
    if (typeof operationId !== "string" || !/^[A-Za-z0-9_:-]{8,160}$/.test(operationId)) throw new Error("Invalid operation ID");
    if (typeof reason !== "string" || reason.length < 1 || reason.length > 160) throw new Error("Invalid operation reason");
      const previous = this.db.prepare("SELECT * FROM boblox_ledger WHERE operation_id=?").get(operationId);
      if (previous) {
        if (previous.user_id !== userId || previous.amount !== amount || previous.reason !== reason) throw new Error("Idempotency conflict");
        return { currency: "BOBLOX", balance: previous.balance_after, operationId, applied: false };
      }
      this.db.prepare("INSERT INTO boblox_accounts(user_id) VALUES (?) ON CONFLICT DO NOTHING").run(userId);
      const balance = this.read(userId).balance + amount;
      if (!Number.isSafeInteger(balance) || balance < 0) throw new Error("Insufficient Boblox or balance overflow");
      this.db.prepare("UPDATE boblox_accounts SET balance=? WHERE user_id=?").run(balance, userId);
      this.db.prepare("INSERT INTO boblox_ledger(operation_id,user_id,amount,balance_after,reason,created_at) VALUES (?,?,?,?,?,?)")
        .run(operationId, userId, amount, balance, reason, new Date().toISOString());
      return { currency: "BOBLOX", balance, operationId, applied: true };
  }

  close() { this.db.close(); }
}

function validateUser(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) throw new Error("Invalid wallet user ID");
}
