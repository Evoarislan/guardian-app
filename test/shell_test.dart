import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/main.dart';
import 'package:guardian_app/proof_log.dart';
import 'package:guardian_app/screens/cancel_window_screen.dart';
import 'package:guardian_app/screens/timeline_screen.dart';
import 'package:guardian_app/widgets/honest_limits.dart';
import 'package:material_ui/material_ui.dart';

const _limits =
    'Demo build — dispatch is a sandbox; Guardian never calls 911 directly.';

Future<ProofLog> _fromDisk() async =>
    ProofLog.parse(File('proofs/episode-log.json').readAsStringSync());

void main() {
  test('bundled asset is identical to the canonical proofs/ export', () {
    expect(File('assets/episode-log.json').readAsStringSync(),
        File('proofs/episode-log.json').readAsStringSync());
  });

  test('honest-limits constant is the exact binding line', () {
    expect(honestLimitsLine, _limits);
  });

  testWidgets('home: two big buttons, simulated label, honest-limits line',
      (tester) async {
    // Phone-shaped portrait surface (the flutter_test default is an
    // 800x600 landscape box, where the buttons come out 103 px tall).
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GuardianApp());
    expect(find.byKey(const Key('im-ok-button')), findsOneWidget);
    expect(find.byKey(const Key('need-help-button')), findsOneWidget);
    expect(find.byKey(const Key('simulated-shell-label')), findsOneWidget);
    expect(find.text(_limits), findsOneWidget);
    expect(find.textContaining('not a medical device'), findsOneWidget);
    final size = tester.getSize(find.byKey(const Key('im-ok-button')));
    expect(size.height, greaterThan(120));
  });

  testWidgets('cancel window: countdown ticks, one tap cancels, no dialog',
      (tester) async {
    await tester.pumpWidget(const GuardianApp());
    await tester.tap(find.byKey(const Key('need-help-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('countdown')), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('57'), findsOneWidget);
    expect(find.text(_limits), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancel-button')));
    await tester.pumpAndSettle();
    // One tap: back home, no confirmation dialog in between.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('home-note')), findsOneWidget);
    expect(find.textContaining('nothing was sent'), findsOneWidget);
  });

  testWidgets('cancel window: cancel button still works after the window ends',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: CancelWindowScreen(windowSeconds: 2)));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Window ended'), findsOneWidget);
    expect(find.textContaining('nothing is sent'), findsWidgets);
    expect(find.byKey(const Key('cancel-button')), findsOneWidget);
  });

  testWidgets('timeline: both episodes, labels on every row, dispatch disabled',
      (tester) async {
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: TimelineScreen(loader: () async => _fromDisk())));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('timeline-title')), findsOneWidget);
    expect(find.textContaining('SIMULATED'), findsWidgets);
    expect(find.byKey(const Key('run-cancelled')), findsOneWidget);
    expect(find.byKey(const Key('run-escalated')), findsOneWidget);
    expect(find.text(_limits), findsOneWidget);

    // 5 + 19 log entries, each with a complete source/freshness label.
    expect(find.text('source: simulator · freshness: simulated'),
        findsNWidgets(24));
    expect(find.textContaining('UNLABELLED'), findsNothing);

    // Dispatch reads as disabled / not sent, never as completed.
    expect(find.textContaining('Dispatch DISABLED: nothing sent'),
        findsOneWidget);
    expect(find.textContaining('NOT SENT'), findsOneWidget);
    expect(find.textContaining('DISPATCH step reached'), findsOneWidget);
    expect(find.textContaining('resolution: dispatched'), findsNothing);
    expect(find.textContaining('Dispatched'), findsNothing);
    expect(find.textContaining('dispatched '), findsNothing);
    expect(find.textContaining('does not re-verify'), findsNWidgets(2));
  });

  test('describeEntry flags an entry with no labels as UNLABELLED data', () {
    final e = LogEntry(
        seq: 0, ts: 0, type: 'cancel_window_lapsed', data: const {}, hash: 'h');
    final v = describeEntry(e, const DataLabels(null, null));
    expect(v.labels.complete, isFalse);
  });

  test('describeEntry never words a disabled dispatch as completed', () {
    final e = LogEntry(
        seq: 1,
        ts: 0,
        type: 'transition',
        data: const {
          'from': 'DISPATCH',
          'to': 'RESOLVED',
          'resolution': 'dispatched',
          'dispatchStatus': 'disabled',
        },
        hash: 'h');
    final v = describeEntry(e, const DataLabels('simulator', 'simulated'));
    expect(v.title, contains('DISABLED'));
    expect(v.title, contains('nothing was sent'));
  });
}
