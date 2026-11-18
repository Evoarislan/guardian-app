// Interactive live rehearsal (Session 4).
//
// One episode on the real Dart engine, driven in real time by the user:
//   - "Simulate fall" plays the labelled simulator fall (the trigger).
//   - "I'm OK" calls engine.wearerCancel(): accepted during the cancel
//     window AND during the cascade, any time before the dispatcher is
//     invoked (the engine's own rule; nothing is re-implemented here).
//   - "Simulated kin ack" calls engine.acknowledge() for the contact the
//     cascade is currently waiting on.
//
// Time is SCALED (see ScaledScheduler): the engine keeps the canonical
// 60 s cancel window and 120 s per-contact ack timeout in episode time;
// only the real wait is shorter. The scale is shown on screen.
//
// Everything is simulated: signals (source=simulator, freshness=
// simulated), kin notifications (MockNotifier, nothing sent), dispatch
// (DISABLED: no token, no transport, no network). No I/O in this file.

import 'package:flutter/foundation.dart';

import '../adapters/trace_simulator.dart';
import '../consent/consent.dart';
import '../engine/guardian_engine.dart';
import 'alarm_service.dart';
import 'consent_gated_notifier.dart';
import 'payload_logging_dispatcher.dart';
import 'proof_episodes.dart';
import 'scaled_scheduler.dart';

/// How an interactive episode ended (derived from the log, not guessed).
enum RehearsalOutcome { wearerCancelled, acknowledged, dispatchStepDisabled }

class InteractiveRehearsal extends ChangeNotifier {
  InteractiveRehearsal({
    ScaledScheduler? scheduler,
    AlarmService? alarm,
    ConsentStore? consent,
  }) : scheduler =
           scheduler ??
           ScaledScheduler(startAt: DateTime.now().millisecondsSinceEpoch),
       alarm = alarm ?? SilentAlarmService(),
       consent = consent ?? ConsentStore(),
       notifier = MockNotifier(),
      dispatcher = PayloadLoggingDispatcher(labels: proofLabels) {
    simulator = TraceSimulatorAdapter(now: this.scheduler.now);
    gate = ConsentGatedNotifier(inner: notifier, consent: this.consent);
    engine = EscalationEngine(
      contacts: syntheticKin,
      cancelWindowSeconds: cancelWindowSeconds,
      cascadeAckTimeoutSeconds: ackTimeoutSeconds,
      notifier: gate,
      dispatcher: dispatcher,
      scheduler: this.scheduler,
      wearerName: 'Synthetic demo wearer',
      locationProvider: simulator.location,
    );
    dispatcher.attachLog(engine.log);
    gate.attachLog(engine.log);
    simulator.onSignal((signal) {
      if (signal.kind == 'accel' && signal.value['type'] == 'fall_pattern') {
        engine.trigger('fall_pattern', {'signal': signal.toJson()});
      }
    });
    this.scheduler.onFire = _changed;
  }

  final ScaledScheduler scheduler;
  final MockNotifier notifier;
  final AlarmService alarm;
  final ConsentStore consent;
  late final ConsentGatedNotifier gate;
  final PayloadLoggingDispatcher dispatcher;
  late final TraceSimulatorAdapter simulator;
  late final EscalationEngine engine;

  bool _disposed = false;
  bool _alarmOn = false;
  bool _cascadeSpoken = false;
  bool _endSpoken = false;
  bool _started = false;
  Anchor? _finalAnchor;

  EventLog get log => engine.log;
  bool get started => _started;

  /// Ask listeners (the screen) to re-read the clock and the log.
  void refresh() => _changed();

  /// Episode over: back to IDLE (wearer cancel) or RESOLVED.
  bool get finished =>
      _started &&
      (engine.state == States.idle || engine.state == States.resolved);

  bool get inCancelWindow => engine.state == States.cancelWindow;
  bool get inCascade => engine.state == States.cascade;

  /// "I'm OK" is offered exactly while the engine would accept it.
  bool get canCancel => inCancelWindow || inCascade;

  /// The contact the cascade is currently waiting on, or null.
  Contact? get currentContact {
    if (!inCascade) return null;
    for (final e in log.entries.reversed) {
      if (e.type == 'cascade_notify_pending') {
        final id = e.data['contactId'];
        for (final c in syntheticKin) {
          if (c.id == id) return c;
        }
      }
    }
    return null;
  }

  /// Episode seconds left in the current wait (cancel window or the
  /// current contact's ack timeout); null outside those states.
  int? get remainingEpisodeSeconds {
    final int fromTs;
    final int totalMs;
    if (inCancelWindow) {
      fromTs = log.entries
          .lastWhere(
            (e) =>
                e.type == 'transition' && e.data['to'] == States.cancelWindow,
          )
          .ts;
      totalMs = engine.cancelWindowMs;
    } else if (inCascade) {
      fromTs = log.entries
          .lastWhere((e) => e.type == 'cascade_notify_pending')
          .ts;
      totalMs = engine.cascadeAckTimeoutMs;
    } else {
      return null;
    }
    final left = totalMs - (scheduler.now() - fromTs);
    return (left < 0 ? 0 : (left / 1000).ceil());
  }

  /// Alarm rule: sounds exactly while the engine is in the cancel window
  /// or the cascade; silent in every other state (IDLE after a cancel,
  /// DISPATCH, RESOLVED). Called on every state refresh.
  void _syncAlarm() {
    final shouldSound = _started && canCancel;
    if (shouldSound && !_alarmOn) {
      _alarmOn = true;
      alarm.start();
      alarm.speak(windowVoicePrompt);
    } else if (!shouldSound && _alarmOn) {
      _stopAlarm();
    }
    if (shouldSound && inCascade && !_cascadeSpoken) {
      _cascadeSpoken = true;
      alarm.speak(cascadeVoicePrompt);
    }
    if (!shouldSound &&
        !_endSpoken &&
        _started &&
        outcome == RehearsalOutcome.dispatchStepDisabled) {
      _endSpoken = true;
      alarm.speak(dispatchDisabledVoicePrompt);
    }
  }

  void _stopAlarm() {
    _alarmOn = false;
    alarm.stop();
  }

  /// True when the contact the cascade is waiting on was skipped for lack
  /// of consent (nobody was notified, so nobody can acknowledge).
  bool get currentContactSkipped {
    final c = currentContact;
    if (c == null) return false;
    return log.entries.any(
      (e) =>
          e.type == 'kin_notification_skipped' && e.data['contactId'] == c.id,
    );
  }

  void _changed() {
    if (_disposed) return;
    _syncAlarm();
    if (finished && _finalAnchor == null) _finalAnchor = log.anchor();
    if (!_disposed) notifyListeners();
  }

  /// Play the simulated fall; opens the cancel window.
  bool simulateFall() {
    if (_started) return false;
    _started = true;
    simulator.playFall();
    _changed();
    return true;
  }

  /// The wearer's "I'm OK". Returns true if the engine accepted it.
  bool imOk() {
    final ok = engine.wearerCancel();
    if (ok) _stopAlarm(); // immediately, before any rebuild
    _changed();
    return ok;
  }

  /// SIMULATED kin acknowledgment for the contact currently notified.
  bool simulateKinAck() {
    final contact = currentContact;
    if (contact == null || currentContactSkipped) return false;
    final ok = engine.acknowledge(contact.id);
    if (ok) _stopAlarm();
    // The engine resolves in microtasks; refresh once they have run.
    Future<void>.delayed(Duration.zero, _changed);
    return ok;
  }

  RehearsalOutcome? get outcome {
    if (!finished) return null;
    final types = log.entries.map((e) => e.type);
    if (types.contains('wearer_cancelled')) {
      return RehearsalOutcome.wearerCancelled;
    }
    if (types.contains('cascade_acknowledged')) {
      return RehearsalOutcome.acknowledged;
    }
    return RehearsalOutcome.dispatchStepDisabled;
  }

  /// The run as an [EpisodeRun], so the timeline card and chain check
  /// used by the other live views apply unchanged. The anchor is frozen
  /// when the episode finished (truncation is caught from then on).
  EpisodeRun snapshot() => EpisodeRun(
    label: 'interactive',
    engine: engine,
    simulator: simulator,
    notifier: notifier,
    dispatcher: dispatcher,
    dataLabels: proofLabels,
    anchor: _finalAnchor ?? log.anchor(),
    checks: const [],
  );

  @override
  void dispose() {
    if (_alarmOn) _stopAlarm();
    _disposed = true;
    scheduler.shutdown();
    super.dispose();
  }
}
