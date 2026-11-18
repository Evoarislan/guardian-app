import 'package:material_ui/material_ui.dart';

import '../consent/consent.dart';

String _useNote(ConsentUse u) => switch (u) {
  ConsentUse.enforced => 'Enforced in this build.',
  ConsentUse.noView =>
    'No active view in this build: this grant is recorded but nothing '
        'uses it yet.',
  ConsentUse.recordedOnly =>
    'Recorded only: nothing in this build sends this yet.',
};

/// Banner + one row per role x data class + the plain-language history.
class ConsentList extends StatelessWidget {
  const ConsentList({super.key, required this.store});

  final ConsentStore store;

  @override
  Widget build(BuildContext context) {
    final history = store.history();
    final verify = store.verify();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          key: const Key('consent-banner'),
          padding: const EdgeInsets.all(12),
          color: const Color(0xFFFFD600),
          child: const Text(
            'LOCAL DEMO STATE. These choices are yours. They are kept only '
            'in memory on this phone, are lost when the app closes, and are '
            'not synced or sent anywhere. Nothing is allowed until you allow '
            'it.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final r in ConsentRole.values) ...[
          const SizedBox(height: 16),
          Text(
            r.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          for (final c in ConsentDataClass.values) _row(r, c),
        ],
        const SizedBox(height: 20),
        const Text(
          'What you have decided',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        if (history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'You have not allowed anything yet.',
              key: Key('consent-history-empty'),
              style: TextStyle(fontSize: 17, color: Colors.white),
            ),
          ),
        for (var i = 0; i < history.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              history[i],
              key: Key('consent-history-$i'),
              style: const TextStyle(fontSize: 17, color: Colors.white),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Record check: ${verify.ok ? 'unbroken' : 'BROKEN'} '
          '(${store.log.entries.length} entries, hash-chained, local only).',
          key: const Key('consent-verify'),
          style: TextStyle(
            fontSize: 16,
            color: verify.ok ? Colors.white : const Color(0xFFFF5252),
          ),
        ),
      ],
    );
  }

  Widget _row(ConsentRole r, ConsentDataClass c) {
    final on = store.isGranted(r, c);
    final use = consentUseOf(r, c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.title}: ${on ? 'ALLOWED' : 'not allowed'}',
                  key: Key('consent-state-${r.id}-${c.id}'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: on ? const Color(0xFF69F0AE) : Colors.white,
                  ),
                ),
                Text(
                  _useNote(use),
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            height: 64,
            child: ElevatedButton(
              key: Key('consent-toggle-${r.id}-${c.id}'),
              onPressed: () =>
                  on ? store.revoke(r, c) : store.grant(r, c),
              child: Text(
                on ? 'Stop' : 'Allow',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
