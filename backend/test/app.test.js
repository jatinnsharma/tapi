// The API end to end over HTTP. Runs against the in-memory store always, and
// against a real MongoDB too when MONGODB_TEST_URI is set.
import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { MongoClient } from 'mongodb';
import { createApp } from '../lib/app.js';
import { createMongoStore } from '../lib/mongo_store.js';
import { createMemoryStore } from './memory_store.js';

const SECRET = 'test-secret';
const verifyToken = async (t) => {
  if (!t.startsWith('good-')) throw new Error('bad token');
  return t.slice(5);
};

const JPEG = Buffer.from('FFD8FFE000104A4649460001', 'hex');
const ID1 = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const ID2 = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';

const stores = [{ name: 'in-memory store', make: async () => ({ store: createMemoryStore() }) }];
if (process.env.MONGODB_TEST_URI) {
  stores.push({
    name: 'real MongoDB + GridFS',
    make: async () => {
      const client = await new MongoClient(process.env.MONGODB_TEST_URI).connect();
      const db = client.db(`rwe_test_${Date.now()}`);
      const store = createMongoStore(db);
      await store.ensureIndexes();
      return { store, cleanup: async () => { await db.dropDatabase(); await client.close(); } };
    },
  });
}

for (const { name, make } of stores) {
  describe(name, () => {
    let server, base, store, cleanup;
    before(async () => {
      ({ store, cleanup } = await make());
      const app = createApp({ verifyToken, store, mediaSecret: SECRET, maxFileBytes: 1000 });
      server = app.listen(0);
      base = `http://127.0.0.1:${server.address().port}`;
    });
    after(async () => {
      server.close();
      await cleanup?.();
    });

    const as = (uid) => ({ authorization: `Bearer good-${uid}` });
    const share = (uid, id, { body = JPEG, query = {}, headers = {} } = {}) => {
      const q = new URLSearchParams({
        type: 'photo', visibility: 'friends', displayName: uid, ...query,
      });
      return fetch(`${base}/memories/${id}?${q}`, {
        method: 'PUT',
        headers: { ...as(uid), 'content-type': 'image/jpeg', ...headers },
        body,
      });
    };
    const feed = async (uid, qs) => {
      const r = await fetch(`${base}/memories/feed?${qs}`, { headers: as(uid) });
      return { status: r.status, body: await r.json() };
    };

    test('health check needs no login and returns nosniff header', async () => {
      const res = await fetch(`${base}/healthz`);
      assert.equal(res.status, 200);
      assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    });

    test('svg uploads are rejected', async () => {
      const svg = Buffer.from('<svg><script>alert(1)</script></svg>');
      const r = await share('alice', 'dddddddd-4444-4444-8444-dddddddddddd', {
        body: svg,
        headers: { 'content-type': 'image/svg+xml' },
      });
      assert.equal(r.status, 415);
    });

    test('everything else needs a valid login', async () => {
      assert.equal((await fetch(`${base}/memories/feed?scope=public`)).status, 401);
      const r = await fetch(`${base}/memories/feed?scope=public`, {
        headers: { authorization: 'Bearer forged' },
      });
      assert.equal(r.status, 401);
      assert.equal((await share('x', ID1, { headers: { authorization: 'Bearer forged' } })).status, 401);
    });

    test('sharing stores the memory and its file can be fetched', async () => {
      const r = await share('alice', ID1, { query: { caption: 'Rock Garden!', lat: '30.75', lng: '76.8' } });
      assert.equal(r.status, 201);
      const m = await r.json();
      assert.equal(m.id, ID1);
      assert.equal(m.caption, 'Rock Garden!');
      assert.equal(m.latitude, 30.75);

      const file = await fetch(`${base}${m.url}`);
      assert.equal(file.status, 200);
      assert.equal(file.headers.get('content-type'), 'image/jpeg');
      assert.deepEqual(Buffer.from(await file.arrayBuffer()), JPEG);
    });

    test('a media link without a valid signature is refused', async () => {
      const m = await (await fetch(`${base}/memories/feed?scope=public`, { headers: as('bob') })).json();
      const { url } = (await (await share('alice', ID2, { query: { visibility: 'public' } })).json());
      assert.ok(m);
      const fileId = url.split('/media/')[1].split('?')[0];
      assert.equal((await fetch(`${base}/media/${fileId}`)).status, 403);
      assert.equal((await fetch(`${base}/media/${fileId}?e=9999999999&t=nope`)).status, 403);
      assert.equal((await fetch(`${base}${url.replace(/e=\d+/, 'e=1')}`)).status, 403);
    });

    test('videos can be seeked with Range', async () => {
      const video = Buffer.from('0123456789abcdefghij');
      const r = await share('alice', 'cccccccc-3333-4333-8333-cccccccccccc', {
        body: video,
        query: { type: 'video', visibility: 'public' },
        headers: { 'content-type': 'video/mp4' },
      });
      const { url } = await r.json();
      const part = await fetch(`${base}${url}`, { headers: { range: 'bytes=5-9' } });
      assert.equal(part.status, 206);
      assert.equal(part.headers.get('content-range'), 'bytes 5-9/20');
      assert.equal(await part.text(), '56789');
      const tail = await fetch(`${base}${url}`, { headers: { range: 'bytes=-4' } });
      assert.equal(await tail.text(), 'ghij');
      const bad = await fetch(`${base}${url}`, { headers: { range: 'bytes=99-120' } });
      assert.equal(bad.status, 416);
    });

    test('public feed shows public memories to anyone, never friends-only ones', async () => {
      const { body } = await feed('zoe', 'scope=public');
      const ids = body.memories.map((m) => m.id);
      assert.ok(ids.includes(ID2));
      assert.ok(!ids.includes(ID1)); // friends-only
    });

    test('friends feed shows only the friends I name, and never private/others', async () => {
      const withAlice = await feed('bob', 'scope=friends&friends=alice');
      assert.ok(withAlice.body.memories.some((m) => m.id === ID1));
      const withoutAlice = await feed('bob', 'scope=friends&friends=carol');
      assert.equal(withoutAlice.body.memories.length, 0);
      const empty = await feed('bob', 'scope=friends');
      assert.equal(empty.body.memories.length, 0);
    });

    test('server-side getFriends overrides client claimed friends', async () => {
      const mockGetFriends = async (uid) => (uid === 'bob' ? ['alice'] : []);
      const appWithFriends = createApp({ verifyToken, store, mediaSecret: SECRET, maxFileBytes: 1000, getFriends: mockGetFriends });
      const s = appWithFriends.listen(0);
      const b = `http://127.0.0.1:${s.address().port}`;
      try {
        const r1 = await fetch(`${b}/memories/feed?scope=friends&friends=carol`, { headers: as('bob') });
        const data1 = await r1.json();
        assert.equal(data1.memories.length, 0);

        const r2 = await fetch(`${b}/memories/feed?scope=friends&friends=alice`, { headers: as('bob') });
        const data2 = await r2.json();
        assert.ok(data2.memories.some((m) => m.id === ID1));

        const r3 = await fetch(`${b}/memories/feed?scope=friends`, { headers: as('bob') });
        const data3 = await r3.json();
        assert.ok(data3.memories.some((m) => m.id === ID1));
      } finally {
        s.close();
      }
    });

    test('a bad scope is refused', async () => {
      assert.equal((await feed('bob', 'scope=all')).status, 400);
    });

    test('only the owner can change, replace or delete a memory', async () => {
      const patch = (uid) => fetch(`${base}/memories/${ID1}`, {
        method: 'PATCH',
        headers: { ...as(uid), 'content-type': 'application/json' },
        body: JSON.stringify({ visibility: 'public' }),
      });
      assert.equal((await patch('mallory')).status, 403);
      assert.equal((await share('mallory', ID1)).status, 403);
      const del = await fetch(`${base}/memories/${ID1}`, { method: 'DELETE', headers: as('mallory') });
      assert.equal(del.status, 403);
      // still there
      assert.ok((await feed('bob', 'scope=friends&friends=alice')).body.memories.some((m) => m.id === ID1));
    });

    test('the owner can change who sees it without uploading again', async () => {
      const r = await fetch(`${base}/memories/${ID1}`, {
        method: 'PATCH',
        headers: { ...as('alice'), 'content-type': 'application/json' },
        body: JSON.stringify({ visibility: 'public', caption: '  Updated  ' }),
      });
      assert.equal(r.status, 200);
      const m = await r.json();
      assert.equal(m.visibility, 'public');
      assert.equal(m.caption, 'Updated');
      assert.ok((await feed('zoe', 'scope=public')).body.memories.some((x) => x.id === ID1));
      const bad = await fetch(`${base}/memories/${ID1}`, {
        method: 'PATCH',
        headers: { ...as('alice'), 'content-type': 'application/json' },
        body: JSON.stringify({ visibility: 'private' }),
      });
      assert.equal(bad.status, 400);
    });

    test('re-sharing replaces the file and leaves no orphan', async () => {
      const before = store.fileCount?.();
      const r = await share('alice', ID1, { body: Buffer.concat([JPEG, JPEG]), query: { visibility: 'public' } });
      assert.equal(r.status, 200);
      if (before !== undefined) assert.equal(store.fileCount(), before);
      const { url } = await r.json();
      const file = await fetch(`${base}${url}`);
      assert.equal((await file.arrayBuffer()).byteLength, JPEG.length * 2);
    });

    test('bad input is refused', async () => {
      assert.equal((await share('alice', 'short')).status, 400);
      assert.equal((await share('alice', ID2, { query: { type: 'audio' } })).status, 400);
      assert.equal((await share('alice', ID2, { query: { visibility: 'private' } })).status, 400);
      assert.equal((await share('alice', ID2, { headers: { 'content-type': 'text/html' } })).status, 415);
      assert.equal((await share('alice', ID2, { query: { type: 'video' } })).status, 415); // image sent as video
      assert.equal((await share('alice', 'dddddddd-4444-4444-8444-dddddddddddd', { body: Buffer.alloc(0) })).status, 400);
    });

    test('a file over the size limit is refused and nothing is kept', async () => {
      const files = store.fileCount?.();
      const r = await share('alice', 'eeeeeeee-5555-4555-8555-eeeeeeeeeeee', { body: Buffer.alloc(2000, 1) });
      assert.equal(r.status, 413);
      assert.equal((await feed('zoe', 'scope=public')).body.memories.some((m) => m.id.startsWith('eeeeeeee')), false);
      if (files !== undefined) assert.equal(store.fileCount(), files);
    });

    test('deleting removes the record and the file', async () => {
      const m = await (await share('dave', 'ffffffff-6666-4666-8666-ffffffffffff', { query: { visibility: 'public' } })).json();
      const before = store.fileCount?.();
      const r = await fetch(`${base}/memories/ffffffff-6666-4666-8666-ffffffffffff`, { method: 'DELETE', headers: as('dave') });
      assert.deepEqual(await r.json(), { deleted: 1 });
      assert.equal((await fetch(`${base}${m.url}`)).status, 404);
      if (before !== undefined) assert.equal(store.fileCount(), before - 1);
      const again = await fetch(`${base}/memories/ffffffff-6666-4666-8666-ffffffffffff`, { method: 'DELETE', headers: as('dave') });
      assert.deepEqual(await again.json(), { deleted: 0 });
    });

    test('deleting an account removes all of that person\'s memories', async () => {
      await share('erin', '11111111-7777-4777-8777-111111111111', { query: { visibility: 'public' } });
      await share('erin', '22222222-7777-4777-8777-222222222222');
      const r = await fetch(`${base}/memories`, { method: 'DELETE', headers: as('erin') });
      assert.deepEqual(await r.json(), { deleted: 2 });
      assert.equal((await feed('zoe', 'scope=friends&friends=erin')).body.memories.length, 0);
    });
  });
}
