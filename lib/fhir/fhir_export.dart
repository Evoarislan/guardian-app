// FHIR R4 export (Session 4). OFFLINE: pure data transformation, no
// network, no file I/O, no server. The output is a Bundle (type
// "collection") as a Dart Map / JSON string that a person could share.
//
// Resources: Patient (synthetic placeholder, no real identifiers),
// Observation (one per health observation), Provenance (one, covering
// the episode log and the observation source).
//
// HONESTY. Every resource carries its source/freshness label:
//   - a `data-label` extension: source + freshness
//     (live | fetched | simulated) + ageSeconds (REQUIRED when fetched);
//   - a `meta.tag` coding for the freshness;
//   - for anything simulated: `meta.security` = v3-ActReason#HTEST
//     ("test health data") and a narrative that says SIMULATED.
// A missing or inconsistent label throws; nothing is defaulted to "live".
//
// This is a record of readings and of an escalation log. It makes no
// diagnosis and no clinical claim; thresholds are wearer settings and
// Guardian is not a medical device.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../adapters/health_store.dart';
import '../engine/event_log.dart' as engine_log;
import '../proof_log.dart' as proof;
import '../rehearsal/proof_episodes.dart' show EpisodeRun;

// ---- Constants (system URIs are identifiers only; never dereferenced) ----

/// Reserved `.invalid` host: these URLs name Guardian's own extensions
/// and code systems and are never fetched.
const String guardianBase = 'https://guardian.invalid/fhir';
const String extDataLabel = '$guardianBase/StructureDefinition/data-label';
const String extEpisodeSummary =
    '$guardianBase/StructureDefinition/episode-summary';
const String extEpisodeLogEntry =
    '$guardianBase/StructureDefinition/episode-log-entry';
const String sysFreshness = '$guardianBase/CodeSystem/data-freshness';
const String sysEventLogHead = '$guardianBase/event-log-head';

const String sysLoinc = 'http://loinc.org';
const String sysUcum = 'http://unitsofmeasure.org';
const String sysObsCategory =
    'http://terminology.hl7.org/CodeSystem/observation-category';
const String sysActReason =
    'http://terminology.hl7.org/CodeSystem/v3-ActReason';
const String sysProvParticipant =
    'http://terminology.hl7.org/CodeSystem/provenance-participant-type';
const String provEntityRoleSystem =
    'http://hl7.org/fhir/provenance-entity-role';

/// Freshness vocabulary (the same three words the app shows).
class Freshness {
  static const live = 'live';
  static const fetched = 'fetched';
  static const simulated = 'simulated';
  static const all = {live, fetched, simulated};
}

const String exportNotice =
    'SIMULATED DATA. Synthetic wearer, simulated signals and readings: not '
    "a real person's record. Guardian is a consumer safety aid, not a "
    'medical device; nothing here is a diagnosis or a clinical finding.';

// ---- Labels ----

/// Source/freshness label. Validates itself: `fetched` needs an age,
/// every label needs a source, freshness must be one of the three words.
class FhirLabel {
  FhirLabel({required this.source, required this.freshness, this.ageSeconds}) {
    if (source.isEmpty) {
      throw ArgumentError('FhirLabel: source is required');
    }
    if (!Freshness.all.contains(freshness)) {
      throw ArgumentError(
        'FhirLabel: freshness must be one of '
        '${Freshness.all.join(', ')}, got "$freshness"',
      );
    }
    if (freshness == Freshness.fetched && ageSeconds == null) {
      throw ArgumentError(
        'FhirLabel: fetched data must carry its age (ageSeconds)',
      );
    }
    if (ageSeconds != null && ageSeconds! < 0) {
      throw ArgumentError('FhirLabel: ageSeconds must be >= 0');
    }
    if (freshness != Freshness.fetched && ageSeconds != null) {
      throw ArgumentError('FhirLabel: ageSeconds only applies to fetched data');
    }
  }

  final String source;
  final String freshness;
  final int? ageSeconds;

  bool get simulated => freshness == Freshness.simulated;

  Map<String, dynamic> toExtension() => {
    'url': extDataLabel,
    'extension': [
      {'url': 'source', 'valueString': source},
      {'url': 'freshness', 'valueCode': freshness},
      if (ageSeconds != null)
        {'url': 'ageSeconds', 'valueUnsignedInt': ageSeconds},
    ],
  };

  Map<String, dynamic> toTag() => {
    'system': sysFreshness,
    'code': freshness,
    'display': freshness == Freshness.simulated
        ? 'SIMULATED: not a real reading'
        : freshness == Freshness.fetched
        ? 'fetched (batch/sync read; see ageSeconds)'
        : 'live',
  };

  /// Worst-case combination for derived resources: simulated beats
  /// fetched beats live. Derived data is never fresher than its inputs.
  static FhirLabel combine(String source, Iterable<FhirLabel> inputs) {
    final list = inputs.toList();
    if (list.isEmpty) {
      throw ArgumentError('FhirLabel.combine: no inputs');
    }
    if (list.any((l) => l.simulated)) {
      return FhirLabel(source: source, freshness: Freshness.simulated);
    }
    final fetched = list.where((l) => l.freshness == Freshness.fetched);
    if (fetched.isNotEmpty) {
      final oldest = fetched
          .map((l) => l.ageSeconds!)
          .reduce((a, b) => a > b ? a : b);
      return FhirLabel(
        source: source,
        freshness: Freshness.fetched,
        ageSeconds: oldest,
      );
    }
    return FhirLabel(source: source, freshness: Freshness.live);
  }
}

// ---- Inputs ----

/// One health observation to export, with its label.
class ExportObservation {
  const ExportObservation(this.observation, this.label);

  /// Label derived from the adapter's own `source` field. The health
  /// stores are batch/sync, so a real read is `fetched` with its age,
  /// never `live`. Unknown sources are refused.
  factory ExportObservation.fromHealthStore(
    HealthObservation o,
    DateTime exportedAt,
  ) {
    final FhirLabel label;
    if (o.source == 'simulated') {
      label = FhirLabel(
        source: 'simulated (${o.deviceLabel})',
        freshness: Freshness.simulated,
      );
    } else if (o.source == 'healthkit' || o.source == 'health_connect') {
      final ageMs = exportedAt.millisecondsSinceEpoch - o.ts;
      label = FhirLabel(
        source: '${o.source} (${o.deviceLabel})',
        freshness: Freshness.fetched,
        ageSeconds: ageMs < 0 ? 0 : ageMs ~/ 1000,
      );
    } else {
      throw ArgumentError(
        'ExportObservation: unknown observation source "${o.source}"',
      );
    }
    return ExportObservation(o, label);
  }

  final HealthObservation observation;
  final FhirLabel label;
}

/// One episode-log entry, reduced to what the export carries.
class FhirLogEntry {
  const FhirLogEntry({
    required this.seq,
    required this.ts,
    required this.type,
    required this.hash,
    required this.summary,
  });

  factory FhirLogEntry.from(
    int seq,
    int ts,
    String type,
    Map<String, dynamic> data,
    String hash,
  ) => FhirLogEntry(
    seq: seq,
    ts: ts,
    type: type,
    hash: hash,
    summary: _summarize(type, data),
  );

  final int seq;
  final int ts;
  final String type;
  final String hash;
  final String summary;
}

String _summarize(String type, Map<String, dynamic> d) {
  switch (type) {
    case 'transition':
      final to = d['to'];
      final res = d['resolution'];
      final extra = res == 'dispatched'
          ? ' (dispatch step reached, dispatcher disabled: nothing sent)'
          : res != null
          ? ' (resolution: $res)'
          : d['reason'] != null
          ? ' (reason: ${d['reason']})'
          : '';
      return '${d['from']} -> $to$extra';
    case 'wearer_cancelled':
      return 'wearer cancelled during ${d['duringState']}';
    case 'cascade_acknowledged':
      return 'acknowledged by ${d['contactId']}';
    case 'cascade_notify_pending':
    case 'cascade_notified':
    case 'cascade_no_response':
      return '${d['contactId']}';
    case 'dispatch_result':
      return 'dispatcher status: ${d['status']} (nothing sent)';
    case 'sandbox_payload_built':
      return 'payload built, sent=${d['sent']}';
    default:
      return type;
  }
}

/// An episode log in export form. The chain-verification claim is
/// carried WITH the name of whoever ran it.
class FhirEpisodeLog {
  FhirEpisodeLog({
    required this.runLabel,
    required this.finalState,
    required this.label,
    required this.headHash,
    required this.chainVerified,
    required this.chainVerifiedBy,
    required this.entries,
  }) {
    if (entries.isEmpty) {
      throw ArgumentError('FhirEpisodeLog: entries must not be empty');
    }
  }

  /// From the Node-recorded proof (assets/episode-log.json). The chain
  /// result is the Node engine's, taken at proof-export time; this export
  /// does not re-verify it and says so.
  factory FhirEpisodeLog.fromProofRun(
    proof.ProofRun run,
    proof.DataLabels labels,
  ) => FhirEpisodeLog(
    runLabel: run.label,
    finalState: run.finalState,
    label: _logLabel(labels.source, labels.freshness),
    headHash: run.headHash,
    chainVerified: run.verifyOk && run.verifyAnchoredOk,
    chainVerifiedBy:
        'Node engine at proof-export time (not re-verified by this export)',
    entries: [
      for (final e in run.entries)
        FhirLogEntry.from(e.seq, e.ts, e.type, e.data, e.hash),
    ],
  );

  /// From a run made in this app by the Dart engine; the chain is
  /// verified here, now, against the run's closing anchor.
  factory FhirEpisodeLog.fromEpisodeRun(EpisodeRun run) {
    final plain = run.log.verify();
    final anchored = run.log.verify(run.anchor);
    return FhirEpisodeLog(
      runLabel: run.label,
      finalState: run.finalState,
      label: _logLabel(
        run.dataLabels['source'] as String?,
        run.dataLabels['freshness'] as String?,
      ),
      headHash: run.anchor.headHash,
      chainVerified: plain.ok && anchored.ok,
      chainVerifiedBy: 'Dart EventLog.verify() and verify(anchor), at export',
      entries: [
        for (final engine_log.LogEntry e in run.log.entries)
          FhirLogEntry.from(e.seq, e.ts, e.type, e.data, e.hash),
      ],
    );
  }

  final String runLabel;
  final String finalState;
  final FhirLabel label;
  final String headHash;
  final bool chainVerified;
  final String chainVerifiedBy;
  final List<FhirLogEntry> entries;
}

FhirLabel _logLabel(String? source, String? freshness) {
  if (source == null || freshness == null) {
    throw ArgumentError(
      'FHIR export refused: the episode log is missing its source/freshness '
      'label (source=$source, freshness=$freshness).',
    );
  }
  return FhirLabel(source: source, freshness: freshness);
}

// ---- Code map (verified against LOINC / UCUM; see SESSION-4-RESULT.md) ----

class _Coding {
  const _Coding(
    this.loinc,
    this.display,
    this.ucum,
    this.inputUnit,
    this.category,
    this.categoryDisplay,
  );
  final String loinc;
  final String display;
  final String ucum;
  final String inputUnit;
  final String category;
  final String categoryDisplay;
}

const Map<String, _Coding> _codings = {
  'heart_rate': _Coding(
    '8867-4',
    'Heart rate',
    '/min',
    'bpm',
    'vital-signs',
    'Vital Signs',
  ),
  'spo2': _Coding(
    '59408-5',
    'Oxygen saturation in Arterial blood by Pulse oximetry',
    '%',
    '%',
    'vital-signs',
    'Vital Signs',
  ),
  'steps': _Coding(
    '55423-8',
    'Number of steps in unspecified time Pedometer',
    '{steps}',
    'count',
    'activity',
    'Activity',
  ),
  'sleep': _Coding(
    '93832-4',
    'Sleep duration',
    'min',
    'minutes',
    'activity',
    'Activity',
  ),
  'resting_heart_rate': _Coding(
    '40443-4',
    'Heart rate --resting',
    '/min',
    'bpm',
    'vital-signs',
    'Vital Signs',
  ),
  'skin_temperature': _Coding(
    '61008-9',
    'Body surface temperature',
    'Cel',
    'celsius',
    'vital-signs',
    'Vital Signs',
  ),
};

/// Observation types the export can code (the adapters' contract).
List<String> get supportedObservationTypes => _codings.keys.toList();

// ---- Helpers ----

String _instant(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

String _hex(String s) => sha256.convert(utf8.encode(s)).toString();

/// Deterministic RFC 4122-shaped UUID (version nibble 5) for urn:uuid.
String _uuidFor(String name) {
  final h = _hex(name);
  final variant = '89ab'[int.parse(h[16], radix: 16) % 4];
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-5${h.substring(13, 16)}-'
      '$variant${h.substring(17, 20)}-${h.substring(20, 32)}';
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

Map<String, dynamic> _narrative(FhirLabel label, String what) => {
  'status': 'generated',
  'div':
      '<div xmlns="http://www.w3.org/1999/xhtml">'
      '${label.simulated ? '<p><b>SIMULATED</b></p>' : ''}'
      '<p>${_esc(what)}</p>'
      '<p>source: ${_esc(label.source)}; freshness: ${label.freshness}'
      '${label.ageSeconds != null ? '; age: ${label.ageSeconds} s' : ''}</p>'
      '</div>',
};

Map<String, dynamic> _meta(FhirLabel label) => {
  if (label.simulated)
    'security': [
      {'system': sysActReason, 'code': 'HTEST', 'display': 'test health data'},
    ],
  'tag': [label.toTag()],
};

// ---- Export ----

/// Build the Bundle. [exportedAt] is injected so output is deterministic
/// in tests.
Map<String, dynamic> buildFhirBundle({
  required FhirEpisodeLog episode,
  required List<ExportObservation> observations,
  required DateTime exportedAt,
}) {
  final recorded = _instant(exportedAt.millisecondsSinceEpoch);
  final bundleId =
      'guardian-export-${_hex('$recorded/${episode.headHash}').substring(0, 12)}';
  String url(String resourceId) =>
      'urn:uuid:${_uuidFor('$bundleId/$resourceId')}';

  // Patient: a placeholder, simulated by construction, with no real
  // identifiers (no identifier, birthDate, address, telecom).
  final patientLabel = FhirLabel(
    source: 'synthetic placeholder (no real person)',
    freshness: Freshness.simulated,
  );
  const patientId = 'guardian-synthetic-wearer';
  final patient = <String, dynamic>{
    'resourceType': 'Patient',
    'id': patientId,
    'meta': _meta(patientLabel),
    'text': _narrative(
      patientLabel,
      'Synthetic demo wearer. Placeholder only; carries no real identifiers.',
    ),
    'extension': [patientLabel.toExtension()],
    'active': true,
    'name': [
      {'use': 'anonymous', 'text': 'Synthetic demo wearer'},
    ],
  };
  final patientRef = <String, dynamic>{
    'reference': url(patientId),
    'type': 'Patient',
    'display': 'Synthetic demo wearer',
  };

  final entries = <Map<String, dynamic>>[
    {'fullUrl': url(patientId), 'resource': patient},
  ];
  final targets = <Map<String, dynamic>>[patientRef];
  final labels = <FhirLabel>[patientLabel, episode.label];

  final seen = <String>{};
  for (final eo in observations) {
    final o = eo.observation;
    final coding = _codings[o.type];
    if (coding == null) {
      throw ArgumentError('Unsupported observation type "${o.type}"');
    }
    if (o.unit != coding.inputUnit) {
      throw ArgumentError(
        'Observation ${o.type}: unit "${o.unit}" does not '
        'match the expected "${coding.inputUnit}"; refusing to mis-code it.',
      );
    }
    final id = 'obs-${o.type.replaceAll('_', '-')}-${o.ts}';
    if (!seen.add(id)) {
      throw ArgumentError('Duplicate observation $id');
    }
    labels.add(eo.label);
    final obs = <String, dynamic>{
      'resourceType': 'Observation',
      'id': id,
      'meta': _meta(eo.label),
      'text': _narrative(
        eo.label,
        '${coding.display}: ${o.value} ${o.unit} (observed ${_instant(o.ts)})',
      ),
      'extension': [eo.label.toExtension()],
      'status': 'final',
      'category': [
        {
          'coding': [
            {
              'system': sysObsCategory,
              'code': coding.category,
              'display': coding.categoryDisplay,
            },
          ],
        },
      ],
      'code': {
        'coding': [
          {'system': sysLoinc, 'code': coding.loinc, 'display': coding.display},
        ],
        'text': coding.display,
      },
      'subject': patientRef,
      'effectiveDateTime': _instant(o.ts),
      'valueQuantity': {
        'value': o.value,
        'unit': o.unit,
        'system': sysUcum,
        'code': coding.ucum,
      },
      'device': {'display': o.deviceLabel},
    };
    entries.add({'fullUrl': url(id), 'resource': obs});
    targets.add({'reference': url(id), 'type': 'Observation'});
  }

  // Provenance: who assembled this, from which sources, and the episode
  // log summary (every log entry's seq/type/time/hash, no raw payloads).
  final provLabel = FhirLabel.combine('Guardian FHIR export (derived)', labels);
  const provId = 'guardian-export-provenance';
  final provenance = <String, dynamic>{
    'resourceType': 'Provenance',
    'id': provId,
    'meta': _meta(provLabel),
    'text': _narrative(
      provLabel,
      'Provenance of this export: episode ${episode.runLabel} and '
      '${observations.length} observation(s).',
    ),
    'extension': [
      provLabel.toExtension(),
      {
        'url': extEpisodeSummary,
        'extension': [
          {'url': 'runLabel', 'valueString': episode.runLabel},
          {'url': 'finalState', 'valueString': episode.finalState},
          {
            'url': 'logLabel',
            'extension': episode.label.toExtension()['extension'],
          },
          {'url': 'headHash', 'valueString': episode.headHash},
          {'url': 'chainVerified', 'valueBoolean': episode.chainVerified},
          {'url': 'chainVerifiedBy', 'valueString': episode.chainVerifiedBy},
          {
            'url': 'dispatch',
            'valueString': 'DISABLED: NOT SENT (no transport, no network)',
          },
          {'url': 'entryCount', 'valueUnsignedInt': episode.entries.length},
        ],
      },
      for (final e in episode.entries)
        {
          'url': extEpisodeLogEntry,
          'extension': [
            {'url': 'seq', 'valueUnsignedInt': e.seq},
            {'url': 'type', 'valueCode': e.type},
            {'url': 'at', 'valueDateTime': _instant(e.ts)},
            {'url': 'summary', 'valueString': e.summary},
            {'url': 'hash', 'valueString': e.hash},
          ],
        },
    ],
    'target': targets,
    'recorded': recorded,
    'agent': [
      {
        'type': {
          'coding': [
            {
              'system': sysProvParticipant,
              'code': 'assembler',
              'display': 'Assembler',
            },
          ],
        },
        'who': {
          'display': 'Guardian app, offline FHIR export (no server contacted)',
        },
      },
    ],
    'entity': [
      {
        'role': 'source',
        'what': {
          'identifier': {'system': sysEventLogHead, 'value': episode.headHash},
          'display':
              'Guardian episode event log "${episode.runLabel}" '
              '(${episode.label.source}; ${episode.label.freshness})',
        },
      },
      if (observations.isNotEmpty)
        {
          'role': 'source',
          'what': {
            'display':
                'Health-store adapter observations ('
                '${observations.map((o) => o.label.freshness).toSet().join(', ')})',
          },
        },
    ],
  };
  entries.add({'fullUrl': url(provId), 'resource': provenance});

  final bundleLabel = FhirLabel.combine('Guardian FHIR export bundle', labels);
  return {
    'resourceType': 'Bundle',
    'id': bundleId,
    // Bundle is a plain Resource in R4 (no top-level extension element),
    // so its label and notice ride on meta (an Element, which may carry
    // extensions).
    'meta': {
      ..._meta(bundleLabel),
      'extension': [
        bundleLabel.toExtension(),
        {
          'url': '$guardianBase/StructureDefinition/export-notice',
          'valueString': exportNotice,
        },
      ],
    },
    'type': 'collection',
    'timestamp': recorded,
    'entry': entries,
  };
}

/// Pretty-printed JSON of the Bundle, ready to share.
String fhirBundleToJson(Map<String, dynamic> bundle) =>
    const JsonEncoder.withIndent('  ').convert(bundle);
