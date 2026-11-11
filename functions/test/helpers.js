// Shared test helpers: trips built from simple walks.
export const T0 = Date.UTC(2026, 9, 14, 8, 0, 0);
export const HOME = { lat: 30.7333, lng: 76.7794 };
const M_PER_DEG_LAT = 111200;

export const north = (p, meters) => ({
  lat: p.lat + meters / M_PER_DEG_LAT,
  lng: p.lng,
});

export const fix = (p, seconds, extra = {}) => ({
  lat: p.lat,
  lng: p.lng,
  t: T0 + seconds * 1000,
  acc: 8,
  ...extra,
});

/** A walk of `meters` going north from `from`, one fix every 10 s (1 m/s). */
export function walk(from, meters, startAt = 0) {
  const fixes = [fix(from, startAt)];
  let p = from;
  let t = startAt;
  for (let walked = 0; walked < meters; walked += 10) {
    t += 10;
    p = north(p, 10);
    fixes.push(fix(p, t));
  }
  return { fixes, end: p, endAt: t };
}

/**
 * An honest visit: walk [toPlace] m north to the place, then [around] m more
 * on foot around it (the trek starts within 200 m of the place).
 */
export function visit(toPlace = 600, around = 300) {
  const there = walk(HOME, toPlace);
  const more = walk(there.end, around, there.endAt);
  return {
    fixes: [...there.fixes, ...more.fixes.slice(1)],
    arriveAt: there.endAt,
    endAt: more.endAt,
  };
}

/** A trip record as the app would submit it. */
export function trip(overrides = {}) {
  return {
    tripId: 'trip-1',
    startedAt: T0,
    endedAt: T0 + 20 * 60000,
    fixes: [],
    ...overrides,
  };
}

export const history = (overrides = {}) => ({
  now: T0 + 25 * 60000,
  todayTripXp: 0,
  placeLastPaidAt: null,
  ...overrides,
});
