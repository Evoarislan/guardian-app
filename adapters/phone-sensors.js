// Guardian adapter: phone sensors (the real-time layer).
//
// The phone is Guardian's base device: it is the only tier that
// exposes RAW accelerometer, GPS, and a voice line together. Fall
// detection and long-lie / inactivity patterns run here. Honest
// limits: fall detection only works while the phone is on the person
// (pocket or pouch), and iOS restricts background sensor work more
// than Android -- on iOS the health stores and check-ins carry more
// of the load.
//
// Contract (duck-typed):
//   onAccelerometer(cb)  cb receives { x, y, z, ts, source }
//                        (acceleration in g, ~50 Hz target on device)
//   onFallPattern(cb)    cb receives { type: 'fall_pattern',
//                        peakG, ts, source } when the on-device
//                        detector fires (impact + post-impact stillness)
//   async currentLocation() -> { lat, lng, accuracyM, ts, source }
// Native sensor bridges implement this on device; the mock emits
// labelled simulated data and can rehearse a fall on demand.

'use strict';

class MockPhoneSensorsAdapter {
  constructor() {
    this._accelCb = null;
    this._fallCb = null;
    this._timer = null;
  }

  onAccelerometer(cb) {
    this._accelCb = cb;
    if (this._timer) return;
    let tick = 0;
    this._timer = setInterval(() => {
      tick += 1;
      // Emit via the CURRENTLY registered callback: a later subscriber
      // replaces the earlier one and must receive subsequent samples.
      const current = this._accelCb;
      if (!current) return;
      // Phone at rest in a pocket: ~1g on one axis, tiny noise.
      current({
        x: 0.02 * Math.sin(tick / 7),
        y: 0.98 + 0.01 * Math.cos(tick / 9),
        z: 0.03 * Math.sin(tick / 5),
        ts: Date.now(),
        source: 'simulated',
      });
    }, 100);
  }

  onFallPattern(cb) {
    this._fallCb = cb;
  }

  /** Rehearsal helper (demo/tests): emit one simulated fall pattern. */
  simulateFall(peakG = 3.2) {
    if (this._fallCb) {
      this._fallCb({
        type: 'fall_pattern',
        peakG,
        ts: Date.now(),
        source: 'simulated',
      });
    }
  }

  async currentLocation() {
    return {
      lat: 43.7615,
      lng: -79.4111,
      accuracyM: 25,
      ts: Date.now(),
      source: 'simulated',
    };
  }

  stop() {
    if (this._timer) clearInterval(this._timer);
    this._timer = null;
  }
}

module.exports = { MockPhoneSensorsAdapter };
