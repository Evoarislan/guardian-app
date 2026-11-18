import 'package:material_ui/material_ui.dart';

import '../adapters/health_store.dart';
import '../consent/consent.dart';
import '../fhir/fhir_export.dart';
import '../proof_log.dart';
import '../proof_log_asset.dart';
import '../widgets/honest_limits.dart';

/// Provider view (Session 4 scope: export only). Shows the recorded proof
/// episode and the simulated health observations, and offers "Export
/// FHIR": an OFFLINE FHIR R4 Bundle built in memory and shown as JSON.
/// Nothing is posted anywhere.
class ProviderScreen extends StatefulWidget {
  const ProviderScreen({
    super.key,
    this.loader,
    this.observations,
    this.now,
    this.consent,
  });

  /// Test seam; defaults to the app-wide store from [ConsentScope].
  final ConsentStore? consent;

  /// Test seams: proof log, observation source, clock.
  final Future<ProofLog> Function()? loader;
  final Future<List<HealthObservation>> Function()? observations;
  final DateTime Function()? now;

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> {
  late final Future<ProofLog> _log;
  late final Future<List<HealthObservation>> _obs;
  String? _json;
  String? _error;

  @override
  void initState() {
    super.initState();
    _log = (widget.loader ?? loadProofLogAsset)();
    _obs =
        (widget.observations ??
        () => MockHealthStoreAdapter().readObservations())();
  }

  ConsentStore? get _consent =>
      widget.consent ?? ConsentScope.maybeOf(context);

  /// Enforcement: no active provider fhir_export grant, no export. The
  /// bundle is not built, so nothing exists to leak.
  Future<void> _export() async {
    final store = _consent;
    if (store == null ||
        !store.isGranted(ConsentRole.provider, ConsentDataClass.fhirExport)) {
      setState(() {
        _json = null;
        _error =
            'Export refused: you have not allowed your provider to receive '
            'FHIR exports (or you stopped it). Nothing was built. Allow it '
            'on the "Who can see what" screen first.';
      });
      return;
    }
    try {
      final log = await _log;
      final obs = await _obs;
      final exportedAt = (widget.now ?? DateTime.now)();
      // The recorded proof episode with the full cascade.
      final run = log.runs.firstWhere(
        (r) => r.label == 'escalated',
        orElse: () => log.runs.last,
      );
      final bundle = buildFhirBundle(
        episode: FhirEpisodeLog.fromProofRun(run, log.labels),
        observations: [
          for (final o in obs) ExportObservation.fromHealthStore(o, exportedAt),
        ],
        exportedAt: exportedAt,
      );
      if (!mounted) return;
      setState(() {
        _json = fhirBundleToJson(bundle);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _json = null;
        _error = 'Export refused: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Provider view — SIMULATED',
          key: Key('provider-title'),
        ),
        backgroundColor: const Color(0xFF263238),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Object>>(
              future: Future.wait<Object>([_log, _obs]),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Could not load the record: ${snap.error}',
                      key: const Key('provider-error'),
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final log = snap.data![0] as ProofLog;
                final obs = snap.data![1] as List<HealthObservation>;
                return _body(log, obs);
              },
            ),
          ),
          const HonestLimitsBar(),
        ],
      ),
    );
  }

  Widget _body(ProofLog log, List<HealthObservation> obs) {
    final now = (widget.now ?? DateTime.now)();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          key: const Key('provider-banner'),
          padding: const EdgeInsets.all(12),
          color: const Color(0xFFFFD600),
          child: const Text(
            'SIMULATED RECORD. Synthetic demo wearer; simulated signals and '
            'readings (source=simulator / simulated, freshness=simulated). '
            'Not a real person. Not a medical record. Guardian is a consumer '
            'safety aid, not a medical device. Export works only while you '
            'have allowed your provider to receive FHIR exports (Consent '
            'screen; local demo state). Even then the export contains only '
            'the synthetic demo wearer, and nothing is sent anywhere.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Recorded proof episode: "escalated" (replay of a file exported '
          '${log.generatedAt}; source: ${log.labels.source} · freshness: '
          '${log.labels.freshness}). Dispatch was DISABLED: NOT SENT.',
          key: const Key('provider-episode'),
          style: const TextStyle(fontSize: 17, color: Colors.white),
        ),
        const SizedBox(height: 12),
        const Text(
          'Health observations',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        for (final o in obs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${o.type}: ${o.value} ${o.unit}  '
              '(source: ${o.source} · freshness: ${_freshnessOf(o)}'
              '${o.source == 'simulated' ? '' : ', age ${(now.millisecondsSinceEpoch - o.ts) ~/ 1000} s'}'
              ')',
              key: Key('provider-obs-${o.type}'),
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          height: 64,
          child: ElevatedButton(
            key: const Key('export-fhir-button'),
            onPressed: _export,
            child: const Text(
              'Export FHIR (simulated)',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              key: const Key('export-error'),
              style: const TextStyle(fontSize: 16, color: Color(0xFFFF5252)),
            ),
          ),
        if (_json != null) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('export-banner'),
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFFF6D00),
            child: const Text(
              'SIMULATED FHIR R4 BUNDLE. Built offline in this app: nothing '
              'was posted to any server. It was not checked by a FHIR server '
              'or the official validator. Select the text to copy it.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            color: const Color(0xFF212121),
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              _json!,
              key: const Key('export-json'),
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _freshnessOf(HealthObservation o) =>
      o.source == 'simulated' ? Freshness.simulated : Freshness.fetched;
}
