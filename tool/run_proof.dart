// Guardian Session 3: Dart proof runner.
//
// Replays BOTH proof episodes (cancelled, escalated) through the Dart
// engine in lib/engine, with the same simulated inputs as
// integration/run-proof.js, verifies each hash chain with the Dart
// EventLog, and exports proofs/episode-log.dart.json (same shape as the
// Node export proofs/episode-log.json, which this tool never touches).
//
//   dart run tool/run_proof.dart [output-path]
//
// dart:io is used ONLY to write the output file. No network, no HTTP.

import 'dart:convert';
import 'dart:io';

import 'package:guardian_app/rehearsal/proof_episodes.dart';

Future<void> main(List<String> args) async {
  final outPath = args.isNotEmpty ? args.first : 'proofs/episode-log.dart.json';
  stdout.writeln('Guardian Session 3 Dart proof run');
  stdout.writeln(
    'Engine: lib/engine (Dart port). Signals: SIMULATED. '
    'Notifier: MockNotifier. Dispatch: DISABLED, no transport.',
  );
  stdout.writeln(
    'Windows: cancel ${cancelWindowSeconds}s, per-contact ack '
    '${ackTimeoutSeconds}s (defaults, simulated clock).',
  );

  final started = DateTime.now();
  final runs = await runProofEpisodes(startAt: started.millisecondsSinceEpoch);
  var failures = 0;
  for (final run in runs) {
    stdout.writeln('\n=== RUN ${run.label} ===');
    final t0 = run.log.entries.first.ts;
    for (final e in run.log.entries) {
      stdout.writeln(
        '  #${e.seq.toString().padLeft(2)}  '
        't+${((e.ts - t0) / 1000).round().toString().padLeft(4)}s  '
        '${e.type.padRight(24)} [${e.hash.substring(0, 10)}]',
      );
    }
    final plain = run.log.verify();
    final anchored = run.log.verify(run.anchor);
    stdout.writeln('  verify()       => ${plain.toJson()}');
    stdout.writeln('  verify(anchor) => ${anchored.toJson()}');
    if (!plain.ok || !anchored.ok) failures++;
    for (final c in run.checks) {
      failures++;
      stdout.writeln('  CHECK FAIL  $c');
    }
    if (run.checks.isEmpty) stdout.writeln('  all behavioural checks ok');
  }

  final out = exportProof(runs, started);
  final file = File(outPath)..createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(out)}\n',
  );
  stdout.writeln('\nExported both episodes -> $outPath');
  stdout.writeln(
    failures == 0
        ? '\nPROOF RESULT: all checks passed'
        : '\nPROOF RESULT: $failures CHECK(S) FAILED',
  );
  exit(failures == 0 ? 0 : 1);
}
