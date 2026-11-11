// Server-side port of lib/features/tracking/domain/trip_split.dart: splits a
// trip into journey (any transport, to the trek and back) and trek (on foot
// from within 200 m of the trek's start, return hike included). Keep the two
// in step; test/trip_split.test.js mirrors test/trip_split_test.dart.
import { distanceMeters } from './trip_guard.js';

export const SPLIT = Object.freeze({
  trekStartRadiusMeters: 200,
  maxTrekSpeedMetersPerSecond: 4,
  speedWindowSeconds: 30,
  minWindowSeconds: 10,
  wobbleMeters: 25,
  minStepMeters: 3,
  vehicleLegMeters: 300,
});

export const PHASE = Object.freeze({
  toTrekStart: 'toTrekStart',
  trekking: 'trekking',
  returning: 'returning',
});

/** Fed with the fixes the trip guard accepted, in order ({lat, lng, t ms}). */
export class TripSplit {
  /** trekStart: {lat, lng}, or null to start the trek where the trip starts. */
  constructor(trekStart = null) {
    this.trekStart = trekStart;
    this.phase = PHASE.toTrekStart;
    this.trekStarted = false;
    this.inVehicle = false;
    this.trekMeters = 0;
    this.journeyMeters = 0;
    this.trekSeconds = 0;
    this.journeySeconds = 0;
    this._vehicleSinceFoot = 0;
    this._window = [];
    this._last = null;
  }

  add(fix) {
    const previous = this._last;
    this._last = fix;
    this._window.push(fix);
    while (this._window.length > 2 &&
        (fix.t - this._window[1].t) / 1000 >= SPLIT.speedWindowSeconds) {
      this._window.shift();
    }

    const inZone = this._inZone(fix);
    if (previous === null) {
      if (inZone) this._startTrek();
      return;
    }

    const seconds = (fix.t - previous.t) / 1000;
    const meters = distanceMeters(previous, fix);
    const counted = seconds < 0 ? 0 : seconds;

    if (this._isVehicle(fix, meters, seconds)) {
      this.inVehicle = true;
      this._vehicleSinceFoot += meters;
    } else if (meters >= SPLIT.minStepMeters) {
      this.inVehicle = false;
      this._vehicleSinceFoot = 0;
    }

    const moved = meters >= SPLIT.minStepMeters ? meters : 0;
    if (this.phase === PHASE.trekking && !this.inVehicle) {
      this.trekMeters += moved;
      this.trekSeconds += counted;
    } else {
      this.journeyMeters += moved;
      this.journeySeconds += counted;
    }

    if (this.phase === PHASE.toTrekStart) {
      if (inZone) this._startTrek();
    } else if (this.phase === PHASE.trekking) {
      if (this._vehicleSinceFoot >= SPLIT.vehicleLegMeters) this.phase = PHASE.returning;
    } else if (inZone && !this.inVehicle) {
      this.phase = PHASE.trekking;
    }
  }

  _startTrek() {
    this.trekStarted = true;
    this.phase = PHASE.trekking;
    this._vehicleSinceFoot = 0;
  }

  _inZone(fix) {
    return this.trekStart === null ||
      distanceMeters(fix, this.trekStart) <= SPLIT.trekStartRadiusMeters;
  }

  _isVehicle(fix, stepMeters, stepSeconds) {
    if (stepSeconds <= 0 || stepMeters / stepSeconds <= SPLIT.maxTrekSpeedMetersPerSecond) {
      return false;
    }
    const first = this._window[0];
    const span = (fix.t - first.t) / 1000;
    if (span >= SPLIT.minWindowSeconds) {
      return distanceMeters(first, fix) / span > SPLIT.maxTrekSpeedMetersPerSecond;
    }
    return stepMeters >= SPLIT.wobbleMeters;
  }
}
