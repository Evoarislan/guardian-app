// Guardian adapter: trace simulator (DEMO / PROOF ONLY, always labelled).
// Dart port of adapters/trace_simulator.js (the Node reference).
//
// HONESTY (binding, steering/safety-and-honesty.md): every Signal this
// adapter emits carries source = "simulator" and freshness = "simulated".
// The labels are applied in one place ([_emit]) and Signal is immutable,
// so a consumer cannot quietly relabel it. No timers, no I/O, no
// randomness: playFall() emits synchronously from the injected clock.

import '../engine/notifier.dart' show Location;

const String simulatorSource = 'simulator';
const String simulatorFreshness = 'simulated';

/// Normalized signal (design.md event spine).
class Signal {
  const Signal({
    required this.id,
    required this.wearerId,
    required this.kind,
    required this.value,
    required this.unit,
    required this.observedAt,
    required this.receivedAt,
  });

  final String id;
  final String wearerId;
  final String kind;
  final Map<String, dynamic> value;
  final String unit;
  final int observedAt;
  final int receivedAt;

  // Labels are constants of the type, not constructor arguments.
  String get source => simulatorSource;
  String get freshness => simulatorFreshness;

  /// Key order matches the Node Signal.
  Map<String, dynamic> toJson() => {
    'id': id,
    'wearerId': wearerId,
    'kind': kind,
    'value': Map<String, dynamic>.of(value),
    'unit': unit,
    'source': source,
    'freshness': freshness,
    'observedAt': observedAt,
    'receivedAt': receivedAt,
  };
}

class TraceSimulatorAdapter {
  TraceSimulatorAdapter({
    this.wearerId = 'synthetic-wearer-001',
    required this._now,
  });

  final String id = 'trace-simulator';
  final String wearerId;
  final int Function() _now;
  void Function(Signal)? _cb;
  int _seq = 0;

  /// Every signal ever emitted, in order.
  final List<Signal> emitted = [];

  void onSignal(void Function(Signal) cb) => _cb = cb;

  Signal _emit(String kind, Map<String, dynamic> value, String unit, int t) {
    _seq += 1;
    final signal = Signal(
      id: 'sig-sim-$_seq',
      wearerId: wearerId,
      kind: kind,
      value: value,
      unit: unit,
      observedAt: t,
      receivedAt: _now(),
    );
    emitted.add(signal);
    _cb?.call(signal);
    return signal;
  }

  /// One simulated fall; returns the fall-pattern trigger signal.
  Signal playFall({double peakG = 3.2}) {
    final t0 = _now();
    _emit('accel', {'x': 0.02, 'y': 0.98, 'z': 0.03}, 'g', t0);
    _emit('accel', {'x': 0.01, 'y': 0.99, 'z': 0.02}, 'g', t0);
    _emit('accel', {'x': 0.4, 'y': peakG, 'z': 0.6}, 'g', t0);
    _emit('accel', {'x': 0.0, 'y': 0.05, 'z': 0.97}, 'g', t0);
    _emit(
      'location',
      {'lat': 43.7615, 'lng': -79.4111, 'accuracyM': 25},
      'deg',
      t0,
    );
    return _emit('accel', {'type': 'fall_pattern', 'peakG': peakG}, 'g', t0);
  }

  /// The simulated location, labelled, for the engine's locationProvider.
  Location location() => const Location(
    lat: 43.7615,
    lng: -79.4111,
    accuracyM: 25,
    source: simulatorSource,
    freshness: simulatorFreshness,
  );
}
