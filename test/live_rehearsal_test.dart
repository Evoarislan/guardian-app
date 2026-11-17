// Session 3: the shell runs the DART engine live (in-process, simulated
// clock) and renders that log, with in-app hash-chain verification.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/main.dart';
import 'package:guardian_app/proof_log.dart';
import 'package:guardian_app/rehearsal/proof_episodes.dart';
import 'package:guardian_app/screens/timeline_screen.dart';
import 'package:guardian_app/widgets/honest_limits.dart';
import 'package:material_ui/material_ui.dart';

Future<ProofLog> _fromDisk() async =>
    ProofLog.parse(File('proofs/episode-log.json').readAsStringSync());

Future<List<EpisodeRun>> _runs() => runProofEpisodes(startAt: 5000000);

Iterable<String> _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 12000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pump a LiveTimelineScreen whose runs were produced (real async) first.
Future<List<EpisodeRun>> _pumpLive(
  WidgetTester tester, {
  Future<void> Function(List<EpisodeRun>)? mutate,
}) async {
  _tall(tester);
  final runs = (await tester.runAsync(_runs))!;
  if (mutate != null) await mutate(runs);
  await tester.pumpWidget(
      MaterialApp(home: LiveTimelineScreen(runner: () async => runs)));
  await tester.pumpAndSettle();
  return runs;
}

void main() {
  testWidgets('home -> live rehearsal runs the Dart engine and renders it',
      (tester) async {
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GuardianApp());
    expect(find.byKey(const Key('live-rehearsal-button')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('live-rehearsal-button')));
    await tester.tap(find.byKey(const Key('live-rehearsal-button')));
    // The real runner (FakeScheduler needs real async to drain microtasks).
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-timeline-title')), findsOneWidget);
    expect(find.byKey(const Key('live-run-cancelled')), findsOneWidget);
    expect(find.byKey(const Key('live-run-escalated')), findsOneWidget);
    expect(find.byKey(const Key('live-verify-escalated')), findsOneWidget);
  });

  testWidgets('live timeline: labels, DISABLED/NOT SENT, no "dispatched"',
      (tester) async {
    await _pumpLive(tester);
    expect(find.byKey(const Key('live-banner')), findsOneWidget);
    expect(find.textContaining('LIVE REHEARSAL, SIMULATED'), findsOneWidget);
    expect(find.textContaining('SIMULATED'), findsWidgets);
    expect(find.text(honestLimitsLine), findsOneWidget);

    // 5 + 19 rows, every one labelled.
    expect(find.text('source: simulator · freshness: simulated'),
        findsNWidgets(24));
    expect(find.textContaining('UNLABELLED'), findsNothing);

    expect(find.textContaining('Dispatch DISABLED: nothing sent'),
        findsOneWidget);
    expect(find.textContaining('NOT SENT'), findsWidgets);
    expect(find.textContaining('DISPATCH step reached'), findsOneWidget);
    for (final t in _allText(tester)) {
      expect(t.toLowerCase().contains('dispatched'), isFalse,
          reason: 'engine wording leaked on screen: $t');
    }
    // Both episodes, escalated one notified in wearer order.
    expect(find.textContaining('Mock notification handed to kin-1'),
        findsOneWidget);
    expect(find.textContaining('Wearer cancelled ('), findsOneWidget);
  });

  testWidgets('live timeline: chain verified shown for both episodes',
      (tester) async {
    await _pumpLive(tester);
    for (final label in ['cancelled', 'escalated']) {
      final t = tester.widget<Text>(find.byKey(Key('live-verify-$label')));
      expect(t.data, startsWith('chain verified'));
      expect(t.data, contains('Dart EventLog.verify()'));
    }
    expect(find.textContaining('CHAIN VERIFICATION FAILED'), findsNothing);
  });

  testWidgets('tampered log FAILS verification in-app (edited entry)',
      (tester) async {
    await _pumpLive(tester, mutate: (runs) async {
      // Rewrite history: the wearer "never cancelled".
      runs[0].log.entries[3].data['duringState'] = 'CASCADE';
    });
    final t = tester.widget<Text>(find.byKey(const Key('live-verify-cancelled')));
    expect(t.data, contains('CHAIN VERIFICATION FAILED at entry #3'));
    expect(t.data, isNot(contains('chain verified')));
    // The untouched episode still verifies.
    final ok = tester.widget<Text>(find.byKey(const Key('live-verify-escalated')));
    expect(ok.data, startsWith('chain verified'));
  });

  testWidgets('tampered log FAILS verification in-app (truncated tail)',
      (tester) async {
    await _pumpLive(tester, mutate: (runs) async {
      runs[1].log.entries.removeRange(15, 19); // drop the dispatch trail
    });
    final t =
        tester.widget<Text>(find.byKey(const Key('live-verify-escalated')));
    expect(t.data, contains('CHAIN VERIFICATION FAILED'));
  });

  test('verifyLiveRun: clean ok, tampered fails, reordered fails', () async {
    final runs = await _runs();
    expect(verifyLiveRun(runs[1]).ok, isTrue);
    final swapped = runs[1].log.entries;
    final a = swapped[5];
    swapped[5] = swapped[6];
    swapped[6] = a;
    final r = verifyLiveRun(runs[1]);
    expect(r.ok, isFalse);
    expect(r.text, contains('CHAIN VERIFICATION FAILED'));
  });

  testWidgets('missing label renders the red UNLABELLED state', (tester) async {
    await _pumpLive(tester, mutate: (runs) async {});
    // Rebuild with a run whose labels were stripped.
    final base = (await tester.runAsync(_runs))!;
    final stripped = EpisodeRun(
      label: base[0].label,
      engine: base[0].engine,
      simulator: base[0].simulator,
      notifier: base[0].notifier,
      dispatcher: base[0].dispatcher,
      dataLabels: const {},
      anchor: base[0].anchor,
      checks: base[0].checks,
    );
    await tester.pumpWidget(MaterialApp(
        home: LiveTimelineScreen(
            key: UniqueKey(), runner: () async => [stripped])));
    await tester.pumpAndSettle();
    expect(find.textContaining('UNLABELLED'), findsWidgets);
  });

  testWidgets('recorded proof view is kept and still says recorded',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(MaterialApp(
        home: TimelineScreen(loader: () async => _fromDisk())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recorded proof run'), findsWidgets);
    expect(find.textContaining('RECORDED PROOF RUN, SIMULATED'), findsOneWidget);
    expect(find.textContaining('does not re-verify'), findsNWidgets(2));
  });
}
