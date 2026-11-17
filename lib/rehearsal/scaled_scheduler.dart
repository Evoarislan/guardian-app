// A Scheduler that runs episode time faster than real time.
//
// The engine keeps its canonical durations (60 s cancel window, 120 s
// per-contact ack timeout) in EPISODE time. This decorator maps episode
// time onto an inner scheduler: a timer for N episode-ms fires after
// N / scale real ms on the inner scheduler, and now() reports episode
// time (start + real elapsed * scale). The engine and its log therefore
// see unshortened windows; only the wall-clock wait is compressed.
//
// No I/O. The inner scheduler is injected (RealScheduler in the app,
// FakeScheduler in tests).

import 'dart:async';

import '../engine/scheduler.dart';

/// Default rehearsal scale: 1 real second = 10 episode seconds.
const int defaultRehearsalScale = 10;

class ScaledScheduler implements Scheduler {
  ScaledScheduler({
    Scheduler? inner,
    this.scale = defaultRehearsalScale,
    int? startAt,
  }) : inner = inner ?? RealScheduler(),
       assert(scale >= 1) {
    _realStart = this.inner.now();
    _episodeStart = startAt ?? _realStart;
  }

  final Scheduler inner;

  /// Episode seconds per real second.
  final int scale;

  late final int _realStart;
  late final int _episodeStart;
  final Set<Object> _live = {};

  /// Called (on a later event-loop turn, after the engine's microtasks
  /// have run) every time a timer fires. The UI uses it to refresh.
  void Function()? onFire;

  @override
  int now() => _episodeStart + (inner.now() - _realStart) * scale;

  /// Episode milliseconds since this scheduler was created.
  int get episodeElapsedMs => now() - _episodeStart;

  /// Real milliseconds since this scheduler was created.
  int get realElapsedMs => inner.now() - _realStart;

  /// Real milliseconds the inner scheduler waits for [episodeMs].
  int realMsFor(int episodeMs) => (episodeMs / scale).round();

  @override
  Object setTimeout(void Function() fn, int ms) {
    late final Object id;
    id = inner.setTimeout(() {
      _live.remove(id);
      fn();
      final notify = onFire;
      if (notify != null) Timer.run(notify);
    }, realMsFor(ms));
    _live.add(id);
    return id;
  }

  @override
  void clearTimeout(Object id) {
    _live.remove(id);
    inner.clearTimeout(id);
  }

  /// Drop every pending timer (screen closed mid-rehearsal). Nothing is
  /// logged: the abandoned episode simply stops.
  void shutdown() {
    onFire = null;
    for (final id in List.of(_live)) {
      inner.clearTimeout(id);
    }
    _live.clear();
  }
}
