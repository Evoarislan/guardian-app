// Guardian escalation engine (Dart port): notifier interface + safe
// implementations. Port of engine/notifier.js.
//
// A Notifier delivers an escalation alert to ONE kin contact and reports
// whether the message was handed off. Acknowledgment arrives out of band
// and is fed back via engine.acknowledge(contactId).
//
// NO real messaging happens here. Twilio wiring belongs behind this
// interface in a later, separately reviewed step.

class Contact {
  const Contact({required this.id, required this.name, this.phone});
  final String id;
  final String name;
  final String? phone;
}

/// Location with its source/freshness labels carried along (a simulated
/// location stays labelled simulated).
class Location {
  const Location({
    required this.lat,
    required this.lng,
    this.accuracyM,
    this.source,
    this.freshness,
  });
  final double lat;
  final double lng;
  final num? accuracyM;
  final String? source;
  final String? freshness;
}

class Alert {
  const Alert({
    required this.episodeId,
    required this.triggerType,
    required this.message,
    this.location,
  });
  final String episodeId;
  final String triggerType;
  final String message;
  final Location? location;
}

class NotifyResult {
  const NotifyResult({required this.delivered, required this.channel});
  final bool delivered;
  final String channel;
}

abstract class Notifier {
  Future<NotifyResult> notify(Contact contact, Alert alert);
}

class ConsoleNotifier implements Notifier {
  @override
  Future<NotifyResult> notify(Contact contact, Alert alert) async {
    // print (not Flutter's debugPrint) keeps lib/engine free of Flutter
    // imports so the Dart proof runner can run under plain `dart run`.
    // ignore: avoid_print
    print(
        '[guardian:notifier] -> ${contact.name} (${contact.id}): ${alert.message}');
    return const NotifyResult(delivered: true, channel: 'console');
  }
}

class NotifyCall {
  const NotifyCall(this.contact, this.alert);
  final Contact contact;
  final Alert alert;
}

class MockNotifier implements Notifier {
  final List<NotifyCall> calls = [];

  @override
  Future<NotifyResult> notify(Contact contact, Alert alert) async {
    calls.add(NotifyCall(contact, alert));
    return const NotifyResult(delivered: true, channel: 'mock');
  }
}
