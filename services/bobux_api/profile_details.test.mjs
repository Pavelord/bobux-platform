import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import express from 'express';
import { ProfileDetailsStore, mountProfileDetails } from './profile_details.mjs';

const directory = mkdtempSync(join(tmpdir(), 'bobux-profile-'));
const path = join(directory, 'profiles.sqlite');
let db = new DatabaseSync(path);
let store = new ProfileDetailsStore(db, () => 123456);
const users = { alice: { id: 'alice', email: 'alice@example.invalid', created: '2026-04-01T00:00:00Z' },
  bob: { id: 'bob', email: 'bob@example.invalid', created: '2026-05-02T12:00:00Z' },
  guest: { id: 'guest', email: 'g@anon.bobux.local' } };
const app = express();
mountProfileDetails(app, store, {
  authenticate: async req => { const record = users[req.get('Authorization')?.replace('Bearer ', '')]; if (!record) throw new Error('invalid token'); return { record }; },
  loadProfile: async id => users[id] ? { id, created_at: '2026-10-01T00:00:00Z' } : null,
  loadAccount: async id => users[id],
  resolveVisitedMap: async (id, user) => ['park', 'valley', 'lift'].includes(id) || id === 'private-' + user ? id : ''
});
const server = app.listen(0, '127.0.0.1');
await new Promise(resolve => server.once('listening', resolve));
const base = `http://127.0.0.1:${server.address().port}/api/rest/v1/rpc/`;
const post = async (route, body = {}, token = 'alice') => {
  const response = await fetch(base + route, { method: 'POST', headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  return { status: response.status, data: await response.json(), cache: response.headers.get('cache-control') };
};
try {
  assert.equal((await post('profile_details', {}, '')).status, 401);
  assert.equal((await post('update_profile_about', { bio: 'hello' }, 'guest')).status, 401);
  assert.equal((await post('profile_details', { user_id: 'missing' })).status, 404);
  const description = 'Привет! [b]Plain text[/b]\nHalloween 🎃';
  const saved = await post('update_profile_about', { bio: description, user_id: 'bob', created_at: '2000-01-01', visited_modes_count: 999 });
  assert.equal(saved.status, 200); assert.equal(saved.data.id, 'alice'); assert.equal(saved.data.bio, description);
  assert.equal(store.details('bob').bio, ''); assert.equal(store.details('alice').visited_modes_count, 0);
  assert.equal((await post('update_profile_about', { bio: '😀'.repeat(1001) })).status, 400);
  assert.equal((await post('update_profile_about', { bio: {} })).status, 400);
  assert.equal((await post('profile_details', { user_id: 'alice' })).data.join_date, users.alice.created);
  assert.equal((await post('profile_details', { user_id: 'bob' })).data.join_date, users.bob.created);
  assert.equal((await post('profile_details', { user_id: 'bob' })).cache, 'private, no-store');
  for (let i = 0; i < 10; i++) await post('record_profile_visit', { map_id: 'park', user_id: 'bob' });
  assert.equal(store.details('alice').visited_modes_count, 1); assert.equal(store.details('bob').visited_modes_count, 0);
  assert.equal((await post('record_profile_visit', { map_id: 'private-bob' })).status, 404);
  assert.equal((await post('record_profile_visit', { map_id: 'missing' })).status, 404);
  await post('import_recent_profile_visits', { map_ids: ['park', 'valley', 'valley', 'lift', 'missing'] });
  assert.equal(store.details('alice').visited_modes_count, 3);
  assert.equal((await post('import_recent_profile_visits', { map_ids: Array(9).fill('park') })).status, 400);
  assert.equal(db.prepare('SELECT first_seen_ms FROM profile_visits WHERE user_id=? AND map_id=?').get('alice', 'park').first_seen_ms, 123456);
  db.close(); db = new DatabaseSync(path); store = new ProfileDetailsStore(db);
  assert.deepEqual(store.details('alice'), { bio: description, visited_modes_count: 3 });
  store.updateAbout('alice', ''); assert.equal(store.details('alice').bio, '');
  console.log('[profile_details] PASS: authenticated ownership, real registration date, Unicode description, unique validated visits, recent history, persistence');
} finally {
  await new Promise(resolve => server.close(resolve));
  db.close(); rmSync(directory, { recursive: true, force: true });
}
