// Guardian escalation engine (Dart port): dispatcher interface + safe
// implementations. Port of engine/dispatcher.js.
//
// A Dispatcher hands a confirmed, unacknowledged emergency to a
// MONITORED dispatch service. Guardian NEVER dials 911 (or any emergency
// number) directly. Dispatch is DISABLED by default in every
// implementation shipped here. No network code exists in this file: no
// HTTP client, no sockets. A real transport must be injected by the
// caller, and none ships.

import 'notifier.dart';

class DispatchResult {
  const DispatchResult({required this.status, this.reference});
  final String status;
  final String? reference;
}

abstract class Dispatcher {
  Future<DispatchResult> dispatch(Map<String, dynamic> alarm);
}

/// Optional capability: a dispatcher that can build a provider-shaped
/// alarm payload from an episode (the engine checks for it, like the
/// Node reference checks for buildAlarmPayload()).
abstract class AlarmPayloadBuilder {
  Map<String, dynamic> buildAlarmPayload(Episode episode, Location? location);
}

/// The engine's active episode.
class Episode {
  Episode({
    required this.id,
    required this.triggerType,
    required this.startedAt,
    required this.wearerName,
  });
  final String id;
  final String triggerType;
  final int startedAt;
  final String wearerName;
  final Set<String> notifiedContacts = {};
}

/// Builds the alarm payload in the shape of Noonlight's sandbox API
/// (POST /dispatch/v1/alarms), identical to the Node reference.
/// Building a payload is not sending it.
Map<String, dynamic> buildNoonlightAlarmPayload(
  Episode episode, [
  Location? location,
]) {
  return {
    'services': {'police': false, 'fire': false, 'medical': true},
    // Omitted entirely when absent (JS drops undefined on stringify).
    if (location != null)
      'location': {
        'coords': {
          'lat': location.lat,
          'lng': location.lng,
          'accuracy': location.accuracyM ?? 50,
        },
      },
    'name':
        episode.wearerName.isNotEmpty ? episode.wearerName : 'Guardian wearer',
    'instructions': 'Guardian escalation: ${episode.triggerType}. '
        'Wearer did not cancel and no kin contact acknowledged.',
    // Local-inspection bookkeeping; dispatch() strips it from the body.
    '_guardian': {'episodeId': episode.id, 'source': 'guardian-engine'},
  };
}

class DisabledDispatcher implements Dispatcher {
  @override
  Future<DispatchResult> dispatch(Map<String, dynamic> alarm) async =>
      const DispatchResult(status: 'disabled');
}

class MockDispatcher implements Dispatcher {
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<DispatchResult> dispatch(Map<String, dynamic> alarm) async {
    calls.add(alarm);
    return DispatchResult(
        status: 'mock-dispatched', reference: 'mock-${calls.length}');
  }
}

/// Request handed to an injected transport. This file defines the shape
/// only; it implements no transport.
class DispatchRequest {
  const DispatchRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });
  final String method;
  final String url;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
}

typedef DispatchTransport = Future<DispatchResult> Function(
    DispatchRequest request);

/// Noonlight sandbox dispatcher. OFF unless ALL hold: enabled == true,
/// a token is present (environment only, never hardcoded), and a
/// transport function is injected (none ships).
class NoonlightSandboxDispatcher implements Dispatcher, AlarmPayloadBuilder {
  // The token stays a private field (never exposed); named private
  // parameters are not used, so the lint below is silenced on purpose.
  // ignore_for_file: prefer_initializing_formals
  NoonlightSandboxDispatcher({
    this.enabled = false,
    String? token,
    DispatchTransport? transport,
  })  : _token = token,
        _transport = transport;

  final bool enabled;
  final String? _token; // memory only; never logged, never stored
  final DispatchTransport? _transport;
  final String baseUrl = 'https://api-sandbox.noonlight.com';

  @override
  Map<String, dynamic> buildAlarmPayload(Episode episode, Location? location) =>
      buildNoonlightAlarmPayload(episode, location);

  @override
  Future<DispatchResult> dispatch(Map<String, dynamic> alarm) async {
    final token = _token;
    if (!enabled || token == null || token.isEmpty) {
      return const DispatchResult(status: 'disabled');
    }
    final transport = _transport;
    if (transport == null) {
      throw StateError('NoonlightSandboxDispatcher: enabled but no transport '
          'injected; the port performs no network calls.');
    }
    // Strip Guardian's bookkeeping from the body actually sent; the
    // caller's map is not mutated. Token travels in the header only.
    final body = Map<String, dynamic>.from(alarm)..remove('_guardian');
    return transport(DispatchRequest(
      method: 'POST',
      url: '$baseUrl/dispatch/v1/alarms',
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body,
    ));
  }
}

/// Factory reading configuration from the supplied environment map ONLY
/// (the caller passes it; this library reads no process environment, so
/// it stays web-compatible). Defaults to a [DisabledDispatcher].
Dispatcher dispatcherFromEnv(
  Map<String, String> env, [
  DispatchTransport? transport,
]) {
  final token = env['GUARDIAN_NOONLIGHT_TOKEN'];
  if (env['GUARDIAN_DISPATCH_ENABLED'] == '1' &&
      token != null &&
      token.isNotEmpty) {
    return NoonlightSandboxDispatcher(
        enabled: true, token: token, transport: transport);
  }
  return DisabledDispatcher();
}
