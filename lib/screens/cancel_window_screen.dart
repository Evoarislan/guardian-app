import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../widgets/honest_limits.dart';
import 'timeline_screen.dart';

/// Engine default cancel window (engine/engine.js: 60 s, wearer-configurable).
const int defaultCancelWindowSeconds = 60;

/// Cancel-window screen: visible countdown and one huge "I'm OK" button.
///
/// SHELL ONLY. This is a visual rehearsal of the window. There is no
/// engine behind it (the Dart port is Phase 2), so when the countdown
/// ends nothing is sent. The real behaviour is the recorded run on the
/// timeline screen. The button is one tap with no confirmation, and it
/// stays available after the countdown ends: a cancel before dispatch
/// still wins.
class CancelWindowScreen extends StatefulWidget {
  const CancelWindowScreen({
    super.key,
    this.windowSeconds = defaultCancelWindowSeconds,
  });

  final int windowSeconds;

  @override
  State<CancelWindowScreen> createState() => _CancelWindowScreenState();
}

class _CancelWindowScreenState extends State<CancelWindowScreen> {
  late int _remaining = widget.windowSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining -= 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _lapsed => _remaining == 0;

  void _cancel() {
    _timer?.cancel();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF7F0000),
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
                      'SIMULATED REHEARSAL: nothing is sent',
                      key: Key('rehearsal-label'),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFD600)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _lapsed ? 'Window ended' : 'Are you OK?',
                      key: const Key('window-heading'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    Text(
                      '$_remaining',
                      key: const Key('countdown'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 96,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    Text(
                      _lapsed
                          ? 'In the real engine the family cascade would start '
                              'now. This shell has no engine, so nothing is '
                              'sent. You can still tap "I\'m OK".'
                          : 'seconds left. Tap the big button if you are OK.',
                      key: const Key('window-explainer'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SizedBox.expand(
                        child: ElevatedButton(
                          key: const Key('cancel-button'),
                          onPressed: _cancel,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                          ),
                          child: const Text("I'm OK",
                              style: TextStyle(
                                  fontSize: 56, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('see-recorded-run-button'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const TimelineScreen()),
                      ),
                      child: const Text(
                          'See what the engine did in the recorded run',
                          style:
                              TextStyle(fontSize: 18, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
            const HonestLimitsBar(),
          ],
        ),
      ),
    );
  }
}
