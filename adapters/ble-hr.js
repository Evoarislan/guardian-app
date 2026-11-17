// Guardian adapter: BLE Heart Rate Profile (service 0x180D,
// characteristic 0x2A37).
//
// The adopted Bluetooth Heart Rate Profile is the one genuinely open
// live route to a wearable: any app may subscribe, no vendor account.
// Honest coverage note (from the feasibility audit): chest straps and
// some watches expose 0x180D reliably; most cheap wrist bands do NOT
// expose it to third-party apps outside workout mode. This adapter is
// therefore one ingestion route among several, never the only one.
//
// Contract (duck-typed):
//   async connect(deviceId) -> void
//   onHeartRate(cb)  cb receives Observation { type: 'heart_rate',
//                    value: bpm, unit: 'bpm', ts, source: 'ble-hr',
//                    deviceLabel }
//   async disconnect() -> void
// A native BLE bridge (e.g. react-native-ble-plx class) implements
// this on device. The mock below emits labelled simulated readings.

'use strict';

class MockBleHrAdapter {
  constructor({ intervalMs = 1000, baseBpm = 70 } = {}) {
    this.intervalMs = intervalMs;
    this.baseBpm = baseBpm;
    this._cb = null;
    this._timer = null;
    this._beat = 0;
    this.deviceLabel = 'mock chest strap';
  }

  async connect(deviceId) {
    this.deviceId = deviceId || 'mock-device';
    if (this._cb) this._start();
  }

  onHeartRate(cb) {
    this._cb = cb;
    if (this.deviceId) this._start();
  }

  _start() {
    if (this._timer) return;
    this._timer = setInterval(() => {
      this._beat += 1;
      // Deterministic gentle wander around the base rate.
      const value = this.baseBpm + Math.round(4 * Math.sin(this._beat / 5));
      this._cb({
        type: 'heart_rate',
        value,
        unit: 'bpm',
        ts: Date.now(),
        source: 'simulated', // mock data is always labelled simulated
        deviceLabel: this.deviceLabel,
      });
    }, this.intervalMs);
  }

  async disconnect() {
    if (this._timer) clearInterval(this._timer);
    this._timer = null;
    this.deviceId = null;
  }
}

module.exports = { MockBleHrAdapter, HEART_RATE_SERVICE: '180D', HEART_RATE_MEASUREMENT: '2A37' };
