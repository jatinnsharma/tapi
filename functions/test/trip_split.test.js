// Mirrors test/trip_split_test.dart: the server must split a trip into
// journey and trek exactly as the app does.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { TripSplit, PHASE } from '../lib/trip_split.js';
import { HOME, T0, north } from './helpers.js';

/** Feeds a TripSplit along a straight line north, a reading every [every] s. */
function trip(trekStart = null) {
  const split = new TripSplit(trekStart);
  let at = HOME;
  let t = 0;
  const emit = () => split.add({ ...at, t: T0 + t * 1000 });
  emit();
  return {
    split,
    move(meters, speed, every = 10) {
      const step = speed * every;
      for (let done = 0; done < meters - 0.01; done += step) {
        const d = Math.min(step, meters - done);
        t += Math.max(1, Math.round(d / speed));
        at = north(at, d);
        emit();
      }
    },
    wait(seconds, every = 10) {
      for (let s = 0; s < seconds; s += every) {
        t += every;
        emit();
      }
    },
  };
}

const near = (actual, expected, tolerance) =>
  assert.ok(Math.abs(actual - expected) <= tolerance, `${actual} not within ${tolerance} of ${expected}`);

const WALK = 1.4;
const CAR = 15;

describe('A trip to a place', () => {
  test('driving there is journey, walking around it is trek', () => {
    const tr = trip(north(HOME, 10000));
    tr.move(9900, CAR);
    assert.equal(tr.split.phase, PHASE.trekking);
    tr.wait(60);
    tr.move(500, WALK);
    near(tr.split.journeyMeters, 9900, 15);
    near(tr.split.trekMeters, 500, 15);
    near(tr.split.trekSeconds, 500 / WALK, 40);
  });

  test('driving on into the car park inside the zone still starts the trek', () => {
    const tr = trip(north(HOME, 3000));
    tr.move(2900, CAR);
    assert.equal(tr.split.phase, PHASE.trekking);
    tr.move(400, WALK);
    assert.equal(tr.split.phase, PHASE.trekking);
    near(tr.split.trekMeters, 400, 15);
  });

  test('walking there counts as journey until 200 m from the place', () => {
    const tr = trip(north(HOME, 2000));
    tr.move(1700, WALK);
    assert.equal(tr.split.phase, PHASE.toTrekStart);
    assert.equal(tr.split.trekMeters, 0);
    tr.move(400, WALK);
    near(tr.split.journeyMeters, 1800, 15);
    near(tr.split.trekMeters, 300, 15);
  });

  test('a return hike is trek; the drive home is journey', () => {
    const tr = trip(north(HOME, 5000));
    tr.move(5000, CAR);
    tr.move(3000, WALK);
    tr.wait(600);
    tr.move(3000, WALK);
    tr.move(5000, CAR);
    assert.equal(tr.split.phase, PHASE.returning);
    near(tr.split.trekMeters, 6000, 30);
    near(tr.split.journeyMeters, 10000, 40);
  });

  test('waiting in traffic is journey time', () => {
    const tr = trip(north(HOME, 6000));
    tr.move(3000, CAR);
    tr.wait(600);
    tr.move(3000, CAR);
    assert.equal(tr.split.trekSeconds, 0);
    assert.ok(tr.split.journeySeconds >= 16 * 60);
  });
});

describe('A trip with no place', () => {
  test('the trek starts at once; a bus ride in the middle is journey', () => {
    const tr = trip();
    assert.equal(tr.split.phase, PHASE.trekking);
    tr.move(500, WALK);
    tr.move(4000, CAR);
    near(tr.split.trekMeters, 500, 30);
    near(tr.split.journeyMeters, 4000, 40);
  });

  test('jogging is still trekking', () => {
    const tr = trip();
    tr.move(2000, 3.2);
    near(tr.split.trekMeters, 2000, 30);
    assert.equal(tr.split.journeyMeters, 0);
  });

  test('a car is spotted with readings every second', () => {
    const tr = trip();
    tr.move(100, WALK, 1);
    tr.move(2000, CAR, 1);
    assert.ok(tr.split.journeyMeters > 1700);
  });
});
