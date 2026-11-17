// Guardian escalation engine (Dart port): the state machine.
// Port of engine/engine.js (the verified Node reference).
//
//   IDLE
//     |  trigger(fall_pattern | inactivity | missed_checkin | manual_sos)
//     v
//   TRIGGERED -> CANCEL_WINDOW  (wearer cancel -> IDLE, logged)
//     |  window lapses without cancel
//     v
//   CASCADE  (ONE ordered pass over kin; each contact gets an ack
//     |        timeout; first acknowledgment -> RESOLVED. The wearer may
//     |        still cancel any time before the dispatcher is actually
//     |        invoked; cancel -> IDLE, logged.)
//     |  pass exhausted with no acknowledgment
//     v
//   DISPATCH  (hand a verified alarm to a MONITORED dispatch partner via
//     |         the Dispatcher interface. Guardian NEVER dials emergency
//     |         numbers. Once dispatch() is invoked the episode is
//     |         beyond recall: a late cancel is logged and refused.)
//     v
//   RESOLVED
//
// There is NO separate dispatch window (canonical timing model).
//
// Notifier/dispatcher failures are logged as engine_error; the episode
// ends RESOLVED with resolution "error" and is cleared. Every transition
// is appended to the hash-chained log BEFORE its side effect fires.

import 'dart:async';

import 'dispatcher.dart';
import 'event_log.dart';
import 'notifier.dart';
import 'scheduler.dart';

/// State names (strings, identical to the Node reference's STATES).
class States {
  static const idle = 'IDLE';
  static const triggered = 'TRIGGERED';
  static const cancelWindow = 'CANCEL_WINDOW';
  static const cascade = 'CASCADE';
  static const dispatch = 'DISPATCH';
  static const resolved = 'RESOLVED';
}

const List<String> triggerTypes = [
  'fall_pattern',
  'inactivity',
  'missed_checkin',
  'manual_sos',
];

int _engineInstanceCounter = 0;

class _AckResult {
  const _AckResult.acked(this.by)
      : acknowledged = true,
        reason = null;
  const _AckResult.notAcked(this.reason)
      : acknowledged = false,
        by = null;
  final bool acknowledged;
  final String? by;
  final String? reason;
}

class _PendingAck {
  _PendingAck(this.contactId, this.finish);
  final String contactId;
  final void Function(_AckResult) finish;
}

class _Wait {
  _Wait(this.completer);
  final Completer<String> completer;
  Object? timerId;
}

class EscalationEngine {
  EscalationEngine({
    required List<Contact> contacts,
    int? cancelWindowSeconds,
    int? cascadeAckTimeoutSeconds,
    required this.notifier,
    required this.dispatcher,
    Scheduler? scheduler,
    String? wearerName,
    this.locationProvider,
    String? logKey,
  })  : contacts = List.of(contacts),
        cancelWindowMs = (cancelWindowSeconds ?? 60) * 1000,
        cascadeAckTimeoutMs = (cascadeAckTimeoutSeconds ?? 120) * 1000,
        scheduler = scheduler ?? RealScheduler(),
        wearerName = (wearerName == null || wearerName.isEmpty)
            ? 'Guardian wearer'
            : wearerName {
    if (contacts.isEmpty) {
      throw ArgumentError(
          'EscalationEngine: contacts must be a non-empty ordered list');
    }
    _engineInstanceCounter += 1;
    _instanceTag = 'i$_engineInstanceCounter';
    log = EventLog(() => this.scheduler.now(), logKey);
  }

  final List<Contact> contacts;
  final int cancelWindowMs;

  /// How long each contact gets to acknowledge before the cascade moves
  /// on. When the last contact's timeout lapses, that IS the no-response
  /// timeout that permits dispatch.
  final int cascadeAckTimeoutMs;
  final Notifier notifier;
  final Dispatcher dispatcher;
  final Scheduler scheduler;
  final String wearerName;
  final Location? Function()? locationProvider;

  late final String _instanceTag;
  late final EventLog log;
  int _episodeCounter = 0;

  String state = States.idle;
  Episode? episode;
  _PendingAck? _pendingAck;
  final Set<_Wait> _activeWaits = {};
  bool _dispatchInvoked = false;

  void _transition(String to, [Map<String, dynamic> data = const {}]) {
    final from = state;
    state = to;
    log.append('transition', {
      'from': from,
      'to': to,
      'episodeId': episode?.id,
      ...data,
    });
  }

  Location? _location() => locationProvider?.call();

  /// Plain wait that wearerCancel()/_failEpisode() can interrupt.
  Future<String> _wait(int ms) {
    final wait = _Wait(Completer<String>());
    wait.timerId = scheduler.setTimeout(() {
      _activeWaits.remove(wait);
      wait.completer.complete('elapsed');
    }, ms);
    _activeWaits.add(wait);
    return wait.completer.future;
  }

  /// Stop every pending timer/wait for the active episode.
  void _interruptWaits() {
    for (final wait in List.of(_activeWaits)) {
      scheduler.clearTimeout(wait.timerId as Object);
      if (!wait.completer.isCompleted) wait.completer.complete('interrupted');
    }
    _activeWaits.clear();
    _pendingAck?.finish(const _AckResult.notAcked('interrupted'));
  }

  /// Register the pending-ack slot for a contact and return a future for
  /// its outcome. The slot exists BEFORE the contact is notified, so an
  /// acknowledgment arriving during (or racing) notify() is captured.
  Future<_AckResult> _beginAckWait(String contactId, int ms) {
    final completer = Completer<_AckResult>();
    var settled = false;
    Object? timerId;
    late final void Function(_AckResult) finish;
    finish = (result) {
      if (settled) return;
      settled = true;
      final id = timerId;
      if (id != null) scheduler.clearTimeout(id);
      if (identical(_pendingAck?.finish, finish)) _pendingAck = null;
      completer.complete(result);
    };
    timerId = scheduler.setTimeout(() {
      finish(const _AckResult.notAcked('timeout'));
    }, ms);
    _pendingAck = _PendingAck(contactId, finish);
    return completer.future;
  }

  /// End the active episode as an error: log, RESOLVED(error), clear.
  void _failEpisode(Episode? failed, Object err) {
    if (failed == null || !identical(episode, failed)) return;
    log.append('engine_error', {
      'episodeId': failed.id,
      'message': _errorMessage(err),
    });
    _interruptWaits();
    _transition(States.resolved, {'resolution': 'error'});
    episode = null;
  }

  static String _errorMessage(Object err) {
    if (err is StateError) return err.message;
    if (err is ArgumentError) return '${err.message}';
    final s = err.toString();
    return s.startsWith('Exception: ') ? s.substring('Exception: '.length) : s;
  }

  /// Start an escalation episode. Valid only from IDLE.
  /// Returns true if the episode started.
  bool trigger(String triggerType, [Map<String, dynamic> details = const {}]) {
    if (state != States.idle) return false;
    if (!triggerTypes.contains(triggerType)) {
      throw ArgumentError(
          'EscalationEngine: unknown trigger type "$triggerType"');
    }
    _episodeCounter += 1;
    final ep = Episode(
      id: 'ep-$_instanceTag-$_episodeCounter',
      triggerType: triggerType,
      startedAt: scheduler.now(),
      wearerName: wearerName,
    );
    episode = ep;
    _dispatchInvoked = false;
    log.append('trigger_received', {
      'episodeId': ep.id,
      'triggerType': triggerType,
      'details': details,
    });
    _transition(States.triggered, {'triggerType': triggerType});
    _transition(States.cancelWindow, {'cancelWindowMs': cancelWindowMs});
    // Fire-and-forget the episode runner; all outcomes land in the log.
    _runEpisode().then<void>((_) {}, onError: (Object err) {
      _failEpisode(ep, err);
    });
    return true;
  }

  /// The wearer says "I am okay". Accepted during the cancel window AND
  /// during the cascade, any time before the dispatcher is actually
  /// invoked. Once dispatch() has been invoked the attempt is logged and
  /// refused. Returns true if a cancel was accepted.
  bool wearerCancel() {
    final ep = episode;
    if (ep == null) return false;
    if (_dispatchInvoked) {
      log.append('wearer_cancel_rejected', {
        'episodeId': ep.id,
        'reason': 'beyond_recall',
        'detail': 'dispatch already invoked',
      });
      return false;
    }
    if (state != States.cancelWindow && state != States.cascade) return false;
    log.append('wearer_cancelled', {
      'episodeId': ep.id,
      'duringState': state,
    });
    _interruptWaits();
    _transition(States.idle, {'reason': 'wearer_cancelled'});
    episode = null;
    return true;
  }

  /// A kin contact acknowledges. Any contact already notified in the
  /// active episode may acknowledge, even if the cascade has moved on to
  /// a later contact. Returns true if the acknowledgment was consumed.
  bool acknowledge(String contactId) {
    final ep = episode;
    final pending = _pendingAck;
    if (state == States.cascade &&
        ep != null &&
        pending != null &&
        ep.notifiedContacts.contains(contactId)) {
      pending.finish(_AckResult.acked(contactId));
      return true;
    }
    return false;
  }

  Future<void> _runEpisode() async {
    final ep = episode!;
    try {
      // CANCEL_WINDOW: lapse -> cascade, unless wearerCancel() intervened.
      await _wait(cancelWindowMs);
      if (!identical(episode, ep) || state != States.cancelWindow) return;
      log.append('cancel_window_lapsed', {'episodeId': ep.id});

      // CASCADE: ONE ordered pass, first acknowledgment wins.
      _transition(States.cascade);
      for (final contact in contacts) {
        if (!identical(episode, ep)) return;
        final alert = Alert(
          episodeId: ep.id,
          triggerType: ep.triggerType,
          message:
              'Guardian alert: possible ${ep.triggerType.replaceAll('_', ' ')} '
              'for ${ep.wearerName}. Please acknowledge if you are responding.',
          location: _location(),
        );
        final ackWait = _beginAckWait(contact.id, cascadeAckTimeoutMs);
        ep.notifiedContacts.add(contact.id);
        // Log-before-side-effect: the intent entry lands first.
        log.append('cascade_notify_pending', {
          'episodeId': ep.id,
          'contactId': contact.id,
        });
        final result = await notifier.notify(contact, alert);
        log.append('cascade_notified', {
          'episodeId': ep.id,
          'contactId': contact.id,
          'delivered': result.delivered,
          'channel': result.channel,
        });

        final ack = await ackWait;
        if (!identical(episode, ep)) return; // cancelled while waiting
        if (ack.acknowledged) {
          log.append('cascade_acknowledged', {
            'episodeId': ep.id,
            'contactId': ack.by,
            'pendingContactId': contact.id,
          });
          _transition(States.resolved, {
            'resolution': 'acknowledged',
            'by': ack.by,
          });
          episode = null;
          return;
        }
        log.append('cascade_no_response', {
          'episodeId': ep.id,
          'contactId': contact.id,
          'waitedMs': cascadeAckTimeoutMs,
        });
      }

      // DISPATCH: cascade exhausted with no acknowledgment.
      if (!identical(episode, ep)) return;
      _transition(States.dispatch, {'reason': 'cascade_exhausted'});
      final d = dispatcher;
      final alarm = d is AlarmPayloadBuilder
          ? (d as AlarmPayloadBuilder).buildAlarmPayload(ep, _location())
          : <String, dynamic>{
              'episodeId': ep.id,
              'triggerType': ep.triggerType,
            };
      // Log-before-side-effect. From the invoke line below, the episode
      // is beyond wearer recall.
      log.append('dispatch_pending', {'episodeId': ep.id});
      _dispatchInvoked = true;
      final dispatchResult = await dispatcher.dispatch(alarm);
      log.append('dispatch_result', {
        'episodeId': ep.id,
        'status': dispatchResult.status,
        'reference': dispatchResult.reference,
      });
      _transition(States.resolved, {
        'resolution': 'dispatched',
        'dispatchStatus': dispatchResult.status,
      });
      episode = null;
    } catch (err) {
      _failEpisode(ep, err);
    }
  }

  /// Start a fresh episode cycle after RESOLVED.
  bool reset() {
    if (state == States.resolved) {
      _transition(States.idle, {'reason': 'reset'});
      return true;
    }
    return false;
  }
}
