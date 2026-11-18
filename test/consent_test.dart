// Session 5 Part 2: consent grants + revocation, enforced.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/adapters/health_store.dart';
import 'package:guardian_app/consent/consent.dart';
import 'package:guardian_app/engine/guardian_engine.dart';
import 'package:guardian_app/main.dart';
import 'package:guardian_app/proof_log.dart';
import 'package:guardian_app/proof_log.dart' as pl;
import 'package:guardian_app/rehearsal/consent_gated_notifier.dart';
import 'package:guardian_app/rehearsal/interactive_rehearsal.dart';
import 'package:guardian_app/rehearsal/proof_episodes.dart';
import 'package:guardian_app/rehearsal/scaled_scheduler.dart';
import 'package:guardian_app/screens/consent_screen.dart';
import 'package:guardian_app/screens/provider_screen.dart';
import 'package:guardian_app/screens/timeline_screen.dart';
import 'package:material_ui/material_ui.dart';

const _kin = ConsentRole.kin;
const _prov = ConsentRole.provider;
const _alerts = ConsentDataClass.alerts;
const _fhir = ConsentDataClass.fhirExport;

int _ms(int day) => DateTime.utc(2026, 11, day).millisecondsSinceEpoch;

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('consent store', () {
    test('deny by default: nothing is granted at first run', () {
      final s = ConsentStore();
      for (final r in ConsentRole.values) {
        for (final c in ConsentDataClass.values) {
          expect(s.isGranted(r, c), isFalse, reason: '${r.id}/${c.id}');
        }
      }
      expect(s.log.entries, isEmpty);
      expect(s.history(), isEmpty);
    });

    test('grant, revoke, re-grant; log chain verifies; repeats log nothing',
        () {
      var t = _ms(17);
      final s = ConsentStore(now: () => DateTime.fromMillisecondsSinceEpoch(t, isUtc: true));
      expect(s.grant(_prov, _fhir), isTrue);
      expect(s.isGranted(_prov, _fhir), isTrue);
      expect(s.grant(_prov, _fhir), isFalse); // already granted
      expect(s.revoke(_kin, _alerts), isFalse); // never granted
      t = _ms(18);
      expect(s.revoke(_prov, _fhir), isTrue);
      expect(s.isGranted(_prov, _fhir), isFalse);
      t = _ms(19);
      expect(s.grant(_prov, _fhir), isTrue);
      expect(s.isGranted(_prov, _fhir), isTrue);
      expect(s.log.entries.map((e) => e.type), [
        'consent_granted',
        'consent_revoked',
        'consent_granted',
      ]);
      expect(s.verify().ok, isTrue);
    });

    test('grants are independent per role and data class', () {
      final s = ConsentStore()..grant(_kin, _alerts);
      expect(s.isGranted(_kin, _alerts), isTrue);
      expect(s.isGranted(_kin, _fhir), isFalse);
      expect(s.isGranted(_prov, _alerts), isFalse);
      expect(s.isGranted(ConsentRole.nutritionist, _alerts), isFalse);
    });

    test('plain-language history names the dates', () {
      var t = _ms(17);
      final s = ConsentStore(now: () => DateTime.fromMillisecondsSinceEpoch(t, isUtc: true));
      s.grant(_prov, _fhir);
      expect(s.history(), [
        'You allowed your provider to receive FHIR exports on Nov 17. '
            'Still allowed.',
      ]);
      t = _ms(18);
      s.revoke(_prov, _fhir);
      expect(s.history(), [
        'You allowed your provider to receive FHIR exports on Nov 17; '
            'you revoked it on Nov 18.',
      ]);
    });

    test('tampering with the consent log is detected', () {
      final s = ConsentStore()
        ..grant(_prov, _fhir)
        ..revoke(_prov, _fhir);
      expect(s.verify().ok, isTrue);
      final anchor = s.log.anchor();
      expect(s.verify(anchor).ok, isTrue);
      s.grant(_kin, _alerts); // the anchor was stored earlier: log grew
      expect(s.verify().ok, isTrue);
      expect(s.verify(anchor).ok, isFalse);
      s.log.entries[0].data['role'] = 'kin'; // edit history
      expect(s.verify().ok, isFalse);
    });

    test('nutritionist grants are modelled, flagged as having no view', () {
      expect(
          consentUseOf(ConsentRole.nutritionist, _alerts), ConsentUse.noView);
      expect(consentUseOf(_kin, _alerts), ConsentUse.enforced);
      expect(consentUseOf(_prov, _fhir), ConsentUse.enforced);
    });
  });

  group('FHIR export enforcement', () {
    final now = DateTime.utc(2026, 11, 17, 12);
    Future<ProofLog> log() async =>
        ProofLog.parse(File('proofs/episode-log.json').readAsStringSync());
    Future<List<HealthObservation>> obs() async => [
      HealthObservation(
        type: 'heart_rate',
        value: 72,
        unit: 'bpm',
        ts: now.millisecondsSinceEpoch - 60000,
        source: 'simulated',
        deviceLabel: 'mock health_connect',
      ),
    ];

    testWidgets('refuse without grant, allow with it, refuse after revoke',
        (tester) async {
      _tall(tester);
      final store = ConsentStore();
      await tester.pumpWidget(MaterialApp(
        home: ProviderScreen(
            loader: log, observations: obs, now: () => now, consent: store),
      ));
      await tester.pumpAndSettle();

      Future<void> press() async {
        await tester.tap(find.byKey(const Key('export-fhir-button')));
        await tester.pumpAndSettle();
      }

      // 1. no grant: refused, nothing built.
      await press();
      expect(find.byKey(const Key('export-error')), findsOneWidget);
      expect(find.textContaining('have not allowed your provider'),
          findsOneWidget);
      expect(find.byKey(const Key('export-json')), findsNothing);
      expect(find.byKey(const Key('export-banner')), findsNothing);

      // 2. granted: proceeds.
      store.grant(_prov, _fhir);
      await press();
      expect(find.byKey(const Key('export-json')), findsOneWidget);
      expect(find.byKey(const Key('export-error')), findsNothing);

      // 3. revoked: refuses again and the bundle is gone from the screen.
      store.revoke(_prov, _fhir);
      await press();
      expect(find.byKey(const Key('export-error')), findsOneWidget);
      expect(find.byKey(const Key('export-json')), findsNothing);
      expect(store.verify().ok, isTrue);
    });

    testWidgets('a kin/alerts grant does not allow the export',
        (tester) async {
      _tall(tester);
      final store = ConsentStore()..grant(_kin, _alerts);
      await tester.pumpWidget(MaterialApp(
        home: ProviderScreen(
            loader: log, observations: obs, now: () => now, consent: store),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-fhir-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('export-json')), findsNothing);
      expect(find.byKey(const Key('export-error')), findsOneWidget);
    });

    testWidgets('provider copy no longer says grants are not implemented',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(MaterialApp(
        home: ProviderScreen(
            loader: log,
            observations: obs,
            now: () => now,
            consent: ConsentStore()),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('NOT '
          'implemented'), findsNothing);
      expect(find.textContaining('have allowed your provider'),
          findsOneWidget);
    });
  });

  group('kin alerts: cascade skip is logged at the notifier boundary', () {
    Future<InteractiveRehearsal> run(ConsentStore store) async {
      final fake = FakeScheduler(0);
      final c = InteractiveRehearsal(
        scheduler: ScaledScheduler(inner: fake, scale: 1, startAt: 0),
        consent: store,
      );
      c.simulateFall();
      await fake.advance(61000);
      await fake.advance(3 * 121000);
      await fake.advance(5000);
      c.refresh();
      return c;
    }

    test('no grant: every contact skipped, logged, still reaches dispatch '
        'step by canonical rules', () async {
      final c = await run(ConsentStore());
      final skips = c.log.entries
          .where((e) => e.type == 'kin_notification_skipped')
          .toList();
      expect(skips.map((e) => e.data['contactId']), ['kin-1', 'kin-2', 'kin-3']);
      expect(skips.every((e) => e.data['reason'] == consentSkipReason), isTrue);
      expect(c.notifier.calls, isEmpty, reason: 'inner notifier never called');
      // Skip is logged BEFORE the engine's own result row for that contact.
      final types = c.log.entries.map((e) => e.type).toList();
      expect(types.indexOf('kin_notification_skipped'),
          lessThan(types.indexOf('cascade_notified')));
      expect(
          c.log.entries
              .where((e) => e.type == 'cascade_notified')
              .every((e) => e.data['delivered'] == false),
          isTrue);
      // Canonical flow unchanged: one pass, exhausted, disabled dispatch.
      expect(c.engine.state, States.resolved);
      expect(c.outcome, RehearsalOutcome.dispatchStepDisabled);
      expect(c.dispatcher.dispatchCalls, 1);
      expect(c.log.verify().ok, isTrue);
      c.dispose();
    });

    test('grant present: kin are notified, no skip rows', () async {
      final c = await run(ConsentStore()..grant(_kin, _alerts));
      expect(c.log.entries.where((e) => e.type == 'kin_notification_skipped'),
          isEmpty);
      expect(c.notifier.calls.map((n) => n.contact.id),
          ['kin-1', 'kin-2', 'kin-3']);
      c.dispose();
    });

    test('revoked mid-episode: later contacts are skipped', () async {
      final store = ConsentStore()..grant(_kin, _alerts);
      final fake = FakeScheduler(0);
      final c = InteractiveRehearsal(
        scheduler: ScaledScheduler(inner: fake, scale: 1, startAt: 0),
        consent: store,
      );
      c.simulateFall();
      await fake.advance(61000); // kin-1 notified
      store.revoke(_kin, _alerts);
      await fake.advance(121000); // kin-2 turn
      expect(c.notifier.calls.map((n) => n.contact.id), ['kin-1']);
      expect(
          c.log.entries
              .where((e) => e.type == 'kin_notification_skipped')
              .map((e) => e.data['contactId']),
          ['kin-2']);
      expect(c.simulateKinAck(), isFalse, reason: 'nobody was told');
      c.dispose();
    });

    test('timeline text says the skip plainly', () async {
      final c = await run(ConsentStore());
      final labels = DataLabels.fromJson(proofLabels);
      pl.LogEntry view(String type) {
        final e = c.log.entries.firstWhere((e) => e.type == type);
        return pl.LogEntry(
            seq: e.seq, ts: e.ts, type: e.type, data: e.data, hash: e.hash);
      }

      final v = describeEntry(view('kin_notification_skipped'), labels);
      expect(v.title, contains('SKIPPED'));
      expect(v.title, contains('consent_not_granted'));
      expect(v.warn, isTrue);
      final n = describeEntry(view('cascade_notified'), labels);
      expect(n.title, contains('NOT notified'));
      c.dispose();
    });
  });

  group('Consent screen', () {
    testWidgets('lists every role x class, labelled local demo state',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(MaterialApp(
          home: ConsentScreen(store: ConsentStore())));
      expect(find.textContaining('LOCAL DEMO STATE'), findsOneWidget);
      for (final r in ConsentRole.values) {
        for (final c in ConsentDataClass.values) {
          expect(find.byKey(Key('consent-toggle-${r.id}-${c.id}')),
              findsOneWidget);
          expect(find.byKey(Key('consent-state-${r.id}-${c.id}')),
              findsOneWidget);
        }
      }
      expect(find.textContaining('No active view in this build'),
          findsNWidgets(3));
      expect(find.byKey(const Key('consent-history-empty')), findsOneWidget);
    });

    testWidgets('Allow / Stop buttons change state and show history',
        (tester) async {
      _tall(tester);
      final store = ConsentStore();
      await tester.pumpWidget(MaterialApp(home: ConsentScreen(store: store)));
      final key = Key('consent-toggle-${_prov.id}-${_fhir.id}');
      final size = tester.getSize(find.byKey(key));
      expect(size.height, greaterThanOrEqualTo(64));
      await tester.tap(find.byKey(key));
      await tester.pump();
      expect(store.isGranted(_prov, _fhir), isTrue);
      expect(find.text('FHIR export: ALLOWED'), findsOneWidget);
      expect(find.byKey(const Key('consent-history-0')), findsOneWidget);
      expect(find.textContaining('Still allowed'), findsOneWidget);
      await tester.tap(find.byKey(key));
      await tester.pump();
      expect(store.isGranted(_prov, _fhir), isFalse);
      expect(find.textContaining('you revoked it on'), findsOneWidget);
      expect(find.textContaining('Record check: unbroken'), findsOneWidget);
    });

    testWidgets('home reaches Consent; big buttons stay >= 120px',
        (tester) async {
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const GuardianApp());
      expect(tester.getSize(find.byKey(const Key('im-ok-button'))).height,
          greaterThanOrEqualTo(120));
      expect(tester.getSize(find.byKey(const Key('need-help-button'))).height,
          greaterThanOrEqualTo(120));
      await tester.tap(find.byKey(const Key('consent-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('consent-title')), findsOneWidget);
    });

    testWidgets('grant on the Consent screen is seen by the Provider screen '
        '(app-wide store)', (tester) async {
      _tall(tester);
      await tester.pumpWidget(const GuardianApp());
      await tester.tap(find.byKey(const Key('consent-button')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(Key('consent-toggle-${_prov.id}-${_fhir.id}')));
      await tester.pump();
      expect(find.text('FHIR export: ALLOWED'), findsOneWidget);
    });
  });
}
