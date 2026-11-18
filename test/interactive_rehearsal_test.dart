// Session 4: the interactive live rehearsal. A user drives one episode of
// the real Dart engine in (scaled) real time. The inner clock is a
// FakeScheduler behind ScaledScheduler(scale: 10), so a test advances
// REAL milliseconds and the engine sees 10x episode time with the
// canonical 60 s / 120 s windows unchanged.
//
// Zone note: the engine's futures must run in the real zone for
// FakeScheduler.advance() to drain them, so every UI action that touches
// the engine is invoked inside tester.runAsync (see _tap).

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/consent/consent.dart';
import 'package:guardian_app/engine/guardian_engine.dart';
import 'package:guardian_app/main.dart';
import 'package:guardian_app/rehearsal/interactive_rehearsal.dart';
import 'package:guardian_app/rehearsal/proof_episodes.dart';
import 'package:guardian_app/rehearsal/scaled_scheduler.dart';
import 'package:guardian_app/screens/interactive_rehearsal_screen.dart';
import 'package:guardian_app/widgets/honest_limits.dart';
import 'package:material_ui/material_ui.dart';

const _labelRow = 'source: simulator · freshness: simulated';

/// Kin alerts allowed (the Session 4 behaviour these tests were written for).
ConsentStore _granted() =>
    ConsentStore()..grant(ConsentRole.kin, ConsentDataClass.alerts);

class _Rig {
  _Rig(this.tester, this.fake);
  final WidgetTester tester;
  final FakeScheduler fake;
  late InteractiveRehearsal ctl;
  late ScaledScheduler scaled;

  InteractiveRehearsal create() {
    scaled = ScaledScheduler(inner: fake, scale: 10, startAt: 5000000);
    return ctl = InteractiveRehearsal(consent: _granted(), scheduler: scaled);
  }

  /// Advance REAL milliseconds (10x episode time) and rebuild.
  Future<void> advanceReal(int ms) async {
    await tester.runAsync(() => fake.advance(ms));
    ctl.refresh(); // the real app does this from a 250 ms UI ticker
    await tester.pump();
  }

  /// Press a button by invoking its handler in the real zone.
  Future<void> tap(String key) async {
    final w = tester.widget(find.byKey(Key(key)));
    final cb = w is ElevatedButton
        ? w.onPressed
        : (w as OutlinedButton).onPressed;
    expect(cb, isNotNull, reason: '$key is disabled');
    await tester.runAsync(() async {
      cb!();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  List<String> get types => ctl.log.entries.map((e) => e.type).toList();

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox()); // cancels the UI ticker
  }
}

Future<_Rig> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final rig = _Rig(tester, FakeScheduler(0));
  await tester.pumpWidget(
      MaterialApp(home: InteractiveRehearsalScreen(create: rig.create)));
  return rig;
}

Iterable<String> _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

/// Honesty invariants that must hold on every state of the screen.
void _honest(_Rig r, {bool expectRows = true}) {
  final tester = r.tester;
  for (final t in _allText(tester)) {
    expect(t.toLowerCase().contains('dispatched'), isFalse,
        reason: '"dispatched" leaked on screen: $t');
  }
  expect(find.textContaining('UNLABELLED'), findsNothing);
  expect(find.text(honestLimitsLine), findsOneWidget);
  expect(find.textContaining('SIMULATED'), findsWidgets);
  if (expectRows) {
    // Every timeline row carries the simulator/simulated label.
    expect(find.text(_labelRow), findsNWidgets(r.ctl.log.entries.length));
  }
}

String _text(WidgetTester t, String key) =>
    t.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('ScaledScheduler', () {
    test('timers are shortened by the scale; now() reports episode time', () async {
      final fake = FakeScheduler(1000);
      final s = ScaledScheduler(inner: fake, scale: 10, startAt: 5000000);
      expect(s.now(), 5000000);
      s.setTimeout(() {}, 60000);
      await fake.advance(5999); // not yet
      expect(s.now(), 5000000 + 5999 * 10);
      expect(s.realMsFor(120000), 12000);
      expect(s.episodeElapsedMs, 59990);
    });

    test('a 60 s episode timer fires after 6 real seconds, not before',
        () async {
      final fake = FakeScheduler(0);
      final s = ScaledScheduler(inner: fake, scale: 10, startAt: 0);
      var fired = false;
      s.setTimeout(() => fired = true, 60000);
      await fake.advance(5999);
      expect(fired, isFalse);
      await fake.advance(1);
      expect(fired, isTrue);
    });

    test('shutdown() drops pending timers and clearTimeout works', () async {
      final fake = FakeScheduler(0);
      final s = ScaledScheduler(inner: fake, scale: 10, startAt: 0);
      var fired = 0;
      final a = s.setTimeout(() => fired++, 1000);
      s.setTimeout(() => fired++, 2000);
      s.clearTimeout(a);
      s.shutdown();
      await fake.advance(10000);
      expect(fired, 0);
    });

    test('engine keeps canonical 60 s / 120 s durations under the scale', () {
      final c = InteractiveRehearsal(
          consent: _granted(),
          scheduler: ScaledScheduler(inner: FakeScheduler(0), scale: 10));
      expect(c.engine.cancelWindowMs, 60000);
      expect(c.engine.cascadeAckTimeoutMs, 120000);
      expect(cancelWindowSeconds, 60);
      expect(ackTimeoutSeconds, 120);
      c.dispose();
    });
  });

  group('real timers (RealScheduler, scale 100 so the test stays short)', () {
    Future<void> until(bool Function() ok, {int maxMs = 8000}) async {
      final sw = Stopwatch()..start();
      while (!ok() && sw.elapsedMilliseconds < maxMs) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('unacknowledged run reaches the disabled dispatch; chain verifies',
        () async {
      var notified = 0;
      final c = InteractiveRehearsal(
          consent: _granted(),
          scheduler: ScaledScheduler(scale: 100)); // RealScheduler inside
      c.addListener(() => notified++);
      c.simulateFall();
      await until(() => c.finished);
      expect(c.engine.state, States.resolved);
      expect(c.outcome, RehearsalOutcome.dispatchStepDisabled);
      expect(c.dispatcher.dispatchCalls, 1);
      expect(c.log.verify().ok, isTrue);
      expect(notified, greaterThan(3), reason: 'UI was told about timer events');
      // 420 episode seconds in about 4.2 real seconds.
      expect(c.scheduler.episodeElapsedMs, greaterThanOrEqualTo(420000));
      c.dispose();
    });

    test('cancel mid-cascade and simulated ack on real timers', () async {
      final a = InteractiveRehearsal(consent: _granted(), scheduler: ScaledScheduler(scale: 100));
      a.simulateFall();
      await until(() => a.inCascade);
      expect(a.currentContact?.id, 'kin-1');
      expect(a.imOk(), isTrue);
      expect(a.outcome, RehearsalOutcome.wearerCancelled);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(a.dispatcher.dispatchCalls, 0);
      expect(a.notifier.calls.length, 1);
      a.dispose();

      final b = InteractiveRehearsal(consent: _granted(), scheduler: ScaledScheduler(scale: 100));
      b.simulateFall();
      await until(() => b.inCascade);
      expect(b.simulateKinAck(), isTrue);
      await until(() => b.finished);
      expect(b.outcome, RehearsalOutcome.acknowledged);
      expect(b.dispatcher.dispatchCalls, 0);
      b.dispose();
    });
  });

  testWidgets('before the fall: scale disclosed, nothing running',
      (tester) async {
    final r = await _pump(tester);
    expect(find.byKey(const Key('rehearsal-start')), findsOneWidget);
    expect(find.byKey(const Key('rehearsal-im-ok')), findsNothing);
    final scale = _text(tester, 'scale-disclosure');
    expect(scale, contains('REHEARSAL TIME IS SCALED'));
    expect(scale, contains('1 real second = 10 episode seconds'));
    expect(scale, contains('60s cancel window'));
    expect(scale, contains('120s per-contact'));
    expect(scale, contains('about 42 real seconds'));
    expect(find.textContaining('INTERACTIVE REHEARSAL, SIMULATED'),
        findsOneWidget);
    expect(find.textContaining('DISABLED'), findsWidgets);
    _honest(r, expectRows: false);
    await r.dispose();
  });

  testWidgets("cancel INSIDE the window: \"I'm OK\" resolves wearer_cancelled",
      (tester) async {
    final r = await _pump(tester);
    await r.tap('rehearsal-start');
    expect(r.ctl.engine.state, States.cancelWindow);
    expect(find.byKey(const Key('rehearsal-im-ok')), findsOneWidget);
    expect(find.byKey(const Key('rehearsal-kin-ack')), findsNothing);

    await r.advanceReal(2000); // 20 episode seconds
    expect(_text(tester, 'rehearsal-countdown'),
        'Cancel window open: 40 episode seconds left (about 4 real seconds)');
    expect(r.ctl.engine.state, States.cancelWindow);

    await r.tap('rehearsal-im-ok');

    expect(r.ctl.engine.state, States.idle);
    expect(r.ctl.outcome, RehearsalOutcome.wearerCancelled);
    final outcome = _text(tester, 'rehearsal-outcome');
    expect(outcome, contains('wearer_cancelled'));
    expect(outcome, contains('CANCEL_WINDOW'));
    expect(outcome, contains('The dispatcher was never invoked'));

    // Log: exactly the engine's semantics (trigger, window, cancel, IDLE).
    final cancelled =
        r.ctl.log.entries.firstWhere((e) => e.type == 'wearer_cancelled');
    expect(cancelled.data['duringState'], 'CANCEL_WINDOW');
    final toIdle = r.ctl.log.entries.last;
    expect(toIdle.type, 'transition');
    expect(toIdle.data['to'], States.idle);
    expect(toIdle.data['reason'], 'wearer_cancelled');
    expect(
        r.types.where((t) =>
            t.startsWith('cascade_') ||
            t.startsWith('dispatch_') ||
            t.startsWith('sandbox_')),
        isEmpty);
    expect(r.ctl.notifier.calls, isEmpty);
    expect(r.ctl.dispatcher.dispatchCalls, 0);
    expect(r.ctl.dispatcher.built, isEmpty);

    // Nothing happens afterwards, even past every window.
    await r.advanceReal(50000);
    expect(r.ctl.engine.state, States.idle);
    expect(r.ctl.notifier.calls, isEmpty);

    // Offsets are episode seconds: the cancel was at t+20s.
    expect(find.textContaining('t+20s'), findsWidgets);
    expect(_text(tester, 'rehearsal-outcome'), outcome);
    final verify = _text(tester, 'interactive-verify');
    expect(verify, startsWith('chain verified'));
    expect(verify, contains('Dart EventLog.verify()'));
    expect(find.textContaining('t+ offsets are EPISODE seconds'),
        findsOneWidget);
    _honest(r);
    expect(find.byKey(const Key('rehearsal-im-ok')), findsNothing);
    await r.dispose();
  });

  testWidgets("cancel MID-CASCADE: \"I'm OK\" stops it before the dispatcher",
      (tester) async {
    final r = await _pump(tester);
    await r.tap('rehearsal-start');
    await r.advanceReal(6000); // window lapses at 60 episode seconds
    expect(r.ctl.engine.state, States.cascade);
    expect(r.ctl.notifier.calls.map((n) => n.contact.id), ['kin-1']);
    expect(_text(tester, 'rehearsal-state'), 'Engine state: CASCADE');

    await r.advanceReal(12000); // kin-1 times out (120 episode seconds)
    expect(r.ctl.notifier.calls.map((n) => n.contact.id), ['kin-1', 'kin-2']);
    expect(r.ctl.engine.state, States.cascade);
    expect(find.byKey(const Key('rehearsal-im-ok')), findsOneWidget);

    await r.tap('rehearsal-im-ok');

    expect(r.ctl.engine.state, States.idle);
    expect(r.ctl.outcome, RehearsalOutcome.wearerCancelled);
    final cancelled =
        r.ctl.log.entries.firstWhere((e) => e.type == 'wearer_cancelled');
    expect(cancelled.data['duringState'], 'CASCADE');
    final toIdle = r.ctl.log.entries.last;
    expect(toIdle.data['reason'], 'wearer_cancelled');
    // Ordered, no skipping, kin-3 never contacted, no dispatch anything.
    expect(r.ctl.notifier.calls.map((n) => n.contact.id), ['kin-1', 'kin-2']);
    expect(r.types.where((t) => t == 'cascade_no_response').length, 1);
    expect(
        r.types.where(
            (t) => t.startsWith('dispatch_') || t.startsWith('sandbox_')),
        isEmpty);
    expect(r.ctl.dispatcher.dispatchCalls, 0);
    expect(r.ctl.dispatcher.built, isEmpty);
    expect(_text(tester, 'rehearsal-outcome'), contains('during CASCADE'));

    // Timers were stopped: more time changes nothing.
    await r.advanceReal(60000);
    expect(r.ctl.notifier.calls.length, 2);
    expect(r.ctl.engine.state, States.idle);
    expect(_text(tester, 'interactive-verify'), startsWith('chain verified'));
    _honest(r);
    await r.dispose();
  });

  testWidgets('SIMULATED kin ack for the current contact resolves acknowledged',
      (tester) async {
    final r = await _pump(tester);
    await r.tap('rehearsal-start');
    await r.advanceReal(6000);
    expect(find.text(
            'SIMULATED kin ack: kin-1 acknowledges\n(simulation control, not a real person)'),
        findsOneWidget);
    await r.advanceReal(12000); // kin-1 no response; kin-2 notified
    expect(find.textContaining('SIMULATED kin ack: kin-2 acknowledges'),
        findsOneWidget);
    expect(find.textContaining('kin-1 acknowledges'), findsNothing);

    await r.tap('rehearsal-kin-ack');

    expect(r.ctl.outcome, RehearsalOutcome.acknowledged);
    expect(r.ctl.engine.state, States.resolved);
    final ack =
        r.ctl.log.entries.firstWhere((e) => e.type == 'cascade_acknowledged');
    expect(ack.data['contactId'], 'kin-2');
    final resolved = r.ctl.log.entries.last;
    expect(resolved.data['to'], States.resolved);
    expect(resolved.data['resolution'], 'acknowledged');
    expect(resolved.data['by'], 'kin-2');
    expect(r.ctl.notifier.calls.map((n) => n.contact.id), ['kin-1', 'kin-2']);
    expect(
        r.types.where(
            (t) => t.startsWith('dispatch_') || t.startsWith('sandbox_')),
        isEmpty);
    expect(r.ctl.dispatcher.dispatchCalls, 0);
    final outcome = _text(tester, 'rehearsal-outcome');
    expect(outcome, contains('acknowledged by kin-2 (SIMULATED kin acknowledgment'));
    expect(find.textContaining('Acknowledged by kin-2 (SIMULATED kin ack'),
        findsOneWidget);
    expect(find.byKey(const Key('rehearsal-im-ok')), findsNothing);
    expect(find.byKey(const Key('rehearsal-kin-ack')), findsNothing);

    await r.advanceReal(60000);
    expect(r.ctl.notifier.calls.length, 2, reason: 'ack stops the cascade');
    expect(_text(tester, 'interactive-verify'), startsWith('chain verified'));
    _honest(r);
    await r.dispose();
  });

  testWidgets('full unacknowledged run reaches the DISABLED dispatch step',
      (tester) async {
    final r = await _pump(tester);
    await r.tap('rehearsal-start');
    await r.advanceReal(6000 + 3 * 12000 - 1);
    expect(r.ctl.engine.state, States.cascade, reason: 'one ms short');
    await r.advanceReal(1);

    // 42 real seconds on the scaled clock: under a minute.
    expect(r.fake.now(), 42000);
    expect(r.fake.now(), lessThan(60000));
    expect(r.scaled.episodeElapsedMs, 420000);

    expect(r.ctl.engine.state, States.resolved);
    expect(r.ctl.outcome, RehearsalOutcome.dispatchStepDisabled);
    expect(r.ctl.notifier.calls.map((n) => n.contact.id),
        ['kin-1', 'kin-2', 'kin-3']);
    expect(r.types.where((t) => t == 'cascade_no_response').length, 3);
    expect(r.types.contains('cascade_acknowledged'), isFalse);
    expect(r.types.contains('wearer_cancelled'), isFalse);

    final iBuilt = r.types.indexOf('sandbox_payload_built');
    final iPending = r.types.indexOf('dispatch_pending');
    final iResult = r.types.indexOf('dispatch_result');
    expect(iBuilt, greaterThan(-1));
    expect(iBuilt, lessThan(iPending));
    expect(iPending, lessThan(iResult));
    final result = r.ctl.log.entries[iResult].data;
    expect(result['status'], 'disabled');
    expect(result['reference'], isNull);
    expect(r.ctl.log.entries[iBuilt].data['sent'], false);
    expect(r.ctl.dispatcher.dispatchCalls, 1,
        reason: 'invoked once, and it answered disabled');

    final outcome = _text(tester, 'rehearsal-outcome');
    expect(outcome, contains('DISABLED: NOT SENT'));
    expect(find.textContaining('Dispatch DISABLED: nothing sent'),
        findsOneWidget);
    expect(find.textContaining('DISPATCH step reached'), findsOneWidget);
    expect(find.textContaining('NOT SENT'), findsWidgets);
    expect(find.byKey(const Key('rehearsal-im-ok')), findsNothing);

    // Beyond recall is not offered; a late cancel is refused and logged.
    expect(r.ctl.canCancel, isFalse);
    expect(r.ctl.imOk(), isFalse);

    final verify = _text(tester, 'interactive-verify');
    expect(verify, startsWith('chain verified'));
    expect(verify, contains('Dart EventLog.verify()'));
    _honest(r);
    await r.dispose();
  });

  testWidgets('chain verification FAILS in the interactive run if tampered',
      (tester) async {
    final r = await _pump(tester);
    await r.tap('rehearsal-start');
    await r.advanceReal(2000);
    await r.tap('rehearsal-im-ok');
    expect(_text(tester, 'interactive-verify'), startsWith('chain verified'));
    // Rewrite history: the wearer "never cancelled".
    r.ctl.log.entries
        .firstWhere((e) => e.type == 'wearer_cancelled')
        .data['duringState'] = 'CASCADE';
    r.ctl.refresh();
    await tester.pump();
    expect(_text(tester, 'interactive-verify'),
        contains('CHAIN VERIFICATION FAILED'));
    await r.dispose();
  });

  testWidgets('"Run another rehearsal" starts a fresh, unstarted episode',
      (tester) async {
    final r = await _pump(tester);
    await r.tap('rehearsal-start');
    await r.tap('rehearsal-im-ok');
    final first = r.ctl;
    await r.tap('rehearsal-again');
    expect(identical(r.ctl, first), isFalse);
    expect(find.byKey(const Key('rehearsal-start')), findsOneWidget);
    expect(r.ctl.log.entries, isEmpty);
    await r.dispose();
  });

  testWidgets('leaving mid-episode stops the engine timers (nothing logged)',
      (tester) async {
    final r = await _pump(tester);
    await r.tap('rehearsal-start');
    final count = r.ctl.log.entries.length;
    await r.dispose();
    await tester.runAsync(() => r.fake.advance(500000));
    expect(r.ctl.log.entries.length, count);
    expect(r.ctl.notifier.calls, isEmpty);
  });

  testWidgets('home has entry points for the interactive rehearsal',
      (tester) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GuardianApp());
    expect(find.byKey(const Key('interactive-rehearsal-button')),
        findsOneWidget);
    expect(find.byKey(const Key('provider-view-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('interactive-rehearsal-button')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(411, 2400); // show the whole list
    await tester.pump();
    expect(find.byKey(const Key('interactive-title')), findsOneWidget);
    expect(find.byKey(const Key('rehearsal-start')), findsOneWidget);
    // Real default: 1 real second = 10 episode seconds.
    expect(_text(tester, 'scale-disclosure'),
        contains('1 real second = 10 episode seconds'));
  });
}
