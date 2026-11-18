// Consent grants and revocation (Session 5, Phase 5 core).
//
// Wearer-owned grants per role x data class. Deny by default: at first
// run NO grant exists. Every grant and revocation is appended to a
// hash-chained log (the engine's EventLog, same anchor/verify
// discipline) BEFORE the in-memory state changes.
//
// HONESTY: in this build the grants are LOCAL DEMO STATE, held in memory
// on this phone and lost when the app closes. Nothing is synced, stored
// on a server or sent anywhere. No I/O in this file.

import 'package:flutter/widgets.dart';

import '../engine/event_log.dart';

enum ConsentRole { kin, provider, nutritionist }

enum ConsentDataClass { alerts, vitalsDigest, fhirExport }

extension ConsentRoleText on ConsentRole {
  String get id => name;
  String get title => switch (this) {
    ConsentRole.kin => 'Family / kin',
    ConsentRole.provider => 'Provider',
    ConsentRole.nutritionist => 'Nutritionist',
  };

  /// Phrase for sentences: "You allowed PHRASE to ...".
  String get phrase => switch (this) {
    ConsentRole.kin => 'your family / kin',
    ConsentRole.provider => 'your provider',
    ConsentRole.nutritionist => 'your nutritionist',
  };
}

extension ConsentDataClassText on ConsentDataClass {
  String get id => switch (this) {
    ConsentDataClass.alerts => 'alerts',
    ConsentDataClass.vitalsDigest => 'vitals_digest',
    ConsentDataClass.fhirExport => 'fhir_export',
  };
  String get title => switch (this) {
    ConsentDataClass.alerts => 'Emergency alerts',
    ConsentDataClass.vitalsDigest => 'Vitals digest',
    ConsentDataClass.fhirExport => 'FHIR export',
  };

  /// Phrase for sentences: "... to PHRASE".
  String get phrase => switch (this) {
    ConsentDataClass.alerts => 'receive emergency alerts',
    ConsentDataClass.vitalsDigest => 'receive a vitals digest',
    ConsentDataClass.fhirExport => 'receive FHIR exports',
  };
}

/// Where a grant is actually used in this build. Shown on the Consent
/// screen so a grant is never mistaken for a working feature.
enum ConsentUse { enforced, noView, recordedOnly }

ConsentUse consentUseOf(ConsentRole r, ConsentDataClass c) {
  if (r == ConsentRole.nutritionist) return ConsentUse.noView;
  if (r == ConsentRole.kin && c == ConsentDataClass.alerts) {
    return ConsentUse.enforced;
  }
  if (r == ConsentRole.provider && c == ConsentDataClass.fhirExport) {
    return ConsentUse.enforced;
  }
  return ConsentUse.recordedOnly;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String consentDate(int tsMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(tsMs, isUtc: true);
  return '${_months[d.month - 1]} ${d.day}';
}

class ConsentStore extends ChangeNotifier {
  /// [now] is the clock (tests inject one). Dates are shown in UTC.
  ConsentStore({DateTime Function()? now})
    : _now = now ?? DateTime.now,
      log = EventLog(now == null ? null : () => now().millisecondsSinceEpoch);

  final DateTime Function() _now;
  final EventLog log;
  final Set<String> _active = {};

  String _k(ConsentRole r, ConsentDataClass c) => '${r.id}/${c.id}';

  bool isGranted(ConsentRole r, ConsentDataClass c) =>
      _active.contains(_k(r, c));

  /// Grant. Returns false (and logs nothing) if already granted.
  bool grant(ConsentRole r, ConsentDataClass c) => _change(r, c, true);

  /// Revoke. Returns false (and logs nothing) if not currently granted.
  bool revoke(ConsentRole r, ConsentDataClass c) => _change(r, c, false);

  bool _change(ConsentRole r, ConsentDataClass c, bool grant) {
    if (isGranted(r, c) == grant) return false;
    // Log first, then change the state (log-before-side-effect).
    log.append(grant ? 'consent_granted' : 'consent_revoked', {
      'role': r.id,
      'dataClass': c.id,
      'at': _now().toUtc().millisecondsSinceEpoch,
      'storage': 'local_demo_state',
    });
    if (grant) {
      _active.add(_k(r, c));
    } else {
      _active.remove(_k(r, c));
    }
    notifyListeners();
    return true;
  }

  int get activeCount => _active.length;

  /// Plain-language history, one line per grant, oldest first.
  List<String> history() {
    final lines = <_Line>[];
    final open = <String, _Line>{};
    for (final e in log.entries) {
      final r = ConsentRole.values.firstWhere((x) => x.id == e.data['role']);
      final c = ConsentDataClass.values.firstWhere(
        (x) => x.id == e.data['dataClass'],
      );
      final at = e.data['at'] as int;
      final key = _k(r, c);
      if (e.type == 'consent_granted') {
        final l = _Line(
          'You allowed ${r.phrase} to ${c.phrase} on ${consentDate(at)}',
        );
        open[key] = l;
        lines.add(l);
      } else {
        open.remove(key)?.revokedOn = consentDate(at);
      }
    }
    return [for (final l in lines) l.text];
  }

  VerifyResult verify([Anchor? anchor]) => log.verify(anchor);
}

class _Line {
  _Line(this.base);
  final String base;
  String? revokedOn;
  String get text => revokedOn == null
      ? '$base. Still allowed.'
      : '$base; you revoked it on $revokedOn.';
}

/// Makes the one [ConsentStore] available to every screen.
class ConsentScope extends InheritedNotifier<ConsentStore> {
  const ConsentScope({
    super.key,
    required ConsentStore store,
    required super.child,
  }) : super(notifier: store);

  /// Null when there is no scope (some tests pump a screen alone).
  static ConsentStore? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ConsentScope>()?.notifier;
}
