// Session 3: structural cross-check of the DART proof runner against the
// Node proof export.
//
// Compares the Dart replay (run in-process through the same code the
// runner and the live rehearsal use, AND the committed runner artifact
// proofs/episode-log.dart.json) against proofs/episode-log.json:
//   same episodes, same entry types in the same order, same state
//   transitions and resolutions, same labels, same notifications.
// Timestamps and hash values are NOT compared (they differ by design:
// the clocks differ). Episode ids are normalized (engine instance tags).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/engine/guardian_engine.dart';
import 'package:guardian_app/rehearsal/proof_episodes.dart';

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

final _epId = RegExp(r'^ep-i\d+-\d+$');
const _timeKeys = {'ts', 'observedAt', 'receivedAt', 'generatedAt'};
const _hashKeys = {'hash', 'prevHash', 'headHash'};

/// Strip timestamps and hashes, normalize episode ids.
Object? _norm(Object? v) {
  if (v is Map) {
    return {
      for (final e in v.entries)
        if (!_timeKeys.contains(e.key) && !_hashKeys.contains(e.key))
          e.key as String: _norm(e.value),
    };
  }
  if (v is List) return v.map(_norm).toList();
  if (v is String && _epId.hasMatch(v)) return 'EP';
  return v;
}

List<String> _types(Map<String, dynamic> run) =>
    [for (final e in run['entries'] as List) (e as Map)['type'] as String];

/// (from, to, reason, resolution, dispatchStatus) of each transition.
List<String> _transitions(Map<String, dynamic> run) => [
      for (final e in run['entries'] as List)
        if ((e as Map)['type'] == 'transition')
          [
            for (final k in ['from', 'to', 'reason', 'resolution', 'dispatchStatus'])
              '$k=${(e['data'] as Map)[k]}'
          ].join(' ')
    ];

void _crossCheck(Map<String, dynamic> dart, Map<String, dynamic> node) {
  final dartRuns = (dart['runs'] as List).cast<Map<String, dynamic>>();
  final nodeRuns = (node['runs'] as List).cast<Map<String, dynamic>>();
  expect(dart['schema'], node['schema']);
  expect(dart['dataLabels'], node['dataLabels']);
  expect([for (final r in dartRuns) r['label']],
      [for (final r in nodeRuns) r['label']]);
  for (var i = 0; i < nodeRuns.length; i++) {
    final d = dartRuns[i];
    final n = nodeRuns[i];
    final label = n['label'];
    expect(_types(d), _types(n), reason: '$label: entry types, in order');
    expect(_transitions(d), _transitions(n),
        reason: '$label: state transitions and resolutions');
    expect(d['finalState'], n['finalState'], reason: '$label: final state');
    expect(d['keyedLog'], n['keyedLog']);
    expect(d['verify'], n['verify']);
    expect(d['verifyAnchored'], n['verifyAnchored']);
    expect((d['anchor'] as Map)['count'], (n['anchor'] as Map)['count']);
    expect(d['dataLabels'], n['dataLabels']);
    expect(d['dispatchSent'], n['dispatchSent']);
    expect(_norm(d['notifierCalls']), _norm(n['notifierCalls']),
        reason: '$label: notifier calls');
    expect(_norm(d['signals']), _norm(n['signals']),
        reason: '$label: simulated signals');
    // Full payload comparison, entry by entry, minus time/hash fields.
    final de = d['entries'] as List;
    final ne = n['entries'] as List;
    for (var k = 0; k < ne.length; k++) {
      expect(_norm((de[k] as Map)['data']), _norm((ne[k] as Map)['data']),
          reason: '$label entry #$k (${(ne[k] as Map)['type']}) data');
    }
  }
}

void main() {
  final node = _readJson('proofs/episode-log.json');

  test('Dart in-process replay matches the Node proof structurally', () async {
    final runs = await runProofEpisodes(startAt: 1000000);
    expect(runs.every((r) => r.checks.isEmpty), isTrue,
        reason: runs.expand((r) => r.checks).join('; '));
    final dart = jsonDecode(jsonEncode(exportProof(runs, DateTime.now())))
        as Map<String, dynamic>;
    _crossCheck(dart, node);
  });

  test('committed runner artifact proofs/episode-log.dart.json matches Node',
      () {
    _crossCheck(_readJson('proofs/episode-log.dart.json'), node);
  });

  test('runner artifact: chains re-verify with the Dart EventLog', () {
    final art = _readJson('proofs/episode-log.dart.json');
    for (final run in (art['runs'] as List).cast<Map<String, dynamic>>()) {
      final log = EventLog();
      for (final e in run['entries'] as List) {
        log.entries.add(LogEntry.fromJson(e as Map<String, dynamic>));
      }
      final anchor = run['anchor'] as Map<String, dynamic>;
      expect(log.verify().ok, isTrue, reason: '${run['label']} plain');
      expect(
          log
              .verify(Anchor(
                  count: anchor['count'] as int,
                  headHash: anchor['headHash'] as String))
              .ok,
          isTrue,
          reason: '${run['label']} anchored');
    }
  });

  test('runner artifact: every record is labelled simulator / simulated', () {
    final art = _readJson('proofs/episode-log.dart.json');
    expect(art['dataLabels'],
        {'source': 'simulator', 'freshness': 'simulated'});
    for (final run in (art['runs'] as List).cast<Map<String, dynamic>>()) {
      expect(run['dataLabels'],
          {'source': 'simulator', 'freshness': 'simulated'});
      expect(run['dispatchSent'], isFalse);
      for (final s in run['signals'] as List) {
        expect((s as Map)['source'], 'simulator');
        expect(s['freshness'], 'simulated');
      }
      for (final c in run['notifierCalls'] as List) {
        final loc = (c as Map)['location'] as Map;
        expect(loc['source'], 'simulator');
        expect(loc['freshness'], 'simulated');
      }
      for (final e in run['entries'] as List) {
        if ((e as Map)['type'] == 'trigger_received') {
          final sig = ((e['data'] as Map)['details'] as Map)['signal'] as Map;
          expect(sig['source'], 'simulator');
          expect(sig['freshness'], 'simulated');
        }
        if (e['type'] == 'sandbox_payload_built') {
          expect((e['data'] as Map)['dataLabels'],
              {'source': 'simulator', 'freshness': 'simulated'});
          expect((e['data'] as Map)['sent'], isFalse);
        }
        if (e['type'] == 'dispatch_result') {
          expect((e['data'] as Map)['status'], 'disabled');
          expect((e['data'] as Map)['reference'], isNull);
        }
      }
    }
  });

  test('no network or dart:io imports in lib/ or the Dart engine', () {
    final bad = RegExp(
        r"import\s+'(dart:io|dart:html|package:http/|package:dio/|dart:js_interop)");
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        if (bad.hasMatch(f.readAsStringSync())) hits.add(f.path);
      }
    }
    expect(hits, isEmpty);
  });
}
