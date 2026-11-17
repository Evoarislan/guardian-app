// Port of integration/payload-logging-dispatcher.js.
//
// The engine logs only dispatch_pending (episode id) and never the built
// sandbox payload. This wrapper delegates to the engine's own
// NoonlightSandboxDispatcher (DISABLED: no token, no transport, no
// network) and appends the built payload to the log BEFORE the engine
// logs dispatch_pending. It appends through the public EventLog.append(),
// so the hash chain stays valid.

import '../engine/guardian_engine.dart';

class PayloadLoggingDispatcher implements Dispatcher, AlarmPayloadBuilder {
  PayloadLoggingDispatcher({this.labels = const {}});

  final Map<String, dynamic> labels;
  final NoonlightSandboxDispatcher _inner = NoonlightSandboxDispatcher(
    enabled: false,
  );
  EventLog? _log;

  /// Payloads built this run (local inspection only).
  final List<Map<String, dynamic>> built = [];

  /// dispatch() calls received (all answered "disabled").
  int dispatchCalls = 0;

  void attachLog(EventLog log) => _log = log;

  @override
  Map<String, dynamic> buildAlarmPayload(Episode episode, Location? location) {
    final log = _log;
    if (log == null) {
      throw StateError('PayloadLoggingDispatcher: attachLog() was not called');
    }
    final payload = _inner.buildAlarmPayload(episode, location);
    built.add(payload);
    log.append('sandbox_payload_built', {
      'episodeId': episode.id,
      'endpoint': '${_inner.baseUrl}/dispatch/v1/alarms',
      'sent': false,
      'reason': 'dispatch disabled in this build: no token, no transport, no network call',
      'dataLabels': labels,
      'payload': payload,
    });
    return payload;
  }

  @override
  Future<DispatchResult> dispatch(Map<String, dynamic> alarm) {
    dispatchCalls += 1;
    return _inner.dispatch(alarm); // disabled: no network call
  }
}
