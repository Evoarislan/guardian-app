// Reads the episode log exported by the Node proof runner
// (integration/run-proof.js -> proofs/episode-log.json, bundled as an
// asset). This is the "log bridge": the shell renders what the
// reference engine recorded; it does not run an engine itself.

import 'dart:convert';

const String proofAssetPath = 'assets/episode-log.json';

/// Source/freshness label. A missing label is kept as null so the UI can
/// show it as UNLABELLED instead of silently defaulting to anything.
class DataLabels {
  const DataLabels(this.source, this.freshness);

  final String? source;
  final String? freshness;

  factory DataLabels.fromJson(Object? json) {
    if (json is Map<String, dynamic>) {
      return DataLabels(json['source'] as String?, json['freshness'] as String?);
    }
    return const DataLabels(null, null);
  }

  bool get complete => source != null && freshness != null;
}

class LogEntry {
  LogEntry({
    required this.seq,
    required this.ts,
    required this.type,
    required this.data,
    required this.hash,
  });

  final int seq;
  final int ts;
  final String type;
  final Map<String, dynamic> data;
  final String hash;

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        seq: json['seq'] as int,
        ts: json['ts'] as int,
        type: json['type'] as String,
        data: (json['data'] as Map<String, dynamic>?) ?? const {},
        hash: json['hash'] as String,
      );
}

class ProofRun {
  ProofRun({
    required this.label,
    required this.finalState,
    required this.verifyOk,
    required this.verifyAnchoredOk,
    required this.labels,
    required this.entries,
    required this.dispatchSent,
    required this.headHash,
  });

  final String label; // "cancelled" | "escalated"
  final String finalState;
  final bool verifyOk;
  final bool verifyAnchoredOk;
  final DataLabels labels;
  final List<LogEntry> entries;
  final bool dispatchSent;
  final String headHash;

  factory ProofRun.fromJson(Map<String, dynamic> json) {
    final verify = json['verify'] as Map<String, dynamic>;
    final anchored = json['verifyAnchored'] as Map<String, dynamic>;
    final anchor = json['anchor'] as Map<String, dynamic>;
    return ProofRun(
      label: json['label'] as String,
      finalState: json['finalState'] as String,
      verifyOk: verify['ok'] == true,
      verifyAnchoredOk: anchored['ok'] == true,
      labels: DataLabels.fromJson(json['dataLabels']),
      entries: (json['entries'] as List<dynamic>)
          .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      dispatchSent: json['dispatchSent'] == true,
      headHash: anchor['headHash'] as String,
    );
  }
}

class ProofLog {
  ProofLog({
    required this.banner,
    required this.generatedAt,
    required this.labels,
    required this.runs,
  });

  final String banner;
  final String generatedAt;
  final DataLabels labels;
  final List<ProofRun> runs;

  factory ProofLog.parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return ProofLog(
      banner: json['banner'] as String? ?? '',
      generatedAt: json['generatedAt'] as String? ?? 'unknown',
      labels: DataLabels.fromJson(json['dataLabels']),
      runs: (json['runs'] as List<dynamic>)
          .map((r) => ProofRun.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}
