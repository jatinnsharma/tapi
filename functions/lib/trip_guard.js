// Server-side port of lib/features/tracking/domain/trip_guard.dart.
// Keep the two in step: ACHIEVEMENT_RULES.md lists the numbers, and
// test/trip_guard.test.js mirrors test/trip_guard_test.dart on the app side.

export const RULES = Object.freeze({
  maxAccuracyMeters: 50,
  // 162 km/h: the journey to a trek may be by vehicle; only beyond this is a
  // teleport. (On foot vs vehicle is trip_split.js's job.)
  maxSpeedMetersPerSecond: 45,
  minStepMeters: 3,
  minJumpMeters: 60,
  minStartDistanceMeters: 100,
  minTravelShare: 0.6,
  minArrivalSeconds: 60,
  minCompletionMeters: 200,
  minCompletionSeconds: 120,
  proofFreshnessSeconds: 90,
  proofSlackMeters: 60,
});

/** Great-circle distance in metres between two {lat, lng} points. */
export function distanceMeters(a, b) {
  const R = 6371008.8;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Judges a trip's GPS readings, as the app does while the trip runs. A fix is
 * { lat, lng, t (ms since epoch), acc (metres, optional), mocked (optional) }.
 */
export class TripGuard {
  #first = null;
  #last = null;
  #verifiedMeters = 0;
  #jumps = 0;
  #mockSeen = false;

  get verifiedMeters() { return this.#verifiedMeters; }
  get jumps() { return this.#jumps; }
  get mockDetected() { return this.#mockSeen; }
  get isClean() { return !this.#mockSeen && this.#jumps === 0; }
  get lastFix() { return this.#last; }
  get firstFix() { return this.#first; }

  /** 'mockLocation' | 'gpsJump' | null */
  get flag() {
    if (this.#mockSeen) return 'mockLocation';
    return this.#jumps > 0 ? 'gpsJump' : null;
  }

  process(fix) {
    if (fix.mocked) {
      this.#mockSeen = true;
      return { accepted: false, addedMeters: 0, flag: 'mockLocation' };
    }
    if (fix.acc != null && fix.acc > RULES.maxAccuracyMeters) {
      return { accepted: false, addedMeters: 0, flag: null };
    }
    const previous = this.#last;
    if (previous === null) {
      this.#first = fix;
      this.#last = fix;
      return { accepted: true, addedMeters: 0, flag: null };
    }
    const seconds = (fix.t - previous.t) / 1000;
    if (!(seconds > 0)) return { accepted: false, addedMeters: 0, flag: null };

    const meters = distanceMeters(previous, fix);
    if (meters >= RULES.minJumpMeters && meters / seconds > RULES.maxSpeedMetersPerSecond) {
      this.#jumps++;
      return { accepted: false, addedMeters: 0, flag: 'gpsJump' };
    }
    this.#last = fix;
    const added = meters >= RULES.minStepMeters ? meters : 0;
    this.#verifiedMeters += added;
    return { accepted: true, addedMeters: added, flag: null };
  }

  /** Why [target] can't pay its XP yet, or null. elapsedSeconds = trip time. */
  arrivalDenial(target, elapsedSeconds) {
    if (this.flag) return this.flag;
    if (this.#first === null) return 'tooSoon';
    const startDistance = distanceMeters(this.#first, target);
    if (startDistance < RULES.minStartDistanceMeters) return 'startedTooClose';
    if (this.#verifiedMeters < startDistance * RULES.minTravelShare) return 'notTravelled';
    if (elapsedSeconds < RULES.minArrivalSeconds) return 'tooSoon';
    return null;
  }

  /** Whether a photo at [nowMs] proves presence at the target. */
  photoProvesPresence(target, radiusMeters, nowMs) {
    const last = this.#last;
    if (last === null || !this.isClean) return false;
    if ((nowMs - last.t) / 1000 > RULES.proofFreshnessSeconds) return false;
    return distanceMeters(last, target) <= radiusMeters + RULES.proofSlackMeters;
  }

  /**
   * Why the whole trip doesn't count as completed, or null. Judged on the
   * trek only (see trip_split.js): driving a long way doesn't make a trip.
   */
  completionDenial(trekMeters, trekSeconds) {
    if (this.flag) return this.flag;
    if (trekMeters < RULES.minCompletionMeters ||
        trekSeconds < RULES.minCompletionSeconds) {
      return 'tooShort';
    }
    return null;
  }
}
