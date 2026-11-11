import { TripGuard, RULES, distanceMeters } from './trip_guard.js';
import { TripSplit } from './trip_split.js';

/** Most XP from trips in one day, and the cooldown per place. */
export const DAILY_TRIP_XP_CAP = 1500;
export const PLACE_COOLDOWN_DAYS = 7;
export const COMPLETION_BONUS = 100;
export const ARRIVAL_RADIUS_METERS = 40;

/**
 * XP a place can pay, by kind of place. The server decides: the app's own
 * number is never trusted, so a modified app can't claim 5000 XP for a bench.
 */
export const PLACE_XP = Object.freeze({
  heritage: 80,
  nature: 70,
  lake: 60,
  photography: 60,
  viewpoint: 70,
  hiddenGem: 110,
  city: 50,
});
export const DEFAULT_PLACE_XP = 50;

/** Largest trip the server will look at. */
export const LIMITS = Object.freeze({
  maxFixes: 6000,
  maxTripHours: 24,
  maxAgeHours: 48,
  maxFutureMinutes: 5,
});

/**
 * Decides what a finished trip earns. Pure: everything it needs about the
 * past comes in through `history`, so it is easy to test.
 *
 * trip = {
 *   tripId, startedAt, endedAt (ms), fixes: [{lat, lng, t, acc?, mocked?}],
 *   mockSeen?: boolean,
 *   place?: { id, name, lat, lng, category }, photoAt?: ms
 * }
 * history = { now (ms), todayTripXp, placeLastPaidAt (ms | null) }
 *
 * Returns { ok, reasons[], verifiedMeters, placeXp, completionXp, totalXp,
 *           counted, placeVisited }
 */
export function evaluateTrip(trip, history) {
  const reasons = [];
  const reject = (reason) => ({
    ok: false, reasons: [reason], verifiedMeters: 0, trekMeters: 0,
    journeyMeters: 0, placeXp: 0,
    completionXp: 0, totalXp: 0, counted: false, placeVisited: false,
  });

  // --- Is this a believable submission at all? ---
  if (!trip || typeof trip.tripId !== 'string' || trip.tripId.length === 0 ||
      trip.tripId.length > 80) {
    return reject('badTripId');
  }
  if (!Number.isFinite(trip.startedAt) || !Number.isFinite(trip.endedAt) ||
      trip.endedAt <= trip.startedAt) {
    return reject('badTimes');
  }
  if ((trip.endedAt - trip.startedAt) / 3600000 > LIMITS.maxTripHours) {
    return reject('tripTooLong');
  }
  if (trip.endedAt > history.now + LIMITS.maxFutureMinutes * 60000) {
    return reject('fromTheFuture');
  }
  if ((history.now - trip.endedAt) / 3600000 > LIMITS.maxAgeHours) {
    return reject('tooOld');
  }
  if (!Array.isArray(trip.fixes) || trip.fixes.length > LIMITS.maxFixes) {
    return reject('badPath');
  }

  // --- Re-run the trip checks over the whole path. ---
  const guard = new TripGuard();
  // The trek starts within 200 m of the place; with no place, at once.
  const hasPlace = trip.place && Number.isFinite(trip.place.lat) && Number.isFinite(trip.place.lng);
  const split = new TripSplit(hasPlace ? { lat: trip.place.lat, lng: trip.place.lng } : null);
  if (trip.mockSeen === true) guard.process({ lat: 0, lng: 0, t: 0, mocked: true });
  for (const f of trip.fixes) {
    if (![f?.lat, f?.lng, f?.t].every(Number.isFinite) ||
        Math.abs(f.lat) > 90 || Math.abs(f.lng) > 180 ||
        f.t < trip.startedAt - 60000 || f.t > trip.endedAt + 60000) {
      return reject('badPath');
    }
    if (guard.process(f).accepted) split.add(f);
  }
  const elapsedSeconds = (trip.endedAt - trip.startedAt) / 1000;

  // --- Completion ---
  const completionDenial = guard.completionDenial(split.trekMeters, split.trekSeconds);
  const counted = completionDenial === null;
  if (!counted) reasons.push(completionDenial);

  // --- The place, if the trip went to one and shows a proof photo ---
  let placeXp = 0;
  let placeVisited = false;
  const place = trip.place;
  if (place && Number.isFinite(trip.photoAt)) {
    const target = { lat: place.lat, lng: place.lng };
    const arrival = guard.arrivalDenial(target, elapsedSeconds);
    const reachedRadius = trip.fixes.some(
      (f) => !f.mocked && distanceMeters(f, target) <= ARRIVAL_RADIUS_METERS &&
             f.t <= trip.photoAt + 60000,
    );
    // The proof photo must be taken inside the trip, at the place.
    const photoInTrip = trip.photoAt >= trip.startedAt && trip.photoAt <= trip.endedAt + 60000;
    // Presence is judged at the photo's own time, from the fixes up to it:
    // walking away afterwards doesn't matter, and neither does arriving later.
    const presence = photoPresenceFromFixes(trip.fixes, target, trip.photoAt);

    if (arrival) reasons.push(arrival);
    else if (!reachedRadius) reasons.push('neverReachedPlace');
    else if (!photoInTrip || !presence) reasons.push('photoNotAtPlace');
    else {
      placeVisited = true;
      placeXp = PLACE_XP[place.category] ?? DEFAULT_PLACE_XP;
      const cooldownMs = PLACE_COOLDOWN_DAYS * 86400000;
      if (history.placeLastPaidAt != null &&
          history.placeLastPaidAt > history.now - cooldownMs) {
        placeXp = 0;
        reasons.push('placeRecentlyPaid');
      }
    }
  }

  // --- Daily cap: place XP first, then the completion bonus. ---
  let left = Math.max(0, DAILY_TRIP_XP_CAP - history.todayTripXp);
  const placePaid = Math.min(placeXp, left);
  left -= placePaid;
  const completionXp = counted ? Math.min(COMPLETION_BONUS, left) : 0;
  if (placePaid < placeXp || (counted && completionXp < COMPLETION_BONUS)) {
    reasons.push('dailyCap');
  }

  return {
    ok: true,
    reasons,
    verifiedMeters: Math.round(guard.verifiedMeters),
    trekMeters: Math.round(split.trekMeters),
    journeyMeters: Math.round(split.journeyMeters),
    placeXp: placePaid,
    completionXp,
    totalXp: placePaid + completionXp,
    counted,
    placeVisited,
  };
}

/** Presence at the photo's time, from the last good fix at or before it. */
function photoPresenceFromFixes(fixes, target, photoAt) {
  const guard = new TripGuard();
  let last = null;
  for (const f of fixes) {
    if (f.t > photoAt) break;
    if (guard.process(f).accepted) last = f;
  }
  if (last === null || !guard.isClean) return false;
  return (photoAt - last.t) / 1000 <= RULES.proofFreshnessSeconds &&
    distanceMeters(last, target) <= ARRIVAL_RADIUS_METERS + RULES.proofSlackMeters;
}
