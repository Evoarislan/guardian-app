// Guardian escalation engine: the state machine.
//
//   IDLE
//     |  trigger(fall_pattern | inactivity | missed_checkin | manual_sos)
//     v
//   TRIGGERED  (recorded, then immediately ->)
//   CANCEL_WINDOW  (wearer may cancel; cancel -> IDLE, logged)
//     |  window lapses without cancel
//     v
//   CASCADE  (kin contacts notified in order; each gets an ack timeout.
//     |        First acknowledgment stops the cascade -> RESOLVED.
//     |        The wearer may still cancel here, any time before the
//     |        dispatcher is actually invoked; cancel -> IDLE, logged.)
//     |  all contacts exhausted without acknowledgment
//     v
//   DISPATCH  (monitored dispatch service via dispatcher interface.
//     |         Guardian NEVER dials emergency numbers directly. Once
//     |         dispatch() has been invoked the episode is beyond
//     |         recall: a late cancel is logged and refused.)
//     v
//   RESOLVED
//
// If the notifier or dispatcher throws, the failure is logged as
// engine_error, the episode ends RESOLVED with resolution "error",
// and the episode is cleared so a new trigger can start (after the
// usual reset() from RESOLVED) without a process restart.
//
// Every transition is appended to a hash-chained EventLog. Side
// effects are logged BEFORE they happen (cascade_notify_pending,
// dispatch_pending) as well as after (cascade_notified,
// dispatch_result): log-before-side-effect keeps the record honest
// even if the process dies mid-call. All timing runs through an
// injected Scheduler: deterministic under test, real on device.

'use strict';

const { EventLog } = require('./eventlog');
const { RealScheduler } = require('./scheduler');

const STATES = Object.freeze({
  IDLE: 'IDLE',
  TRIGGERED: 'TRIGGERED',
  CANCEL_WINDOW: 'CANCEL_WINDOW',
  CASCADE: 'CASCADE',
  DISPATCH: 'DISPATCH',
  RESOLVED: 'RESOLVED',
});

const TRIGGER_TYPES = Object.freeze([
  'fall_pattern',
  'inactivity',
  'missed_checkin',
  'manual_sos',
]);

// Process-local instance sequence: every engine instance gets a unique
// tag, so episode IDs minted by different instances never collide even
// though each instance numbers its own episodes from 1.
let engineInstanceCounter = 0;

class EscalationEngine {
  /**
   * @param {object} config
   * @param {Array<{id: string, name: string, phone?: string}>} config.contacts
   *   Ordered kin cascade. First acknowledgment wins.
   * @param {number} [config.cancelWindowSeconds=60]
   * @param {number} [config.cascadeAckTimeoutSeconds=120]
   *   How long each contact gets to acknowledge before the cascade
   *   moves on. When the last contact's timeout lapses, that IS the
   *   no-response timeout that permits dispatch.
   * @param {object} config.notifier    notify(contact, alert) interface
   * @param {object} config.dispatcher  dispatch(alarm) interface
   * @param {object} [config.scheduler] defaults to RealScheduler
   * @param {string} [config.wearerName]
   * @param {Function|object} [config.locationProvider]
   *   Optional: () -> {lat, lng, accuracyM} or a plain location object.
   */
  constructor(config) {
    if (!config || !Array.isArray(config.contacts) || config.contacts.length === 0) {
      throw new Error('EscalationEngine: config.contacts must be a non-empty ordered array');
    }
    if (!config.notifier || typeof config.notifier.notify !== 'function') {
      throw new Error('EscalationEngine: config.notifier with notify() is required');
    }
    if (!config.dispatcher || typeof config.dispatcher.dispatch !== 'function') {
      throw new Error('EscalationEngine: config.dispatcher with dispatch() is required');
    }
    this.contacts = config.contacts.slice();
    this.cancelWindowMs = (config.cancelWindowSeconds != null ? config.cancelWindowSeconds : 60) * 1000;
    this.cascadeAckTimeoutMs =
      (config.cascadeAckTimeoutSeconds != null ? config.cascadeAckTimeoutSeconds : 120) * 1000;
    this.notifier = config.notifier;
    this.dispatcher = config.dispatcher;
    this.scheduler = config.scheduler || new RealScheduler();
    this.wearerName = config.wearerName || 'Guardian wearer';
    this.locationProvider = config.locationProvider || null;

    engineInstanceCounter += 1;
    this._instanceTag = `i${engineInstanceCounter}`;
    this._episodeCounter = 0;

    this.log = new EventLog(() => this.scheduler.now());
    this.state = STATES.IDLE;
    this.episode = null;
    this._pendingAck = null; // { contactId, finish } while CASCADE waits
    this._activeWaits = new Set(); // interruptible plain waits (cancel window)
    this._dispatchInvoked = false;
  }

  _transition(to, data = {}) {
    const from = this.state;
    this.state = to;
    this.log.append('transition', { from, to, episodeId: this.episode ? this.episode.id : null, ...data });
  }

  _location() {
    if (!this.locationProvider) return undefined;
    return typeof this.locationProvider === 'function'
      ? this.locationProvider()
      : this.locationProvider;
  }

  /** Plain wait that wearerCancel()/_failEpisode() can interrupt. */
  _wait(ms) {
    return new Promise((resolve) => {
      const handle = { timerId: null, resolve };
      handle.timerId = this.scheduler.setTimeout(() => {
        this._activeWaits.delete(handle);
        resolve('elapsed');
      }, ms);
      this._activeWaits.add(handle);
    });
  }

  /** Stop every pending timer/wait for the active episode. */
  _interruptWaits() {
    for (const handle of [...this._activeWaits]) {
      this.scheduler.clearTimeout(handle.timerId);
      handle.resolve('interrupted');
    }
    this._activeWaits.clear();
    if (this._pendingAck) {
      this._pendingAck.finish({ acknowledged: false, reason: 'interrupted' });
    }
  }

  /**
   * Register the pending-ack slot for a contact and return a promise
   * for its outcome: { acknowledged: true, by } or
   * { acknowledged: false, reason: 'timeout' | 'interrupted' }.
   * The slot is registered BEFORE the contact is notified, so an
   * acknowledgment that arrives during (or racing) the notify call
   * itself is still captured.
   */
  _beginAckWait(contactId, ms) {
    return new Promise((resolve) => {
      let settled = false;
      const finish = (result) => {
        if (settled) return;
        settled = true;
        this.scheduler.clearTimeout(timerId);
        if (this._pendingAck && this._pendingAck.finish === finish) {
          this._pendingAck = null;
        }
        resolve(result);
      };
      const timerId = this.scheduler.setTimeout(() => {
        finish({ acknowledged: false, reason: 'timeout' });
      }, ms);
      this._pendingAck = { contactId, finish };
    });
  }

  /** End the active episode as an error: log, RESOLVED(error), clear. */
  _failEpisode(episode, err) {
    if (!episode || this.episode !== episode) return;
    this.log.append('engine_error', {
      episodeId: episode.id,
      message: String(err && err.message ? err.message : err),
    });
    this._interruptWaits();
    this._transition(STATES.RESOLVED, { resolution: 'error' });
    this.episode = null;
  }

  /**
   * Start an escalation episode. Valid only from IDLE.
   * @param {string} triggerType one of TRIGGER_TYPES
   * @param {object} [details] trigger evidence (kept in the log)
   * @returns {boolean} true if the episode started
   */
  trigger(triggerType, details = {}) {
    if (this.state !== STATES.IDLE) return false;
    if (!TRIGGER_TYPES.includes(triggerType)) {
      throw new Error(`EscalationEngine: unknown trigger type "${triggerType}"`);
    }
    this._episodeCounter += 1;
    const episode = {
      id: `ep-${this._instanceTag}-${this._episodeCounter}`,
      triggerType,
      startedAt: this.scheduler.now(),
      wearerName: this.wearerName,
      notifiedContacts: new Set(),
    };
    this.episode = episode;
    this._dispatchInvoked = false;
    this.log.append('trigger_received', {
      episodeId: episode.id,
      triggerType,
      details,
    });
    this._transition(STATES.TRIGGERED, { triggerType });
    this._transition(STATES.CANCEL_WINDOW, {
      cancelWindowMs: this.cancelWindowMs,
    });
    // Fire-and-forget the episode runner; all outcomes land in the log.
    this._runEpisode().catch((err) => this._failEpisode(episode, err));
    return true;
  }

  /**
   * The wearer says "I am okay". Accepted during the cancel window AND
   * during the cascade, any time before the dispatcher is actually
   * invoked: timers/waits are stopped, the cancel is logged, and the
   * episode ends (return to IDLE, as with a cancel-window cancel).
   * Once dispatch() has been invoked the episode is beyond recall:
   * the attempt is logged and false is returned.
   * @returns {boolean} true if a cancel was accepted
   */
  wearerCancel() {
    if (!this.episode) return false;
    if (this._dispatchInvoked) {
      this.log.append('wearer_cancel_rejected', {
        episodeId: this.episode.id,
        reason: 'beyond_recall',
        detail: 'dispatch already invoked',
      });
      return false;
    }
    if (this.state !== STATES.CANCEL_WINDOW && this.state !== STATES.CASCADE) {
      return false;
    }
    this.log.append('wearer_cancelled', {
      episodeId: this.episode.id,
      duringState: this.state,
    });
    this._interruptWaits();
    this._transition(STATES.IDLE, { reason: 'wearer_cancelled' });
    this.episode = null;
    return true;
  }

  /**
   * A kin contact acknowledges ("I am responding"). Stops the cascade.
   * Any contact already notified in the active episode may acknowledge,
   * even if the cascade has since moved on to a later contact: their
   * (late) ack resolves the currently pending wait.
   * @returns {boolean} true if this acknowledgment was consumed
   */
  acknowledge(contactId) {
    if (
      this.state === STATES.CASCADE &&
      this.episode &&
      this._pendingAck &&
      this.episode.notifiedContacts.has(contactId)
    ) {
      this._pendingAck.finish({ acknowledged: true, by: contactId });
      return true;
    }
    return false;
  }

  async _runEpisode() {
    const episode = this.episode;
    try {
      // CANCEL_WINDOW: lapse -> cascade, unless wearerCancel() intervened.
      await this._wait(this.cancelWindowMs);
      if (this.episode !== episode || this.state !== STATES.CANCEL_WINDOW) {
        return; // cancelled (or superseded); cancel already logged
      }
      this.log.append('cancel_window_lapsed', { episodeId: episode.id });

      // CASCADE: contacts in order, first acknowledgment wins.
      this._transition(STATES.CASCADE, {});
      for (const contact of this.contacts) {
        if (this.episode !== episode) return;
        const alert = {
          episodeId: episode.id,
          triggerType: episode.triggerType,
          message:
            `Guardian alert: possible ${episode.triggerType.replace(/_/g, ' ')} ` +
            `for ${episode.wearerName}. Please acknowledge if you are responding.`,
          location: this._location(),
        };
        // Fix: the ack slot exists BEFORE notify runs, so an ack that
        // arrives during the notify call itself is not lost.
        const ackWait = this._beginAckWait(contact.id, this.cascadeAckTimeoutMs);
        episode.notifiedContacts.add(contact.id);
        // Log-before-side-effect: the intent entry lands first.
        this.log.append('cascade_notify_pending', {
          episodeId: episode.id,
          contactId: contact.id,
        });
        const result = await this.notifier.notify(contact, alert);
        this.log.append('cascade_notified', {
          episodeId: episode.id,
          contactId: contact.id,
          delivered: !!(result && result.delivered),
          channel: result && result.channel ? result.channel : 'unknown',
        });

        const ack = await ackWait;
        if (this.episode !== episode) return; // cancelled while waiting
        if (ack.acknowledged) {
          this.log.append('cascade_acknowledged', {
            episodeId: episode.id,
            contactId: ack.by,
            pendingContactId: contact.id,
          });
          this._transition(STATES.RESOLVED, {
            resolution: 'acknowledged',
            by: ack.by,
          });
          this.episode = null;
          return;
        }
        this.log.append('cascade_no_response', {
          episodeId: episode.id,
          contactId: contact.id,
          waitedMs: this.cascadeAckTimeoutMs,
        });
      }

      // DISPATCH: cascade exhausted with no acknowledgment.
      if (this.episode !== episode) return;
      this._transition(STATES.DISPATCH, { reason: 'cascade_exhausted' });
      const alarm =
        typeof this.dispatcher.buildAlarmPayload === 'function'
          ? this.dispatcher.buildAlarmPayload(episode, this._location())
          : { episodeId: episode.id, triggerType: episode.triggerType };
      // Log-before-side-effect: the intent entry lands first. From the
      // invoke line below, the episode is beyond wearer recall.
      this.log.append('dispatch_pending', { episodeId: episode.id });
      this._dispatchInvoked = true;
      const dispatchResult = await this.dispatcher.dispatch(alarm);
      this.log.append('dispatch_result', {
        episodeId: episode.id,
        status: dispatchResult && dispatchResult.status ? dispatchResult.status : 'unknown',
        reference:
          dispatchResult && dispatchResult.reference ? dispatchResult.reference : null,
      });
      this._transition(STATES.RESOLVED, {
        resolution: 'dispatched',
        dispatchStatus: dispatchResult && dispatchResult.status,
      });
      this.episode = null;
    } catch (err) {
      this._failEpisode(episode, err);
    }
  }

  /** Start a fresh episode cycle after RESOLVED. */
  reset() {
    if (this.state === STATES.RESOLVED) {
      this._transition(STATES.IDLE, { reason: 'reset' });
      return true;
    }
    return false;
  }
}

module.exports = { EscalationEngine, STATES, TRIGGER_TYPES };
