import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { payTrip } from './lib/ledger.js';

initializeApp();

/**
 * Judges a finished trip and pays XP into verified_xp/{uid}. The app can't
 * write that path (see firestore.rules), so XP here only comes from this
 * function. Set enforceAppCheck to true once App Check is set up in the
 * Firebase console, so only the real app can call it.
 */
export const verifyTrip = onCall(
  {
    region: 'asia-south1',
    enforceAppCheck: false,
    maxInstances: 10,
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
    const trip = request.data;
    if (!trip || typeof trip !== 'object') {
      throw new HttpsError('invalid-argument', 'No trip sent.');
    }
    const result = await payTrip(
      getFirestore(), request.auth.uid, trip, Date.now(), FieldValue,
    );
    return result;
  },
);
