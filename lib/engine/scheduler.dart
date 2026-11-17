// Guardian escalation engine (Dart port): schedulers.
//
// Port of engine/scheduler.js (the verified Node reference). The engine
// never touches global timers or the wall clock directly; it runs
// against a [Scheduler], so behaviour is deterministic in tests
// ([FakeScheduler]) and real on device ([RealScheduler]).

import 'dart:async';

/// Scheduler contract: now() in ms, setTimeout/clearTimeout.
abstract class Scheduler {
  int now();
  Object setTimeout(void Function() fn, int ms);
  void clearTimeout(Object id);
}

class RealScheduler implements Scheduler {
  @override
  int now() => DateTime.now().millisecondsSinceEpoch;

  @override
  Object setTimeout(void Function() fn, int ms) =>
      Timer(Duration(milliseconds: ms), fn);

  @override
  void clearTimeout(Object id) {
    if (id is Timer) id.cancel();
  }
}

/// Resolves after the microtask queue has fully drained (a zero-delay
/// timer is an event-loop task, so every pending microtask runs first).
/// Equivalent of the Node reference's setImmediate-based drain.
Future<void> drainMicrotasks() => Future<void>.delayed(Duration.zero);

class _FakeTimer {
  _FakeTimer(this.fn, this.at);
  final void Function() fn;
  final int at;
}

/// Deterministic manual clock for tests. Timers fire only on advance().
class FakeScheduler implements Scheduler {
  FakeScheduler([int startAt = 0]) : _t = startAt;

  int _t;
  // Default Map is insertion-ordered (like JS Map).
  final Map<int, _FakeTimer> _timers = {};
  int _nextId = 1;

  @override
  int now() => _t;

  @override
  Object setTimeout(void Function() fn, int ms) {
    final id = _nextId++;
    _timers[id] = _FakeTimer(fn, _t + ms);
    return id;
  }

  @override
  void clearTimeout(Object id) {
    _timers.remove(id);
  }

  /// Advance the clock, firing every timer that comes due, in due-time
  /// order (insertion order breaks ties). Microtasks are drained between
  /// firings, so a one-shot advance() reaches the same end state as the
  /// equivalent stepped advances.
  Future<void> advance(int ms) async {
    final target = _t + ms;
    await drainMicrotasks();
    for (;;) {
      int? dueId;
      var dueAt = 1 << 62;
      for (final entry in _timers.entries) {
        if (entry.value.at <= target && entry.value.at < dueAt) {
          dueId = entry.key;
          dueAt = entry.value.at;
        }
      }
      if (dueId == null) break;
      final timer = _timers.remove(dueId)!;
      _t = timer.at;
      timer.fn();
      await drainMicrotasks();
    }
    _t = target;
  }
}
