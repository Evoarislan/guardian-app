// Guardian escalation engine: dispatcher interface + safe implementations.
//
// A Dispatcher hands a confirmed, unacknowledged emergency to a MONITORED
// dispatch service. Guardian NEVER dials 911 (or any emergency number)
// directly: automated dialing of emergency lines is prohibited, and real
// dispatch is legally a monitored central-station function. The
// dispatcher interface exists so a monitored service (Noonlight class)
// can sit in that seat under its own partnership and onboarding.
//
// Interface (duck-typed):
//   async dispatch(alarm) -> { status: string, reference?: string }
//     alarm: output of NoonlightSandboxDispatcher.buildAlarmPayload()
//            or the engine's internal episode summary.
//
// Dispatch is DISABLED by default in every implementation shipped here.
// No network calls are made anywhere in this scaffold.

'use strict';

/**
 * Builds the alarm payload in the shape of Noonlight's sandbox API
 * (POST /dispatch/v1/alarms). Field layout follows Noonlight's public
 * developer documentation as of Nov 2026; re-verify against their docs
 * at integration time. Building a payload is not sending it.
 *
 * @param {object} episode  { id, triggerType, startedAt, wearerName }
 * @param {object} [location] { lat, lng, accuracyM }
 * @returns {object} alarm payload (not sent)
 */
function buildNoonlightAlarmPayload(episode, location) {
  return {
    services: { police: false, fire: false, medical: true },
    location: location
      ? {
          coords: {
            lat: location.lat,
            lng: location.lng,
            accuracy: location.accuracyM != null ? location.accuracyM : 50,
          },
        }
      : undefined,
    name: episode.wearerName || 'Guardian wearer',
    instructions:
      `Guardian escalation: ${episode.triggerType}. ` +
      'Wearer did not cancel and no kin contact acknowledged.',
    // Guardian bookkeeping, kept in the built payload for local
    // inspection only; dispatch() strips this field from the body
    // actually sent to the API:
    _guardian: { episodeId: episode.id, source: 'guardian-engine' },
  };
}

class DisabledDispatcher {
  async dispatch() {
    return { status: 'disabled' };
  }
}

class MockDispatcher {
  constructor() {
    /** @type {Array<object>} */
    this.calls = [];
  }

  async dispatch(alarm) {
    this.calls.push(alarm);
    return { status: 'mock-dispatched', reference: `mock-${this.calls.length}` };
  }
}

/**
 * Noonlight sandbox dispatcher. OFF unless ALL of these hold:
 *   - constructed with enabled: true (the factory below wires this from
 *     the GUARDIAN_DISPATCH_ENABLED environment variable), AND
 *   - a token is present (GUARDIAN_NOONLIGHT_TOKEN, environment only --
 *     never hardcode, never commit), AND
 *   - a transport function is injected (the scaffold ships none, so
 *     even an "enabled" instance performs no network call here; real
 *     transport lands in the integration step, behind review).
 */
class NoonlightSandboxDispatcher {
  constructor({ enabled = false, token = null, transport = null } = {}) {
    this.enabled = enabled === true;
    this._token = token; // held in memory only; never logged, never stored
    this._transport = transport;
    this.baseUrl = 'https://api-sandbox.noonlight.com';
  }

  buildAlarmPayload(episode, location) {
    return buildNoonlightAlarmPayload(episode, location);
  }

  async dispatch(alarm) {
    if (!this.enabled || !this._token) {
      return { status: 'disabled' };
    }
    if (typeof this._transport !== 'function') {
      throw new Error(
        'NoonlightSandboxDispatcher: enabled but no transport injected; ' +
          'the scaffold performs no network calls.'
      );
    }
    // Strip Guardian's internal bookkeeping from the body actually
    // sent (it stays on the object returned by buildAlarmPayload()
    // for inspection; the caller's object is not mutated). The token
    // travels in the Authorization header only -- never in the body,
    // never logged.
    const source = alarm && typeof alarm === 'object' ? alarm : {};
    const { _guardian: _bookkeeping, ...body } = source;
    return this._transport({
      method: 'POST',
      url: `${this.baseUrl}/dispatch/v1/alarms`,
      headers: {
        Authorization: `Bearer ${this._token}`,
        'Content-Type': 'application/json',
      },
      body,
    });
  }
}

/**
 * Factory reading configuration from the environment ONLY.
 * Defaults to a DisabledDispatcher.
 */
function dispatcherFromEnv(env = process.env, transport = null) {
  if (env.GUARDIAN_DISPATCH_ENABLED === '1' && env.GUARDIAN_NOONLIGHT_TOKEN) {
    return new NoonlightSandboxDispatcher({
      enabled: true,
      token: env.GUARDIAN_NOONLIGHT_TOKEN,
      transport,
    });
  }
  return new DisabledDispatcher();
}

module.exports = {
  buildNoonlightAlarmPayload,
  DisabledDispatcher,
  MockDispatcher,
  NoonlightSandboxDispatcher,
  dispatcherFromEnv,
};
