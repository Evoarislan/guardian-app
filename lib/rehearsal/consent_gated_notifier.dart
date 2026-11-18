// Kin-alert consent enforcement at the notifier boundary (Session 5).
//
// The engine is not modified: it calls notifier.notify() for each contact
// in the wearer's order, and logs the result. This wrapper checks the
// wearer's CURRENT kin/alerts grant first. With no grant (never granted,
// or revoked) it does NOT call the inner notifier. It appends a
// 'kin_notification_skipped' entry (reason consent_not_granted) to the
// episode log BEFORE returning, and reports delivered=false so the
// engine's own 'cascade_notified' row says the contact was not notified.
// The cascade then proceeds by the canonical rules (still one ordered
// pass; it exhausts to the disabled dispatch step in simulation).

import '../consent/consent.dart';
import '../engine/event_log.dart';
import '../engine/notifier.dart';

const String consentSkipReason = 'consent_not_granted';
const String consentSkipChannel = 'skipped_no_consent';

class ConsentGatedNotifier implements Notifier {
  ConsentGatedNotifier({required this.inner, required this.consent});

  final Notifier inner;
  final ConsentStore consent;
  EventLog? _log;

  /// The episode log the skip entries go to (set once the engine exists).
  void attachLog(EventLog log) => _log = log;

  @override
  Future<NotifyResult> notify(Contact contact, Alert alert) async {
    if (!consent.isGranted(ConsentRole.kin, ConsentDataClass.alerts)) {
      _log?.append('kin_notification_skipped', {
        'episodeId': alert.episodeId,
        'contactId': contact.id,
        'reason': consentSkipReason,
        'role': ConsentRole.kin.id,
        'dataClass': ConsentDataClass.alerts.id,
      });
      return const NotifyResult(delivered: false, channel: consentSkipChannel);
    }
    return inner.notify(contact, alert);
  }
}
