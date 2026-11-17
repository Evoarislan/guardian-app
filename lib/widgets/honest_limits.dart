import 'package:material_ui/material_ui.dart';

/// The binding honest-limits line. It appears on every screen.
const String honestLimitsLine =
    'Demo build — dispatch is a sandbox; Guardian never calls 911 directly.';

const String notMedicalDeviceLine =
    'Guardian is a consumer safety aid, not a medical device.';

const String phoneOnPersonLine =
    'Fall detection works only while the phone is on the person. '
    'Sensing differs between Android and iOS. (Shell build: no sensors are active.)';

/// Bottom bar shown on every screen.
class HonestLimitsBar extends StatelessWidget {
  const HonestLimitsBar({super.key, this.extended = false});

  /// Extended adds the other binding limits (home screen).
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF263238),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            honestLimitsLine,
            key: Key('honest-limits-line'),
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (extended) ...const [
            SizedBox(height: 4),
            Text(notMedicalDeviceLine,
                style: TextStyle(color: Colors.white, fontSize: 14)),
            SizedBox(height: 4),
            Text(phoneOnPersonLine,
                style: TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}
