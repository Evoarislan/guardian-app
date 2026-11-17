// Session 4: FHIR R4 export, validated OFFLINE against fixtures written
// by hand from the R4 definitions (test/fixtures/fhir_r4/). No server,
// no HAPI, no network. The checker is a structural check, not the
// official HL7 validator (see SESSION-4-RESULT.md for what that means).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/adapters/health_store.dart';
import 'package:guardian_app/fhir/fhir_export.dart';
import 'package:guardian_app/proof_log.dart';
import 'package:guardian_app/rehearsal/proof_episodes.dart';

import 'support/fhir_r4_check.dart';

final DateTime _exportedAt = DateTime.utc(2026, 11, 17, 12, 0, 0);
final int _t = _exportedAt.millisecondsSinceEpoch;

/// Fixed observations: one per supported type, 1..6 minutes old.
List<HealthObservation> _obs({String source = 'simulated'}) {
  const series = {
    'heart_rate': (72, 'bpm'),
    'spo2': (97, '%'),
    'steps': (1240, 'count'),
    'sleep': (402, 'minutes'),
    'resting_heart_rate': (61, 'bpm'),
    'skin_temperature': (36.4, 'celsius'),
  };
  var i = 0;
  return [
    for (final e in series.entries)
      HealthObservation(
        type: e.key,
        value: e.value.$1,
        unit: e.value.$2,
        ts: _t - (++i) * 60000,
        source: source,
        deviceLabel: source == 'simulated' ? 'mock health_connect' : 'test band',
      ),
  ];
}

ProofLog _recorded() =>
    ProofLog.parse(File('proofs/episode-log.json').readAsStringSync());

FhirEpisodeLog _recordedEpisode() {
  final log = _recorded();
  final run = log.runs.firstWhere((r) => r.label == 'escalated');
  return FhirEpisodeLog.fromProofRun(run, log.labels);
}

List<ExportObservation> _simObs() => [
  for (final o in _obs()) ExportObservation.fromHealthStore(o, _exportedAt),
];

Map<String, dynamic> _bundle({
  FhirEpisodeLog? episode,
  List<ExportObservation>? observations,
}) => buildFhirBundle(
  episode: episode ?? _recordedEpisode(),
  observations: observations ?? _simObs(),
  exportedAt: _exportedAt,
);

List<Map<String, dynamic>> _resources(Map<String, dynamic> b, [String? type]) => [
  for (final e in (b['entry'] as List))
    if (type == null ||
        ((e as Map)['resource'] as Map)['resourceType'] == type)
      (e as Map)['resource'] as Map<String, dynamic>,
];

/// The data-label extension of a resource (or of a Bundle's meta).
Map<String, dynamic> _label(Map<String, dynamic> r) {
  final exts =
      (r['resourceType'] == 'Bundle'
              ? (r['meta'] as Map)['extension']
              : r['extension'])
          as List;
  final ext = exts.cast<Map>().firstWhere((e) => e['url'] == extDataLabel);
  return {
    for (final s in (ext['extension'] as List).cast<Map>())
      s['url'] as String: s.entries.firstWhere((e) => e.key != 'url').value,
  };
}

bool _hasHtest(Map<String, dynamic> r) =>
    ((r['meta'] as Map)['security'] as List? ?? const []).cast<Map>().any(
      (c) => c['system'] == sysActReason && c['code'] == 'HTEST',
    );

void main() {
  final defs = Fhir4Definitions.load();
  final codings = loadCodings();

  group('checker self-test (hand-written R4 fixtures)', () {
    test('valid minimal resources are accepted', () {
      final f = jsonDecode(
        File('test/fixtures/fhir_r4/valid_minimal.json').readAsStringSync(),
      );
      for (final r in (f['resources'] as List).cast<Map<String, dynamic>>()) {
        expect(
          defs.check(r),
          isEmpty,
          reason: '${r['resourceType']} should be valid',
        );
      }
    });

    test('invalid resources are each rejected for the stated reason', () {
      final f = jsonDecode(
        File('test/fixtures/fhir_r4/invalid_minimal.json').readAsStringSync(),
      );
      for (final c in (f['cases'] as List).cast<Map<String, dynamic>>()) {
        final problems = defs.check(c['resource'] as Map<String, dynamic>);
        expect(
          problems.any((p) => p.contains(c['expect'] as String)),
          isTrue,
          reason: 'expected "${c['expect']}" in $problems',
        );
      }
    });

    test('an unresolvable urn:uuid reference is caught', () {
      final b = _bundle();
      final prov = _resources(b, 'Provenance').single;
      (prov['target'] as List).add({
        'reference': 'urn:uuid:00000000-0000-5000-8000-000000000000',
      });
      expect(
        defs.checkBundle(b).any((p) => p.contains('does not resolve')),
        isTrue,
      );
    });
  });

  group('Bundle structure', () {
    test('passes the R4 structural checks', () {
      final b = _bundle();
      expect(defs.checkBundle(b), isEmpty);
    });

    test('resource types and counts', () {
      final b = _bundle();
      expect(b['resourceType'], 'Bundle');
      expect(b['type'], 'collection');
      expect(b['timestamp'], '2026-11-17T12:00:00.000Z');
      final types = _resources(b).map((r) => r['resourceType']).toList();
      expect(types.where((t) => t == 'Patient').length, 1);
      expect(types.where((t) => t == 'Observation').length, 6);
      expect(types.where((t) => t == 'Provenance').length, 1);
      expect(types.length, 8);
      for (final e in (b['entry'] as List).cast<Map>()) {
        expect(e['fullUrl'], startsWith('urn:uuid:'));
      }
    });

    test('Observation: required fields, LOINC + UCUM + category per type', () {
      final b = _bundle();
      final obs = _resources(b, 'Observation');
      final byLoinc = {
        for (final o in obs)
          (((o['code'] as Map)['coding'] as List).single as Map)['code']: o,
      };
      final spec = (codings['observations'] as Map).cast<String, dynamic>();
      for (final entry in spec.entries) {
        final s = entry.value as Map<String, dynamic>;
        final o = byLoinc[s['loinc']];
        expect(o, isNotNull, reason: '${entry.key} -> ${s['loinc']}');
        expect(o!['status'], 'final');
        final coding = ((o['code'] as Map)['coding'] as List).single as Map;
        expect(coding['system'], 'http://loinc.org');
        expect(coding['display'], s['display']);
        final cat =
            (((o['category'] as List).single as Map)['coding'] as List).single
                as Map;
        expect(
          cat['system'],
          'http://terminology.hl7.org/CodeSystem/observation-category',
        );
        expect(cat['code'], s['category']);
        final q = o['valueQuantity'] as Map;
        expect(q['system'], 'http://unitsofmeasure.org');
        expect(q['code'], s['ucum']);
        expect(q['unit'], s['unit']);
        expect(q['value'], isA<num>());
        expect(o['effectiveDateTime'], matches(RegExp(r'Z$')));
        expect((o['subject'] as Map)['type'], 'Patient');
      }
      // Values pass through untouched (no re-stamping, no rounding).
      final hr = byLoinc['8867-4']!;
      expect((hr['valueQuantity'] as Map)['value'], 72);
      expect(
        hr['effectiveDateTime'],
        DateTime.fromMillisecondsSinceEpoch(
          _t - 60000,
          isUtc: true,
        ).toIso8601String(),
      );
    });

    test('references resolve: subject -> Patient, Provenance targets all', () {
      final b = _bundle();
      final urls = {
        for (final e in (b['entry'] as List).cast<Map>())
          ((e['resource'] as Map)['id'] as String): e['fullUrl'] as String,
      };
      final patientUrl = urls['guardian-synthetic-wearer'];
      for (final o in _resources(b, 'Observation')) {
        expect((o['subject'] as Map)['reference'], patientUrl);
      }
      final prov = _resources(b, 'Provenance').single;
      final targets = (prov['target'] as List)
          .cast<Map>()
          .map((t) => t['reference'])
          .toSet();
      expect(targets, containsAll(urls.values.where((u) => u != urls['guardian-export-provenance'])));
      expect(targets.length, 7); // Patient + 6 Observations
      expect(prov['recorded'], b['timestamp']);
      final agent = (prov['agent'] as List).single as Map;
      expect(agent['who'], isNotEmpty);
      expect(
        ((agent['type'] as Map)['coding'] as List).single,
        containsPair('system', sysProvParticipant),
      );
    });

    test('Patient is a placeholder: no real identifiers of any kind', () {
      final p = _resources(_bundle(), 'Patient').single;
      for (final k in [
        'identifier',
        'birthDate',
        'gender',
        'address',
        'telecom',
        'photo',
        'contact',
        'generalPractitioner',
        'managingOrganization',
      ]) {
        expect(p.containsKey(k), isFalse, reason: 'Patient must not carry $k');
      }
      expect(p['name'], [
        {'use': 'anonymous', 'text': 'Synthetic demo wearer'},
      ]);
    });

    test('Provenance carries the episode log summary, chain result, hashes', () {
      final prov = _resources(_bundle(), 'Provenance').single;
      final exts = (prov['extension'] as List).cast<Map>();
      final summary = exts.firstWhere((e) => e['url'] == extEpisodeSummary);
      Object? v(String url) => (summary['extension'] as List)
          .cast<Map>()
          .firstWhere((e) => e['url'] == url)
          .entries
          .firstWhere((e) => e.key != 'url')
          .value;
      final ep = _recordedEpisode();
      expect(v('runLabel'), 'escalated');
      expect(v('headHash'), ep.headHash);
      expect(v('chainVerified'), isTrue);
      expect(v('chainVerifiedBy'), contains('Node engine'));
      expect(v('chainVerifiedBy'), contains('not re-verified'));
      expect(v('dispatch'), contains('DISABLED: NOT SENT'));
      expect(v('entryCount'), ep.entries.length);
      final logEntries = exts.where((e) => e['url'] == extEpisodeLogEntry);
      expect(logEntries.length, ep.entries.length);
      expect(logEntries.length, 19);
      final entity = (prov['entity'] as List).cast<Map>().first;
      expect(entity['role'], 'source');
      expect(
        ((entity['what'] as Map)['identifier'] as Map)['value'],
        ep.headHash,
      );
    });

    test('deterministic and JSON round-trips', () {
      final a = fhirBundleToJson(_bundle());
      final b = fhirBundleToJson(_bundle());
      expect(a, b);
      expect(jsonDecode(a), _bundle());
    });

    test('no "dispatched" wording anywhere in the export', () {
      expect(fhirBundleToJson(_bundle()).toLowerCase(), isNot(contains('dispatched')));
    });
  });

  group('source / freshness labelling survives export', () {
    test('simulated: unmistakable on EVERY resource and the Bundle', () {
      final b = _bundle();
      expect(_label(b)['freshness'], Freshness.simulated);
      expect(_hasHtest(b), isTrue);
      expect(
        (((b['meta'] as Map)['extension'] as List).cast<Map>().any(
          (e) => (e['valueString'] as String?)?.startsWith('SIMULATED DATA') ?? false,
        )),
        isTrue,
      );
      for (final r in _resources(b)) {
        final l = _label(r);
        expect(l['freshness'], Freshness.simulated, reason: '${r['resourceType']}');
        expect(l['source'], isNotEmpty);
        expect(l.containsKey('ageSeconds'), isFalse);
        expect(_hasHtest(r), isTrue, reason: 'HTEST on ${r['resourceType']}');
        final tag = ((r['meta'] as Map)['tag'] as List).cast<Map>().single;
        expect(tag['system'], sysFreshness);
        expect(tag['code'], 'simulated');
        expect(tag['display'], contains('SIMULATED'));
        expect(((r['text'] as Map)['div'] as String), contains('<b>SIMULATED</b>'));
      }
    });

    test('fetched keeps its age; not marked as test data; never "live"', () {
      final fetched = [
        for (final o in _obs(source: 'health_connect'))
          ExportObservation.fromHealthStore(o, _exportedAt),
      ];
      final b = _bundle(observations: fetched);
      expect(defs.checkBundle(b), isEmpty);
      final ages = <int>[];
      for (final o in _resources(b, 'Observation')) {
        final l = _label(o);
        expect(l['freshness'], Freshness.fetched);
        expect(l['source'], contains('health_connect'));
        ages.add(l['ageSeconds'] as int);
        expect(_hasHtest(o), isFalse);
        expect(
          (((o['meta'] as Map)['tag'] as List).single as Map)['code'],
          'fetched',
        );
        expect(((o['text'] as Map)['div'] as String), isNot(contains('SIMULATED')));
      }
      expect(ages..sort(), [60, 120, 180, 240, 300, 360]);
      // The derived Provenance and the Bundle are NOT fresher than the
      // synthetic patient and simulated log they include.
      expect(_label(_resources(b, 'Provenance').single)['freshness'], Freshness.simulated);
      expect(_label(b)['freshness'], Freshness.simulated);
    });

    test('live survives too (no age, not test data)', () {
      final live = ExportObservation(
        HealthObservation(
          type: 'heart_rate',
          value: 80,
          unit: 'bpm',
          ts: _t,
          source: 'ble',
          deviceLabel: 'test strap',
        ),
        FhirLabel(source: 'ble_hr (test strap)', freshness: Freshness.live),
      );
      final b = _bundle(observations: [live]);
      expect(defs.checkBundle(b), isEmpty);
      final o = _resources(b, 'Observation').single;
      final l = _label(o);
      expect(l['freshness'], Freshness.live);
      expect(l['source'], 'ble_hr (test strap)');
      expect(l.containsKey('ageSeconds'), isFalse);
      expect(_hasHtest(o), isFalse);
    });

    test('all three can coexist in one Bundle, each keeping its own label', () {
      final mixed = [
        ExportObservation.fromHealthStore(_obs()[0], _exportedAt), // simulated
        ExportObservation.fromHealthStore(
          _obs(source: 'healthkit')[1],
          _exportedAt,
        ), // fetched
        ExportObservation(
          HealthObservation(
            type: 'resting_heart_rate',
            value: 60,
            unit: 'bpm',
            ts: _t,
            source: 'ble',
            deviceLabel: 'strap',
          ),
          FhirLabel(source: 'ble_hr', freshness: Freshness.live),
        ),
      ];
      final b = _bundle(observations: mixed);
      expect(defs.checkBundle(b), isEmpty);
      final fresh = _resources(b, 'Observation')
          .map((o) => _label(o)['freshness'])
          .toList();
      expect(fresh, [Freshness.simulated, Freshness.fetched, Freshness.live]);
    });

    test('FhirLabel.combine: simulated > fetched (oldest age) > live', () {
      FhirLabel f(int age) =>
          FhirLabel(source: 's', freshness: Freshness.fetched, ageSeconds: age);
      final live = FhirLabel(source: 's', freshness: Freshness.live);
      final sim = FhirLabel(source: 's', freshness: Freshness.simulated);
      expect(FhirLabel.combine('d', [live, f(30), f(90)]).ageSeconds, 90);
      expect(FhirLabel.combine('d', [live, f(30)]).freshness, Freshness.fetched);
      expect(FhirLabel.combine('d', [live]).freshness, Freshness.live);
      expect(FhirLabel.combine('d', [live, f(30), sim]).freshness, Freshness.simulated);
      expect(() => FhirLabel.combine('d', []), throwsArgumentError);
    });

    test('Dart-engine run: label comes from the run, chain verified now', () async {
      final run = await runEscalatedEpisode(startAt: 7000000);
      final b = _bundle(episode: FhirEpisodeLog.fromEpisodeRun(run));
      expect(defs.checkBundle(b), isEmpty);
      final summary = (_resources(b, 'Provenance').single['extension'] as List)
          .cast<Map>()
          .firstWhere((e) => e['url'] == extEpisodeSummary);
      final byUrl = {
        for (final s in (summary['extension'] as List).cast<Map>()) s['url']: s,
      };
      expect(byUrl['chainVerified']!['valueBoolean'], isTrue);
      expect(byUrl['chainVerifiedBy']!['valueString'], contains('Dart EventLog.verify()'));
      expect(fhirBundleToJson(b).toLowerCase(), isNot(contains('dispatched')));
    });

    test('a tampered Dart log is exported as chainVerified=false', () async {
      final run = await runEscalatedEpisode(startAt: 7000000);
      run.log.entries[3].data['to'] = 'RESOLVED';
      final b = _bundle(episode: FhirEpisodeLog.fromEpisodeRun(run));
      final summary = (_resources(b, 'Provenance').single['extension'] as List)
          .cast<Map>()
          .firstWhere((e) => e['url'] == extEpisodeSummary);
      final verified = (summary['extension'] as List)
          .cast<Map>()
          .firstWhere((s) => s['url'] == 'chainVerified');
      expect(verified['valueBoolean'], isFalse);
    });
  });

  test('the shareable file written by tool/export_fhir.dart passes the checks',
      () {
    final f = File('proofs/fhir-bundle.simulated.json');
    expect(f.existsSync(), isTrue, reason: 'run: dart run tool/export_fhir.dart');
    final b = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    expect(defs.checkBundle(b), isEmpty);
    expect(_label(b)['freshness'], Freshness.simulated);
    for (final r in _resources(b)) {
      expect(_label(r)['freshness'], Freshness.simulated);
      expect(_hasHtest(r), isTrue);
    }
    expect(f.readAsStringSync().toLowerCase(), isNot(contains('dispatched')));
  });

  group('refusals (no silent defaults)', () {
    test('episode log without a label is refused', () {
      final log = _recorded();
      final run = log.runs.first;
      expect(
        () => FhirEpisodeLog.fromProofRun(run, const DataLabels(null, null)),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => FhirEpisodeLog.fromProofRun(run, const DataLabels('simulator', null)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('FhirLabel validation', () {
      expect(
        () => FhirLabel(source: 's', freshness: Freshness.fetched),
        throwsArgumentError,
        reason: 'fetched needs an age',
      );
      expect(
        () => FhirLabel(source: 's', freshness: 'real-time'),
        throwsArgumentError,
      );
      expect(
        () => FhirLabel(source: '', freshness: Freshness.live),
        throwsArgumentError,
      );
      expect(
        () => FhirLabel(source: 's', freshness: Freshness.live, ageSeconds: 3),
        throwsArgumentError,
      );
      expect(
        () => FhirLabel(source: 's', freshness: Freshness.fetched, ageSeconds: -1),
        throwsArgumentError,
      );
    });

    test('unknown source, wrong unit, unsupported type, duplicates', () {
      final o = _obs().first;
      HealthObservation copy({String? source, String? unit, String? type}) =>
          HealthObservation(
            type: type ?? o.type,
            value: o.value,
            unit: unit ?? o.unit,
            ts: o.ts,
            source: source ?? o.source,
            deviceLabel: o.deviceLabel,
          );
      expect(
        () => ExportObservation.fromHealthStore(copy(source: 'fitbit-cloud'), _exportedAt),
        throwsArgumentError,
      );
      expect(
        () => _bundle(
          observations: [
            ExportObservation.fromHealthStore(copy(unit: 'mmHg'), _exportedAt),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _bundle(
          observations: [
            ExportObservation.fromHealthStore(copy(type: 'blood_glucose'), _exportedAt),
          ],
        ),
        throwsArgumentError,
      );
      final one = ExportObservation.fromHealthStore(o, _exportedAt);
      expect(() => _bundle(observations: [one, one]), throwsArgumentError);
    });
  });

  group('offline guarantee', () {
    test('no network or file I/O imports anywhere in lib/', () {
      final banned = RegExp(
        r"dart:io|dart:html|dart:js|package:http|package:dio|HttpClient|WebSocket|RawSocket|Socket\.connect|Uri\.http|launchUrl",
      );
      final hits = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsLinesSync();
        for (var i = 0; i < src.length; i++) {
          final line = src[i].trim();
          if (line.startsWith('//')) continue; // comments may name the ban
          if (banned.hasMatch(line)) hits.add('${f.path}:${i + 1}: $line');
        }
      }
      expect(hits, isEmpty);
    });

    test('the FHIR exporter has no transport: only data in, Map out', () {
      final src = File('lib/fhir/fhir_export.dart').readAsStringSync();
      expect(src, isNot(contains('http.')));
      expect(src, isNot(contains('hapi')));
    });
  });
}
