// Mock health-store adapter (Dart port of the contract in
// adapters/health-store.js). SIMULATED data only: every row carries
// source 'simulated' and its real timestamp; nothing is re-stamped.
// Ported in Session 2 only so the Node suite's FIX11 scenario has a
// Dart mirror. Real Health Connect / HealthKit reads are Phase 3.

class HealthObservation {
  const HealthObservation({
    required this.type,
    required this.value,
    required this.unit,
    required this.ts,
    required this.source,
    required this.deviceLabel,
  });
  final String type;
  final num value;
  final String unit;
  final int ts;
  final String source;
  final String deviceLabel;
}

const Map<String, ({num value, String unit})> _simulatedSeries = {
  'heart_rate': (value: 72, unit: 'bpm'),
  'spo2': (value: 97, unit: '%'),
  'steps': (value: 1240, unit: 'count'),
  'sleep': (value: 402, unit: 'minutes'),
  'resting_heart_rate': (value: 61, unit: 'bpm'),
  'skin_temperature': (value: 36.4, unit: 'celsius'),
};

class MockHealthStoreAdapter {
  MockHealthStoreAdapter({this.platform = 'health_connect'}) {
    final baseTs = DateTime.now().millisecondsSinceEpoch;
    var i = 0;
    for (final type in _simulatedSeries.keys) {
      final s = _simulatedSeries[type]!;
      _series.add(HealthObservation(
        type: type,
        value: s.value,
        unit: s.unit,
        ts: baseTs - (i + 1) * 60000,
        source: 'simulated',
        deviceLabel: 'mock $platform',
      ));
      i += 1;
    }
  }

  final String platform;
  final List<HealthObservation> _series = [];

  Future<List<HealthObservation>> readObservations({
    List<String>? types,
    int sinceTs = 0,
  }) async {
    final wanted =
        (types != null && types.isNotEmpty) ? types : _simulatedSeries.keys.toList();
    return _series
        .where((row) => wanted.contains(row.type) && row.ts >= sinceTs)
        .toList();
  }

  Future<HealthObservation?> latestObservation(String type) async {
    final rows = await readObservations(types: [type]);
    return rows.isEmpty ? null : rows.first;
  }
}
