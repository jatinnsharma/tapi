// Tests the trip-album rules (trip_plans/{tripId}/photos) against the
// Firestore emulator. Run with `npm test` (needs Java 21+, see README.md).
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { doc, setDoc, getDoc, deleteDoc } from 'firebase/firestore';

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

const db = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const pref = (d, id = 'p1') => doc(d, `trip_plans/t1/photos/${id}`);
const photo = (over = {}) => ({
  uploaderUid: 'alice',
  uploaderName: 'Alice',
  takenAt: '2026-11-18T09:00:00.000Z',
  thumbFileId: 'drive-thumb-1',
  viewFileId: 'drive-view-1',
  createdAt: '2026-11-18T10:00:00.000Z',
  ...over,
});

async function seed({ withPhoto = false } = {}) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, 'trip_plans/t1'), {
      ownerUid: 'olga',
      memberUids: ['olga', 'alice', 'bob'],
    });
    if (withPhoto) await setDoc(pref(f), photo());
  });
}

console.log('Adding photos');
await seed();
await check('a member adds her own photo', () =>
  assertSucceeds(setDoc(pref(db('alice')), photo())));
await seed();
await check("a member can't add a photo in someone else's name", () =>
  assertFails(setDoc(pref(db('bob')), photo())));
await check("someone who isn't on the trip can't add photos", () =>
  assertFails(setDoc(pref(db('mallory')), photo({ uploaderUid: 'mallory' }))));
await check('signed out: no', () => assertFails(setDoc(pref(anon()), photo())));
await check('extra fields are refused', () =>
  assertFails(setDoc(pref(db('alice')), photo({ xp: 9999 }))));
await check('a missing file id is refused', () => {
  const { viewFileId, ...noView } = photo();
  return assertFails(setDoc(pref(db('alice')), noView));
});
await check('location must be numbers', () =>
  assertFails(setDoc(pref(db('alice')), photo({ latitude: 'here' }))));
await check('with a location is fine', () =>
  assertSucceeds(setDoc(pref(db('alice')), photo({ latitude: 25.3, longitude: 83 }))));

console.log('Seeing photos');
await seed({ withPhoto: true });
await check('another member sees it', () => assertSucceeds(getDoc(pref(db('bob')))));
await check("someone who isn't on the trip doesn't", () =>
  assertFails(getDoc(pref(db('mallory')))));

console.log('Retrying and removing');
await seed({ withPhoto: true });
await check('the uploader can write the same record again (a retry)', () =>
  assertSucceeds(setDoc(pref(db('alice')), photo())));
await check("another member can't overwrite it", () =>
  assertFails(setDoc(pref(db('bob')), photo({ uploaderUid: 'bob' }))));
await check("another member can't delete it", () =>
  assertFails(deleteDoc(pref(db('bob')))));
await check('the trip owner can delete it', () =>
  assertSucceeds(deleteDoc(pref(db('olga')))));
await seed({ withPhoto: true });
await check('the uploader can delete it', () =>
  assertSucceeds(deleteDoc(pref(db('alice')))));

console.log(`\n${passed} passed, ${failed} failed`);
await env.cleanup();
process.exit(failed === 0 ? 0 : 1);
