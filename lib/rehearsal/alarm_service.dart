// Alarm + voice prompt on the cancel affordance (Session 5).
//
// While an episode is in its cancel window and during the cascade, the
// wearer gets a LOUD alarm and a SPOKEN prompt that names the cancel
// action ("tap I'm OK"). This file is only the interface and the
// silent fallback; it has no platform imports so tests and the plain
// Dart runner can use it. The real implementation (audioplayers +
// flutter_tts) is in device_alarm_service.dart.
//
// The alarm is a wearer-facing affordance, not an escalation step: it
// does not write to the episode event log (the log holds the
// transitions the engine takes; adding rows would change the
// engine-parity timelines). Its state is shown on screen instead.

abstract class AlarmService {
  /// True while [start] has been called and [stop] has not.
  bool get isSounding;

  /// Plain statement of what this implementation actually does. Shown on
  /// screen so nobody assumes sound is playing when it cannot be.
  String get description;

  /// False when this implementation can never produce sound.
  bool get canProduceSound;

  /// Last playback/speech error, or null. Shown on screen if set.
  String? get lastError;

  /// Start the looping alarm tone. Idempotent.
  Future<void> start();

  /// Silence the alarm AND any speech in progress. Idempotent; must never
  /// throw.
  Future<void> stop();

  /// Speak [text] aloud.
  Future<void> speak(String text);
}

/// Voice prompt used when the cancel window opens. Names the cancel action.
const String windowVoicePrompt =
    'Guardian detected a possible fall. Your contacts will be alerted soon. '
    "If you are OK, tap the big I'm OK button to cancel.";

/// Voice prompt used when the cascade starts contacting kin.
const String cascadeVoicePrompt =
    'Guardian is now contacting your family, one at a time. '
    "Tap the big I'm OK button to cancel.";

/// Voice prompt used once the cascade is exhausted in this build.
const String dispatchDisabledVoicePrompt =
    'Nobody answered. Dispatch is switched off in this build, '
    'so nothing was sent to anyone.';

/// FALLBACK implementation: produces NO sound and NO speech. Used when no
/// real implementation is given (tests, plain Dart). It still tracks
/// state so wiring can be observed, and says plainly that it is silent.
class SilentAlarmService implements AlarmService {
  bool _on = false;
  final List<String> spoken = [];

  @override
  bool get isSounding => _on;

  @override
  bool get canProduceSound => false;

  @override
  String? get lastError => null;

  @override
  String get description =>
      'NO SOUND in this build: silent fallback alarm (state only). '
      'Nothing is played and nothing is spoken.';

  @override
  Future<void> start() async => _on = true;

  @override
  Future<void> stop() async => _on = false;

  @override
  Future<void> speak(String text) async => spoken.add(text);
}
