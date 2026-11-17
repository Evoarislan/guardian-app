// Guardian Session 4: offline FHIR R4 export of the recorded proof episode.
//
//   dart run tool/export_fhir.dart [proof-log.json] [output.json]
//
// Reads the recorded proof log (default proofs/episode-log.json), takes
// the SIMULATED observations from the mock health store, builds the R4
// Bundle, checks it for the labels this export promises, and writes it.
// dart:io is used ONLY to read the input file and write the output file.
// No network, no HAPI, no server: nothing is posted anywhere.

import 'dart:convert';
import 'dart:io';

import 'package:guardian_app/adapters/health_store.dart';
import 'package:guardian_app/fhir/fhir_export.dart';
import 'package:guardian_app/proof_log.dart';

Future<void> main(List<String> args) async {
  final inPath = args.isNotEmpty ? args[0] : 'proofs/episode-log.json';
  final outPath = args.length > 1 ? args[1] : 'proofs/fhir-bundle.simulated.json';

  final log = ProofLog.parse(File(inPath).readAsStringSync());
  final run = log.runs.firstWhere(
    (r) => r.label == 'escalated',
    orElse: () => log.runs.last,
  );
  final now = DateTime.now().toUtc();
  final observations = await MockHealthStoreAdapter().readObservations();
  final bundle = buildFhirBundle(
    episode: FhirEpisodeLog.fromProofRun(run, log.labels),
    observations: [
      for (final o in observations) ExportObservation.fromHealthStore(o, now),
    ],
    exportedAt: now,
  );
  final json = fhirBundleToJson(bundle);
  File(outPath).writeAsStringSync('$json\n');

  final entries = (bundle['entry'] as List).cast<Map>();
  final counts = <String, int>{};
  for (final e in entries) {
    final t = (e['resource'] as Map)['resourceType'] as String;
    counts[t] = (counts[t] ?? 0) + 1;
  }
  stdout.writeln('Guardian Session 4 FHIR R4 export (OFFLINE, SIMULATED)');
  stdout.writeln('  episode:   ${run.label} from $inPath (generated ${log.generatedAt})');
  stdout.writeln('  bundle id: ${bundle['id']}');
  stdout.writeln('  resources: $counts');
  stdout.writeln('  wrote:     $outPath (${utf8.encode(json).length} bytes)');
  stdout.writeln('  nothing was posted to any server.');
}
