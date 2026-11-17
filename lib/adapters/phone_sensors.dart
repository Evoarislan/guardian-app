// Mock phone-sensors adapter (Dart port of the contract in
// adapters/phone-sensors.js). SIMULATED data only: every sample carries
// source 'simulated'. Ported in Session 2 only so the Node suite's FIX9
// scenario has a Dart mirror. The real sensor adapter is Phase 2.

import 'dart:async';
import 'dart:math' as math;

class AccelSample {
  const AccelSample({
    required this.x,
    required this.y,
    required this.z,
    required this.ts,
    required this.source,
  });
  final double x, y, z;
  final int ts;
  final String source;
}

class MockPhoneSensorsAdapter {
  void Function(AccelSample)? _accelCb;
  void Function(Map<String, dynamic>)? _fallCb;
  Timer? _timer;

  /// Registers the accelerometer callback. A later call REPLACES the
  /// earlier callback; only the current one receives samples.
  void onAccelerometer(void Function(AccelSample) cb) {
    _accelCb = cb;
    if (_timer != null) return;
    var tick = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      tick += 1;
      final current = _accelCb;
      if (current == null) return;
      current(AccelSample(
        x: 0.02 * math.sin(tick / 7),
        y: 0.98 + 0.01 * math.cos(tick / 9),
        z: 0.03 * math.sin(tick / 5),
        ts: DateTime.now().millisecondsSinceEpoch,
        source: 'simulated',
      ));
    });
  }

  void onFallPattern(void Function(Map<String, dynamic>) cb) {
    _fallCb = cb;
  }

  /// Rehearsal helper (demo/tests): emit one simulated fall pattern.
  void simulateFall([double peakG = 3.2]) {
    _fallCb?.call({
      'type': 'fall_pattern',
      'peakG': peakG,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'source': 'simulated',
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
