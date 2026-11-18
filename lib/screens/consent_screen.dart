import 'package:material_ui/material_ui.dart';

import '../consent/consent.dart';
import '../widgets/honest_limits.dart';
import 'consent_widgets.dart';

/// Consent screen: every role x data class with a big Allow / Stop button.
/// Grants are LOCAL DEMO STATE in this build and say so.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, this.store});

  /// Test seam; defaults to the app-wide store from [ConsentScope].
  final ConsentStore? store;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  ConsentStore? _own;

  ConsentStore get _store =>
      widget.store ?? ConsentScope.maybeOf(context) ?? (_own ??= ConsentStore());

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Who can see what', key: Key('consent-title')),
        backgroundColor: const Color(0xFF263238),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => ConsentList(store: store),
            ),
          ),
          const HonestLimitsBar(),
        ],
      ),
    );
  }
}
