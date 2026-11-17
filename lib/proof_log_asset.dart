// Loads the bundled Node-recorded proof log (assets/episode-log.json).
// Kept apart from proof_log.dart so that file stays pure Dart (usable by
// tools running under plain `dart`, e.g. tool/export_fhir.dart).

import 'package:flutter/services.dart' show rootBundle;

import 'proof_log.dart';

Future<ProofLog> loadProofLogAsset() async =>
    ProofLog.parse(await rootBundle.loadString(proofAssetPath));
