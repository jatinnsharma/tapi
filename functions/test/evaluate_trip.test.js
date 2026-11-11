// What the server pays for a submitted trip, including forged submissions.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluateTrip, DAILY_TRIP_XP_CAP, PLACE_XP, LIMITS,
} from '../lib/evaluate_trip.js';
import { HOME, T0, north, fix, walk, trip, history, visit } from './helpers.js';

const PLACE_POS = north(HOME, 600);
const place = (over = {}) => ({
  id: 'wiki-1', name: 'Sukhna Lake', category: 'heritage', ...PLACE_POS, ...over,
});

/**
 * An honest trip: walk 600 m to the place, take the photo there, walk 300 m
 * around it (the trek), finish.
 */
function honestTrip(over = {}) {
  const v = visit(600, 300);
  return trip({
    fixes: v.fixes,
    startedAt: T0,
    endedAt: T0 + (v.endAt + 60) * 1000,
    place: place(),
    photoAt: T0 + (v.arriveAt + 20) * 1000,
    ...over,
  });
}

describe('An honest trip', () => {
  test('pays the place and the completion bonus', () => {
    const r = evaluateTrip(honestTrip(), history());
    assert.equal(r.ok, true);
    assert.equal(r.counted, true);
    assert.equal(r.placeVisited, true);
    assert.equal(r.placeXp, PLACE_XP.heritage);
    assert.equal(r.completionXp, 100);
    assert.equal(r.totalXp, PLACE_XP.heritage + 100);
    assert.deepEqual(r.reasons, []);
    assert.ok(Math.abs(r.verifiedMeters - 900) < 15);
    // Walking up to 200 m from the place is journey; the rest is trek.
    assert.ok(Math.abs(r.journeyMeters - 400) < 15, `journey ${r.journeyMeters}`);
    assert.ok(Math.abs(r.trekMeters - 500) < 15, `trek ${r.trekMeters}`);
  });

  test('driving to the place and trekking there pays, like walking there', () => {
    // 3 km by car at 15 m/s, then 400 m on foot.
    const fixes = [fix(HOME, 0)];
    let t = 0;
    for (let m = 150; m <= 3000; m += 150) {
      t += 10;
      fixes.push(fix(north(HOME, m), t));
    }
    const atPlace = north(HOME, 3000);
    const onFoot = walk(atPlace, 400, t);
    const all = [...fixes, ...onFoot.fixes.slice(1)];
    const r = evaluateTrip(
      trip({
        fixes: all,
        endedAt: T0 + (onFoot.endAt + 30) * 1000,
        place: place({ ...atPlace }),
        photoAt: T0 + (t + 20) * 1000,
      }),
      history({ now: T0 + (onFoot.endAt + 60) * 1000 }),
    );
    assert.equal(r.ok, true);
    assert.deepEqual(r.reasons, []);
    assert.equal(r.counted, true);
    assert.equal(r.placeXp, PLACE_XP.heritage);
    assert.ok(r.journeyMeters > 2700);
    assert.ok(Math.abs(r.trekMeters - 400) < 20);
  });

  test('a long drive without trekking pays no completion bonus', () => {
    const fixes = [fix(HOME, 0)];
    let t = 0;
    for (let m = 150; m <= 6000; m += 150) {
      t += 10;
      fixes.push(fix(north(HOME, m), t));
    }
    const r = evaluateTrip(
      trip({ fixes, endedAt: T0 + (t + 30) * 1000 }),
      history({ now: T0 + (t + 60) * 1000 }),
    );
    assert.equal(r.counted, false);
    assert.equal(r.completionXp, 0);
    assert.ok(r.reasons.includes('tooShort'));
  });

  test('a trip with no place pays only the completion bonus', () => {
    const r = evaluateTrip(honestTrip({ place: undefined, photoAt: undefined }), history());
    assert.equal(r.totalXp, 100);
    assert.equal(r.placeVisited, false);
  });

  test('a place without the proof photo pays no place XP', () => {
    const r = evaluateTrip(honestTrip({ photoAt: undefined }), history());
    assert.equal(r.placeXp, 0);
    assert.equal(r.completionXp, 100);
  });
});

describe('Cheating on the place', () => {
  test('teleporting there pays nothing', () => {
    const t = honestTrip({
      fixes: [fix(HOME, 0), fix(PLACE_POS, 5), fix(PLACE_POS, 600)],
      endedAt: T0 + 700 * 1000,
      photoAt: T0 + 610 * 1000,
    });
    const r = evaluateTrip(t, history());
    assert.equal(r.totalXp, 0);
    assert.equal(r.counted, false);
    assert.ok(r.reasons.includes('gpsJump'));
  });

  test('the app saying it saw a mock location pays nothing', () => {
    const r = evaluateTrip(honestTrip({ mockSeen: true }), history());
    assert.equal(r.totalXp, 0);
    assert.ok(r.reasons.includes('mockLocation'));
  });

  test('a fix marked as mocked pays nothing', () => {
    const t = honestTrip();
    t.fixes[10] = { ...t.fixes[10], mocked: true };
    assert.equal(evaluateTrip(t, history()).totalXp, 0);
  });

  test('a photo taken long after leaving the place does not count', () => {
    const w = walk(HOME, 600);
    const r = evaluateTrip(
      honestTrip({ photoAt: T0 + (w.endAt + 300) * 1000, endedAt: T0 + (w.endAt + 400) * 1000 }),
      history(),
    );
    assert.equal(r.placeXp, 0);
    assert.ok(r.reasons.includes('photoNotAtPlace'));
  });

  test('a photo claimed before the trip began does not count', () => {
    const r = evaluateTrip(honestTrip({ photoAt: T0 - 3600 * 1000 }), history());
    assert.equal(r.placeXp, 0);
  });

  test('a path that never reaches the place pays no place XP', () => {
    const w = walk(HOME, 300);
    const r = evaluateTrip(
      honestTrip({ fixes: w.fixes, endedAt: T0 + (w.endAt + 120) * 1000, photoAt: T0 + (w.endAt + 20) * 1000 }),
      history(),
    );
    assert.equal(r.placeXp, 0);
  });

  test('starting right next to the place pays no place XP', () => {
    const start = north(PLACE_POS, -30);
    const w = walk(start, 30);
    const r = evaluateTrip(
      honestTrip({ fixes: w.fixes, endedAt: T0 + (w.endAt + 200) * 1000, photoAt: T0 + (w.endAt + 20) * 1000 }),
      history(),
    );
    assert.equal(r.placeXp, 0);
    assert.ok(r.reasons.includes('startedTooClose'));
  });
});

describe('The server sets the XP, not the app', () => {
  test('an unknown kind of place pays the default, not what the app asks', () => {
    const t = honestTrip({ place: place({ category: 'bench', xp: 99999 }) });
    const r = evaluateTrip(t, history());
    assert.equal(r.placeXp, 50);
  });

  test('every kind of place pays within the table', () => {
    for (const [category, xp] of Object.entries(PLACE_XP)) {
      const r = evaluateTrip(honestTrip({ place: place({ category }) }), history());
      assert.equal(r.placeXp, xp, category);
    }
  });
});

describe('Limits', () => {
  test('a place paid in the last 7 days pays no XP but still completes', () => {
    const r = evaluateTrip(
      honestTrip(),
      history({ placeLastPaidAt: T0 - 2 * 86400000 }),
    );
    assert.equal(r.placeXp, 0);
    assert.equal(r.completionXp, 100);
    assert.ok(r.reasons.includes('placeRecentlyPaid'));
  });

  test('a place paid 8 days ago pays again', () => {
    const r = evaluateTrip(honestTrip(), history({ placeLastPaidAt: T0 - 8 * 86400000 }));
    assert.equal(r.placeXp, PLACE_XP.heritage);
  });

  test('the daily cap trims the payout, place first', () => {
    const r = evaluateTrip(honestTrip(), history({ todayTripXp: DAILY_TRIP_XP_CAP - 50 }));
    assert.equal(r.placeXp, 50);
    assert.equal(r.completionXp, 0);
    assert.equal(r.totalXp, 50);
    assert.ok(r.reasons.includes('dailyCap'));
  });

  test('at the cap, nothing is paid', () => {
    const r = evaluateTrip(honestTrip(), history({ todayTripXp: DAILY_TRIP_XP_CAP }));
    assert.equal(r.totalXp, 0);
  });

  test('start-and-finish farming pays nothing', () => {
    const r = evaluateTrip(
      trip({ fixes: [fix(HOME, 0)], endedAt: T0 + 5000 }),
      history(),
    );
    assert.equal(r.totalXp, 0);
    assert.equal(r.counted, false);
  });
});

describe('Forged or broken submissions are rejected outright', () => {
  const expectRejected = (t, why) => {
    const r = evaluateTrip(t, history());
    assert.equal(r.ok, false);
    assert.equal(r.totalXp, 0);
    assert.deepEqual(r.reasons, [why]);
  };

  test('no trip id', () => expectRejected(honestTrip({ tripId: '' }), 'badTripId'));
  test('a trip id that is not text', () => expectRejected(honestTrip({ tripId: 42 }), 'badTripId'));
  test('ending before it began', () =>
    expectRejected(honestTrip({ endedAt: T0 - 1000 }), 'badTimes'));
  test('times that are not numbers', () =>
    expectRejected(honestTrip({ startedAt: 'soon' }), 'badTimes'));
  test('a trip longer than a day', () =>
    expectRejected(honestTrip({ endedAt: T0 + 25 * 3600 * 1000 }), 'tripTooLong'));
  test('a trip that ends in the future', () =>
    expectRejected(honestTrip({ endedAt: T0 + 3 * 3600 * 1000 }), 'fromTheFuture'));
  test('an old trip replayed days later', () => {
    const r = evaluateTrip(honestTrip(), history({ now: T0 + 3 * 86400000 }));
    assert.equal(r.ok, false);
    assert.deepEqual(r.reasons, ['tooOld']);
  });
  test('too many readings', () =>
    expectRejected(
      honestTrip({ fixes: Array.from({ length: LIMITS.maxFixes + 1 }, (_, i) => fix(HOME, i)) }),
      'badPath',
    ));
  test('a reading with a missing coordinate', () => {
    const t = honestTrip();
    t.fixes[3] = { t: t.fixes[3].t, lat: t.fixes[3].lat };
    expectRejected(t, 'badPath');
  });
  test('a reading outside the Earth', () => {
    const t = honestTrip();
    t.fixes[3] = { ...t.fixes[3], lat: 200 };
    expectRejected(t, 'badPath');
  });
  test('a reading from outside the trip\'s time', () => {
    const t = honestTrip();
    t.fixes[3] = { ...t.fixes[3], t: T0 - 3600 * 1000 };
    expectRejected(t, 'badPath');
  });
  test('no trip at all', () => {
    const r = evaluateTrip(null, history());
    assert.equal(r.ok, false);
  });
});
