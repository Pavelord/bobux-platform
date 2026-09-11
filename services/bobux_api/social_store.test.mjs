import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import express from 'express';
import { SocialStore, mountSocial } from './social_store.mjs';

const directory = mkdtempSync(join(tmpdir(), 'bobux-social-'));
const filename = join(directory, 'social.sqlite');
let clock = 1000000;
let store = new SocialStore(filename, () => clock);
const pairs = new Set(['alice:bob']);
const app = express();
mountSocial(app, store, {
  authenticate: async req => {
    const token = req.get('Authorization')?.replace('Bearer ', '');
    if (!['alice', 'bob', 'eve', 'guest'].includes(token)) throw new Error('invalid token');
    return {record:{id:token,email:token === 'guest' ? 'x@anon.bobux.local' : `${token}@example.invalid`}};
  },
  areFriends: async (a,b) => pairs.has([a,b].sort().join(':')),
  isPublicMap: async id => id === 'public_map'
});
const server = app.listen(0, '127.0.0.1');
await new Promise(resolve => server.once('listening', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
const request = async (user, path, payload) => {
  const response = await fetch(base + '/api/social' + path, {method:payload ? 'POST' : 'GET',
    headers:{'Authorization':`Bearer ${user}`,'Content-Type':'application/json'},body:payload ? JSON.stringify(payload) : undefined});
  return {status:response.status,body:await response.json()};
};
try {
  assert.equal((await request('', '/messages/bob')).status, 401);
  assert.equal((await request('guest', '/messages/bob')).status, 401);
  const payload = {text:'Привет! [b]Literal text[/b]', request_id:'send_1',sender:'eve'};
  const replies = await Promise.all(Array.from({length:6}, () => request('alice','/messages/bob',payload)));
  assert.ok(replies.every(r => r.status === 200));
  assert.equal(new Set(replies.map(r => r.body.message.seq)).size,1);
  assert.equal(replies[0].body.message.sender,'alice');
  assert.equal((await request('alice','/messages/bob',{...payload,text:'different'})).status,409);
  const inbox = await request('bob','/messages/alice');
  assert.equal(inbox.body.messages.length,1);
  assert.equal(inbox.body.messages[0].body,payload.text);
  assert.equal((await request('eve','/messages/alice')).status,403);
  assert.equal((await request('alice','/messages/eve',payload)).status,403);
  assert.equal((await request('alice','/messages/bob?before=-1')).status,400);
  assert.equal((await request('alice','/messages/bob',{text:' '.repeat(10),request_id:'blank'})).status,400);
  assert.equal((await request('alice','/messages/bob',{text:'a'.repeat(2001),request_id:'large'})).status,400);
  pairs.clear();
  assert.equal((await request('bob','/messages/alice')).status,403);
  assert.equal((await request('alice','/messages/bob',{text:'blocked',request_id:'removed'})).status,403);
  pairs.add('alice:bob');
  for (let i=0;i<29;i++) store.send('alice','bob',`message ${i}`,`batch_${i}`);
  assert.throws(() => store.send('alice','bob','flood','flood'), e=>e.status===429);
  clock += 60001;
  for (let i=29;i<59;i++) store.send('alice','bob',`message ${i}`,`batch_${i}`);
  const page = store.history('alice','bob');
  assert.equal(page.messages.length,50);
  assert.ok(page.has_more);
  assert.equal(store.history('alice','bob',{before:page.messages[0].seq}).messages.length,10);
  assert.equal(store.history('bob','alice',{after:page.messages.at(-1).seq}).messages.length,0);
  const legacy = [{target_type:'map',target_id:'public_map',user_id:'bob'}];
  store.seedLikes(legacy); store.seedLikes(legacy);
  assert.equal(store.rating('public_map').rating_positive,1);
  assert.equal((await request('alice','/maps/private_map/vote',{vote:1})).status,404);
  assert.equal((await request('alice','/maps/public_map/vote',{vote:2})).status,400);
  await request('alice','/maps/public_map/vote',{vote:1});
  await request('alice','/maps/public_map/vote',{vote:1});
  const changed = await request('alice','/maps/public_map/vote',{vote:-1});
  assert.deepEqual(changed.body,{rating_positive:1,rating_negative:1,user_vote:-1});
  store.close();
  store = new SocialStore(filename);
  assert.equal(store.history('alice','bob').messages.length,50);
  assert.equal(store.rating('public_map').rating_negative,1);
  console.log('[social_store] PASS: two users, access control, persistence, idempotency, pagination, rate limit, votes');
} finally {
  await new Promise(resolve=>server.close(resolve));
  store.close();
  rmSync(directory,{recursive:true,force:true});
}
