// Audio capsules: voice notes left at a spot, found nearby, reportable.
import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../lib/app.js';
import { createMemoryStore } from './memory_store.js';

const verifyToken = async (t) => {
  if (!t.startsWith('good-')) throw new Error('bad token');
  return t.slice(5);
};
// alice and bob are friends; carol is not.
const getFriends = async (uid) =>
  ({ alice: ['bob'], bob: ['alice'] })[uid] ?? [];

const AUDIO = Buffer.from('00000020667479704d344120', 'hex'); // m4a header
const GHAT = { lat: 25.2900, lng: 83.0060 };
const id = (n) => `cccccccc-${String(n).padStart(4, '0')}-4111-8111-cccccccccccc`;

describe('audio capsules', () => {
  let server, base, store;
  before(() => {
    store = createMemoryStore();
    const app = createApp({ verifyToken, store, mediaSecret: 's', getFriends });
    server = app.listen(0);
    base = `http://127.0.0.1:${server.address().port}`;
  });
  after(() => server.close());

  const as = (uid) => ({ authorization: `Bearer good-${uid}` });
  const leave = (uid, n, { at = GHAT, visibility = 'public', body = AUDIO, type = 'voice' } = {}) => {
    const q = new URLSearchParams({
      type, visibility, displayName: uid, caption: `Capsule ${n}`,
      ...(at ? { lat: at.lat, lng: at.lng } : {}),
    });
    return fetch(`${base}/memories/${id(n)}?${q}`, {
      method: 'PUT',
      headers: { ...as(uid), 'content-type': 'audio/mp4' },
      body,
    });
  };
  const nearby = async (uid, at = GHAT, radius) => {
    const q = new URLSearchParams({ lat: at.lat, lng: at.lng, ...(radius ? { radius } : {}) });
    const r = await fetch(`${base}/memories/nearby?${q}`, { headers: as(uid) });
    return { status: r.status, body: await r.json() };
  };

  test('a capsule needs a location', async () => {
    const r = await leave('alice', 1, { at: null });
    assert.equal(r.status, 400);
  });

  test('audio is refused as a photo, and over 5 MB', async () => {
    assert.equal((await leave('alice', 2, { type: 'photo' })).status, 415);
    const big = Buffer.alloc(5 * 1024 * 1024 + 1);
    assert.equal((await leave('alice', 3, { body: big })).status, 413);
  });

  test('left and found nearby, nearest first; far ones are not', async () => {
    assert.equal((await leave('alice', 10)).status, 201);
    assert.equal((await leave('alice', 11, { at: { lat: 25.2930, lng: 83.0060 } })).status, 201); // ~330 m
    assert.equal((await leave('alice', 12, { at: { lat: 25.3500, lng: 83.0060 } })).status, 201); // ~6.7 km
    const { status, body } = await nearby('carol');
    assert.equal(status, 200);
    assert.deepEqual(body.memories.map((m) => m.caption), ['Capsule 10', 'Capsule 11']);
    assert.equal(body.memories[0].type, 'voice');
    const close = await nearby('carol', GHAT, 100);
    assert.deepEqual(close.body.memories.map((m) => m.caption), ['Capsule 10']);
  });

  test('two capsules per person per spot', async () => {
    assert.equal((await leave('dave', 20)).status, 201);
    assert.equal((await leave('dave', 21)).status, 201);
    const third = await leave('dave', 22);
    assert.equal(third.status, 429);
    assert.match((await third.json()).error, /2 capsules here/);
  });

  test('friends-only capsules: friends and the owner, not strangers', async () => {
    const spot = { lat: 25.3100, lng: 83.0100 };
    assert.equal((await leave('alice', 30, { at: spot, visibility: 'friends' })).status, 201);
    const seen = async (uid) =>
      (await nearby(uid, spot, 50)).body.memories.map((m) => m.caption);
    assert.deepEqual(await seen('bob'), ['Capsule 30']);
    assert.deepEqual(await seen('alice'), ['Capsule 30']);
    assert.deepEqual(await seen('carol'), []);
  });

  test('three different reports hide a capsule; own and repeat reports do not count', async () => {
    const spot = { lat: 25.3200, lng: 83.0200 };
    assert.equal((await leave('erin', 40, { at: spot })).status, 201);
    const report = (uid) =>
      fetch(`${base}/memories/${id(40)}/report`, { method: 'POST', headers: as(uid) });
    assert.equal((await report('erin')).status, 400);
    for (const uid of ['bob', 'bob', 'carol']) assert.equal((await report(uid)).status, 200);
    const visible = async () => (await nearby('frank', spot, 50)).body.memories.length;
    assert.equal(await visible(), 1); // Two different reporters so far.
    await report('dave');
    assert.equal(await visible(), 0);
  });

  test('nearby needs a position and a login', async () => {
    const r = await fetch(`${base}/memories/nearby?lat=abc&lng=1`, { headers: as('x') });
    assert.equal(r.status, 400);
    const anon = await fetch(`${base}/memories/nearby?lat=1&lng=1`);
    assert.equal(anon.status, 401);
  });
});
