// Session 4: provider view "Export FHIR" action (offline, simulated).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/adapters/health_store.dart';
import 'package:guardian_app/consent/consent.dart';
import 'package:guardian_app/fhir/fhir_export.dart';
import 'package:guardian_app/main.dart';
import 'package:guardian_app/proof_log.dart';
import 'package:guardian_app/screens/provider_screen.dart';
import 'package:guardian_app/widgets/honest_limits.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fhir_r4_check.dart';

final DateTime _now = DateTime.utc(2026, 11, 17, 12, 0, 0);

Future<ProofLog> _fromDisk() async =>
    ProofLog.parse(File('proofs/episode-log.json').readAsStringSync());

Future<List<HealthObservation>> _obs() async {
  final t = _now.millisecondsSinceEpoch;
  return [
    HealthObservation(
        type: 'heart_rate',
        value: 72,
        unit: 'bpm',
        ts: t - 60000,
        source: 'simulated',
        deviceLabel: 'mock health_connect'),
    HealthObservation(
        type: 'spo2',
        value: 97,
        unit: '%',
        ts: t - 120000,
        source: 'simulated',
        deviceLabel: 'mock health_connect'),
  ];
}

ConsentStore _allowed() =>
    ConsentStore()..grant(ConsentRole.provider, ConsentDataClass.fhirExport);

Widget _app({
  Future<ProofLog> Function()? loader,
  Future<List<HealthObservation>> Function()? observations,
  ConsentStore? consent,
}) =>
    MaterialApp(
        home: ProviderScreen(
            loader: loader ?? _fromDisk,
            observations: observations ?? _obs,
            consent: consent ?? _allowed(),
            now: () => _now));

Iterable<String> _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('provider view: labelled, nothing exported until the action',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('provider-title')), findsOneWidget);
    expect(find.textContaining('SIMULATED RECORD'), findsOneWidget);
    expect(find.textContaining('not a medical device'), findsWidgets);
    expect(find.text(honestLimitsLine), findsOneWidget);
    expect(find.byKey(const Key('export-fhir-button')), findsOneWidget);
    expect(find.byKey(const Key('export-json')), findsNothing);
    expect(find.byKey(const Key('provider-episode')), findsOneWidget);
    expect(find.textContaining('source: simulator · freshness: simulated'),
        findsOneWidget);
    // Each observation row carries source and freshness.
    for (final type in ['heart_rate', 'spo2']) {
      final t = tester.widget<Text>(find.byKey(Key('provider-obs-$type')));
      expect(t.data, contains('source: simulated · freshness: simulated'));
    }
  });

  testWidgets('Export FHIR shows the SIMULATED Bundle JSON, offline',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-fhir-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('export-banner')), findsOneWidget);
    expect(find.textContaining('SIMULATED FHIR R4 BUNDLE'), findsOneWidget);
    expect(find.textContaining('nothing was posted to any server'),
        findsOneWidget);
    expect(find.textContaining('not checked by a FHIR server'),
        findsOneWidget);

    final shown = tester
        .widget<SelectableText>(find.byKey(const Key('export-json')))
        .data!;
    final bundle = jsonDecode(shown) as Map<String, dynamic>;
    expect(bundle['resourceType'], 'Bundle');
    expect(bundle['type'], 'collection');
    expect(bundle['timestamp'], '2026-11-17T12:00:00.000Z');
    final types = (bundle['entry'] as List)
        .map((e) => ((e as Map)['resource'] as Map)['resourceType'])
        .toList();
    expect(types, ['Patient', 'Observation', 'Observation', 'Provenance']);
    // The Bundle that is displayed passes the offline R4 structural check.
    expect(Fhir4Definitions.load().checkBundle(bundle), isEmpty);
    // And its labels survived.
    expect(shown, contains('"freshness"'));
    expect(shown, contains('"valueCode": "simulated"'));
    expect(shown, contains('HTEST'));
    expect(shown, contains('SIMULATED DATA'));
    expect(shown.toLowerCase(), isNot(contains('dispatched')));
    // Identical to what the exporter builds for the same inputs.
    final log = await _fromDisk();
    final expected = buildFhirBundle(
      episode: FhirEpisodeLog.fromProofRun(
          log.runs.firstWhere((r) => r.label == 'escalated'), log.labels),
      observations: [
        for (final o in await _obs())
          ExportObservation.fromHealthStore(o, _now)
      ],
      exportedAt: _now,
    );
    expect(fhirBundleToJson(expected), shown);

    for (final t in _allText(tester)) {
      expect(t.toLowerCase().contains('dispatched'), isFalse,
          reason: 'engine wording leaked on screen: ${t.split('\n').first}');
    }
  });

  testWidgets('export is refused when the recorded log has no label',
      (tester) async {
    _tall(tester);
    final base = await _fromDisk();
    Future<ProofLog> unlabelled() async => ProofLog(
        banner: base.banner,
        generatedAt: base.generatedAt,
        labels: const DataLabels(null, null),
        runs: base.runs);
    await tester.pumpWidget(_app(loader: unlabelled));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-fhir-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-error')), findsOneWidget);
    expect(find.textContaining('Export refused'), findsOneWidget);
    expect(find.byKey(const Key('export-json')), findsNothing);
  });

  testWidgets('home opens the provider view', (tester) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GuardianApp());
    await tester.tap(find.byKey(const Key('provider-view-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('provider-title')), findsOneWidget);
  });
}
