// Guardian adapter: health-store (Apple HealthKit / Health Connect).
//
// The health stores are Guardian's vendor-neutral aggregation layer:
// they already collect from Apple Watch, Garmin, Fitbit, Samsung, and
// most bands whose owners sync to the phone. The app reads ONE contract
// per OS instead of integrating each vendor. Native bridges (React
// Native / Flutter / native modules) implement this contract on device;
// this file defines the contract and a mock for development.
//
// Every record an adapter returns is an Observation:
// @typedef {Object} Observation
// @property {string} type        'heart_rate' | 'spo2' | 'steps' |
//                                'sleep' | 'resting_heart_rate' |
//                                'skin_temperature'
// @property {number} value
// @property {string} unit        'bpm' | '%' | 'count' | 'minutes' | 'celsius'
// @property {number} ts          epoch ms when the sample was taken
// @property {string} source      'healthkit' | 'health_connect' |
//                                'simulated' -- SIMULATED DATA IS ALWAYS
//                                LABELLED 'simulated', never dressed up
//                                as a real reading.
// @property {string} [deviceLabel] e.g. 'Apple Watch', 'generic band'
//
// HealthStoreAdapter contract (duck-typed):
//   async readObservations({ types, sinceTs }) -> Observation[]
//   async latestObservation(type) -> Observation | null

'use strict';

const SIMULATED_SERIES = {
  heart_rate: { value: 72, unit: 'bpm' },
  spo2: { value: 97, unit: '%' },
  steps: { value: 1240, unit: 'count' },
  sleep: { value: 402, unit: 'minutes' },
  resting_heart_rate: { value: 61, unit: 'bpm' },
  skin_temperature: { value: 36.4, unit: 'celsius' },
};

class MockHealthStoreAdapter {
  constructor({ platform = 'health_connect' } = {}) {
    this.platform = platform; // which store this mock stands in for
    // The mock's simulated series is materialized ONCE, at construction,
    // with fixed sample timestamps (one sample per type, 1-6 minutes
    // before construction). readObservations reports those timestamps
    // as-is: a sample's ts is when the sample was taken, and a read
    // must never re-stamp an old sample into a newer window just to
    // make the window look populated.
    const baseTs = Date.now();
    this._series = Object.keys(SIMULATED_SERIES).map((type, i) => ({
      type,
      value: SIMULATED_SERIES[type].value,
      unit: SIMULATED_SERIES[type].unit,
      ts: baseTs - (i + 1) * 60_000,
      // Honest labelling: the mock never claims a real store source.
      source: 'simulated',
      deviceLabel: `mock ${platform}`,
    }));
  }

  async readObservations({ types, sinceTs = 0 } = {}) {
    const wanted = types && types.length ? types : Object.keys(SIMULATED_SERIES);
    // Honest window semantics: only samples taken at or after sinceTs
    // are returned, with their original timestamps. A window beyond
    // the series returns an empty array, not re-stamped rows.
    return this._series
      .filter((row) => wanted.includes(row.type) && row.ts >= sinceTs)
      .map((row) => ({ ...row }));
  }

  async latestObservation(type) {
    const rows = await this.readObservations({ types: [type] });
    return rows.length ? rows[0] : null;
  }
}

module.exports = { MockHealthStoreAdapter };
