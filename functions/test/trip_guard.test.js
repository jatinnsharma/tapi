// Mirrors test/trip_guard_test.dart: the server must judge a path exactly as
// the app does.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { TripGuard } from '../lib/trip_guard.js';
import { HOME, north, fix, walk } from './helpers.js';

const feed = (g, fixes) => fixes.forEach((f) => g.process(f));

describe('GPS readings', () => {
  test('a normal walk adds up its distance', () => {
    const g = new TripGuard();
    feed(g, walk(HOME, 500).fixes);
    assert.ok(Math.abs(g.verifiedMeters - 500) < 12);
    assert.equal(g.isClean, true);
  });

  test('a mock-location reading is rejected and flags the trip', () => {
    const g = new TripGuard();
    g.process(fix(HOME, 0));
    const r = g.process(fix(north(HOME, 20), 10, { mocked: true }));
    assert.equal(r.accepted, false);
    assert.equal(r.flag, 'mockLocation');
    assert.equal(g.flag, 'mockLocation');
    assert.equal(g.verifiedMeters, 0);
  });

  test('a teleport is rejected, flagged, and adds no distance', () => {
    const g = new TripGuard();
    g.process(fix(HOME, 0));
    const r = g.process(fix(north(HOME, 3000), 10));
    assert.equal(r.accepted, false);
    assert.equal(r.flag, 'gpsJump');
    assert.equal(g.jumps, 1);
    assert.equal(g.verifiedMeters, 0);
  });

  test('a spoofer who jumps and stays keeps failing', () => {
    const g = new TripGuard();
    g.process(fix(HOME, 0));
    for (let t = 10; t <= 50; t += 10) {
      assert.equal(g.process(fix(north(HOME, 3000), t)).accepted, false);
    }
    assert.equal(g.jumps, 5);
  });

  test('a long gap with a short move is fine', () => {
    const g = new TripGuard();
    g.process(fix(HOME, 0));
    assert.equal(g.process(fix(north(HOME, 900), 600)).accepted, true);
    assert.equal(g.isClean, true);
  });

  test('a car on the journey is fine; a teleport is not', () => {
    const g = new TripGuard();
    g.process(fix(HOME, 0));
    assert.equal(g.process(fix(north(HOME, 80), 10)).accepted, true);
    assert.equal(g.process(fix(north(HOME, 480), 20)).accepted, true); // 40 m/s
    assert.equal(g.isClean, true);
    assert.equal(g.process(fix(north(HOME, 3480), 30)).accepted, false); // 300 m/s
    assert.equal(g.flag, 'gpsJump');
  });

  test('imprecise readings are ignored without flagging', () => {
    const g = new TripGuard();
    g.process(fix(HOME, 0));
    const r = g.process(fix(north(HOME, 20), 10, { acc: 120 }));
    assert.equal(r.accepted, false);
    assert.equal(r.flag, null);
    assert.equal(g.isClean, true);
  });

  test('standing still adds nothing', () => {
    const g = new TripGuard();
    g.process(fix(HOME, 0));
    for (let t = 10; t <= 600; t += 10) {
      g.process(fix(north(HOME, t % 20 === 0 ? 1 : 2), t));
    }
    assert.ok(g.verifiedMeters < 5);
  });

  test('readings out of order or at the same time are ignored', () => {
    const g = new TripGuard();
    g.process(fix(HOME, 100));
    assert.equal(g.process(fix(north(HOME, 30), 100)).accepted, false);
    assert.equal(g.process(fix(north(HOME, 30), 50)).accepted, false);
  });
});

describe('Arriving at a place', () => {
  const place = north(HOME, 600);

  test('a real walk there pays', () => {
    const g = new TripGuard();
    feed(g, walk(HOME, 600).fixes);
    assert.equal(g.arrivalDenial(place, 600), null);
  });

  test('starting next to the place does not pay', () => {
    const start = north(place, 30);
    const g = new TripGuard();
    feed(g, walk(start, 30).fixes);
    assert.equal(g.arrivalDenial(place, 600), 'startedTooClose');
  });

  test('teleporting there does not pay', () => {
    const g = new TripGuard();
    g.process(fix(HOME, 0));
    g.process(fix(place, 5));
    assert.equal(g.arrivalDenial(place, 600), 'gpsJump');
  });

  test('a short walk cannot cover a long distance', () => {
    const g = new TripGuard();
    feed(g, walk(HOME, 200).fixes);
    assert.equal(g.arrivalDenial(north(HOME, 3000), 600), 'notTravelled');
  });

  test('arriving within a minute does not pay', () => {
    const g = new TripGuard();
    feed(g, walk(HOME, 600).fixes);
    assert.equal(g.arrivalDenial(place, 30), 'tooSoon');
  });

  test('no readings yet means no arrival', () => {
    assert.equal(new TripGuard().arrivalDenial(place, 600), 'tooSoon');
  });
});

describe('Photo proof of presence', () => {
  const place = north(HOME, 600);
  const arrived = () => {
    const g = new TripGuard();
    feed(g, walk(HOME, 600).fixes);
    return g;
  };

  test('counts when the last reading is fresh and at the place', () => {
    const g = arrived();
    assert.equal(g.photoProvesPresence(place, 40, g.lastFix.t + 20000), true);
  });

  test('does not count if the user has since walked away', () => {
    const g = arrived();
    feed(g, walk(g.lastFix, 300, 700).fixes.map((f) => ({ ...f })));
    assert.equal(g.photoProvesPresence(place, 40, g.lastFix.t), false);
  });

  test('does not count on a stale reading', () => {
    const g = arrived();
    assert.equal(g.photoProvesPresence(place, 40, g.lastFix.t + 600000), false);
  });

  test('never counts on a flagged trip', () => {
    const g = arrived();
    g.process(fix(north(place, 5), 9999, { mocked: true }));
    assert.equal(g.photoProvesPresence(place, 40, g.lastFix.t), false);
  });
});

describe('Completing a trip', () => {
  test('a real trip counts', () => {
    const g = new TripGuard();
    feed(g, walk(HOME, 300).fixes);
    assert.equal(g.completionDenial(300, 360), null);
  });

  test('start-and-finish farming does not', () => {
    const g = new TripGuard();
    g.process(fix(HOME, 0));
    assert.equal(g.completionDenial(0, 3), 'tooShort');
  });

  test('a long sit with no movement does not', () => {
    const g = new TripGuard();
    g.process(fix(HOME, 0));
    assert.equal(g.completionDenial(0, 7200), 'tooShort');
  });

  test('a flagged trip never counts', () => {
    const g = new TripGuard();
    feed(g, walk(HOME, 500).fixes);
    g.process(fix(north(HOME, 520), 9999, { mocked: true }));
    assert.equal(g.completionDenial(500, 3600), 'mockLocation');
  });
});
