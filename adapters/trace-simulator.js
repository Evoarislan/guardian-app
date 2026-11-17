// Guardian adapter: trace simulator (DEMO / PROOF ONLY, always labelled).
//
// Replays a recorded-style fall trace as normalized Signals (the event
// spine shape from .kiro/specs/guardian/design.md):
//
//   Signal { id, wearerId, kind, value, unit, source, freshness,
//            observedAt, receivedAt }
//
// HONESTY (binding, steering/safety-and-honesty.md): every Signal this
// adapter emits carries source = "simulator" and freshness =
// "simulated". There is no code path here that emits anything else.
// The labels are applied in one place (_emit) and the emitted object
// is frozen, so a downstream consumer cannot quietly relabel it.
//
// No timers, no I/O, no randomness: playFall() emits synchronously and
// deterministically from the injected clock, so a proof run is
// reproducible.

'use strict';

const SOURCE = 'simulator';
const FRESHNESS = 'simulated';

class TraceSimulatorAdapter {
  /**
   * @param {object} [options]
   * @param {string} [options.wearerId] synthetic wearer id
   * @param {() => number} [options.now] clock in ms (inject the
   *   scheduler's now() so signal times match the engine log's clock)
   */
  constructor({ wearerId = 'synthetic-wearer-001', now = () => Date.now() } = {}) {
    this.id = 'trace-simulator';
    this.wearerId = wearerId;
    this._now = now;
    this._cb = null;
    this._seq = 0;
    /** every signal ever emitted, in order (for the proof printout) */
    this.emitted = [];
  }

  /** Register the single consumer of emitted Signals. */
  onSignal(cb) {
    this._cb = cb;
  }

  _emit(kind, value, unit, observedAt) {
    this._seq += 1;
    const signal = Object.freeze({
      id: `sig-sim-${this._seq}`,
      wearerId: this.wearerId,
      kind,
      value,
      unit,
      source: SOURCE,
      freshness: FRESHNESS,
      observedAt,
      receivedAt: this._now(),
    });
    this.emitted.push(signal);
    if (this._cb) this._cb(signal);
    return signal;
  }

  /**
   * Play one simulated fall: a few at-rest samples, an impact spike,
   * post-impact stillness, a simulated location fix, and finally the
   * fall-pattern trigger signal the detector would raise.
   * @param {object} [options]
   * @param {number} [options.peakG=3.2]
   * @returns {object} the trigger Signal (kind "accel", value.type
   *   "fall_pattern")
   */
  playFall({ peakG = 3.2 } = {}) {
    const t0 = this._now();
    // At rest: ~1 g on one axis.
    this._emit('accel', { x: 0.02, y: 0.98, z: 0.03 }, 'g', t0);
    this._emit('accel', { x: 0.01, y: 0.99, z: 0.02 }, 'g', t0);
    // Impact spike.
    this._emit('accel', { x: 0.4, y: peakG, z: 0.6 }, 'g', t0);
    // Post-impact stillness (the "long lie" start).
    this._emit('accel', { x: 0.0, y: 0.05, z: 0.97 }, 'g', t0);
    this._emit('location', { lat: 43.7615, lng: -79.4111, accuracyM: 25 }, 'deg', t0);
    return this._emit('accel', { type: 'fall_pattern', peakG }, 'g', t0);
  }

  /** The simulated location, labelled, for the engine's locationProvider. */
  location() {
    return Object.freeze({
      lat: 43.7615,
      lng: -79.4111,
      accuracyM: 25,
      source: SOURCE,
      freshness: FRESHNESS,
    });
  }
}

module.exports = { TraceSimulatorAdapter, SOURCE, FRESHNESS };
