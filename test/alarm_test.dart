// Session 5 Part 1: alarm + voice prompt wiring. A mock alarm records
// start/stop/speak. No test needs an audio device.

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/consent/consent.dart';
import 'package:guardian_app/engine/guardian_engine.dart';
import 'package:guardian_app/rehearsal/alarm_service.dart';
import 'package:guardian_app/rehearsal/interactive_rehearsal.dart';
import 'package:guardian_app/rehearsal/scaled_scheduler.dart';

class MockAlarm implements AlarmService {
  final List<String> calls = [];
  final List<String> spoken = [];
  bool _on = false;

  @override
  bool get isSounding => _on;
  @override
  bool get canProduceSound => false;
  @override
  String? get lastError => null;
  @override
  String get description => 'mock alarm (records calls)';
  @override
  Future<void> start() async {
    _on = true;
    calls.add('start');
  }

  @override
  Future<void> stop() async {
    _on = false;
    calls.add('stop');
  }

  @override
  Future<void> speak(String text) async {
    calls.add('speak');
    spoken.add(text);
  }
}

class _Rig {
  _Rig({bool kinAllowed = true}) {
    scaled = ScaledScheduler(inner: fake, scale: 1, startAt: 0);
    ctl = InteractiveRehearsal(
      scheduler: scaled,
      alarm: alarm,
      consent: ConsentStore()
        ..grant(ConsentRole.provider, ConsentDataClass.fhirExport),
    );
    if (kinAllowed) {
      ctl.consent.grant(ConsentRole.kin, ConsentDataClass.alerts);
    }
  }

  final fake = FakeScheduler(0);
  final alarm = MockAlarm();
  late final ScaledScheduler scaled;
  late final InteractiveRehearsal ctl;

  /// Advance episode milliseconds; refresh like the UI ticker does.
  Future<void> advance(int ms) async {
    await fake.advance(ms);
    ctl.refresh();
  }
}

void main() {
  test('alarm is off before the fall; starts on trigger with the voice prompt',
      () async {
    final r = _Rig();
    expect(r.alarm.isSounding, isFalse);
    expect(r.alarm.calls, isEmpty);
    r.ctl.simulateFall();
    expect(r.ctl.engine.state, States.cancelWindow);
    expect(r.alarm.isSounding, isTrue);
    expect(r.alarm.calls, ['start', 'speak']);
    r.ctl.dispose();
  });

  test('voice prompt names the cancel action', () {
    for (final t in [windowVoicePrompt, cascadeVoicePrompt]) {
      expect(t, contains("I'm OK"));
      expect(t.toLowerCase(), contains('tap'));
      expect(t.toLowerCase(), contains('cancel'));
    }
    final r = _Rig()..ctl.simulateFall();
    expect(r.alarm.spoken.first, windowVoicePrompt);
    // No medical claims in what is spoken.
    for (final t in [windowVoicePrompt, cascadeVoicePrompt]) {
      expect(t.toLowerCase(), isNot(contains('injur')));
      expect(t.toLowerCase(), isNot(contains('diagnos')));
    }
    r.ctl.dispose();
  });

  test('cancel INSIDE the window stops the alarm immediately', () async {
    final r = _Rig()..ctl.simulateFall();
    await r.advance(20000);
    expect(r.alarm.isSounding, isTrue);
    expect(r.ctl.imOk(), isTrue);
    expect(r.alarm.isSounding, isFalse);
    expect(r.alarm.calls.last, 'stop');
    await r.advance(600000);
    expect(r.alarm.isSounding, isFalse);
    expect(r.alarm.calls.where((c) => c == 'start').length, 1);
    r.ctl.dispose();
  });

  test('alarm keeps sounding into the cascade, cascade prompt spoken once',
      () async {
    final r = _Rig()..ctl.simulateFall();
    await r.advance(61000);
    expect(r.ctl.engine.state, States.cascade);
    expect(r.alarm.isSounding, isTrue);
    expect(r.alarm.spoken, [windowVoicePrompt, cascadeVoicePrompt]);
    await r.advance(10000);
    expect(r.alarm.spoken.length, 2);
    r.ctl.dispose();
  });

  test('MID-CASCADE cancel stops the alarm', () async {
    final r = _Rig()..ctl.simulateFall();
    await r.advance(61000);
    await r.advance(125000); // past the first ack timeout
    expect(r.ctl.engine.state, States.cascade);
    expect(r.alarm.isSounding, isTrue);
    expect(r.ctl.imOk(), isTrue);
    expect(r.alarm.isSounding, isFalse);
    r.ctl.dispose();
  });

  test('kin acknowledgment stops the alarm', () async {
    final r = _Rig()..ctl.simulateFall();
    await r.advance(61000);
    expect(r.alarm.isSounding, isTrue);
    expect(r.ctl.simulateKinAck(), isTrue);
    expect(r.alarm.isSounding, isFalse);
    await r.advance(1000);
    expect(r.ctl.engine.state, States.resolved);
    expect(r.alarm.isSounding, isFalse);
    r.ctl.dispose();
  });

  test('dispatch step reached (disabled): alarm is off at RESOLVED',
      () async {
    final r = _Rig()..ctl.simulateFall();
    await r.advance(61000);
    await r.advance(3 * 121000);
    await r.advance(5000);
    expect(r.ctl.engine.state, States.resolved);
    expect(r.ctl.outcome, RehearsalOutcome.dispatchStepDisabled);
    expect(r.alarm.isSounding, isFalse);
    expect(r.alarm.spoken.last, dispatchDisabledVoicePrompt);
    expect(r.ctl.dispatcher.dispatchCalls, 1);
    r.ctl.dispose();
  });

  test('leaving mid-episode (dispose) silences the alarm', () async {
    final r = _Rig()..ctl.simulateFall();
    expect(r.alarm.isSounding, isTrue);
    r.ctl.dispose();
    expect(r.alarm.isSounding, isFalse);
  });

  test('silent fallback says plainly that it makes no sound', () async {
    final s = SilentAlarmService();
    expect(s.canProduceSound, isFalse);
    expect(s.description, contains('NO SOUND'));
    await s.start();
    expect(s.isSounding, isTrue);
    await s.stop();
    expect(s.isSounding, isFalse);
  });
}
