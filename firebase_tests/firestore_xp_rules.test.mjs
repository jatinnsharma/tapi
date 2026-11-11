// Tests the explorers/{uid} XP rules against the Firestore emulator, as
// signed-in users trying honest and dishonest writes.
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import {
  doc, setDoc, updateDoc, getDoc, serverTimestamp, Timestamp,
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

const profile = (over = {}) => ({
  uid: 'alice', displayName: 'Alice',
  createdAt: '2026-10-14T00:00:00.000Z', totalXp: 0, ...over,
});

// Seeds alice's doc with rules off.
async function seed(data) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'explorers/alice'), data);
  });
}
const alice = () => env.authenticatedContext('alice').firestore();
const ref = (db) => doc(db, 'explorers/alice');
const hoursAgo = (h) => Timestamp.fromMillis(Date.now() - h * 3600 * 1000);

console.log('Creating a profile');
await env.clearFirestore();
await check('sign-up with 0 XP works', () =>
  assertSucceeds(setDoc(ref(alice()), profile())));
await env.clearFirestore();
await check('sign-up claiming 5000 XP is refused', () =>
  assertFails(setDoc(ref(alice()), profile({ totalXp: 5000 }))));
await env.clearFirestore();
await check("nobody can create someone else's profile", () =>
  assertFails(setDoc(doc(env.authenticatedContext('mallory').firestore(), 'explorers/alice'), profile())));

console.log('Writing XP');
await seed(profile());
await check('first sync of 4000 XP (earned before signing up) works', () =>
  assertSucceeds(updateDoc(ref(alice()), { totalXp: 4000, xpUpdatedAt: serverTimestamp() })));
await seed(profile());
await check('first sync of 999999 XP is refused', () =>
  assertFails(updateDoc(ref(alice()), { totalXp: 999999, xpUpdatedAt: serverTimestamp() })));
await seed(profile());
await check('XP change without the server clock is refused', () =>
  assertFails(updateDoc(ref(alice()), { totalXp: 100 })));
await seed(profile());
await check('XP change with a made-up clock is refused', () =>
  assertFails(updateDoc(ref(alice()), { totalXp: 100, xpUpdatedAt: Timestamp.fromMillis(Date.now() - 10 * 86400000) })));

await seed(profile({ totalXp: 4000, xpUpdatedAt: hoursAgo(1) }));
await check('+500 XP an hour later works', () =>
  assertSucceeds(updateDoc(ref(alice()), { totalXp: 4500, xpUpdatedAt: serverTimestamp() })));
await seed(profile({ totalXp: 4000, xpUpdatedAt: hoursAgo(1) }));
await check('+50000 XP an hour later is refused', () =>
  assertFails(updateDoc(ref(alice()), { totalXp: 54000, xpUpdatedAt: serverTimestamp() })));
await seed(profile({ totalXp: 4000, xpUpdatedAt: hoursAgo(24 * 10) }));
await check('+20000 XP after ten days works (3000/day)', () =>
  assertSucceeds(updateDoc(ref(alice()), { totalXp: 24000, xpUpdatedAt: serverTimestamp() })));
await seed(profile({ totalXp: 4000, xpUpdatedAt: hoursAgo(24 * 10) }));
await check('+90000 XP after ten days is refused', () =>
  assertFails(updateDoc(ref(alice()), { totalXp: 94000, xpUpdatedAt: serverTimestamp() })));
await seed(profile({ totalXp: 4000, xpUpdatedAt: hoursAgo(1) }));
await check('XP going down (reinstall) works', () =>
  assertSucceeds(updateDoc(ref(alice()), { totalXp: 0, xpUpdatedAt: serverTimestamp() })));
await seed(profile({ totalXp: 4000, xpUpdatedAt: hoursAgo(1) }));
await check('negative XP is refused', () =>
  assertFails(updateDoc(ref(alice()), { totalXp: -5, xpUpdatedAt: serverTimestamp() })));
await seed(profile({ totalXp: 4000, xpUpdatedAt: hoursAgo(1) }));
await check('XP as text is refused', () =>
  assertFails(updateDoc(ref(alice()), { totalXp: '9999999', xpUpdatedAt: serverTimestamp() })));

console.log('Loopholes around the time stamp');
await seed(profile({ totalXp: 4000, xpUpdatedAt: hoursAgo(1) }));
await check('rewinding xpUpdatedAt without changing XP is refused', () =>
  assertFails(updateDoc(ref(alice()), { xpUpdatedAt: hoursAgo(24 * 30) })));
await seed(profile({ totalXp: 4000, xpUpdatedAt: hoursAgo(1) }));
await check('replacing the whole doc to wipe xpUpdatedAt is refused', () =>
  assertFails(setDoc(ref(alice()), profile({ totalXp: 4000 }))));

console.log('Normal profile editing still works');
await seed(profile({ totalXp: 4000, xpUpdatedAt: hoursAgo(1) }));
await check('changing the bio leaves XP alone and works', () =>
  assertSucceeds(updateDoc(ref(alice()), { bio: 'Hello' })));
await seed(profile({ totalXp: 4000, xpUpdatedAt: hoursAgo(1) }));
await check('merge-writing the name works', () =>
  assertSucceeds(setDoc(ref(alice()), { displayName: 'Alice B' }, { merge: true })));
await seed(profile());
await check('a profile from before XP existed can still edit its bio', async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'explorers/alice'), { uid: 'alice', displayName: 'A', email: 'a@x.com', createdAt: 'x' });
  });
  await assertSucceeds(updateDoc(ref(alice()), { bio: 'hi' }));
});

console.log('Other people');
await seed(profile());
await check("someone else can't change my XP", () =>
  assertFails(updateDoc(doc(env.authenticatedContext('mallory').firestore(), 'explorers/alice'), { totalXp: 100, xpUpdatedAt: serverTimestamp() })));
await check('signed-in users can read profiles', () =>
  assertSucceeds(getDoc(doc(env.authenticatedContext('mallory').firestore(), 'explorers/alice'))));
await check('signed-out users cannot', () =>
  assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'explorers/alice'))));
await seed(profile());
await check('I can delete my own profile', () =>
  assertSucceeds(env.authenticatedContext('alice').firestore() && (async () => {
    const { deleteDoc } = await import('firebase/firestore');
    return deleteDoc(ref(alice()));
  })()));

console.log('Server-verified XP (verified_xp)');
const seedVerified = async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'verified_xp/alice'), { totalXp: 500 });
    await setDoc(doc(ctx.firestore(), 'verified_xp/alice/entries/t1'), { paidAt: 1 });
  });
};
const vref = (db) => doc(db, 'verified_xp/alice');
const mallory = () => env.authenticatedContext('mallory').firestore();
await seedVerified();
await check('anyone signed in can read a total (leaderboard)', () =>
  assertSucceeds(getDoc(vref(mallory()))));
await check('signed-out users cannot read it', () =>
  assertFails(getDoc(vref(env.unauthenticatedContext().firestore()))));
await check('alice cannot raise her own verified XP', () =>
  assertFails(updateDoc(vref(alice()), { totalXp: 99999 })));
await check('alice cannot create her own verified XP doc', async () => {
  await env.clearFirestore();
  await assertFails(setDoc(vref(alice()), { totalXp: 99999 }));
});
await seedVerified();
await check('alice cannot delete it', async () => {
  const { deleteDoc } = await import('firebase/firestore');
  await assertFails(deleteDoc(vref(alice())));
});
await check('alice cannot forge a ledger entry', () =>
  assertFails(setDoc(doc(alice(), 'verified_xp/alice/entries/t2'), { paidAt: 2 })));
await check('alice cannot forge a place cooldown reset', () =>
  assertFails(setDoc(doc(alice(), 'verified_xp/alice/places/p1'), { paidAt: 0 })));
await check('alice can read her own ledger', () =>
  assertSucceeds(getDoc(doc(alice(), 'verified_xp/alice/entries/t1'))));
await check("others cannot read alice's ledger", () =>
  assertFails(getDoc(doc(mallory(), 'verified_xp/alice/entries/t1'))));

await env.cleanup();
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
