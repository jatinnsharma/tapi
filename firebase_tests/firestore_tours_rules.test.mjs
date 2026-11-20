// Tests the community rules (curated tours and their ratings, place tips,
// reports) against
// the Firestore emulator, as signed-in users trying honest and dishonest
// writes. Run with `npm test` (needs Java 21+, see README.md).
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import {
  doc, setDoc, getDoc, deleteDoc, updateDoc, serverTimestamp,
} from 'firebase/firestore';

const env = await initializeTestEnvironment({
  projectId: 'demo-xp-rules',
  firestore: {
    rules: readFileSync('../firestore.rules', 'utf8'),
    host: '127.0.0.1',
    port: 8085,
  },
});

let passed = 0;
let failed = 0;
async function check(name, expectation) {
  try {
    await expectation();
    console.log('  PASS', name);
    passed++;
  } catch (e) {
    console.log('  FAIL', name, '->', String(e.message).split('\n')[0]);
    failed++;
  }
}

const stop = (n) => ({ name: `Stop ${n}`, lat: 25.3, lng: 83.0 + n / 100, category: 'heritage' });
const tour = (over = {}) => ({
  creatorUid: 'alice',
  creatorName: 'Alice',
  cityId: 'varanasi',
  cityName: 'Varanasi',
  title: 'Ghats at dawn',
  description: 'A sunrise walk.',
  stops: [stop(1), stop(2), stop(3)],
  createdAt: serverTimestamp(),
  ...over,
});

const alice = () => env.authenticatedContext('alice').firestore();
const bob = () => env.authenticatedContext('bob').firestore();
const anon = () => env.unauthenticatedContext().firestore();
const tref = (db) => doc(db, 'curated_tours/t1');
const rref = (db, uid) => doc(db, `curated_tours/t1/ratings/${uid}`);

async function seedTour() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'curated_tours/t1'), { ...tour(), createdAt: new Date() });
  });
}

console.log('Publishing a tour');
await env.clearFirestore();
await check('alice publishes her own tour', () =>
  assertSucceeds(setDoc(tref(alice()), tour())));
await env.clearFirestore();
await check("bob can't publish a tour in alice's name", () =>
  assertFails(setDoc(tref(bob()), tour())));
await check('fewer than 3 stops is refused', () =>
  assertFails(setDoc(tref(alice()), tour({ stops: [stop(1), stop(2)] }))));
await check('more than 15 stops is refused', () =>
  assertFails(setDoc(tref(alice()), tour({
    stops: Array.from({ length: 16 }, (_, i) => stop(i)),
  }))));
await check('an empty title is refused', () =>
  assertFails(setDoc(tref(alice()), tour({ title: '' }))));
await check('an 81-character title is refused', () =>
  assertFails(setDoc(tref(alice()), tour({ title: 'x'.repeat(81) }))));
await check('extra fields (e.g. fake ratings) are refused', () =>
  assertFails(setDoc(tref(alice()), tour({ averageRating: 5 }))));
await check('a client-chosen creation time is refused', () =>
  assertFails(setDoc(tref(alice()), tour({ createdAt: new Date(2020, 1, 1) }))));
await check('signed-out users cannot publish', () =>
  assertFails(setDoc(tref(anon()), tour())));

console.log('Reading, editing and deleting');
await seedTour();
await check('anyone signed in can read a tour', () =>
  assertSucceeds(getDoc(tref(bob()))));
await check('signed-out users cannot read tours', () =>
  assertFails(getDoc(tref(anon()))));
await check('tours cannot be edited after publishing', () =>
  assertFails(updateDoc(tref(alice()), { title: 'New title' })));
await check("bob cannot delete alice's tour", () =>
  assertFails(deleteDoc(tref(bob()))));
await check('alice can delete her tour', () =>
  assertSucceeds(deleteDoc(tref(alice()))));

console.log('Rating');
await seedTour();
await check('bob rates 4 stars', () =>
  assertSucceeds(setDoc(rref(bob(), 'bob'), { name: 'Bob', stars: 4, review: 'Lovely' })));
await check('bob changes his rating', () =>
  assertSucceeds(setDoc(rref(bob(), 'bob'), { name: 'Bob', stars: 5, review: '' })));
await check("bob can't rate in someone else's name", () =>
  assertFails(setDoc(rref(bob(), 'carol'), { name: 'Carol', stars: 1, review: '' })));
await check('alice cannot rate her own tour', () =>
  assertFails(setDoc(rref(alice(), 'alice'), { name: 'Alice', stars: 5, review: '' })));
await check('6 stars is refused', () =>
  assertFails(setDoc(rref(bob(), 'bob'), { name: 'Bob', stars: 6, review: '' })));
await check('0 stars is refused', () =>
  assertFails(setDoc(rref(bob(), 'bob'), { name: 'Bob', stars: 0, review: '' })));
await check('a 501-character review is refused', () =>
  assertFails(setDoc(rref(bob(), 'bob'), { name: 'Bob', stars: 3, review: 'x'.repeat(501) })));
await check('anyone signed in can read ratings', () =>
  assertSucceeds(getDoc(rref(alice(), 'bob'))));

console.log('Place tips');
await env.clearFirestore();
const tipRef = (db, id = 'tip1') => doc(db, `location_communities/wiki-ghat/tips/${id}`);
const tipData = (over = {}) => ({
  uid: 'alice', displayName: 'Alice', text: 'Go at sunrise',
  timestamp: '2026-11-17T06:00:00.000Z', ...over,
});
await check('alice posts a tip', () =>
  assertSucceeds(setDoc(tipRef(alice()), tipData())));
await check("bob can't post a tip as alice", () =>
  assertFails(setDoc(tipRef(bob(), 'tip2'), tipData())));
await check('a 281-character tip is refused', () =>
  assertFails(setDoc(tipRef(alice(), 'tip3'), tipData({ text: 'x'.repeat(281) }))));
await check('an empty tip is refused', () =>
  assertFails(setDoc(tipRef(alice(), 'tip4'), tipData({ text: '' }))));
await check('extra fields on a tip are refused', () =>
  assertFails(setDoc(tipRef(alice(), 'tip5'), tipData({ pinned: true }))));
await check("bob can't delete alice's tip", () =>
  assertFails(deleteDoc(tipRef(bob()))));
await check('alice deletes her tip', () =>
  assertSucceeds(deleteDoc(tipRef(alice()))));
await check('bob reports a tip', () =>
  assertSucceeds(setDoc(doc(bob(), 'reports/r1'), {
    reportedUid: 'alice', reportedBy: 'bob', reason: 'Spam or advertising',
    contentType: 'locationTip', locationId: 'wiki-ghat', tipId: 'tip1', text: 'x',
    createdAt: '2026-11-17T06:00:00.000Z',
  })));
await check('reports cannot be read back', () =>
  assertFails(getDoc(doc(bob(), 'reports/r1'))));

await env.cleanup();
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
