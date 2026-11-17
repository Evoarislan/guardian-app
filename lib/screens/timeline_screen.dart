import 'package:material_ui/material_ui.dart';

import '../proof_log.dart';
import '../proof_log_asset.dart';
import '../rehearsal/proof_episodes.dart';
import '../widgets/honest_limits.dart';

/// Plain-language view of one log entry, plus its data label.
class EntryView {
  const EntryView(this.title, this.labels, {this.warn = false});

  final String title;
  final DataLabels labels;

  /// True for rows about dispatch: rendered in an accent colour.
  final bool warn;
}

String _s(Object? v) => v == null ? 'none' : '$v';

/// Turns a recorded log entry into text. Dispatch wording is deliberate:
/// the engine records resolution "dispatched" even when the dispatcher
/// answered "disabled". The shell must never present that as a completed
/// dispatch, so every dispatch row says DISABLED / nothing sent.
EntryView describeEntry(LogEntry e, DataLabels runLabels) {
  final d = e.data;
  switch (e.type) {
    case 'trigger_received':
      final details = d['details'];
      final signal =
          details is Map<String, dynamic> ? details['signal'] : null;
      final sig = signal is Map<String, dynamic> ? signal : null;
      final labels = sig == null
          ? const DataLabels(null, null)
          : DataLabels(sig['source'] as String?, sig['freshness'] as String?);
      final type = _s(d['triggerType']).replaceAll('_', ' ');
      return EntryView(
          'Trigger: $type (signal ${_s(sig?['id'])})', labels);
    case 'transition':
      final from = _s(d['from']);
      final to = _s(d['to']);
      if (to == 'DISPATCH') {
        return EntryView(
            'DISPATCH step reached ($from → $to, reason: '
            '${_s(d['reason'])}). Dispatch is DISABLED in this build.',
            runLabels,
            warn: true);
      }
      if (to == 'RESOLVED' && d['resolution'] == 'dispatched') {
        // Never print "dispatched" as an outcome.
        return EntryView(
            '$from → RESOLVED. Dispatch DISABLED: nothing was sent '
            '(dispatcher status: ${_s(d['dispatchStatus'])}).',
            runLabels,
            warn: true);
      }
      final extra = d['reason'] != null
          ? ' (reason: ${d['reason']})'
          : d['resolution'] != null
              ? ' (resolution: ${d['resolution']})'
              : '';
      return EntryView('State: $from → $to$extra', runLabels);
    case 'wearer_cancelled':
      return EntryView(
          "Wearer cancelled (\"I'm OK\") during ${_s(d['duringState'])}. "
          'Good outcome; escalation stopped.',
          runLabels);
    case 'cancel_window_lapsed':
      return EntryView('Cancel window lapsed with no cancel', runLabels);
    case 'cascade_notify_pending':
      return EntryView(
          'Intent logged before sending: notify ${_s(d['contactId'])}',
          runLabels);
    case 'cascade_notified':
      return EntryView(
          'Mock notification handed to ${_s(d['contactId'])} '
          '(channel: ${_s(d['channel'])}). Nothing was really sent.',
          runLabels);
    case 'cascade_no_response':
      final waited = d['waitedMs'] is num ? (d['waitedMs'] as num) / 1000 : null;
      return EntryView(
          'No acknowledgment from ${_s(d['contactId'])}'
          '${waited == null ? '' : ' after ${waited.toStringAsFixed(0)} s'}',
          runLabels);
    case 'cascade_acknowledged':
      return EntryView(
          'Acknowledged by ${_s(d['contactId'])} (SIMULATED kin acknowledgment; '
          'no real person was contacted)',
          runLabels);
    case 'sandbox_payload_built':
      return EntryView(
          'Sandbox alarm payload built and logged. NOT SENT '
          '(sent=${_s(d['sent'])}; ${_s(d['endpoint'])} was not contacted).',
          runLabels,
          warn: true);
    case 'dispatch_pending':
      return EntryView(
          'Intent logged: dispatcher invoked (dispatcher is disabled)',
          runLabels,
          warn: true);
    case 'dispatch_result':
      final status = _s(d['status']);
      final ref = _s(d['reference']);
      return EntryView(
          status == 'disabled'
              ? 'Dispatch DISABLED: nothing sent '
                  '(status: disabled, partner reference: $ref)'
              : 'Dispatcher status: $status (partner reference: $ref)',
          runLabels,
          warn: true);
    default:
      return EntryView('${e.type}: $d', runLabels);
  }
}

/// Timeline of the recorded proof run (proofs/episode-log.json).
class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key, this.loader});

  /// Test seam; defaults to the bundled asset.
  final Future<ProofLog> Function()? loader;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorded proof run — SIMULATED',
            key: Key('timeline-title')),
        backgroundColor: const Color(0xFF263238),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<ProofLog>(
              future: (loader ?? loadProofLogAsset)(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Could not read the recorded proof log: ${snap.error}',
                      key: const Key('timeline-error'),
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _ProofView(log: snap.data!);
              },
            ),
          ),
          const HonestLimitsBar(),
        ],
      ),
    );
  }
}

class _ProofView extends StatelessWidget {
  const _ProofView({required this.log});

  final ProofLog log;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          key: const Key('proof-banner'),
          padding: const EdgeInsets.all(12),
          color: const Color(0xFFFFD600),
          child: Text(
            'RECORDED PROOF RUN, SIMULATED. ${log.banner}\n'
            'Exported ${log.generatedAt}. This is a replay of a file, not live data.',
            style: const TextStyle(
                fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
        for (final run in log.runs)
          RunCard(
            run: run,
            verifyKey: Key('verify-${run.label}'),
            verifyLine:
                'Log chain check, run by the Node engine at export time: '
                '${run.verifyOk && run.verifyAnchoredOk ? 'OK' : 'FAILED'} '
                '(head ${run.headHash.substring(0, 10)}…). '
                'This app does not re-verify the chain.',
          ),
      ],
    );
  }
}

class RunCard extends StatelessWidget {
  const RunCard({
    super.key,
    required this.run,
    required this.verifyLine,
    required this.verifyKey,
    this.verifyColor = Colors.white70,
    this.cardKey,
    this.outcome,
    this.timeNote,
  });

  final ProofRun run;

  /// Overrides the label-derived outcome text (interactive runs).
  final String? outcome;

  /// Shown under the outcome, e.g. that t+ offsets are scaled episode time.
  final String? timeNote;
  final String verifyLine;
  final Key verifyKey;
  final Color verifyColor;
  final Key? cardKey;

  String get _outcome => outcome != null
      ? outcome!
      : run.label == 'cancelled'
      ? 'Wearer cancelled inside the window. Engine back to IDLE; '
          'cancellation logged.'
      : 'Window lapsed, one ordered cascade pass, no acknowledgment. '
          'Dispatch step reached but DISABLED: nothing was sent.';

  @override
  Widget build(BuildContext context) {
    final t0 = run.entries.first.ts;
    return Card(
      key: cardKey ?? Key('run-${run.label}'),
      color: const Color(0xFF212121),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(run.label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 4),
            Text(_outcome,
                style: const TextStyle(fontSize: 18, color: Colors.white)),
            const SizedBox(height: 4),
            Text('Final engine state: ${run.finalState}',
                style: const TextStyle(fontSize: 16, color: Colors.white)),
            if (timeNote != null)
              Text(timeNote!,
                  key: const Key('run-time-note'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFD600))),
            Text(
              verifyLine,
              key: verifyKey,
              style: TextStyle(fontSize: 14, color: verifyColor),
            ),
            const Divider(color: Colors.white54),
            for (final e in run.entries)
              _EntryRow(
                  offsetSec: ((e.ts - t0) / 1000).round(),
                  entry: e,
                  view: describeEntry(e, run.labels)),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow(
      {required this.offsetSec, required this.entry, required this.view});

  final int offsetSec;
  final LogEntry entry;
  final EntryView view;

  @override
  Widget build(BuildContext context) {
    final labelText = view.labels.complete
        ? 'source: ${view.labels.source} · freshness: ${view.labels.freshness}'
        : 'UNLABELLED (source/freshness missing)';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            't+${offsetSec}s  #${entry.seq}  ${view.title}',
            style: TextStyle(
              fontSize: 17,
              color: view.warn ? const Color(0xFFFFAB40) : Colors.white,
              fontWeight: view.warn ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            labelText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: view.labels.complete
                  ? const Color(0xFFFFD600)
                  : const Color(0xFFFF5252),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// Live rehearsal (Dart engine, in-process, simulated clock)
// ------------------------------------------------------------------

/// Runs the two proof episodes through the Dart engine. Test seam.
typedef RehearsalRunner = Future<List<EpisodeRun>> Function();

Future<List<EpisodeRun>> runLiveRehearsal() =>
    runProofEpisodes(startAt: DateTime.now().millisecondsSinceEpoch);

/// In-app chain verification of one live run, using the Dart EventLog
/// verify() on the log object itself (and against the anchor captured
/// when the run finished, so truncation is caught too).
class ChainCheck {
  const ChainCheck(this.ok, this.text);
  final bool ok;
  final String text;
}

ChainCheck verifyLiveRun(EpisodeRun run) {
  final plain = run.log.verify();
  if (!plain.ok) {
    return ChainCheck(false,
        'CHAIN VERIFICATION FAILED at entry #${plain.failedAt} (Dart EventLog.verify(), run in this app).');
  }
  final anchored = run.log.verify(run.anchor);
  if (!anchored.ok) {
    return ChainCheck(false,
        'CHAIN VERIFICATION FAILED against the anchor at entry #${anchored.failedAt} (Dart EventLog.verify(anchor), run in this app).');
  }
  final head = run.anchor.headHash.substring(0, 10);
  return ChainCheck(true,
      'chain verified: ${run.log.entries.length} entries, head $head… '
      '(Dart EventLog.verify() and verify(anchor), run in this app just now).');
}

ProofRun toProofRun(EpisodeRun run, bool verified) => ProofRun(
      label: run.label,
      finalState: run.finalState,
      verifyOk: verified,
      verifyAnchoredOk: verified,
      labels: DataLabels.fromJson(run.dataLabels),
      entries: run.log.entries
          .map((e) => LogEntry(
              seq: e.seq, ts: e.ts, type: e.type, data: e.data, hash: e.hash))
          .toList(),
      dispatchSent: false,
      headHash: run.anchor.headHash,
    );

/// Timeline of a LIVE rehearsal: the Dart engine runs both episodes
/// in-process on a fast-forwarded simulated clock, and this screen renders
/// the log those engines just wrote, then verifies each hash chain.
class LiveTimelineScreen extends StatefulWidget {
  const LiveTimelineScreen({super.key, this.runner});

  /// Test seam; defaults to the real Dart-engine rehearsal.
  final RehearsalRunner? runner;

  @override
  State<LiveTimelineScreen> createState() => _LiveTimelineScreenState();
}

class _LiveTimelineScreenState extends State<LiveTimelineScreen> {
  late final Future<List<EpisodeRun>> _future;
  final Stopwatch _clock = Stopwatch();

  @override
  void initState() {
    super.initState();
    _clock.start();
    _future = (widget.runner ?? runLiveRehearsal)().whenComplete(_clock.stop);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live rehearsal (Dart engine) — SIMULATED',
            key: Key('live-timeline-title')),
        backgroundColor: const Color(0xFF263238),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<EpisodeRun>>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'The live rehearsal failed: ${snap.error}',
                      key: const Key('live-timeline-error'),
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Container(
                      key: const Key('live-banner'),
                      padding: const EdgeInsets.all(12),
                      color: const Color(0xFFFFD600),
                      child: Text(
                        'LIVE REHEARSAL, SIMULATED. Run just now, in this app, '
                        'by the Dart engine. Signals are simulated '
                        '(source=simulator, freshness=simulated). Kin '
                        'notifications are mock: nothing was sent. Dispatch is '
                        'DISABLED (no transport): NOT SENT. The default windows '
                        '(cancel ${cancelWindowSeconds}s, per-contact '
                        '${ackTimeoutSeconds}s) ran on a fast-forwarded '
                        'simulated clock, in about ${_clock.elapsedMilliseconds} '
                        'ms of real time.',
                        style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    for (final run in snap.data!) _liveCard(run),
                  ],
                );
              },
            ),
          ),
          const HonestLimitsBar(),
        ],
      ),
    );
  }

  Widget _liveCard(EpisodeRun run) {
    final check = verifyLiveRun(run);
    return RunCard(
      run: toProofRun(run, check.ok),
      cardKey: Key('live-run-${run.label}'),
      verifyKey: Key('live-verify-${run.label}'),
      verifyLine: check.text,
      verifyColor: check.ok ? const Color(0xFF69F0AE) : const Color(0xFFFF5252),
    );
  }
}
