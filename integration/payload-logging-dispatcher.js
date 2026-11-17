// Guardian integration: payload-logging dispatcher wrapper.
//
// Why this exists: the engine (pre-existing, unmodified) calls
// dispatcher.buildAlarmPayload() and then logs only `dispatch_pending`
// with the episode id, so the sandbox payload itself never reaches the
// event log. The Session 1 claim is "payload built and written to the
// log, never sent". This wrapper delegates to the engine's own
// NoonlightSandboxDispatcher (dispatch DISABLED: no token, no
// transport, no network) and appends the built payload to the log
// BEFORE the engine logs dispatch_pending, preserving
// log-before-side-effect ordering.
//
// It appends through the public EventLog.append(), so the hash chain
// stays valid. It does not touch engine internals.

'use strict';

const { NoonlightSandboxDispatcher } = require('../engine');

class PayloadLoggingDispatcher {
  /**
   * @param {object} [options]
   * @param {object} [options.labels] data-source labels recorded next
   *   to the payload (the engine's payload builder drops unknown
   *   fields, so the labels travel beside it, not inside it)
   */
  constructor({ labels = {} } = {}) {
    // Disabled by construction: enabled=false, no token, no transport.
    this._inner = new NoonlightSandboxDispatcher({ enabled: false });
    this._labels = labels;
    this._log = null;
    /** payloads built this run (local inspection only) */
    this.built = [];
    /** dispatch() calls received (all answered "disabled") */
    this.dispatchCalls = 0;
  }

  /** Attach the engine's log once the engine exists. */
  attachLog(log) {
    this._log = log;
  }

  buildAlarmPayload(episode, location) {
    if (!this._log) {
      throw new Error('PayloadLoggingDispatcher: attachLog() was not called');
    }
    const payload = this._inner.buildAlarmPayload(episode, location);
    this.built.push(payload);
    this._log.append('sandbox_payload_built', {
      episodeId: episode.id,
      endpoint: `${this._inner.baseUrl}/dispatch/v1/alarms`,
      sent: false,
      reason: 'dispatch disabled in this build: no token, no transport, no network call',
      dataLabels: this._labels,
      payload,
    });
    return payload;
  }

  async dispatch(alarm) {
    this.dispatchCalls += 1;
    // Inner dispatcher is disabled: returns { status: 'disabled' } and
    // performs no network call.
    return this._inner.dispatch(alarm);
  }
}

module.exports = { PayloadLoggingDispatcher };
