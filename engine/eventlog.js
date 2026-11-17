// Guardian escalation engine: hash-chained event log.
//
// Every state transition and notable event in an escalation episode is
// appended here. Each entry carries a hash of its own content chained
// to the previous entry's hash, so any later edit, deletion, or
// reordering of history is detectable by verify().
//
// Keyed mode: if the environment variable GUARDIAN_LOG_KEY is set when
// the log is constructed, entries are chained with HMAC-SHA256 under
// that key instead of a plain SHA-256. A chain built under a key cannot
// be recomputed by someone who does not hold the key.
//
// HONEST LIMIT (read this before trusting the chain): tamper-EVIDENCE
// holds against an anchor. anchor() returns { count, headHash }; if
// that pair is stored OUTSIDE this log (printed, emailed, written to
// another system) and later passed to verify(anchor), edits,
// truncation, and wholesale replacement of the entries are all
// detected. WITHOUT an externally stored anchor or the key, an
// attacker who can rewrite the entire log can also recompute a
// self-consistent plain chain, and that full rewrite is UNDETECTABLE
// by verify() alone. Anchoring the head externally is what makes the
// chain evidentiary; the chain by itself is only tamper-evident
// against partial edits.
//
// Pattern note: hash-chained, append-only receipt logs are a known
// technique (used in our earlier proof-of-work projects); this is a
// fresh implementation written for Guardian.

'use strict';

const { createHash, createHmac } = require('node:crypto');

const GENESIS_HASH = 'guardian-genesis';

function hashEntry(key, seq, ts, type, data, prevHash) {
  const payload = JSON.stringify({ seq, ts, type, data, prevHash });
  return key
    ? createHmac('sha256', key).update(payload).digest('hex')
    : createHash('sha256').update(payload).digest('hex');
}

class EventLog {
  /**
   * @param {Function} [nowFn] clock, defaults to Date.now
   * @param {object} [options]
   * @param {string|null} [options.key] HMAC key; defaults to
   *   process.env.GUARDIAN_LOG_KEY when set, otherwise plain SHA-256.
   */
  constructor(nowFn, options = {}) {
    this._now = typeof nowFn === 'function' ? nowFn : () => Date.now();
    this._key =
      options.key != null
        ? options.key
        : process.env.GUARDIAN_LOG_KEY || null;
    this.entries = [];
  }

  /** True when this log chains entries with HMAC-SHA256 under a key. */
  get keyed() {
    return this._key != null;
  }

  /**
   * Append an event. Returns the stored entry (including its hash).
   * @param {string} type
   * @param {object} [data]
   */
  append(type, data = {}) {
    const seq = this.entries.length;
    const ts = this._now();
    const prevHash = seq === 0 ? GENESIS_HASH : this.entries[seq - 1].hash;
    const hash = hashEntry(this._key, seq, ts, type, data, prevHash);
    const entry = { seq, ts, type, data, prevHash, hash };
    this.entries.push(entry);
    return entry;
  }

  /**
   * A compact external reference to the current chain head. Store the
   * returned pair OUTSIDE this log; passing it back to verify(anchor)
   * later detects truncation and replacement, which a bare verify()
   * cannot (see the honest-limit note at the top of this file).
   * @returns {{count: number, headHash: string}}
   */
  anchor() {
    return {
      count: this.entries.length,
      headHash:
        this.entries.length === 0
          ? GENESIS_HASH
          : this.entries[this.entries.length - 1].hash,
    };
  }

  /**
   * Recompute the whole chain. When an anchor previously returned by
   * anchor() is supplied, the chain must ALSO still end at that anchor:
   * a different entry count (e.g. entries truncated away, which leaves
   * an internally consistent prefix) or a different head hash fails.
   * @param {{count: number, headHash: string}} [anchor]
   * @returns {{ok: boolean, failedAt: number|null}}
   *   failedAt is the seq of the first entry that does not check out.
   */
  verify(anchor) {
    for (let i = 0; i < this.entries.length; i++) {
      const e = this.entries[i];
      const expectedPrev = i === 0 ? GENESIS_HASH : this.entries[i - 1].hash;
      if (e.seq !== i) return { ok: false, failedAt: i };
      if (e.prevHash !== expectedPrev) return { ok: false, failedAt: i };
      if (e.hash !== hashEntry(this._key, e.seq, e.ts, e.type, e.data, e.prevHash)) {
        return { ok: false, failedAt: i };
      }
    }
    if (anchor) {
      if (this.entries.length !== anchor.count) {
        // First seq that no longer matches the anchored chain: the
        // first missing entry if truncated, the first extra if extended.
        return {
          ok: false,
          failedAt: Math.min(this.entries.length, anchor.count),
        };
      }
      const headHash =
        this.entries.length === 0
          ? GENESIS_HASH
          : this.entries[this.entries.length - 1].hash;
      if (headHash !== anchor.headHash) {
        return { ok: false, failedAt: Math.max(0, this.entries.length - 1) };
      }
    }
    return { ok: true, failedAt: null };
  }

  /**
   * Serializable snapshot of the log, so a proof runner can write the
   * episode log to a file (e.g. episode-log.json). JSON.stringify(log)
   * produces the same shape via toJSON().
   * @returns {{keyed: boolean, entries: Array<object>}}
   */
  toJSON() {
    return {
      keyed: this.keyed,
      entries: this.entries.map((e) => ({ ...e })),
    };
  }

  /** JSON string form of toJSON(), ready to write to disk. */
  serialize() {
    return JSON.stringify(this.toJSON(), null, 2);
  }
}

module.exports = { EventLog, GENESIS_HASH };
