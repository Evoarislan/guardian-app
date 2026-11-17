import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../rehearsal/interactive_rehearsal.dart';
import '../rehearsal/proof_episodes.dart';
import '../rehearsal/scaled_scheduler.dart';
import '../widgets/honest_limits.dart';
import 'timeline_screen.dart';

/// The scale disclosure, shown on screen and asserted in tests.
String scaleDisclosure(int scale) =>
    'REHEARSAL TIME IS SCALED: 1 real second = $scale episode seconds. '
    'The engine still uses the canonical windows in episode time '
    '(${cancelWindowSeconds}s cancel window, ${ackTimeoutSeconds}s per-contact '
    'acknowledgment timeout), so here they last '
    '${cancelWindowSeconds ~/ scale} and ${ackTimeoutSeconds ~/ scale} real '
    'seconds. A full unacknowledged run takes about '
    '${(cancelWindowSeconds + syntheticKin.length * ackTimeoutSeconds) ~/ scale} '
    'real seconds. Timeline t+ offsets are episode seconds.';

/// Interactive live rehearsal: the user drives one episode of the real
/// Dart engine in real time (scaled clock). Everything on this screen is
/// SIMULATED; dispatch is DISABLED and nothing is sent.
class InteractiveRehearsalScreen extends StatefulWidget {
  const InteractiveRehearsalScreen({super.key, this.create});

  /// Test seam (inject a fake-clock scheduler). Defaults to a real clock
  /// scaled by [defaultRehearsalScale].
  final InteractiveRehearsal Function()? create;

  @override
  State<InteractiveRehearsalScreen> createState() =>
      _InteractiveRehearsalScreenState();
}

class _InteractiveRehearsalScreenState
    extends State<InteractiveRehearsalScreen> {
  late InteractiveRehearsal _c;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _c = _make();
  }

  InteractiveRehearsal _make() {
    final c = (widget.create ?? InteractiveRehearsal.new)();
    c.addListener(_onChange);
    return c;
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (_c.finished) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _start() {
    _c.simulateFall();
    _ticker?.cancel();
    // Only refreshes the countdown text; the engine runs on its own timers.
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  void _again() {
    _ticker?.cancel();
    _ticker = null;
    _c.removeListener(_onChange);
    _c.dispose();
    setState(() => _c = _make());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _c.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  String _outcomeText() {
    final entries = _c.log.entries;
    switch (_c.outcome!) {
      case RehearsalOutcome.wearerCancelled:
        final during = entries
            .firstWhere((e) => e.type == 'wearer_cancelled')
            .data['duringState'];
        return "RESOLVED: wearer_cancelled. \"I'm OK\" was accepted during "
            '$during. Escalation stopped: a good outcome. The dispatcher '
            'was never invoked.';
      case RehearsalOutcome.acknowledged:
        final by = entries
            .firstWhere((e) => e.type == 'cascade_acknowledged')
            .data['contactId'];
        return 'RESOLVED: acknowledged by $by (SIMULATED kin acknowledgment, '
            'no real person was contacted). Escalation stopped. The '
            'dispatcher was never invoked.';
      case RehearsalOutcome.dispatchStepDisabled:
        return 'RESOLVED: cascade exhausted with no acknowledgment. The '
            'dispatch step was reached but is DISABLED: NOT SENT. No '
            'dispatch partner reference exists.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final scale = c.scheduler.scale;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Interactive rehearsal — SIMULATED',
          key: Key('interactive-title'),
        ),
        backgroundColor: const Color(0xFF263238),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Container(
                  key: const Key('interactive-banner'),
                  padding: const EdgeInsets.all(12),
                  color: const Color(0xFFFFD600),
                  child: Text(
                    'INTERACTIVE REHEARSAL, SIMULATED. You are driving the '
                    'real Dart engine in real time. Signals are simulated '
                    '(source=simulator, freshness=simulated). Kin '
                    'notifications are mock: nothing is sent. Dispatch is '
                    'DISABLED (no transport): NOT SENT.',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  color: const Color(0xFFFF6D00),
                  child: Text(
                    scaleDisclosure(scale),
                    key: const Key('scale-disclosure'),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _controls(c, scale),
                if (c.started) _timeline(c, scale),
              ],
            ),
          ),
          const HonestLimitsBar(),
        ],
      ),
    );
  }

  Widget _controls(InteractiveRehearsal c, int scale) {
    if (!c.started) {
      return Column(
        children: [
          const Text(
            'Nothing has happened yet. Press the button to play the simulated '
            'fall and open the cancel window.',
            key: Key('interactive-status'),
            style: TextStyle(fontSize: 18, color: Colors.white),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 80,
            child: ElevatedButton(
              key: const Key('rehearsal-start'),
              onPressed: _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB71C1C),
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Simulate a fall (SIMULATED)',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }
    if (c.finished) {
      return Column(
        children: [
          Text(
            _outcomeText(),
            key: const Key('rehearsal-outcome'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: OutlinedButton(
              key: const Key('rehearsal-again'),
              onPressed: _again,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white),
              ),
              child: const Text(
                'Run another rehearsal',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
        ],
      );
    }
    final left = c.remainingEpisodeSeconds ?? 0;
    final realLeft = (left / scale).ceil();
    final contact = c.currentContact;
    final what = c.inCancelWindow
        ? 'Cancel window open'
        : 'Cascade: waiting on ${contact?.id ?? 'kin'} to acknowledge';
    return Column(
      children: [
        Text(
          'Engine state: ${c.engine.state}',
          key: const Key('rehearsal-state'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          '$what: $left episode seconds left (about $realLeft real seconds)',
          key: const Key('rehearsal-countdown'),
          style: const TextStyle(fontSize: 18, color: Colors.white),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 180,
          child: ElevatedButton(
            key: const Key('rehearsal-im-ok'),
            onPressed: c.canCancel ? c.imOk : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: const Text(
              "I'M OK",
              style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (c.inCascade && contact != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 72,
            child: OutlinedButton(
              key: const Key('rehearsal-kin-ack'),
              onPressed: c.simulateKinAck,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFD600),
                side: const BorderSide(color: Color(0xFFFFD600), width: 2),
              ),
              child: Text(
                'SIMULATED kin ack: ${contact.id} acknowledges\n'
                '(simulation control, not a real person)',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _timeline(InteractiveRehearsal c, int scale) {
    final run = c.snapshot();
    final ChainCheck check;
    if (c.finished) {
      check = verifyLiveRun(run);
    } else {
      final plain = run.log.verify();
      check = ChainCheck(
        plain.ok,
        plain.ok
            ? 'chain verified so far: ${run.log.entries.length} entries '
                  '(Dart EventLog.verify(), episode still running; the final '
                  'check against the closing anchor follows when it ends).'
            : 'CHAIN VERIFICATION FAILED at entry #${plain.failedAt} '
                  '(Dart EventLog.verify(), run in this app).',
      );
    }
    return RunCard(
      run: toProofRun(run, check.ok),
      cardKey: const Key('interactive-run'),
      verifyKey: const Key('interactive-verify'),
      verifyLine: check.text,
      verifyColor: check.ok ? const Color(0xFF69F0AE) : const Color(0xFFFF5252),
      outcome: c.finished
          ? 'Episode finished. Outcome is shown above the timeline.'
          : 'Episode in progress. Every row below was appended to the '
                'hash-chained log before its action.',
      timeNote:
          't+ offsets are EPISODE seconds (scaled clock, 1 real second '
          '= $scale episode seconds).',
    );
  }
}
