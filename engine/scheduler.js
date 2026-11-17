// Guardian escalation engine: schedulers.
//
// The engine never touches global timers or the wall clock directly.
// It runs against a Scheduler so behaviour is deterministic in tests
// (FakeScheduler) and real on device (RealScheduler).
//
// Scheduler contract (duck-typed):
//   now() -> number (ms)
//   setTimeout(fn, ms) -> id
//   clearTimeout(id)

'use strict';

class RealScheduler {
  now() {
    return Date.now();
  }
  setTimeout(fn, ms) {
    return setTimeout(fn, ms);
  }
  clearTimeout(id) {
    clearTimeout(id);
  }
}

/** Resolve after the microtask queue has fully drained. */
function drainMicrotasks() {
  // setImmediate is a macrotask: every pending microtask (including
  // chains spawned by microtasks) runs before its callback fires.
  return new Promise((resolve) => setImmediate(resolve));
}

/** Deterministic manual clock for tests. Timers fire only on advance(). */
class FakeScheduler {
  constructor(startAt = 0) {
    this._t = startAt;
    this._timers = new Map();
    this._nextId = 1;
  }

  now() {
    return this._t;
  }

  setTimeout(fn, ms) {
    const id = this._nextId++;
    this._timers.set(id, { fn, at: this._t + ms });
    return id;
  }

  clearTimeout(id) {
    this._timers.delete(id);
  }

  /**
   * Advance the clock, firing every timer that comes due, in due-time
   * order (insertion order breaks ties). Async: microtasks are drained
   * between timer firings, so promise continuations triggered by one
   * firing (e.g. the engine scheduling its next step) complete before
   * the next firing is considered. A single one-shot advance() therefore
   * reaches the same end state as the equivalent stepped advances.
   */
  async advance(ms) {
    const target = this._t + ms;
    await drainMicrotasks();
    for (;;) {
      let dueId = null;
      let dueAt = Infinity;
      // Map iteration is insertion-ordered; the strict "<" keeps the
      // earliest-inserted timer among equal due times.
      for (const [id, timer] of this._timers) {
        if (timer.at <= target && timer.at < dueAt) {
          dueId = id;
          dueAt = timer.at;
        }
      }
      if (dueId === null) break;
      const timer = this._timers.get(dueId);
      this._timers.delete(dueId);
      this._t = timer.at;
      timer.fn();
      await drainMicrotasks();
    }
    this._t = target;
  }
}

module.exports = { RealScheduler, FakeScheduler };
