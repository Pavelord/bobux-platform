import express from 'express';
import { createHash } from 'node:crypto';

const fail = (message, status = 400) => Object.assign(new Error(message), { status });
export class PlaceCommerce {
  constructor(wallet, now = Date.now) {
    this.wallet = wallet;
    this.now = now;
    wallet.db.exec(`CREATE TABLE IF NOT EXISTS bobux_place_passes (
      user_id TEXT NOT NULL, map_id TEXT NOT NULL, product TEXT NOT NULL,
      price INTEGER NOT NULL, purchased_ms INTEGER NOT NULL,
      PRIMARY KEY(user_id,map_id,product)) STRICT;`);
  }
  owned(user, map) {
    return user === map.owner || !!this.wallet.db.prepare('SELECT 1 FROM bobux_place_passes WHERE user_id=? AND map_id=? AND product=?').get(user, map.id, 'boost_coin_v1');
  }
  status(user, map) {
    const day = new Date(this.now()).toISOString().slice(0, 10);
    const operation = `place-daily:${user}:${day}`;
    return { owned: this.owned(user, map), price: map.price, daily_enabled: map.daily,
      daily_amount: 10, daily_claimed: !!this.wallet.db.prepare('SELECT 1 FROM boblox_ledger WHERE operation_id=?').get(operation),
      next_daily_ms: Date.parse(day) + 86400000, ...this.wallet.read(user) };
  }
  claim(user, map) {
    if (!map.daily) throw fail('В этом режиме нет ежедневной награды.');
    const day = new Date(this.now()).toISOString().slice(0, 10);
    const credit = this.wallet.apply({ userId: user, amount: 10, operationId: `place-daily:${user}:${day}`, reason: 'platform:daily_reward' });
    return { ...this.status(user, map), applied: credit.applied };
  }
  purchase(user, map, expectedPrice) {
    if (!Number.isSafeInteger(map.price) || map.price < 1 || map.price > 1000000) throw fail('Геймпасс не опубликован.');
    if (expectedPrice !== map.price) throw fail('Цена изменилась. Откройте покупку заново.', 409);
    return this.wallet.transaction(() => {
      if (this.owned(user, map)) return { ...this.status(user, map), purchased: false };
      const key = createHash('sha256').update(`${map.id}\0boost_coin_v1\0${user}`).digest('hex');
      this.wallet.applyInTransaction({ userId: user, amount: -map.price, operationId: `pass-buy:${key}`, reason: 'place:boost_coin_v1' });
      const revenue = Math.floor(map.price * 0.7);
      if (revenue > 0) this.wallet.applyInTransaction({ userId: map.owner, amount: revenue, operationId: `pass-sale:${key}`, reason: 'place:creator_revenue' });
      this.wallet.db.prepare('INSERT INTO bobux_place_passes VALUES (?,?,?,?,?)').run(user, map.id, 'boost_coin_v1', map.price, this.now());
      return { ...this.status(user, map), purchased: true };
    });
  }
}

export function definition(id, owner, data) {
  let price = 0, daily = false;
  for (const section of ['instances', 'gui']) {
    for (const entry of data?.roblox_manifest?.[section] || []) {
      const attrs = entry?.properties?.Attributes || {};
      if (attrs.PrefabId === 'daily_boblox') daily = true;
      if (attrs.PrefabId === 'gamepass_coin') {
        const value = Number(attrs.Price ?? 150);
        if (Number.isSafeInteger(value) && value >= 1 && value <= 1000000) price = value;
      }
    }
  }
  return { id, owner, price, daily };
}

export function mountPlaceCommerce(app, wallet, authenticate, resolveMap) {
  const store = wallet ? new PlaceCommerce(wallet) : null;
  const route = action => async (req, res) => {
    res.set('Cache-Control', 'private, no-store');
    try {
      if (!store) throw fail('Кошелёк временно недоступен.', 503);
      let auth;
      try { auth = await authenticate(req); }
      catch { throw fail('Войдите в аккаунт Bobux.', 401); }
      const user = auth?.record;
      if (!user?.id || user.email?.endsWith('@anon.bobux.local')) throw fail('Войдите в аккаунт Bobux.', 401);
      const mapId = String(req.body?.map_id ?? req.query.map_id ?? '');
      if (!mapId || mapId.length > 200) throw fail('Некорректный режим.');
      const map = await resolveMap(mapId);
      if (!map) throw fail('Сначала опубликуйте режим с этой механикой.', 404);
      res.json({ ok: true, ...action(store, user.id, map, req.body || {}) });
    } catch (error) { res.status(Number(error.status) || 400).json({ ok: false, error: error.message }); }
  };
  app.get('/api/boblox/place/status', route((s,u,m) => s.status(u,m)));
  app.post('/api/boblox/place/daily', express.json({limit:'2kb'}), route((s,u,m) => s.claim(u,m)));
  app.post('/api/boblox/place/purchase', express.json({limit:'2kb'}), route((s,u,m,b) => s.purchase(u,m,b.expected_price)));
}
