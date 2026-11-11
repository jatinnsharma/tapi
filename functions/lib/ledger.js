import { evaluateTrip } from './evaluate_trip.js';

/** The day a trip counts toward, in India time (the app is Chandigarh-only). */
export function dayKey(ms) {
  return new Date(ms + 330 * 60000).toISOString().slice(0, 10);
}

/** Safe id for a place document. */
export function placeDocId(id) {
  return String(id ?? '').replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 100);
}

/**
 * Pays a trip once. Runs inside a Firestore transaction:
 *   verified_xp/{uid}                    { totalXp, dayKey, dayXp }
 *   verified_xp/{uid}/entries/{tripId}   the stored result (replay protection)
 *   verified_xp/{uid}/places/{placeId}   { paidAt } (7-day cooldown)
 * Submitting the same trip again returns the stored result and pays nothing.
 */
export async function payTrip(db, uid, trip, now, FieldValue) {
  const root = db.collection('verified_xp').doc(uid);
  const entryRef = root.collection('entries').doc(trip.tripId);
  const placeKey = trip.place?.id ? placeDocId(trip.place.id) : null;
  const placeRef = placeKey ? root.collection('places').doc(placeKey) : null;

  return db.runTransaction(async (tx) => {
    const reads = [tx.get(entryRef), tx.get(root)];
    if (placeRef) reads.push(tx.get(placeRef));
    const [entry, summary, placeDoc] = await Promise.all(reads);

    if (entry.exists) return { ...entry.data().result, replay: true };

    const s = summary.exists ? summary.data() : {};
    const today = dayKey(now);
    const todayTripXp = s.dayKey === today ? (s.dayXp ?? 0) : 0;
    const placeLastPaidAt = placeDoc?.exists ? placeDoc.data().paidAt : null;

    const result = evaluateTrip(trip, { now, todayTripXp, placeLastPaidAt });
    // Even rejected trips are recorded, so they can't be retried with edits.
    tx.set(entryRef, { result, paidAt: now, placeId: placeKey, at: FieldValue.serverTimestamp() });

    if (result.ok && result.totalXp > 0) {
      tx.set(root, {
        totalXp: (s.totalXp ?? 0) + result.totalXp,
        dayKey: today,
        dayXp: todayTripXp + result.totalXp,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    if (placeRef && result.placeXp > 0) tx.set(placeRef, { paidAt: now });
    return { ...result, replay: false };
  });
}
