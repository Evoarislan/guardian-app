// Export-format cross-check: replays the two Session 1 proof scenarios
// (cancelled, escalated) on the DART engine, with the same setup as
// integration/run-proof.js, and compares the serialized log against the
// Node export proofs/episode-log.json.
//
// Setup mirrored from the Node proof runner: three synthetic kin, default
// windows (cancel 60 s, ack 120 s), FakeScheduler seeded with the Node
// run's first-entry timestamp, trigger evidence and location taken from
// the Node export (the simulator adapter is not ported), and a payload-
// logging dispatcher wrapper (disabled, no token, no transport) that
// appends sandbox_payload_built before the engine logs dispatch_pending.
// Runs are created cancelled-first, then escalated, exactly like the Node
// runner, so the engines' instance tags (i1, i2) and episode ids match.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/engine/guardian_engine.dart';

const kin = [
  Contact(id: 'kin-1', name: 'Synthetic Kin 1 (first in wearer order)'),
  Contact(id: 'kin-2', name: 'Synthetic Kin 2'),
  Contact(id: 'kin-3', name: 'Synthetic Kin 3'),
];

/// Port of integration/payload-logging-dispatcher.js (test support).
class PayloadLoggingDispatcher implements Dispatcher, AlarmPayloadBuilder {
  PayloadLoggingDispatcher(this.labels);
  final Map<String, dynamic> labels;
  final NoonlightSandboxDispatcher _inner =
      NoonlightSandboxDispatcher(enabled: false);
  late EventLog log;
  final List<Map<String, dynamic>> built = [];
  int dispatchCalls = 0;

  @override
  Map<String, dynamic> buildAlarmPayload(Episode episode, Location? location) {
    final payload = _inner.buildAlarmPayload(episode, location);
    built.add(payload);
    log.append('sandbox_payload_built', {
      'episodeId': episode.id,
      'endpoint': '${_inner.baseUrl}/dispatch/v1/alarms',
      'sent': false,
      'reason':
          'dispatch disabled in this build: no token, no transport, no network call',
      'dataLabels': labels,
      'payload': payload,
    });
    return payload;
  }

  @override
  Future<DispatchResult> dispatch(Map<String, dynamic> alarm) {
    dispatchCalls += 1;
    return _inner.dispatch(alarm);
  }
}

class Run {
  Run(this.engine, this.scheduler, this.notifier, this.dispatcher);
  final EscalationEngine engine;
  final FakeScheduler scheduler;
  final MockNotifier notifier;
  final PayloadLoggingDispatcher dispatcher;
}

Run build(Map<String, dynamic> nodeRun) {
  final entries = nodeRun['entries'] as List;
  final start = (entries.first as Map)['ts'] as int;
  // Location comes from the Node export (escalated run notified kin with
  // it); the cancelled run never logs a location.
  final calls = nodeRun['notifierCalls'] as List;
  final loc = calls.isNotEmpty ? calls.first['location'] as Map? : null;
  final scheduler = FakeScheduler(start);
  final notifier = MockNotifier();
  final dispatcher =
      PayloadLoggingDispatcher(Map<String, dynamic>.from(nodeRun['dataLabels']));
  final engine = EscalationEngine(
    contacts: kin,
    cancelWindowSeconds: 60,
    cascadeAckTimeoutSeconds: 120,
    notifier: notifier,
    dispatcher: dispatcher,
    scheduler: scheduler,
    wearerName: 'Synthetic demo wearer',
    locationProvider: () => Location(
      lat: (loc?['lat'] ?? 43.7615) as double,
      lng: (loc?['lng'] ?? -79.4111) as double,
      accuracyM: (loc?['accuracyM'] ?? 25) as num,
      source: 'simulator',
      freshness: 'simulated',
    ),
  );
  dispatcher.log = engine.log;
  return Run(engine, scheduler, notifier, dispatcher);
}

Map<String, dynamic> exportRun(String label, Run r) {
  final plain = r.engine.log.verify();
  final anchor = r.engine.log.anchor();
  return jsonDecode(jsonEncode({
    'label': label,
    'finalState': r.engine.state,
    'keyedLog': r.engine.log.keyed,
    'verify': plain,
    'verifyAnchored': r.engine.log.verify(anchor),
    'anchor': anchor,
    'entries': jsonDecode(r.engine.log.serialize())['entries'],
  })) as Map<String, dynamic>;
}

void main() {
  late Map<String, dynamic> node;
  late Map<String, dynamic> nodeCancelled;
  late Map<String, dynamic> nodeEscalated;
  late Map<String, dynamic> dartCancelled;
  late Map<String, dynamic> dartEscalated;
  late Run escalatedRun;

  setUpAll(() async {
    node = jsonDecode(File('proofs/episode-log.json').readAsStringSync())
        as Map<String, dynamic>;
    final runs = (node['runs'] as List).cast<Map<String, dynamic>>();
    nodeCancelled = runs.firstWhere((r) => r['label'] == 'cancelled');
    nodeEscalated = runs.firstWhere((r) => r['label'] == 'escalated');

    // (a) cancelled: same order as the Node runner (instance tag i1).
    final a = build(nodeCancelled);
    final detailsA = (nodeCancelled['entries'] as List).first['data']['details']
        as Map<String, dynamic>;
    a.engine.trigger('fall_pattern', detailsA);
    await a.scheduler.advance(20 * 1000);
    expect(a.engine.wearerCancel(), true);
    await a.scheduler.advance((60 + 3 * 120 + 60) * 1000);
    dartCancelled = exportRun('cancelled', a);

    // (b) escalated (instance tag i2).
    final b = build(nodeEscalated);
    escalatedRun = b;
    final detailsB = (nodeEscalated['entries'] as List).first['data']['details']
        as Map<String, dynamic>;
    b.engine.trigger('fall_pattern', detailsB);
    await b.scheduler.advance(60 * 1000);
    for (var i = 0; i < kin.length; i++) {
      await b.scheduler.advance(120 * 1000);
    }
    dartEscalated = exportRun('escalated', b);
  });

  test('Dart verify() accepts the Node-exported chains (hash compatibility)', () {
    for (final run in [nodeCancelled, nodeEscalated]) {
      final log = EventLog(() => 0);
      for (final e in (run['entries'] as List).cast<Map<String, dynamic>>()) {
        log.entries.add(LogEntry.fromJson(e));
      }
      final anchor = Anchor(
        count: run['anchor']['count'] as int,
        headHash: run['anchor']['headHash'] as String,
      );
      expect(log.verify().ok, true, reason: '${run['label']} plain verify');
      expect(log.verify(anchor).ok, true, reason: '${run['label']} anchored');
    }
  });

  test('escalated: Dart log carries the same event types, in order, as Node', () {
    List<String> types(Map<String, dynamic> r) =>
        (r['entries'] as List).map((e) => e['type'] as String).toList();
    expect(types(dartEscalated), types(nodeEscalated));
    expect(dartEscalated['finalState'], nodeEscalated['finalState']);
    expect(dartEscalated['verify'], nodeEscalated['verify']);
    expect(dartEscalated['verifyAnchored'], nodeEscalated['verifyAnchored']);
    expect(dartEscalated['verify'], {'ok': true, 'failedAt': null});
  });

  test('cancelled: Dart log carries the same event types, in order, as Node', () {
    List<String> types(Map<String, dynamic> r) =>
        (r['entries'] as List).map((e) => e['type'] as String).toList();
    expect(types(dartCancelled), types(nodeCancelled));
    expect(dartCancelled['finalState'], 'IDLE');
    expect(dartCancelled['finalState'], nodeCancelled['finalState']);
    expect(dartCancelled['verify'], nodeCancelled['verify']);
    expect(dartCancelled['verifyAnchored'], nodeCancelled['verifyAnchored']);
  });

  test('escalated: every entry (fields, data, ts, hashes) equals the Node export', () {
    expect(dartEscalated['entries'], nodeEscalated['entries']);
    expect(dartEscalated['anchor'], nodeEscalated['anchor']);
    expect(dartEscalated['keyedLog'], nodeEscalated['keyedLog']);
  });

  test('cancelled: every entry (fields, data, ts, hashes) equals the Node export', () {
    expect(dartCancelled['entries'], nodeCancelled['entries']);
    expect(dartCancelled['anchor'], nodeCancelled['anchor']);
  });

  test('escalated: kin notified once each in wearer order; payload built, never sent',
      () {
    expect(escalatedRun.notifier.calls.map((c) => c.contact.id).toList(),
        (nodeEscalated['notifierCalls'] as List).map((c) => c['contactId']).toList());
    expect(escalatedRun.notifier.calls.map((c) => c.alert.message).toList(),
        (nodeEscalated['notifierCalls'] as List).map((c) => c['message']).toList());
    expect(escalatedRun.dispatcher.built.length, 1);
    final result = (dartEscalated['entries'] as List)
        .firstWhere((e) => e['type'] == 'dispatch_result');
    expect(result['data']['status'], 'disabled');
    expect(result['data']['reference'], isNull);
  });

  test('Dart export top-level shape: keys the engine log provides', () {
    final snapshot = jsonDecode(escalatedRun.engine.log.serialize())
        as Map<String, dynamic>;
    expect(snapshot.keys.toList(), ['keyed', 'entries']);
    expect((snapshot['entries'] as List).first.keys.toList(),
        ['seq', 'ts', 'type', 'data', 'prevHash', 'hash']);
    // Key order of a Node entry is identical.
    expect((nodeEscalated['entries'] as List).first.keys.toList(),
        ['seq', 'ts', 'type', 'data', 'prevHash', 'hash']);
  });
}
