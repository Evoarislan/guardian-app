// Dart parity suite: mirrors engine/test/run-tests.js case for case
// (21 scenarios, same names, same setups, same expectations, same order).
// The Node engine is the reference; this suite holds the Dart port to it.

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/adapters/health_store.dart';
import 'package:guardian_app/adapters/phone_sensors.dart';
import 'package:guardian_app/engine/guardian_engine.dart';

/// Let queued continuations run (Node: flush with setImmediate rounds).
Future<void> flush([int rounds = 10]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class Ctx {
  Ctx(this.engine, this.scheduler, this.notifier, this.dispatcher);
  final EscalationEngine engine;
  final FakeScheduler scheduler;
  final MockNotifier notifier;
  final MockDispatcher dispatcher;
}

Ctx makeEngine({Notifier? notifier, Dispatcher? dispatcher}) {
  final scheduler = FakeScheduler(1000000);
  final mockNotifier = MockNotifier();
  final mockDispatcher = MockDispatcher();
  final engine = EscalationEngine(
    contacts: const [
      Contact(id: 'kin-1', name: 'Daughter', phone: '+1-555-0101'),
      Contact(id: 'kin-2', name: 'Son', phone: '+1-555-0102'),
      Contact(id: 'kin-3', name: 'Neighbour', phone: '+1-555-0103'),
    ],
    cancelWindowSeconds: 30,
    cascadeAckTimeoutSeconds: 60,
    notifier: notifier ?? mockNotifier,
    dispatcher: dispatcher ?? mockDispatcher,
    scheduler: scheduler,
    wearerName: 'Test Wearer',
  );
  return Ctx(engine, scheduler, mockNotifier, mockDispatcher);
}

LogEntry? find(EscalationEngine e, String type) {
  for (final x in e.log.entries) {
    if (x.type == type) return x;
  }
  return null;
}

LogEntry? findTransitionTo(EscalationEngine e, String to) {
  for (final x in e.log.entries) {
    if (x.type == 'transition' && x.data['to'] == to) return x;
  }
  return null;
}

/// Notifier whose behaviour is supplied per test.
class FnNotifier implements Notifier {
  FnNotifier(this.fn);
  final Future<NotifyResult> Function(Contact, Alert) fn;
  final List<NotifyCall> calls = [];
  @override
  Future<NotifyResult> notify(Contact contact, Alert alert) {
    calls.add(NotifyCall(contact, alert));
    return fn(contact, alert);
  }
}

class FnDispatcher implements Dispatcher {
  FnDispatcher(this.fn);
  final Future<DispatchResult> Function(Map<String, dynamic>) fn;
  final List<Map<String, dynamic>> calls = [];
  @override
  Future<DispatchResult> dispatch(Map<String, dynamic> alarm) {
    calls.add(alarm);
    return fn(alarm);
  }
}

void main() {
  // --- original behaviour ---

  test('fall trigger reaches CASCADE after the cancel window lapses', () async {
    final c = makeEngine();
    expect(c.engine.state, States.idle);
    expect(c.engine.trigger('fall_pattern', {'peakG': 3.1}), true);
    expect(c.engine.state, States.cancelWindow);
    expect(c.notifier.calls.length, 0, reason: 'no cascade during cancel window');

    await c.scheduler.advance(29999);
    expect(c.engine.state, States.cancelWindow, reason: 'window has not lapsed yet');

    await c.scheduler.advance(1);
    expect(c.engine.state, States.cascade);
    expect(c.notifier.calls.length, 1, reason: 'first kin contact notified');
    expect(c.notifier.calls[0].contact.id, 'kin-1');
  });

  test('wearer cancel during the window prevents the cascade and returns to IDLE',
      () async {
    final c = makeEngine();
    c.engine.trigger('inactivity', {'stillMinutes': 95});
    await c.scheduler.advance(10000);

    expect(c.engine.wearerCancel(), true);
    expect(c.engine.state, States.idle);

    await c.scheduler.advance(10 * 60000);
    expect(c.engine.state, States.idle);
    expect(c.notifier.calls.length, 0, reason: 'cascade never ran');
    expect(c.dispatcher.calls.length, 0, reason: 'dispatch never fired');

    final types = c.engine.log.entries.map((e) => e.type).toList();
    expect(types, contains('wearer_cancelled'));
  });

  test('cascade stops at the first acknowledgment', () async {
    final c = makeEngine();
    c.engine.trigger('missed_checkin', {'missedByMinutes': 45});
    await c.scheduler.advance(30000);
    expect(c.engine.state, States.cascade);
    expect(c.notifier.calls.length, 1);

    await c.scheduler.advance(60000);
    expect(c.notifier.calls.length, 2, reason: 'cascade moved to second contact');
    expect(c.notifier.calls[1].contact.id, 'kin-2');

    expect(c.engine.acknowledge('kin-2'), true);
    await flush();
    expect(c.engine.state, States.resolved);
    expect(c.notifier.calls.length, 2, reason: 'third contact never notified');
    expect(c.dispatcher.calls.length, 0, reason: 'no dispatch after acknowledgment');

    final ack = find(c.engine, 'cascade_acknowledged');
    expect(ack, isNotNull);
    expect(ack!.data['contactId'], 'kin-2');
  });

  test('dispatch fires only after cascade exhaustion (no-response timeouts)',
      () async {
    final c = makeEngine();
    c.engine.trigger('manual_sos', {});
    await c.scheduler.advance(30000);
    expect(c.engine.state, States.cascade);
    expect(c.dispatcher.calls.length, 0, reason: 'no dispatch while cascade is live');

    await c.scheduler.advance(60000);
    await c.scheduler.advance(60000);
    expect(c.notifier.calls.length, 3);
    expect(c.engine.state, States.cascade, reason: 'third contact still has time');
    expect(c.dispatcher.calls.length, 0,
        reason: 'dispatch waits for full exhaustion');

    await c.scheduler.advance(60000);
    expect(c.engine.state, States.resolved);
    expect(c.dispatcher.calls.length, 1, reason: 'dispatch fired exactly once');
    expect(c.dispatcher.calls[0]['episodeId'],
        find(c.engine, 'trigger_received')!.data['episodeId']);

    final d = find(c.engine, 'dispatch_result');
    expect(d, isNotNull);
    expect(d!.data['status'], 'mock-dispatched');
  });

  test('event log verifies intact and detects tampering', () async {
    final c = makeEngine();
    c.engine.trigger('fall_pattern', {'peakG': 2.8});
    await c.scheduler.advance(30000);
    c.engine.acknowledge('kin-1');
    await flush();
    expect(c.engine.state, States.resolved);

    final intact = c.engine.log.verify();
    expect(intact.ok, true, reason: 'untouched chain verifies');
    expect(intact.failedAt, isNull);

    c.engine.log.entries[1].data['triggerType'] = 'manual_sos';
    final tampered = c.engine.log.verify();
    expect(tampered.ok, false, reason: 'edited entry breaks the chain');
    expect(tampered.failedAt, 1);
  });

  test('trigger is rejected while an episode is active; bad types throw',
      () async {
    final c = makeEngine();
    expect(
      () => c.engine.trigger('earthquake', {}),
      throwsA(predicate((Object e) =>
          e is ArgumentError && e.toString().contains('unknown trigger type'))),
    );
    expect(c.engine.trigger('fall_pattern', {}), true);
    expect(c.engine.trigger('fall_pattern', {}), false,
        reason: 'second trigger ignored mid-episode');
  });

  // --- LOOP FIX 1 ---

  test('FIX1: wearer cancel during CASCADE stops the episode and prevents dispatch',
      () async {
    final c = makeEngine();
    c.engine.trigger('fall_pattern', {'peakG': 3.4});
    await c.scheduler.advance(30000);
    await c.scheduler.advance(60000);
    expect(c.engine.state, States.cascade);
    expect(c.notifier.calls.length, 2);

    expect(c.engine.wearerCancel(), true, reason: 'cancel accepted during cascade');
    expect(c.engine.state, States.idle);

    await c.scheduler.advance(10 * 60000);
    expect(c.engine.state, States.idle);
    expect(c.notifier.calls.length, 2, reason: 'cascade stopped; kin-3 never notified');
    expect(c.dispatcher.calls.length, 0, reason: 'dispatch never fired after cancel');

    final cancel = find(c.engine, 'wearer_cancelled');
    expect(cancel, isNotNull, reason: 'late cancel is logged');
    expect(cancel!.data['duringState'], States.cascade);
  });

  test('FIX1: wearer cancel after dispatch is invoked is refused and logged beyond recall',
      () async {
    late EscalationEngine engineRef;
    bool? cancelDuringDispatch;
    final dispatcher = FnDispatcher((alarm) async {
      cancelDuringDispatch = engineRef.wearerCancel();
      return const DispatchResult(status: 'sent', reference: 'ref-1');
    });
    final c = makeEngine(dispatcher: dispatcher);
    engineRef = c.engine;

    c.engine.trigger('manual_sos', {});
    await c.scheduler.advance(30000 + 3 * 60000);
    expect(dispatcher.calls.length, 1);
    expect(cancelDuringDispatch, false,
        reason: 'cancel refused once dispatch is invoked');
    expect(c.engine.state, States.resolved);

    final rejected = find(c.engine, 'wearer_cancel_rejected');
    expect(rejected, isNotNull, reason: 'refused cancel is logged');
    expect(rejected!.data['reason'], 'beyond_recall');
    final resolved = findTransitionTo(c.engine, States.resolved)!;
    expect(resolved.data['resolution'], 'dispatched');
  });

  test('FIX2: late ack from kin-1 during kin-2 window resolves without dispatch',
      () async {
    final c = makeEngine();
    c.engine.trigger('fall_pattern', {});
    await c.scheduler.advance(30000);
    await c.scheduler.advance(60000);
    expect(c.notifier.calls.length, 2);
    expect(c.engine.state, States.cascade);

    expect(c.engine.acknowledge('kin-1'), true,
        reason: 'late ack from a notified contact is consumed');
    await flush();
    expect(c.engine.state, States.resolved);
    expect(c.notifier.calls.length, 2, reason: 'cascade stopped by the late ack');
    expect(c.dispatcher.calls.length, 0, reason: 'no dispatch after late ack');

    final ack = find(c.engine, 'cascade_acknowledged');
    expect(ack, isNotNull);
    expect(ack!.data['contactId'], 'kin-1', reason: 'the acking contact is credited');
    expect(ack.data['pendingContactId'], 'kin-2');
  });

  test('FIX2: ack from a contact never notified is refused', () async {
    final c = makeEngine();
    c.engine.trigger('fall_pattern', {});
    await c.scheduler.advance(30000);
    expect(c.engine.acknowledge('kin-3'), false,
        reason: 'kin-3 has not been notified yet');
    expect(c.engine.state, States.cascade);
  });

  test('FIX4: ack slot is registered before notify, so an ack during notify is captured',
      () async {
    late EscalationEngine engineRef;
    bool? ackResult;
    final notifier = FnNotifier((contact, alert) async {
      // The contact acknowledges synchronously, inside the notify call.
      ackResult = engineRef.acknowledge(contact.id);
      return const NotifyResult(delivered: true, channel: 'mock');
    });
    final c = makeEngine(notifier: notifier);
    engineRef = c.engine;

    c.engine.trigger('fall_pattern', {});
    await c.scheduler.advance(30000);
    expect(ackResult, true, reason: 'ack during notify was consumed, not lost');
    expect(c.engine.state, States.resolved,
        reason: 'episode resolved without waiting out the ack timeout');
    expect(c.dispatcher.calls.length, 0);
  });

  test('FIX3: throwing dispatcher recovers to RESOLVED(error) and a new trigger works',
      () async {
    final dispatcher = FnDispatcher((alarm) async {
      throw Exception('dispatch boom');
    });
    final c = makeEngine(dispatcher: dispatcher);
    c.engine.trigger('manual_sos', {});
    await c.scheduler.advance(30000 + 3 * 60000);
    expect(dispatcher.calls.length, 1);
    expect(c.engine.state, States.resolved);

    final err = find(c.engine, 'engine_error');
    expect(err, isNotNull, reason: 'engine_error is logged');
    expect(err!.data['message'], matches(RegExp('dispatch boom')));
    final resolved = findTransitionTo(c.engine, States.resolved)!;
    expect(resolved.data['resolution'], 'error');

    expect(c.engine.reset(), true);
    expect(c.engine.state, States.idle);
    expect(c.engine.trigger('fall_pattern', {}), true,
        reason: 'new trigger works after error');
    expect(c.engine.state, States.cancelWindow);
  });

  test('FIX3: throwing notifier recovers to RESOLVED(error)', () async {
    final notifier = FnNotifier((contact, alert) async {
      throw Exception('notify boom');
    });
    final c = makeEngine(notifier: notifier);
    c.engine.trigger('fall_pattern', {});
    await c.scheduler.advance(30000);
    expect(c.engine.state, States.resolved);
    final err = find(c.engine, 'engine_error');
    expect(err, isNotNull, reason: 'engine_error is logged');
    expect(err!.data['message'], matches(RegExp('notify boom')));
    expect(c.dispatcher.calls.length, 0);
  });

  test('FIX5: one-shot FakeScheduler advance reaches the same end state as stepped advance',
      () async {
    final stepped = makeEngine();
    stepped.engine.trigger('manual_sos', {});
    await stepped.scheduler.advance(30000);
    await stepped.scheduler.advance(60000);
    await stepped.scheduler.advance(60000);
    await stepped.scheduler.advance(60000);
    await flush();

    final oneShot = makeEngine();
    oneShot.engine.trigger('manual_sos', {});
    await oneShot.scheduler.advance(30000 + 3 * 60000);
    await flush();

    expect(oneShot.engine.state, States.resolved);
    expect(oneShot.engine.state, stepped.engine.state);
    expect(oneShot.dispatcher.calls.length, 1);
    expect(oneShot.dispatcher.calls.length, stepped.dispatcher.calls.length);
    expect(
      oneShot.engine.log.entries.map((e) => e.type).toList(),
      stepped.engine.log.entries.map((e) => e.type).toList(),
      reason: 'same log event sequence via one-shot and stepped advance',
    );
  });

  test('FIX6: intent entries are logged before each notify/dispatch side effect',
      () async {
    final c = makeEngine();
    c.engine.trigger('manual_sos', {});
    await c.scheduler.advance(30000 + 3 * 60000);
    final types = c.engine.log.entries.map((e) => e.type).toList();

    for (var i = 0; i < types.length; i++) {
      if (types[i] == 'cascade_notified') {
        expect(types[i - 1], 'cascade_notify_pending');
      }
      if (types[i] == 'dispatch_result') {
        expect(types[i - 1], 'dispatch_pending');
      }
    }
    expect(types.where((t) => t == 'cascade_notify_pending').length, 3);
    expect(types.where((t) => t == 'dispatch_pending').length, 1);
  });

  test('FIX8: verify(anchor) fails after truncation; serialize exports the entries',
      () async {
    final log = EventLog(() => 42);
    log.append('a', {'n': 1});
    log.append('b', {'n': 2});
    log.append('c', {'n': 3});

    final anchor = log.anchor();
    expect(anchor.count, 3);
    expect(anchor.headHash, log.entries[2].hash);
    expect(log.verify(anchor).ok, true, reason: 'chain matches its own anchor');

    log.entries.removeLast();
    log.entries.removeLast();
    expect(log.verify().ok, true,
        reason: 'prefix alone still verifies (the honest limit)');
    expect(log.verify(anchor).ok, false,
        reason: 'truncation fails against the anchor');

    final exported = log.toJson();
    expect((exported['entries'] as List).length, 1);
    expect((exported['entries'] as List)[0]['type'], 'a');
    // serialize() produces JSON text carrying the same single entry.
    expect(log.serialize(), contains('"type": "a"'));
    expect(log.toJson()['entries'] as List, hasLength(1));
  });

  test('FIX8: keyed mode (log key) chains with HMAC and fails without the key',
      () async {
    final plain = EventLog(() => 7);
    final keyed = EventLog(() => 7, 'unit-test-key');
    expect(keyed.keyed, true);
    keyed.append('x', {'v': 1});
    keyed.append('y', {'v': 2});
    expect(keyed.verify().ok, true, reason: 'keyed chain verifies under its key');
    expect(keyed.verify(keyed.anchor()).ok, true);

    plain.entries.addAll(keyed.entries.map((e) => e.copy()));
    expect(plain.verify().ok, false,
        reason: 'an HMAC chain cannot be recomputed/verified without the key');
  });

  test('FIX7: Noonlight transport receives the Authorization header and a body without _guardian',
      () async {
    final captured = <DispatchRequest>[];
    final d = NoonlightSandboxDispatcher(
      enabled: true,
      token: 'tok-secret-123',
      transport: (req) async {
        captured.add(req);
        return const DispatchResult(status: 'ok', reference: 'nz-1');
      },
    );
    final payload = buildNoonlightAlarmPayload(
      Episode(
        id: 'ep-x',
        triggerType: 'fall_pattern',
        startedAt: 0,
        wearerName: 'Wearer One',
      ),
      const Location(lat: 43.7, lng: -79.4, accuracyM: 10),
    );
    expect(payload['_guardian'], isNotNull,
        reason: 'built payload keeps _guardian for inspection');

    await d.dispatch(payload);
    expect(captured.length, 1);
    expect(captured[0].method, 'POST');
    expect(captured[0].headers['Authorization'], 'Bearer tok-secret-123');
    expect(captured[0].headers['Content-Type'], 'application/json');
    expect(captured[0].body['_guardian'], isNull,
        reason: '_guardian stripped from the sent body');
    expect(captured[0].body['name'], 'Wearer One');
    expect((captured[0].body['services'] as Map)['medical'], true);
    expect(payload['_guardian'], isNotNull,
        reason: 'the built payload object itself is not mutated');
  });

  test('FIX9: phone-sensors emits accelerometer samples via the currently registered callback',
      () async {
    final sensors = MockPhoneSensorsAdapter();
    final first = <AccelSample>[];
    final second = <AccelSample>[];
    sensors.onAccelerometer(first.add);
    sensors.onAccelerometer(second.add); // replaces the first
    await Future<void>.delayed(const Duration(milliseconds: 350));
    sensors.stop();
    expect(second.length, greaterThanOrEqualTo(1),
        reason: 'second subscriber received samples (got ${second.length})');
    expect(first.length, 0,
        reason: 'only the currently registered callback receives samples');
    expect(second[0].source, 'simulated');
  });

  test('FIX11: health-store readObservations respects sinceTs honestly (no re-stamping)',
      () async {
    final adapter = MockHealthStoreAdapter();
    final all = await adapter.readObservations();
    expect(all.length, 6, reason: 'one simulated sample per type');
    final hr = all.firstWhere((r) => r.type == 'heart_rate');

    final again = await adapter.readObservations(types: ['heart_rate']);
    expect(again.length, 1);
    expect(again[0].ts, hr.ts,
        reason: 'timestamps are stable across reads, never re-stamped');

    final atTs =
        await adapter.readObservations(types: ['heart_rate'], sinceTs: hr.ts);
    expect(atTs.length, 1,
        reason: 'a sample at sinceTs is inside the window (at/after)');

    final afterTs = await adapter
        .readObservations(types: ['heart_rate'], sinceTs: hr.ts + 1);
    expect(afterTs, isEmpty, reason: 'nothing is fabricated into a later window');

    final beyond = await adapter.readObservations(
        sinceTs: DateTime.now().millisecondsSinceEpoch + 60000);
    expect(beyond, isEmpty, reason: 'a window beyond the series is honestly empty');
  });

  test('FIX10: two engine instances mint distinct episode IDs', () async {
    final a = makeEngine();
    final b = makeEngine();
    a.engine.trigger('fall_pattern', {});
    b.engine.trigger('fall_pattern', {});
    final idA = find(a.engine, 'trigger_received')!.data['episodeId'];
    final idB = find(b.engine, 'trigger_received')!.data['episodeId'];
    expect(idA, isNotNull);
    expect(idB, isNotNull);
    expect(idA, isNot(idB),
        reason: 'episode IDs must differ across instances ($idA vs $idB)');
  });
}
