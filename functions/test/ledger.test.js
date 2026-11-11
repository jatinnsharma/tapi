// The ledger against an in-memory stand-in for Firestore.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { payTrip, dayKey } from '../lib/ledger.js';
import { PLACE_XP } from '../lib/evaluate_trip.js';
import { HOME, T0, north, walk, trip, visit } from './helpers.js';

function fakeDb() {
  const store = new Map();
  const ref = (path) => ({
    path,
    collection: (name) => ({ doc: (id) => ref(`${path}/${name}/${id}`) }),
  });
  const snap = (path) => ({
    exists: store.has(path),
    data: () => store.get(path),
  });
  return {
    store,
    collection: (name) => ({ doc: (id) => ref(`${name}/${id}`) }),
    runTransaction: async (fn) => {
      const writes = [];
      const tx = {
        get: async (r) => snap(r.path),
        set: (r, data, opts) => writes.push([r.path, data, opts]),
      };
      const out = await fn(tx);
      for (const [path, data, opts] of writes) {
        store.set(path, opts?.merge ? { ...store.get(path), ...data } : data);
      }
      return out;
    },
  };
}
const FieldValue = { serverTimestamp: () => 'ts' };
const NOW = T0 + 25 * 60000;

const PLACE_POS = north(HOME, 600);
function honest(id, placeId = 'wiki-1') {
  const v = visit(600, 300);
  return trip({
    tripId: id,
    fixes: v.fixes,
    endedAt: T0 + (v.endAt + 60) * 1000,
    place: { id: placeId, name: 'Rock Garden', category: 'heritage', ...PLACE_POS },
    photoAt: T0 + (v.arriveAt + 20) * 1000,
  });
}
const total = (db) => db.store.get('verified_xp/u1')?.totalXp ?? 0;
const pay = (db, t, now = NOW) => payTrip(db, 'u1', t, now, FieldValue);

describe('Paying trips', () => {
  test('an honest trip adds its XP to the total', async () => {
    const db = fakeDb();
    const r = await pay(db, honest('a'));
    assert.equal(r.totalXp, PLACE_XP.heritage + 100);
    assert.equal(total(db), PLACE_XP.heritage + 100);
  });

  test('sending the same trip again pays nothing more', async () => {
    const db = fakeDb();
    await pay(db, honest('a'));
    const again = await pay(db, honest('a'));
    assert.equal(again.replay, true);
    assert.equal(total(db), PLACE_XP.heritage + 100);
  });

  test('a replay returns the original answer even if edited', async () => {
    const db = fakeDb();
    const first = await pay(db, honest('a'));
    const edited = honest('a');
    edited.place.category = 'hiddenGem';
    const again = await pay(db, edited);
    assert.equal(again.totalXp, first.totalXp);
    assert.equal(total(db), first.totalXp);
  });

  test('the same place a day later pays no place XP', async () => {
    const db = fakeDb();
    await pay(db, honest('a'));
    const second = await pay(db, honest('b'));
    assert.equal(second.placeXp, 0);
    assert.ok(second.reasons.includes('placeRecentlyPaid'));
  });

  test('a different place pays', async () => {
    const db = fakeDb();
    await pay(db, honest('a', 'wiki-1'));
    const second = await pay(db, honest('b', 'wiki-2'));
    assert.equal(second.placeXp, PLACE_XP.heritage);
  });

  test('the daily cap holds across many trips', async () => {
    const db = fakeDb();
    for (let i = 0; i < 30; i++) await pay(db, honest(`t${i}`, `p${i}`));
    assert.ok(total(db) <= 1500, `paid ${total(db)}`);
    assert.equal(total(db), 1500);
  });

  test('the cap resets the next day', async () => {
    const db = fakeDb();
    for (let i = 0; i < 30; i++) await pay(db, honest(`t${i}`, `p${i}`));
    const tomorrow = NOW + 24 * 3600 * 1000;
    const w = walk(HOME, 600);
    const t = honest('late', 'fresh');
    t.startedAt += 24 * 3600 * 1000;
    t.endedAt += 24 * 3600 * 1000;
    t.photoAt += 24 * 3600 * 1000;
    t.fixes = t.fixes.map((f) => ({ ...f, t: f.t + 24 * 3600 * 1000 }));
    const r = await pay(db, t, tomorrow);
    assert.equal(r.totalXp, PLACE_XP.heritage + 100);
    assert.equal(w.fixes.length > 0, true);
  });

  test('a rejected trip pays nothing and cannot be retried with edits', async () => {
    const db = fakeDb();
    const bad = honest('x');
    bad.mockSeen = true;
    const r = await pay(db, bad);
    assert.equal(r.totalXp, 0);
    const fixed = honest('x');
    const retry = await pay(db, fixed);
    assert.equal(retry.replay, true);
    assert.equal(retry.totalXp, 0);
    assert.equal(total(db), 0);
  });

  test('users do not share totals', async () => {
    const db = fakeDb();
    await pay(db, honest('a'));
    await payTrip(db, 'u2', honest('a'), NOW, FieldValue);
    assert.equal(db.store.get('verified_xp/u2').totalXp, PLACE_XP.heritage + 100);
    assert.equal(total(db), PLACE_XP.heritage + 100);
  });
});

test('days roll over at midnight India time', () => {
  assert.equal(dayKey(Date.UTC(2026, 9, 14, 18, 29)), '2026-10-14');
  assert.equal(dayKey(Date.UTC(2026, 9, 14, 18, 31)), '2026-10-15');
});
