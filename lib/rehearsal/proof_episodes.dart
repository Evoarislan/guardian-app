// The two proof episodes (cancelled, escalated), replayed through the
// DART engine with the same simulated inputs as integration/run-proof.js.
// Shared by the proof runner (tool/run_proof.dart) and the in-app live
// rehearsal, so both exercise exactly the same code.
//
// What is real and what is not:
//   - Engine, state machine, hash-chained log: the real Dart engine.
//   - Signals: SIMULATED (source=simulator, freshness=simulated).
//   - Kin notifications: the engine's MockNotifier. Nothing is sent.
//   - Dispatch: DISABLED (no token, no transport). Payload built and
//     logged, never sent.
//   - Time: FakeScheduler, DEFAULT windows (cancel 60 s, per-contact ack
//     120 s) unshortened on a simulated clock.
//
// No dart:io, no HTTP: this file performs no I/O of any kind.

import '../adapters/trace_simulator.dart';
import '../engine/guardian_engine.dart';
import 'payload_logging_dispatcher.dart';

const int cancelWindowSeconds = 60; // engine default, not shortened
const int ackTimeoutSeconds = 120; // engine default, not shortened

const List<Contact> syntheticKin = [
  Contact(id: 'kin-1', name: 'Synthetic Kin 1 (first in wearer order)'),
  Contact(id: 'kin-2', name: 'Synthetic Kin 2'),
  Contact(id: 'kin-3', name: 'Synthetic Kin 3'),
];

const Map<String, dynamic> proofLabels = {
  'source': simulatorSource,
  'freshness': simulatorFreshness,
};

/// One replayed episode and everything needed to export or render it.
class EpisodeRun {
  EpisodeRun({
    required this.label,
    required this.engine,
    required this.simulator,
    required this.notifier,
    required this.dispatcher,
    required this.dataLabels,
    required this.anchor,
    required this.checks,
  });

  final String label; // "cancelled" | "escalated"
  final EscalationEngine engine;
  final TraceSimulatorAdapter simulator;
  final MockNotifier notifier;
  final PayloadLoggingDispatcher dispatcher;

  /// Source/freshness labels the run carries. A run with missing labels
  /// renders UNLABELLED in the shell.
  final Map<String, dynamic> dataLabels;

  /// Chain head captured when the run finished (store-outside-the-log
  /// anchor, as in the Node proof).
  final Anchor anchor;

  /// Failed checks (empty = every behavioural check passed).
  final List<String> checks;

  EventLog get log => engine.log;
  String get finalState => engine.state;
}

class _Ctx {
  _Ctx(int startAt)
    : scheduler = FakeScheduler(startAt),
      notifier = MockNotifier(),
      dispatcher = PayloadLoggingDispatcher(labels: proofLabels) {
    simulator = TraceSimulatorAdapter(now: scheduler.now);
    engine = EscalationEngine(
      contacts: syntheticKin,
      cancelWindowSeconds: cancelWindowSeconds,
      cascadeAckTimeoutSeconds: ackTimeoutSeconds,
      notifier: notifier,
      dispatcher: dispatcher,
      scheduler: scheduler,
      wearerName: 'Synthetic demo wearer',
      locationProvider: simulator.location,
    );
    dispatcher.attachLog(engine.log);
    simulator.onSignal((signal) {
      if (signal.kind == 'accel' && signal.value['type'] == 'fall_pattern') {
        engine.trigger('fall_pattern', {'signal': signal.toJson()});
      }
    });
  }

  final FakeScheduler scheduler;
  final MockNotifier notifier;
  final PayloadLoggingDispatcher dispatcher;
  late final TraceSimulatorAdapter simulator;
  late final EscalationEngine engine;
}

EpisodeRun _finish(String label, _Ctx c, List<String> failed) => EpisodeRun(
  label: label,
  engine: c.engine,
  simulator: c.simulator,
  notifier: c.notifier,
  dispatcher: c.dispatcher,
  dataLabels: proofLabels,
  anchor: c.engine.log.anchor(),
  checks: failed,
);

/// (a) fall -> wearer cancels inside the cancel window.
Future<EpisodeRun> runCancelledEpisode({required int startAt}) async {
  final c = _Ctx(startAt);
  final failed = <String>[];
  void check(String what, bool ok) {
    if (!ok) failed.add(what);
  }

  c.simulator.playFall();
  check(
    'CANCEL_WINDOW after the trigger',
    c.engine.state == States.cancelWindow,
  );
  await c.scheduler.advance(20 * 1000);
  check('still CANCEL_WINDOW at t+20s', c.engine.state == States.cancelWindow);
  check('wearerCancel() accepted', c.engine.wearerCancel());
  check('engine returned to IDLE', c.engine.state == States.idle);
  await c.scheduler.advance(
    (cancelWindowSeconds + 3 * ackTimeoutSeconds + 60) * 1000,
  );
  check(
    'still IDLE after all windows would have lapsed',
    c.engine.state == States.idle,
  );
  check('no kin notified', c.notifier.calls.isEmpty);
  check(
    'no payload built, no dispatch call',
    c.dispatcher.built.isEmpty && c.dispatcher.dispatchCalls == 0,
  );
  check(
    'cancellation is in the log',
    c.engine.log.entries.any((e) => e.type == 'wearer_cancelled'),
  );
  check(
    'no cascade or dispatch entries',
    !c.engine.log.entries.any(
      (e) => RegExp(r'^cascade_|^dispatch_|^sandbox_').hasMatch(e.type),
    ),
  );
  return _finish('cancelled', c, failed);
}

/// (b) fall -> window lapses -> one ordered cascade pass -> DISPATCH
/// step (disabled) -> RESOLVED.
Future<EpisodeRun> runEscalatedEpisode({required int startAt}) async {
  final c = _Ctx(startAt);
  final failed = <String>[];
  void check(String what, bool ok) {
    if (!ok) failed.add(what);
  }

  c.simulator.playFall();
  check(
    'CANCEL_WINDOW after the trigger',
    c.engine.state == States.cancelWindow,
  );
  await c.scheduler.advance(cancelWindowSeconds * 1000);
  check('window lapsed -> CASCADE', c.engine.state == States.cascade);
  check(
    'only kin-1 notified so far',
    c.notifier.calls.length == 1 && c.notifier.calls[0].contact.id == 'kin-1',
  );
  for (var i = 0; i < syntheticKin.length; i++) {
    await c.scheduler.advance(ackTimeoutSeconds * 1000);
  }
  check('cascade exhausted -> RESOLVED', c.engine.state == States.resolved);
  check(
    'kin notified once each, in wearer order',
    c.notifier.calls.map((n) => n.contact.id).join(',') ==
        syntheticKin.map((k) => k.id).join(','),
  );
  final types = c.engine.log.entries.map((e) => e.type).toList();
  final iBuilt = types.indexOf('sandbox_payload_built');
  final iPending = types.indexOf('dispatch_pending');
  final iResult = types.indexOf('dispatch_result');
  check(
    'payload logged BEFORE dispatch_pending, then dispatch_result',
    iBuilt >= 0 && iBuilt < iPending && iPending < iResult,
  );
  final dispatchEntry = c.engine.log.entries
      .where((e) => e.type == 'transition' && e.data['to'] == States.dispatch)
      .firstOrNull;
  check(
    'DISPATCH entered with reason cascade_exhausted',
    dispatchEntry?.data['reason'] == 'cascade_exhausted',
  );
  if (iResult >= 0) {
    final r = c.engine.log.entries[iResult].data;
    check(
      'dispatch NOT sent: status=disabled, no reference',
      r['status'] == 'disabled' && r['reference'] == null,
    );
  } else {
    check('dispatch_result present', false);
  }
  if (iBuilt >= 0) {
    check(
      'payload entry records sent=false',
      c.engine.log.entries[iBuilt].data['sent'] == false,
    );
  }
  check(
    'no kin acknowledgment occurred',
    !types.contains('cascade_acknowledged'),
  );
  return _finish('escalated', c, failed);
}

/// Both proof episodes, cancelled first then escalated (same order as the
/// Node runner, so engine instance tags and episode ids line up).
Future<List<EpisodeRun>> runProofEpisodes({required int startAt}) async {
  final cancelled = await runCancelledEpisode(startAt: startAt);
  final escalated = await runEscalatedEpisode(startAt: startAt);
  return [cancelled, escalated];
}

/// One run in the exact shape of a run in proofs/episode-log.json.
Map<String, dynamic> exportRun(EpisodeRun run) {
  final snapshot = run.log.toJson();
  final plain = run.log.verify();
  final anchored = run.log.verify(run.anchor);
  return {
    'label': run.label,
    'finalState': run.finalState,
    'keyedLog': snapshot['keyed'],
    'verify': plain.toJson(),
    'verifyAnchored': anchored.toJson(),
    'anchor': run.anchor.toJson(),
    'dataLabels': run.dataLabels,
    'signals': run.simulator.emitted.map((s) => s.toJson()).toList(),
    'notifierCalls': run.notifier.calls
        .map(
          (c) => {
            'contactId': c.contact.id,
            'message': c.alert.message,
            'location': c.alert.location == null
                ? null
                : {
                    'lat': c.alert.location!.lat,
                    'lng': c.alert.location!.lng,
                    'accuracyM': c.alert.location!.accuracyM,
                    'source': c.alert.location!.source,
                    'freshness': c.alert.location!.freshness,
                  },
          },
        )
        .toList(),
    'dispatchSent': false,
    'entries': snapshot['entries'],
  };
}

/// Whole-file export, same top-level shape as proofs/episode-log.json.
Map<String, dynamic> exportProof(List<EpisodeRun> runs, DateTime generatedAt) =>
    {
      'schema': 'guardian.episode-log/1',
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'banner':
          'Dart-engine proof run. SIMULATED signals (source=simulator, freshness=simulated). '
          'Mock kin notifier, dispatch disabled: nothing was sent. Simulated clock, default windows.',
      'dataLabels': proofLabels,
      'runs': runs.map(exportRun).toList(),
    };
