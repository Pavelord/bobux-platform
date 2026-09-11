import { DatabaseSync } from 'node:sqlite';
import express from 'express';

const error = (status, message) => Object.assign(new Error(message), { status });
const id = value => {
  const result = String(value || '');
  if (!/^[a-zA-Z0-9_:-]{1,160}$/.test(result)) throw error(400, 'Invalid identifier.');
  return result;
};

export class SocialStore {
  constructor(filename, now = Date.now) {
    this.now = now;
    this.db = new DatabaseSync(filename);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS direct_messages (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, sender TEXT NOT NULL, recipient TEXT NOT NULL,
        body TEXT NOT NULL, request_id TEXT NOT NULL, created_ms INTEGER NOT NULL,
        UNIQUE(sender, request_id));
      CREATE INDEX IF NOT EXISTS message_pair ON direct_messages(sender, recipient, seq);
      CREATE INDEX IF NOT EXISTS message_rate ON direct_messages(sender, created_ms);
      CREATE TABLE IF NOT EXISTS map_votes (map_id TEXT NOT NULL, user_id TEXT NOT NULL,
        vote INTEGER NOT NULL CHECK(vote IN (-1,1)), PRIMARY KEY(map_id,user_id));`);
  }
  close() { this.db.close(); }
  send(sender, recipient, body, requestId) {
    id(sender); id(recipient); id(requestId);
    if (sender === recipient) throw error(400, 'Choose a friend.');
    if (typeof body !== 'string' || !body.trim() || body.length > 2000) throw error(400, 'Message must contain 1–2000 characters.');
    const text = body.trim();
    const prior = this.db.prepare('SELECT * FROM direct_messages WHERE sender=? AND request_id=?').get(sender, requestId);
    if (prior) {
      if (prior.recipient !== recipient || prior.body !== text) throw error(409, 'Request already used.');
      return prior;
    }
    const recent = this.db.prepare('SELECT count(*) AS n FROM direct_messages WHERE sender=? AND created_ms>?').get(sender, this.now() - 60000);
    if (recent.n >= 30) throw error(429, 'Too many messages. Try again in a minute.');
    const result = this.db.prepare('INSERT INTO direct_messages(sender,recipient,body,request_id,created_ms) VALUES(?,?,?,?,?)').run(sender,recipient,text,requestId,this.now());
    return this.db.prepare('SELECT * FROM direct_messages WHERE seq=?').get(result.lastInsertRowid);
  }
  history(user, peer, { before = 0, after = 0 } = {}) {
    id(user); id(peer);
    if (!Number.isSafeInteger(before) || !Number.isSafeInteger(after) || before < 0 || after < 0 || (before && after)) throw error(400, 'Invalid cursor.');
    const where = after ? 'seq > ?' : 'seq < ?';
    const order = after ? 'ASC' : 'DESC';
    const rows = this.db.prepare(`SELECT seq,sender,recipient,body,created_ms FROM direct_messages WHERE
      ((sender=? AND recipient=?) OR (sender=? AND recipient=?)) AND ${where} ORDER BY seq ${order} LIMIT 50`)
      .all(user,peer,peer,user, after || before || Number.MAX_SAFE_INTEGER);
    if (!after) rows.reverse();
    return { messages: rows, has_more: rows.length === 50 };
  }
  seedLikes(rows) {
    const insert = this.db.prepare('INSERT OR IGNORE INTO map_votes(map_id,user_id,vote) VALUES(?,?,1)');
    for (const row of rows) if (row.target_type === 'map' && row.target_id && row.user_id) insert.run(row.target_id, row.user_id);
  }
  rating(mapId) {
    const row = this.db.prepare('SELECT sum(vote=1) AS positive, sum(vote=-1) AS negative FROM map_votes WHERE map_id=?').get(mapId);
    return { rating_positive: Number(row.positive || 0), rating_negative: Number(row.negative || 0) };
  }
  vote(user, mapId, value) {
    id(user); id(mapId);
    if (value !== 1 && value !== -1) throw error(400, 'Vote must be 1 or -1.');
    this.db.prepare('INSERT INTO map_votes(map_id,user_id,vote) VALUES(?,?,?) ON CONFLICT(map_id,user_id) DO UPDATE SET vote=excluded.vote').run(mapId,user,value);
    return { ...this.rating(mapId), user_vote: value };
  }
}

export function mountSocial(app, store, { authenticate, areFriends, isPublicMap }) {
  const authenticated = handler => async (req, res) => {
    try {
      let user;
      try { user = await authenticate(req); } catch { throw error(401, 'Sign in to continue.'); }
      if (!user?.record?.id || String(user.record.email || '').endsWith('@anon.bobux.local')) throw error(401, 'Sign in to continue.');
      await handler(req, res, user.record.id);
    } catch (e) { res.status(e.status || 500).json({ error: e.status ? e.message : 'Could not complete this request.' }); }
  };
  const friend = async (user, peer) => {
    id(peer);
    if (!await areFriends(user, peer)) throw error(403, 'Messages are available between friends.');
  };
  app.get('/api/social/messages/:peer', authenticated(async (req,res,user) => {
    await friend(user, req.params.peer);
    res.set('Cache-Control','no-store').json(store.history(user,req.params.peer,{before:Number(req.query.before || 0),after:Number(req.query.after || 0)}));
  }));
  app.post('/api/social/messages/:peer', express.json({limit:'12kb'}), authenticated(async (req,res,user) => {
    await friend(user,req.params.peer);
    const message = store.send(user,req.params.peer,req.body?.text,req.body?.request_id);
    res.set('Cache-Control','no-store').json({message});
  }));
  app.post('/api/social/maps/:map/vote', express.json({limit:'1kb'}), authenticated(async (req,res,user) => {
    if (!await isPublicMap(id(req.params.map))) throw error(404,'Experience not found.');
    res.json(store.vote(user,req.params.map,req.body?.vote));
  }));
}
