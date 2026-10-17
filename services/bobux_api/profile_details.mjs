import express from 'express';

const fail = (status, message) => Object.assign(new Error(message), { status });
const cleanId = value => {
  if (typeof value !== 'string' || !value.trim() || value.length > 256) throw fail(400, 'Invalid profile or experience id.');
  return value.trim();
};

// Share the existing social SQLite connection. Neither profile edits nor visit
// history write author maps, inventory, avatar data, or account registration dates.
export class ProfileDetailsStore {
  constructor(db, now = () => Date.now()) {
    this.db = db;
    this.now = now;
    db.exec(`CREATE TABLE IF NOT EXISTS profile_about (
      user_id TEXT PRIMARY KEY, bio TEXT NOT NULL, updated_ms INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS profile_visits (
      user_id TEXT NOT NULL, map_id TEXT NOT NULL, first_seen_ms INTEGER NOT NULL,
      PRIMARY KEY(user_id,map_id));`);
    this.readAbout = db.prepare('SELECT bio FROM profile_about WHERE user_id=?');
    this.writeAbout = db.prepare('INSERT INTO profile_about(user_id,bio,updated_ms) VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET bio=excluded.bio, updated_ms=excluded.updated_ms');
    this.countVisits = db.prepare('SELECT count(*) AS n FROM profile_visits WHERE user_id=?');
    this.insertVisit = db.prepare('INSERT OR IGNORE INTO profile_visits(user_id,map_id,first_seen_ms) VALUES(?,?,?)');
  }
  details(user) {
    cleanId(user);
    return { bio: this.readAbout.get(user)?.bio || '', visited_modes_count: Number(this.countVisits.get(user).n) };
  }
  updateAbout(user, bio) {
    cleanId(user);
    if (typeof bio !== 'string' || [...bio].length > 1000) throw fail(400, 'Description must contain at most 1000 characters.');
    const text = bio.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '').trim();
    this.writeAbout.run(user, text, this.now());
    return this.details(user);
  }
  recordVisit(user, map) {
    this.insertVisit.run(cleanId(user), cleanId(map), this.now());
    return this.details(user);
  }
}

export function mountProfileDetails(app, store, { authenticate, loadProfile, loadAccount, resolveVisitedMap }) {
  const route = handler => async (req, res) => {
    try {
      let actor;
      try { actor = await authenticate(req); } catch { throw fail(401, 'Sign in to continue.'); }
      if (!actor?.record?.id) throw fail(401, 'Sign in to continue.');
      res.set('Cache-Control', 'private, no-store');
      await handler(req, res, actor.record);
    } catch (error) { res.status(error.status || 500).json({ message: error.status ? error.message : 'Could not load the profile. Try again.' }); }
  };
  app.post('/api/rest/v1/rpc/profile_details', express.json({ limit: '4kb' }), route(async (req, res, actor) => {
    const target = cleanId(req.body?.user_id || actor.id);
    const profile = await loadProfile(target);
    if (!profile) throw fail(404, 'Player profile was not found.');
    // Prefer the immutable auth account date to a profile recreated during an
    // old account migration. Never accept a client-supplied registration date.
    const account = target === actor.id ? actor : await loadAccount(target);
    const joined = account?.created || profile.created_at || profile.created || '';
    res.json({ id: target, join_date: joined, ...store.details(target) });
  }));
  app.post('/api/rest/v1/rpc/update_profile_about', express.json({ limit: '8kb' }), route(async (req, res, actor) => {
    if (String(actor.email || '').endsWith('@anon.bobux.local')) throw fail(401, 'Sign in to edit your description.');
    res.json({ id: actor.id, ...store.updateAbout(actor.id, req.body?.bio) });
  }));
  app.post('/api/rest/v1/rpc/record_profile_visit', express.json({ limit: '4kb' }), route(async (req, res, actor) => {
    const map = await resolveVisitedMap(cleanId(req.body?.map_id), actor.id);
    if (!map) throw fail(404, 'Experience was not found.');
    res.json({ id: actor.id, ...store.recordVisit(actor.id, map) });
  }));
  app.post('/api/rest/v1/rpc/import_recent_profile_visits', express.json({ limit: '4kb' }), route(async (req, res, actor) => {
    const ids = req.body?.map_ids;
    if (!Array.isArray(ids) || ids.length > 8) throw fail(400, 'Invalid recent experience history.');
    const maps = [...new Set(ids.map(cleanId))];
    for (const id of maps) {
      const map = await resolveVisitedMap(id, actor.id);
      if (map) store.recordVisit(actor.id, map);
    }
    res.json({ id: actor.id, ...store.details(actor.id) });
  }));
}
