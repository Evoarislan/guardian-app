import 'package:material_ui/material_ui.dart';

import '../widgets/honest_limits.dart';
import 'cancel_window_screen.dart';
import 'interactive_rehearsal_screen.dart';
import 'provider_screen.dart';
import 'timeline_screen.dart';

/// Wearer home: two huge buttons, large type, high contrast.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _note;

  void _imOk() {
    // Shell only: there is no check-in scheduler or engine behind this
    // yet, so nothing is recorded or sent. Say so on screen.
    setState(() => _note =
        'Demo shell: "I\'m OK" is not recorded or sent anywhere. '
        'No check-in scheduler exists in this build.');
  }

  Future<void> _needHelp() async {
    final cancelled = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CancelWindowScreen()),
    );
    if (!mounted) return;
    if (cancelled == true) {
      setState(() => _note =
          'Cancelled. Simulated rehearsal only: nothing was sent and '
          'nothing was recorded.');
    }
  }

  void _openTimeline() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TimelineScreen()),
    );
  }

  void _openLiveRehearsal() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LiveTimelineScreen()),
    );
  }

  void _openInteractive() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => const InteractiveRehearsalScreen()),
    );
  }

  void _openProvider() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProviderScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Guardian',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    const Text(
                      'SIMULATED DEMO SHELL: no sensors, no real alerts.',
                      key: Key('simulated-shell-label'),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFD600)),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      flex: 3,
                      child: _BigButton(
                        key: const Key('im-ok-button'),
                        label: "I'm OK",
                        color: const Color(0xFF1B5E20),
                        onPressed: _imOk,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      flex: 3,
                      child: _BigButton(
                        key: const Key('need-help-button'),
                        label: 'I need help',
                        color: const Color(0xFFB71C1C),
                        onPressed: _needHelp,
                      ),
                    ),
                    if (_note != null) ...[
                      const SizedBox(height: 8),
                      Text(_note!,
                          key: const Key('home-note'),
                          style: const TextStyle(
                              fontSize: 16, color: Colors.white)),
                    ],
                    const SizedBox(height: 8),
                    // One compact row, so the two big buttons keep their
                    // height. Every destination is itself labelled SIMULATED.
                    Row(
                      children: [
                        Expanded(
                          child: _SmallButton(
                            key: const Key('interactive-rehearsal-button'),
                            label: 'Interactive\nrehearsal',
                            onPressed: _openInteractive,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _SmallButton(
                            key: const Key('live-rehearsal-button'),
                            label: 'Auto live\nrehearsal',
                            onPressed: _openLiveRehearsal,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _SmallButton(
                            key: const Key('open-timeline-button'),
                            label: 'Recorded\nproof run',
                            onPressed: _openTimeline,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _SmallButton(
                            key: const Key('provider-view-button'),
                            label: 'Provider\nview',
                            onPressed: _openProvider,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const HonestLimitsBar(extended: true),
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      ),
      child:
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
